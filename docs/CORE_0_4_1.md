# AgentServer bridge proposal

This document describes a proposed core extension. **Spectre 0.4.0 does not
provide this AgentServer bridge.** The filename names a possible patch target,
not a commitment that Spectre 0.4.1 will include the contract below.

`spectre_morph` prepares declarative changes and calls an adapter. It does not
start processes, retain a journal, own storage, or implement another authority
engine. A trusted application adapter can be developed and tested today; the
default adapter requires the future core bridge.

## Existing contracts reused

The package depends on `spectre ~> 0.4.0` and reuses its data contracts:

| Core module | Role |
| --- | --- |
| `Spectre.Skill.Definition` | Validates declarative runtime Skills. |
| `Spectre.Governance.ChangeSet.Operation` | Validates an operation and produces its portable `to_data/1` representation. |
| `Spectre.Canonical.Value` | Validates portable supporting evidence without a new codec. |

See the released [Skill definition](https://github.com/elchemista/spectre/blob/0.4.0/lib/spectre/skill/definition.ex)
and [operation contract](https://github.com/elchemista/spectre/blob/0.4.0/lib/spectre/governance/change_set/operation.ex).
An operation names a type registered by trusted host code; authored data cannot
choose an implementation module, function, evaluator, or policy.

The existing `Spectre.Morph` API in core remains unchanged. It belongs to the
retained Instance evolution path. The new package uses the `SpectreMorph`
namespace and does not silently redirect AgentServers to that legacy runtime.

## Proposed public entry point

The default adapter would call a core module with this public shape:

```elixir
# Proposed core API; absent from Spectre 0.4.0.
Spectre.Server.Evolution.contract_version() # => 1
Spectre.Server.Evolution.call(target, action, request, opts)
# => {:ok, result_map} | {:error, reason}
```

It checks that `contract_version/0` and `call/4` are exported and that the
contract version is exactly `1`. Without that match it returns
`{:error, :agent_server_evolution_unavailable}`. There is no private
`GenServer.call`, implicit legacy fallback, or automatic activation.

| Action | Successful result |
| --- | --- |
| `:snapshot` | `%{revision: opaque_non_nil_value}` plus optional boundary-owned fields. |
| `:evaluate` | `%{candidate: opaque_non_nil_value}` and optional `:report`. |
| `:approve` | `%{approval: opaque_non_nil_value}`. |
| `:reject` | A result map. |
| `:activate` | A result map. |

The request carries the stage's available `:base`, `:operations`, `:by`,
`:reason`, `:evidence`, `:candidate`, and `:approval`. `:base` is the returned
snapshot map; operations are core `Operation.to_data/1` maps. Candidate and
approval values are opaque boundary receipts, not values the caller invents.

## Core responsibilities

The future core implementation must authenticate the caller and resolve its
authority. A `:by` label in a request is attribution, **not authentication**.
Human approval is required when configured by the application's policy; the
package does not hardcode a universal human-approval requirement.

The snapshot revision must cover the evolution-relevant session, active
Definition, mount authority and resets. A checkpoint's write revision alone
cannot establish that the same agent definition and authority are still active.

Evaluation, approval and activation must refer to the same immutable candidate
and base. Core owns validation of evaluation results and approvals, stale-base
checks, authority ceilings, and the final activation decision. A model-generated
operation or an adapter receipt never grants authority on its own.

Activation must be fenced against concurrent activation and reset, recoverable
after a crash, and coordinated through existing core storage and GAM contracts.
Writing a Domain and a Server store does not by itself make their changes one
atomic database transaction. The bridge must define the actual durable commit
and recovery boundary before it can claim successful activation.

## Connect data-defined handlers to Server execution

Installing a Definition and updating routes is insufficient: AgentServer currently
dispatches to compiled Server callbacks. The bridge needs a data-Skill dispatch
path using `Spectre.Skill.Runtime.route/3` and `respond/4`. Their response kinds
must enter the existing Server lifecycle:

- Reply responses become ordinary Server responses.
- Operation requests enter the registered operation and Managed GAM path.
- Work responses reuse Execution materialization/runtime contracts and the
  existing operation executor, with exact Definition/program references and
  continuation state preserved in checkpoints.

The compatibility `Spectre.Runtime.SkillDispatch` handles replies; it is not a
complete AgentServer bridge. Evaluation must reject handler kinds the new bridge
does not support yet. Data-defined Skills must not generate compiled Server
modules or execute operation requests outside the registered admission path.

## Start with an idle boundary

The first implementation should return a busy result when relevant workers,
pending interactions or outbox work can still use an affected mount. This keeps
activation understandable without adding a draining or scheduling framework.
An application can retry after that work settles.

Rejection must not activate anything. An evaluation report is not approval;
approval is not proof of activation. Failed or uncertain activation must remain
distinguishable from an observed successful commit.

## What can be tested now

The package's test adapter exercises its request construction, stage order and
receipt handling. Those tests do not establish real AgentServer activation,
storage atomicity, crash recovery, or GAM authority enforcement. Such guarantees
need integration tests against an implementation of the proposed core boundary.

See [Adapters](ADAPTERS.md) for the small extension point and its trust boundary.
