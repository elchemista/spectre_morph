defmodule SpectreMorph.Operation do
  @moduledoc "Builds inert Skill changes using Spectre's existing data contracts."

  alias Spectre.Governance.ChangeSet.Operation, as: CoreOperation
  alias Spectre.Skill.Definition

  @skill_types ["mount_skill", "replace_skill"]
  @type operation_type :: :mount_skill | :replace_skill | :disable_skill

  @doc """
  Builds a mount, replacement or disable operation without publishing or applying it.

  Mounts and replacements accept runtime Skill attributes as a plain map or
  keyword list. Core normalizes the transport payload before validating the
  nested Skill definition. Compiled modules, structs and executable data are
  not accepted. Disable operations take only the mount identifier.
  """
  @spec new(operation_type() | String.t(), String.t(), map() | keyword() | nil) ::
          {:ok, CoreOperation.t()} | {:error, term()}
  def new(type, mount_id, definition \\ nil)

  def new(type, mount_id, definition) when is_binary(mount_id) and mount_id != "" do
    with {:ok, operation} <-
           CoreOperation.new(%{type: type, payload: payload(type, mount_id, definition)}) do
      validate(operation)
    end
  end

  def new(_type, mount_id, _definition), do: {:error, {:invalid_morph_mount_id, mount_id}}

  defp payload(type, mount_id, definition) do
    if type in [:disable_skill, "disable_skill"] and is_nil(definition) do
      %{"mount_id" => mount_id}
    else
      %{
        "mount_id" => mount_id,
        "definition" => attributes(definition),
        "bindings" => %{},
        "opts" => %{}
      }
    end
  end

  defp attributes(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs), do: Map.new(attrs), else: attrs
  end

  defp attributes(attrs), do: attrs

  defp validate(%CoreOperation{type: type, payload: payload} = operation)
       when type in @skill_types do
    with {:ok, _definition} <- Definition.new(payload["definition"]), do: {:ok, operation}
  end

  defp validate(%CoreOperation{type: "disable_skill", payload: payload} = operation) do
    if Map.keys(payload) == ["mount_id"],
      do: {:ok, operation},
      else: {:error, :disable_skill_does_not_accept_definition}
  end

  defp validate(%CoreOperation{type: type}),
    do: {:error, {:unsupported_morph_operation, type}}
end
