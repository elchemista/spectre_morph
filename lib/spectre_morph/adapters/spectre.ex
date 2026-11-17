defmodule SpectreMorph.Adapters.Spectre do
  @moduledoc """
  Bridge reserved for Spectre's future AgentServer evolution contract.

  Spectre 0.4.0 does not implement this contract. Calls return
  `{:error, :agent_server_evolution_unavailable}` without messaging the target.
  The proposed core API is documented in `docs/CORE_0_4_1.md`; its availability
  is detected by capability, not inferred from a package version string.
  """

  @behaviour SpectreMorph.Adapter
  @core Spectre.Server.Evolution
  @contract_version 1

  @doc "Checks the proposed core contract without contacting an agent process."
  @spec available?() :: boolean()
  def available? do
    Code.ensure_loaded?(@core) and function_exported?(@core, :contract_version, 0) and
      function_exported?(@core, :call, 4) and
      invoke_core(:contract_version, []) == @contract_version
  end

  @impl true
  @spec call(term(), SpectreMorph.Adapter.action(), map(), keyword()) ::
          SpectreMorph.Adapter.reply()
  def call(target, action, request, opts) do
    if available?() do
      invoke_core(:call, [target, action, request, opts])
    else
      {:error, :agent_server_evolution_unavailable}
    end
  end

  # Late binding keeps the preparation compatible with a core where this API is absent.
  @spec invoke_core(atom(), [term()]) :: term()
  defp invoke_core(function, arguments), do: apply(@core, function, arguments)
end
