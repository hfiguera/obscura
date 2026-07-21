defmodule Obscura.Fixtures.CustomOperator do
  @moduledoc false

  @behaviour Obscura.Operator.Custom

  @impl Obscura.Operator.Custom
  def apply(_value, _context, %{replacement: replacement} = options)
      when is_binary(replacement) do
    {:ok, replacement, Map.get(options, :metadata, %{})}
  end

  def apply(_value, _context, _options), do: {:error, :invalid_fixture_options}
end
