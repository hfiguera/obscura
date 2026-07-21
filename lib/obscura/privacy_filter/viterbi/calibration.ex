defmodule Obscura.PrivacyFilter.Viterbi.Calibration do
  @moduledoc false

  @keys [
    "transition_bias_background_stay",
    "transition_bias_background_to_start",
    "transition_bias_inside_to_continue",
    "transition_bias_inside_to_end",
    "transition_bias_end_to_background",
    "transition_bias_end_to_start"
  ]

  @spec load(Path.t()) :: {:ok, map()} | {:error, term()}
  def load(path) when is_binary(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, payload} <- Jason.decode(contents),
         do: parse(payload)
  end

  @spec parse(map()) :: {:ok, map()} | {:error, term()}
  def parse(%{"operating_points" => %{"default" => %{"biases" => biases}}})
      when is_map(biases) do
    actual = biases |> Map.keys() |> Enum.sort()

    if actual == Enum.sort(@keys) do
      Enum.reduce_while(biases, {:ok, %{}}, &parse_bias/2)
    else
      {:error, {:invalid_viterbi_calibration_keys, actual, Enum.sort(@keys)}}
    end
  end

  def parse(_payload), do: {:error, :invalid_viterbi_calibration_artifact}

  defp parse_bias({key, value}, {:ok, acc}) when is_number(value) and not is_boolean(value),
    do: {:cont, {:ok, Map.put(acc, String.to_atom(key), :erlang.float(value))}}

  defp parse_bias({key, value}, {:ok, _acc}),
    do: {:halt, {:error, {:invalid_viterbi_bias, key, value}}}
end
