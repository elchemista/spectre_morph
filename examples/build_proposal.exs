# Run with: mix run examples/build_proposal.exs
# Builds data using released Spectre 0.4 contracts. It changes no running agent.
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
IO.inspect(Spectre.Governance.ChangeSet.Operation.to_data(operation), label: "Proposed operation")
IO.inspect(SpectreMorph.Adapters.Spectre.available?(), label: "AgentServer bridge available?")
