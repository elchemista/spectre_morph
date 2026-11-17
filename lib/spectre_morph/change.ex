defmodule SpectreMorph.Change do
  @moduledoc """
  Transient context for a proposed Skill change.

  This value is an ergonomic workflow, not an authorization receipt or a durable
  record. The runtime owns candidates, approvals and activation. Keep this value
  in the calling task; it includes the runtime address and host adapter options.
  """

  alias Spectre.Governance.ChangeSet.Operation

  @typedoc "Local workflow stage; the runtime independently verifies every request."
  @type stage :: :draft | :evaluated | :approved | :rejected

  @type t :: %__MODULE__{
          target: term(),
          adapter: module(),
          adapter_options: keyword(),
          by: String.t() | nil,
          reason: String.t() | nil,
          evidence: map(),
          base: map() | nil,
          operations: [Operation.t()],
          candidate: term(),
          approval: term(),
          report: term(),
          state: stage(),
          error: term()
        }

  defstruct [
    :target,
    :by,
    :reason,
    :base,
    :candidate,
    :approval,
    :report,
    :error,
    adapter: SpectreMorph.Adapters.Spectre,
    adapter_options: [],
    evidence: %{},
    operations: [],
    state: :draft
  ]

  @doc "Builds the runtime request without exposing adapter configuration or addresses."
  @spec request(t()) :: map()
  def request(%__MODULE__{} = change) do
    %{
      base: change.base,
      operations: Enum.map(change.operations, &Operation.to_data/1),
      by: change.by,
      reason: change.reason,
      evidence: change.evidence,
      candidate: change.candidate,
      approval: change.approval
    }
  end

  @doc false
  @spec fail(t(), term()) :: t()
  def fail(%__MODULE__{error: nil} = change, reason), do: %{change | error: reason}
  def fail(%__MODULE__{} = change, _reason), do: change
end
