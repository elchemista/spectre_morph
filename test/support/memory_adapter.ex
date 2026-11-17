defmodule SpectreMorph.Test.MemoryAdapter do
  @moduledoc false
  @behaviour SpectreMorph.Adapter

  def initial do
    %{
      revision: {make_ref(), 0},
      candidates: %{},
      approvals: %{},
      applications: [],
      calls: [],
      approval_allowed?: true
    }
  end

  @impl true
  def call(target, action, request, options) do
    Agent.get_and_update(target, fn state ->
      state = %{state | calls: state.calls ++ [{action, request, options}]}
      dispatch(state, action, request)
    end)
  end

  defp dispatch(state, :snapshot, _request),
    do: {{:ok, %{revision: state.revision, origin: :test_runtime}}, state}

  defp dispatch(state, action, request) do
    if request.base.revision == state.revision,
      do: perform(state, action, request),
      else: {{:error, :stale_revision}, state}
  end

  defp perform(state, :evaluate, request) do
    candidate = make_ref()
    record = %{binding: bound_request(request), rejected?: false, consumed?: false}
    state = %{state | candidates: Map.put(state.candidates, candidate, record)}
    {{:ok, %{candidate: candidate, report: %{passed: true}}}, state}
  end

  defp perform(state, action, request) do
    case verify_candidate(state, request) do
      :ok -> apply_action(state, action, request)
      {:error, _reason} = error -> {error, state}
    end
  end

  defp apply_action(%{approval_allowed?: false} = state, :approve, _request),
    do: {{:error, :not_authorized}, state}

  defp apply_action(state, :approve, request) do
    approval = make_ref()
    state = %{state | approvals: Map.put(state.approvals, approval, request.candidate)}
    {{:ok, %{approval: approval}}, state}
  end

  defp apply_action(state, :reject, request) do
    record = %{Map.fetch!(state.candidates, request.candidate) | rejected?: true}
    state = %{state | candidates: Map.put(state.candidates, request.candidate, record)}
    {{:ok, %{}}, state}
  end

  defp apply_action(state, :activate, request) do
    if Map.get(state.approvals, request.approval) == request.candidate do
      {session, revision} = state.revision
      next_revision = {session, revision + 1}
      record = %{Map.fetch!(state.candidates, request.candidate) | consumed?: true}

      next = %{
        state
        | revision: next_revision,
          candidates: Map.put(state.candidates, request.candidate, record),
          applications: state.applications ++ [request.operations]
      }

      {{:ok, %{revision: next_revision, candidate: request.candidate}}, next}
    else
      {{:error, :invalid_approval}, state}
    end
  end

  defp verify_candidate(state, request) do
    case Map.get(state.candidates, request.candidate) do
      nil ->
        {:error, :invalid_candidate}

      %{rejected?: true} ->
        {:error, :candidate_rejected}

      %{consumed?: true} ->
        {:error, :candidate_consumed}

      %{binding: expected} ->
        if bound_request(request) == expected, do: :ok, else: {:error, :candidate_changed}
    end
  end

  defp bound_request(request),
    do: Map.take(request, [:base, :operations, :by, :reason, :evidence])
end
