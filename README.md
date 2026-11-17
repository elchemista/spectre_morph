# Spectre Morph

Prepare, evaluate and request activation of declarative Skill changes for a
Spectre agent. The host chooses the review policy and required approvals.
Spectre remains responsible for authority and the running agent's lifecycle.

**Preparation status:** the proposal builder uses released Spectre 0.4 data
contracts. Live AgentServer evolution requires a proposed core extension that
is not present in 0.4.0. This repository prepares that integration; it does not
modify Spectre or replace its existing `Spectre.Morph` API.

[Adapter contract](docs/ADAPTERS.md) ·
[Proposed core integration](docs/CORE_0_4_1.md)

## Architecture

```text
Host or agent proposes a Skill change
                  │
           SpectreMorph
    build inert operations / review workflow
                  │
        host-selected Adapter.call/4
                  │
       Future AgentServer boundary
    authenticate / evaluate / approve / activate
                  │
   existing Definition store, Skill lifecycle and GAM
```

The package adds no supervised process, journal or storage backend. Drafts are
ordinary values in the calling task. Evaluation, approval and activation are
separate requests; the runtime owns their durable records and final decision.

## Install the local preparation

```elixir
# In the host application's mix.exs:
{:spectre_morph, path: "../spectre_morph"}
```

The package depends on `spectre ~> 0.4.0` to reuse its Skill and governance
operation validators. A compatible future 0.4 patch can provide the missing
runtime boundary. No core changes are applied by this package.

## Build a proposal today

A Skill is declarative data validated by `Spectre.Skill.Definition`. It can
reference operations already registered by the host; it cannot carry a new
executable module or callback.

```elixir
skill = %{
  id: "returns",
  declared_version: 1,
  publisher_ref: "host:shop",
  applicability: %{scopes: ["support"], positive: ["returns"], negative: []},
  prompt_fragments: [
    %{id: "reply", content: "Returns are accepted within 30 days.", token_cap: 32}
  ],
  flows: [
    %{
      id: "support",
      routes: [
        %{
          label: "returns",
          match: %{kind: "exact", value: "returns"},
          handler: %{kind: "reply", prompt: "reply"}
        }
      ]
    }
  ]
}

{:ok, operation} = SpectreMorph.Operation.new(:mount_skill, "returns", skill)
Spectre.Governance.ChangeSet.Operation.to_data(operation)
```

This builds an inert operation; it neither mounts a Skill nor grants authority.
Run the complete [proposal example](examples/build_proposal.exs):

```sh
mix deps.get
mix run examples/build_proposal.exs
```

## Workflow with an evolution-capable runtime

The following API is prepared for a compatible runtime adapter. The default
adapter reports `:agent_server_evolution_unavailable` on Spectre 0.4.0.
A custom application adapter can exercise the same workflow today.

```elixir
# `server` is the host-owned target, and `skill` is the data built above.
change =
  server
  |> SpectreMorph.change(by: "operator:alice", reason: "Add returns guidance")
  |> SpectreMorph.mount_skill("returns", skill)
  |> SpectreMorph.evaluate()
  |> SpectreMorph.approve(by: "reviewer:bob")

case SpectreMorph.activate(change) do
  {:ok, result} -> result
  {:error, reason} -> {:error, reason}
end
```

`by:` attributes the request; it does not authenticate the actor. The runtime
must authenticate the caller, verify the exact candidate and any required
approval, and compare the current revision before activation. Application
policy decides whether a human, a trusted host policy or additional evaluation
is required. Calling `approve/2` does not itself establish that authority.

Use `replace_skill(change, mount_id, definition)` or
`disable_skill(change, mount_id)` for the other supported mutations. The
receiving runtime verifies that the target can be changed and that permissions
are not expanded. This initial API authors runtime Skill data; arbitrary
compiled Server code is outside its scope.

A draft becomes locally `:evaluated`, `:approved` or `:rejected` only after a
successful adapter response. The first error is preserved through the pipeline.
`SpectreMorph.status/1` reports that local workflow state, not the live agent's
activation status. Keep the transient Change outside Server assigns and
checkpoints; it contains a runtime address and trusted adapter options.

### Select an application adapter

```elixir
change = SpectreMorph.change(server,
  adapter: MyApp.EvolutionAdapter,
  adapter_options: [timeout: 5_000],
  by: "operator:alice",
  reason: "Add returns guidance")
```

The host configures the adapter and policy. A model may supply proposed Skill
data; it must not select the adapter or authenticated reviewer. See
[Adapters](docs/ADAPTERS.md) for the single callback and receipt shapes.

### Current core capability

```elixir
SpectreMorph.Adapters.Spectre.available?()
# false on Spectre 0.4.0
```

The default adapter checks for a versioned public core capability before
contacting the target. It does not send undocumented Server messages, inspect
private process state or start an Instance as a hidden fallback.

The [core integration proposal](docs/CORE_0_4_1.md) records the remaining work:
revision fencing, authoritative review and approval, Skill lifecycle updates,
busy handling and recovery through existing core storage and GAM contracts.
These require real core integration tests when the bridge is implemented.

## Development

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix credo --strict
mix dialyzer
mix docs --warnings-as-errors
```

Tests use the released core data validators and an explicitly test-only runtime
adapter. They cover proposal construction, stage errors, stale revisions,
forged receipts and concurrent activation. They do not claim AgentServer
activation works on the unmodified Spectre 0.4 runtime.
