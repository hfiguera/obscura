defmodule Obscura.LLM.Message do
  @moduledoc """
  Provider-independent message helpers.
  """

  @doc """
  Returns a normalized role for atom-keyed or string-keyed message maps.
  """
  @spec role(map()) :: atom() | String.t() | nil
  def role(message) when is_map(message) do
    Map.get(message, :role, Map.get(message, "role"))
  end

  @doc """
  Returns string content for atom-keyed or string-keyed message maps.
  """
  @spec content(map()) :: String.t() | nil
  def content(message) when is_map(message) do
    Map.get(message, :content, Map.get(message, "content"))
  end

  @doc """
  Puts content back into the same message key style.
  """
  @spec put_content(map(), String.t()) :: map()
  def put_content(message, content) when is_map(message) and is_binary(content) do
    cond do
      Map.has_key?(message, :content) -> Map.put(message, :content, content)
      Map.has_key?(message, "content") -> Map.put(message, "content", content)
      true -> message
    end
  end

  @doc """
  Returns true if the message role is included in configured roles.
  """
  @spec role_selected?(map(), [atom() | String.t()]) :: boolean()
  def role_selected?(message, roles) do
    role = role(message)
    normalized = normalize_role(role)
    Enum.any?(roles, &(normalize_role(&1) == normalized))
  end

  defp normalize_role(nil), do: nil
  defp normalize_role(role) when is_atom(role), do: Atom.to_string(role)
  defp normalize_role(role) when is_binary(role), do: role
end
