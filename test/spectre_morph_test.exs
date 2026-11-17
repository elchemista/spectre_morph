Code.require_file("support/memory_adapter.ex", __DIR__)

defmodule SpectreMorphTest do
  use ExUnit.Case, async: true

  alias Spectre.Governance.ChangeSet.Operation
  alias SpectreMorph.{Adapter, Change}
  alias SpectreMorph.Test.MemoryAdapter

  defmodule FailingAdapter do
    @moduledoc false
    @behaviour SpectreMorph.Adapter

    @impl true
    def call(_target, _action, _request, options) do
      case Keyword.fetch!(options, :failure) do
        :exception -> raise "private backend detail"
        :exit -> exit(:backend_gone)
        :error -> {:error, :backend_refused}
        :invalid -> :unexpected
        {:reply, value} -> value
      end
    end
  end

  defmodule LostReplyAdapter do
    @moduledoc false
    @behaviour SpectreMorph.Adapter

    @impl true
    def call(target, action, request, options) do
      case MemoryAdapter.call(target, action, request, options) do
        {:ok, _result} when action == :activate -> exit(:reply_lost)
        reply -> reply
      end
    end
  end

  setup do
    target = start_supervised!({Agent, &MemoryAdapter.initial/0})
    %{target: target}
  end

  test "evaluates and activates exact data-only operations through the host", %{target: target} do
    change =
      target
      |> draft()
      |> SpectreMorph.mount_skill("refunds", skill())
      |> SpectreMorph.replace_skill("old-refunds", skill())
      |> SpectreMorph.disable_skill("retired")

    assert %Change{base: %{revision: _, origin: :test_runtime}} = change
    assert Enum.all?(change.operations, &match?(%Operation{}, &1))

    approved = change |> SpectreMorph.evaluate(timeout: 500) |> SpectreMorph.approve()
    assert SpectreMorph.status(approved) == %{state: :approved, error: nil}
    assert approved.report == %{passed: true}
    assert {:ok, %{candidate: candidate}} = SpectreMorph.activate(approved)
    assert candidate == approved.candidate

    state = Agent.get(target, & &1)
    assert [operations] = state.applications
    assert Enum.map(operations, & &1["type"]) == ["mount_skill", "replace_skill", "disable_skill"]
    assert Enum.map(state.calls, &elem(&1, 0)) == [:snapshot, :evaluate, :approve, :activate]
    assert {:evaluate, request, [timeout: 500]} = Enum.at(state.calls, 1)
    assert request.base == change.base
    assert request.by == "operator:alice"
    refute Map.has_key?(request, :adapter_options)
    refute Map.has_key?(request, :target)
  end

  test "the backend rejects forged approval despite a forged local stage", %{target: target} do
    evaluated = target |> proposal() |> SpectreMorph.evaluate()
    forged = %{evaluated | state: :approved, approval: make_ref()}
    assert {:error, :invalid_approval} = SpectreMorph.activate(forged)
    assert Agent.get(target, & &1.applications) == []
  end

  test "candidate binding rejects changed operations or evidence", %{target: target} do
    approved = target |> proposal() |> SpectreMorph.evaluate() |> SpectreMorph.approve()
    assert {:error, :candidate_changed} = SpectreMorph.activate(%{approved | operations: []})

    assert {:error, :candidate_changed} =
             SpectreMorph.activate(%{approved | evidence: %{changed: true}})

    assert Agent.get(target, & &1.applications) == []
  end

  test "approval denial is not replaced by an actor audit label", %{target: target} do
    Agent.update(target, &%{&1 | approval_allowed?: false})
    change = target |> proposal() |> SpectreMorph.evaluate() |> SpectreMorph.approve()
    assert change.error == :not_authorized
    assert {:error, :not_authorized} = SpectreMorph.activate(change)
    assert Agent.get(target, & &1.applications) == []
  end

  test "replies cannot preseed approval or overwrite receipts from another stage", %{
    target: target
  } do
    approval = make_ref()

    evaluated =
      target
      |> proposal()
      |> using_reply(%{candidate: make_ref(), approval: approval, report: :evaluated})
      |> SpectreMorph.evaluate()

    assert evaluated.state == :evaluated
    assert evaluated.approval == nil

    original = target |> proposal() |> SpectreMorph.evaluate()

    approved =
      original
      |> using_reply(%{approval: approval, candidate: make_ref(), report: :overwritten})
      |> SpectreMorph.approve()

    assert approved.state == :approved
    assert approved.approval == approval
    assert approved.candidate == original.candidate
    assert approved.report == original.report
  end

  test "invalid audit labels and nonportable evidence never contact the backend", %{
    target: target
  } do
    for {options, expected} <- [
          {[reason: "Review"], {:required, :by}},
          {[by: "operator"], {:required, :reason}},
          {[by: "  ", reason: "Review"], {:required, :by}},
          {[by: "operator", reason: "  "], {:required, :reason}},
          {[by: "operator", reason: "Review", evidence: self()], :invalid_evidence}
        ] do
      change = SpectreMorph.change(target, Keyword.put(options, :adapter, MemoryAdapter))
      assert change.error == expected
    end

    assert %{error: :invalid_options} = SpectreMorph.change(target, %{})
    assert %{error: :invalid_options} = SpectreMorph.change(target, [:invalid])

    change =
      SpectreMorph.change(target,
        by: "operator",
        reason: "Review",
        evidence: %{runtime_pid: self()},
        adapter: MemoryAdapter
      )

    assert change.error != nil
    assert Agent.get(target, & &1.calls) == []
  end

  test "rejected candidates remain rejected even if the local stage is changed", %{target: target} do
    evaluated = target |> proposal() |> SpectreMorph.evaluate()
    approved = SpectreMorph.approve(evaluated)
    rejected = SpectreMorph.reject(evaluated)
    assert SpectreMorph.status(rejected) == %{state: :rejected, error: nil}
    assert {:error, :candidate_rejected} = SpectreMorph.activate(approved)
  end

  test "concurrent activation uses backend CAS once and rejects replay", %{target: target} do
    approved = target |> proposal() |> SpectreMorph.evaluate() |> SpectreMorph.approve()

    results =
      1..12
      |> Task.async_stream(fn _ -> SpectreMorph.activate(approved) end, max_concurrency: 12)
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :stale_revision})) == 11
    assert length(Agent.get(target, & &1.applications)) == 1
    assert {:error, :stale_revision} = SpectreMorph.activate(approved)
  end

  test "a lost activation reply is not automatically retried or applied twice", %{target: target} do
    approved = target |> proposal() |> SpectreMorph.evaluate() |> SpectreMorph.approve()
    uncertain = %{approved | adapter: LostReplyAdapter}

    assert {:error, {:adapter_exit, :reply_lost}} = SpectreMorph.activate(uncertain)
    state = Agent.get(target, & &1)
    assert length(state.applications) == 1
    assert Enum.count(state.calls, &match?({:activate, _, _}, &1)) == 1

    assert {:error, :stale_revision} = SpectreMorph.activate(uncertain)
    assert length(Agent.get(target, & &1.applications)) == 1
  end

  test "a reset session invalidates a draft even when its numeric revision is unchanged", %{
    target: target
  } do
    change = proposal(target)
    Agent.update(target, &%{&1 | revision: {make_ref(), 0}})
    assert %{error: :stale_revision} = SpectreMorph.evaluate(change)
  end

  test "invalid stages and empty proposals never request evaluation", %{target: target} do
    change = draft(target)
    assert %{error: :no_changes} = SpectreMorph.evaluate(change)
    assert %{error: {:invalid_stage, :evaluated, :draft}} = SpectreMorph.approve(change)
    assert {:error, {:invalid_stage, :approved, :draft}} = SpectreMorph.activate(change)
    assert Enum.map(Agent.get(target, & &1.calls), &elem(&1, 0)) == [:snapshot]
  end

  test "the first error stays sticky through every later stage", %{target: target} do
    failed = target |> draft() |> SpectreMorph.evaluate()

    repeated =
      failed
      |> SpectreMorph.mount_skill("refunds", skill())
      |> SpectreMorph.approve()
      |> SpectreMorph.reject()

    assert repeated.error == :no_changes
    assert {:error, :no_changes} = SpectreMorph.activate(repeated)
    assert Enum.map(Agent.get(target, & &1.calls), &elem(&1, 0)) == [:snapshot]
  end

  test "Spectre 0.4 bridge is explicitly unavailable and leaves the target untouched", %{
    target: target
  } do
    change = SpectreMorph.change(target, by: "operator:alice", reason: "Add support")
    assert change.error == :agent_server_evolution_unavailable
    assert {:error, :agent_server_evolution_unavailable} = SpectreMorph.activate(change)
    assert Agent.get(target, & &1.calls) == []
  end

  test "backend errors, exits and exceptions become explicit failures" do
    for {failure, expected} <- [
          error: :backend_refused,
          exit: {:adapter_exit, :backend_gone},
          exception: {:adapter_exception, RuntimeError},
          invalid: {:invalid_adapter_reply, :snapshot}
        ] do
      change =
        SpectreMorph.change(:unused,
          by: "operator",
          reason: "Review",
          adapter: FailingAdapter,
          adapter_options: [failure: failure]
        )

      assert change.error == expected
    end
  end

  test "missing and nil backend receipts cannot advance the workflow" do
    for action <- [:snapshot, :evaluate, :approve] do
      assert {:error, {:invalid_adapter_reply, ^action}} =
               Adapter.invoke(FailingAdapter, :unused, action, %{}, failure: {:reply, {:ok, %{}}})

      key = %{snapshot: :revision, evaluate: :candidate, approve: :approval}[action]

      assert {:error, {:invalid_adapter_reply, ^action}} =
               Adapter.invoke(FailingAdapter, :unused, action, %{},
                 failure: {:reply, {:ok, %{key => nil}}}
               )
    end
  end

  defp draft(target) do
    SpectreMorph.change(target,
      by: "operator:alice",
      reason: "Add refund help",
      adapter: MemoryAdapter
    )
  end

  defp proposal(target), do: target |> draft() |> SpectreMorph.mount_skill("refunds", skill())

  defp using_reply(change, reply) do
    %{change | adapter: FailingAdapter, adapter_options: [failure: {:reply, {:ok, reply}}]}
  end

  defp skill do
    %{
      id: "refunds",
      publisher_ref: "host:tests",
      declared_version: 1,
      prompt_budget: 64,
      applicability: %{scopes: ["support"], positive: ["refund"], negative: []},
      prompt_fragments: [
        %{id: "reply", content: "Refund help", token_cap: 32, budget_class: "small"}
      ],
      flows: [
        %{
          id: "support",
          routes: [
            %{
              label: "refund",
              match: %{kind: "exact", value: "refund"},
              handler: %{kind: "reply", prompt: "reply"}
            }
          ]
        }
      ]
    }
  end
end
