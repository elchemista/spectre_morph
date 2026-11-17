defmodule SpectreMorph.Adapter do
  @moduledoc """
  Host-selected boundary to an evolution-capable runtime.

  Implementations own durable candidates and authenticate review and activation.
  A stage or actor label supplied by the caller never constitutes authority.
  See `docs/ADAPTERS.md` for the request and response contract.
  """

  @type action :: :snapshot | :evaluate | :approve | :reject | :activate
  @type reply :: {:ok, map()} | {:error, term()}

  @doc "Handles one explicit workflow action on the host's target."
  @callback call(target :: term(), action(), request :: map(), options :: keyword()) :: reply()

  @doc false
  @spec invoke(module(), term(), action(), map(), keyword()) :: reply()
  def invoke(adapter, target, action, request, opts) do
    if is_atom(adapter) and Code.ensure_loaded?(adapter) and
         function_exported?(adapter, :call, 4) do
      dispatch(adapter, target, action, request, opts)
    else
      {:error, :invalid_adapter}
    end
  end

  @spec dispatch(module(), term(), action(), map(), keyword()) :: reply()
  defp dispatch(adapter, target, action, request, opts) do
    case adapter.call(target, action, request, opts) do
      {:ok, reply} when is_map(reply) -> validate(action, reply)
      {:error, _reason} = error -> error
      _other -> {:error, {:invalid_adapter_reply, action}}
    end
  rescue
    exception -> {:error, {:adapter_exception, exception.__struct__}}
  catch
    :exit, reason -> {:error, {:adapter_exit, reason}}
  end

  @spec validate(action(), map()) :: reply()
  defp validate(:snapshot, %{revision: revision} = reply) when not is_nil(revision),
    do: {:ok, reply}

  defp validate(:evaluate, %{candidate: candidate} = reply) when not is_nil(candidate),
    do: {:ok, reply}

  defp validate(:approve, %{approval: approval} = reply) when not is_nil(approval),
    do: {:ok, reply}

  defp validate(action, reply) when action in [:reject, :activate], do: {:ok, reply}
  defp validate(action, _reply), do: {:error, {:invalid_adapter_reply, action}}
end
