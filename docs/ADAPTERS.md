# Adapters

`SpectreMorph.Adapter` is the package's single extension point. An adapter
connects proposal authoring to an authoritative application boundary; it does
not let authored content choose a backend, an actor, or a policy.

## One callback

```elixir
@callback call(target, action, request_map, opts) ::
            {:ok, map()} | {:error, term()}
```

`target` identifies the application-owned evolution target. `opts` is a trusted
host keyword list. Supported actions are `:snapshot`, `:evaluate`, `:approve`,
`:reject`, and `:activate`. Errors remain explicit rather than being converted
into successful stage transitions.

| Action | Required successful receipt |
| --- | --- |
| `:snapshot` | A map containing non-`nil` `:revision`. |
| `:evaluate` | A map containing non-`nil` `:candidate`; `:report` is optional. |
| `:approve` | A map containing non-`nil` `:approval`. |
| `:reject`, `:activate` | A map describing the result. |

Revision, candidate and approval values are opaque. The package preserves them;
their authenticity, immutability and meaning belong to the receiving boundary.
There is no imposed hash, signature format, storage provider or second journal.

## Request fields

Stages pass the fields available at that point:

| Field | Meaning |
| --- | --- |
| `:base` | The snapshot map, including its revision. |
| `:operations` | A list of core `Operation.to_data/1` maps. |
| `:by` | An attribution label; not an authenticated principal. |
| `:reason` | The stated purpose of the change. |
| `:evidence` | Supporting portable data; its meaning is verified by the boundary. |
| `:candidate` | The receipt returned by evaluation. |
| `:approval` | The receipt returned by approval. |

The snapshot stage has no prior base or candidate. Later stages must validate
that their receipts still apply to the original base and exact proposed change.

## Application adapter

A host can delegate the callback to its own implementation:

```elixir
defmodule MyApp.EvolutionAdapter do
  @behaviour SpectreMorph.Adapter

  @impl true
  def call(target, action, request, opts) do
    MyApp.EvolutionBoundary.call(target, action, request, opts)
  end
end
```

`MyApp.EvolutionBoundary` is application code, not a module supplied by this
package. It must enforce authentication, policy, evaluation requirements and
atomic activation with recovery. A test-only fake backend can return predictable
receipts to test a proposal flow; those receipts are not production approvals.

Select the adapter in trusted host configuration. Optional `:adapter_options`
are forwarded as a keyword list; options supplied for an individual stage are
merged over them, with stage values winning. This supports application controls
such as timeouts without putting provider configuration into authored payloads.
The adapter and authenticated actor must never be selected by model output.
Run expensive evaluation in existing task/worker infrastructure rather than in
an agent's coordinating callback. The package performs calls in its caller's
process and does not start another worker pool.

## Default Spectre adapter

`SpectreMorph.Adapters.Spectre` requires the proposed public
`Spectre.Server.Evolution` contract, version `1`. On Spectre 0.4.0 it returns
`{:error, :agent_server_evolution_unavailable}` because that bridge is absent.
It does not send undocumented messages to a Server or invoke `Spectre.Morph`.

The proposed boundary and its remaining core responsibilities are documented in
[AgentServer bridge proposal](CORE_0_4_1.md). Supporting a compatible future core
release requires no separate adapter registry or plugin framework.
