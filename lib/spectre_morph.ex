defmodule SpectreMorph do
  @moduledoc """
  Explicit, host-controlled Skill evolution for Spectre agents.

  Build inert mount, replace and disable proposals, then request evaluation,
  approval and activation through a host adapter. Core Skill and operation
  validators are reused; this package owns no runtime, store or authority.

  The default AgentServer adapter requires a future core extension. On Spectre
  0.4.0 it reports `:agent_server_evolution_unavailable`. A custom adapter can
  exercise the workflow today; production activation remains its responsibility.
  """

  alias Spectre.Canonical.Value
  alias SpectreMorph.{Adapter, Change, Operation}

  @change_options [:adapter, :adapter_options, :by, :reason, :evidence]

  @doc """
  Opens a draft against the runtime's current opaque revision.

  `by:` and `reason:` are audit labels, not authentication. The host selects
  `adapter:` and `adapter_options:`; they must never come from model output.
  The first error remains on the returned Change through subsequent stages.
  """
  @spec change(term(), keyword()) :: Change.t()
  def change(target, opts \\ []) do
    with :ok <- options(opts),
         {:ok, opts} <- Keyword.validate(opts, @change_options),
         :ok <- required(Keyword.get(opts, :by), :by),
         :ok <- required(Keyword.get(opts, :reason), :reason),
         evidence = Keyword.get(opts, :evidence, %{}),
         :ok <- evidence(evidence),
         adapter_options = Keyword.get(opts, :adapter_options, []),
         :ok <- options(adapter_options) do
      %Change{
        target: target,
        adapter: Keyword.get(opts, :adapter, SpectreMorph.Adapters.Spectre),
        adapter_options: adapter_options,
        by: Keyword.fetch!(opts, :by),
        reason: Keyword.fetch!(opts, :reason),
        evidence: evidence
      }
      |> snapshot()
    else
      {:error, reason} -> Change.fail(%Change{target: target}, reason)
    end
  end

  @doc "Adds a declarative runtime Skill to a draft; it executes no code."
  @spec mount_skill(Change.t(), String.t(), map() | keyword()) :: Change.t()
  def mount_skill(change, mount_id, definition),
    do: append(change, :mount_skill, mount_id, definition)

  @doc "Proposes replacing a runtime Skill; the runtime verifies the target and authority."
  @spec replace_skill(Change.t(), String.t(), map() | keyword()) :: Change.t()
  def replace_skill(change, mount_id, definition),
    do: append(change, :replace_skill, mount_id, definition)

  @doc "Proposes disabling a Skill without discarding its in-flight execution history."
  @spec disable_skill(Change.t(), String.t()) :: Change.t()
  def disable_skill(change, mount_id), do: append(change, :disable_skill, mount_id, nil)

  @doc "Requests candidate evaluation using host-selected options and policy."
  @spec evaluate(Change.t(), keyword()) :: Change.t()
  def evaluate(change, opts \\ []),
    do: transition(change, :draft, :evaluated, :evaluate, opts)

  @doc "Requests approval; the runtime authenticates the reviewer and verifies the candidate."
  @spec approve(Change.t(), keyword()) :: Change.t()
  def approve(change, opts \\ []),
    do: transition(change, :evaluated, :approved, :approve, opts)

  @doc "Requests rejection of an evaluated candidate."
  @spec reject(Change.t(), keyword()) :: Change.t()
  def reject(change, opts \\ []),
    do: transition(change, :evaluated, :rejected, :reject, opts)

  @doc """
  Requests activation of the exact approved candidate.

  The runtime rechecks the live revision, approval and current authority. Adapter
  errors are returned without retry. After an exit or ambiguous failure, inspect
  the runtime's actual revision before deciding whether to retry.
  """
  @spec activate(Change.t(), keyword()) :: Adapter.reply()
  def activate(change, opts \\ [])
  def activate(%Change{error: error}, _opts) when not is_nil(error), do: {:error, error}

  def activate(%Change{} = change, opts) do
    with :ok <- stage(change, :approved), do: request(change, :activate, opts)
  end

  @doc "Returns the local stage and first error; it is not runtime activation status."
  @spec status(Change.t()) :: %{state: Change.stage(), error: term()}
  def status(%Change{} = change), do: Map.take(change, [:state, :error])

  @spec snapshot(Change.t()) :: Change.t()
  defp snapshot(change) do
    case Adapter.invoke(change.adapter, change.target, :snapshot, %{}, change.adapter_options) do
      {:ok, base} -> %{change | base: base}
      {:error, reason} -> Change.fail(change, reason)
    end
  end

  @spec append(Change.t(), atom(), String.t(), term()) :: Change.t()
  defp append(%Change{error: error} = change, _type, _id, _definition)
       when not is_nil(error),
       do: change

  defp append(%Change{} = change, type, id, definition) do
    with :ok <- stage(change, :draft),
         {:ok, operation} <- Operation.new(type, id, definition) do
      %{change | operations: change.operations ++ [operation]}
    else
      {:error, reason} -> Change.fail(change, reason)
    end
  end

  @spec transition(Change.t(), Change.stage(), Change.stage(), Adapter.action(), keyword()) ::
          Change.t()
  defp transition(%Change{error: error} = change, _expected, _next, _action, _opts)
       when not is_nil(error),
       do: change

  defp transition(%Change{} = change, expected, next, action, opts) do
    with :ok <- stage(change, expected),
         :ok <- has_operations(change, action),
         {:ok, reply} <- request(change, action, opts) do
      change
      |> Map.merge(Map.take(reply, reply_fields(action)))
      |> Map.put(:state, next)
    else
      {:error, reason} -> Change.fail(change, reason)
    end
  end

  @spec reply_fields(Adapter.action()) :: [atom()]
  defp reply_fields(:evaluate), do: [:candidate, :report]
  defp reply_fields(:approve), do: [:approval]
  defp reply_fields(:reject), do: []

  @spec request(Change.t(), Adapter.action(), keyword()) :: Adapter.reply()
  defp request(change, action, opts) do
    with :ok <- options(opts) do
      Adapter.invoke(
        change.adapter,
        change.target,
        action,
        Change.request(change),
        Keyword.merge(change.adapter_options, opts)
      )
    end
  end

  @spec stage(Change.t(), Change.stage()) :: :ok | {:error, term()}
  defp stage(%Change{state: expected}, expected), do: :ok
  defp stage(%Change{state: actual}, expected), do: {:error, {:invalid_stage, expected, actual}}

  @spec has_operations(Change.t(), Adapter.action()) :: :ok | {:error, term()}
  defp has_operations(%Change{operations: []}, :evaluate), do: {:error, :no_changes}
  defp has_operations(_change, _action), do: :ok

  @spec options(term()) :: :ok | {:error, term()}
  defp options(opts) when is_list(opts) do
    if Keyword.keyword?(opts), do: :ok, else: {:error, :invalid_options}
  end

  defp options(_opts), do: {:error, :invalid_options}

  @spec required(term(), atom()) :: :ok | {:error, term()}
  defp required(value, key) when is_binary(value) do
    if String.trim(value) != "", do: :ok, else: {:error, {:required, key}}
  end

  defp required(_value, key), do: {:error, {:required, key}}

  @spec evidence(term()) :: :ok | {:error, term()}
  defp evidence(value) when is_map(value) and not is_struct(value), do: Value.validate(value)
  defp evidence(_value), do: {:error, :invalid_evidence}
end
