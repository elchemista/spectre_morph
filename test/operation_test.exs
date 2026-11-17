defmodule SpectreMorph.OperationTest do
  use ExUnit.Case, async: true

  alias Spectre.Governance.ChangeSet.Operation, as: CoreOperation
  alias Spectre.Skill.Definition
  alias SpectreMorph.Operation

  test "mount and replacement preserve normalized runtime attributes for the Composer" do
    for type <- [:mount_skill, :replace_skill] do
      assert {:ok, %CoreOperation{} = operation} = Operation.new(type, "returns", skill())
      data = CoreOperation.to_data(operation)
      assert data["type"] == Atom.to_string(type)

      assert Map.keys(data["payload"]) |> Enum.sort() ==
               ["bindings", "definition", "mount_id", "opts"]

      assert data["payload"]["mount_id"] == "returns"
      assert data["payload"]["bindings"] == %{}
      assert data["payload"]["opts"] == %{}
      assert data["payload"]["definition"]["id"] == "returns"
      refute Map.has_key?(data["payload"]["definition"], "canonical")
      assert {:ok, _} = Definition.new(data["payload"]["definition"])
    end
  end

  test "keyword attributes and plain maps describe the same operation" do
    assert {:ok, expected} = Operation.new(:mount_skill, "returns", skill())
    assert {:ok, ^expected} = Operation.new(:mount_skill, "returns", Map.to_list(skill()))
  end

  test "disable carries only the stable mount identifier" do
    assert {:ok, operation} = Operation.new(:disable_skill, "returns")

    assert CoreOperation.to_data(operation) == %{
             "type" => "disable_skill",
             "payload" => %{"mount_id" => "returns"}
           }

    assert {:error, :disable_skill_does_not_accept_definition} =
             Operation.new(:disable_skill, "returns", skill())
  end

  test "mount identifiers must be nonempty binaries" do
    for mount_id <- [nil, "", :returns, 12, %{}, []] do
      assert {:error, {:invalid_morph_mount_id, ^mount_id}} =
               Operation.new(:disable_skill, mount_id)
    end
  end

  test "canonical type strings work without admitting unknown operation types or creating atoms" do
    assert {:ok, %CoreOperation{type: "disable_skill"}} =
             Operation.new("disable_skill", "returns")

    type = "unsupported_morph_" <> Integer.to_string(System.unique_integer([:positive]))
    assert_raise ArgumentError, fn -> String.to_existing_atom(type) end
    assert {:error, {:unsupported_morph_operation, ^type}} = Operation.new(type, "returns")
    assert_raise ArgumentError, fn -> String.to_existing_atom(type) end
    assert {:error, _} = Operation.new(nil, "returns")
  end

  test "plain but invalid definitions are checked by the existing Skill contract" do
    assert {:error, {:unknown_runtime_skill_fields, ["unexpected"]}} =
             Operation.new(:mount_skill, "returns", Map.put(skill(), :unexpected, true))

    for attrs <- [nil, %{}, [], ["not keyword attributes"], %{id: "returns", flows: :invalid}] do
      assert {:error, _} = Operation.new(:replace_skill, "returns", attrs)
    end
  end

  test "compiled definitions, modules, callbacks and quoted code remain inert rejected input" do
    assert {:ok, definition} = Definition.new(skill())

    for invalid <- [
          definition,
          Spectre.Skill.Definition,
          fn -> flunk("authored code must not run") end,
          quote(do: send(self(), :authored_code)),
          Map.put(skill(), :metadata, %{callback: fn -> :private end})
        ] do
      assert {:error, _} = Operation.new(:mount_skill, "returns", invalid)
    end

    refute_receive :authored_code
  end

  defp skill do
    %{
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
  end
end
