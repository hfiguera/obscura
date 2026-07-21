defmodule Obscura.Recognizer.NER.FakeServing do
  @moduledoc """
  Deterministic fake NER serving used by fixtures and tests.

  The struct intentionally has a small `Inspect` representation so configured
  source texts or model outputs are not printed accidentally.
  """

  @enforce_keys [:outputs]
  defstruct [:outputs]

  @type t :: %__MODULE__{outputs: map() | list()}

  @doc """
  Creates a fake serving from either a text-to-outputs map or a single output list.
  """
  @spec new(map() | list()) :: t()
  def new(outputs) when is_map(outputs) or is_list(outputs), do: %__MODULE__{outputs: outputs}

  @doc """
  Returns fake model outputs for one text.
  """
  @spec predict(t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def predict(%__MODULE__{outputs: outputs}, text, _opts \\ []) when is_binary(text) do
    case outputs do
      outputs when is_list(outputs) -> {:ok, outputs}
      outputs when is_map(outputs) -> {:ok, Map.get(outputs, text, [])}
    end
  end

  @doc """
  Returns fake model outputs for many texts.
  """
  @spec predict_many(t(), [String.t()], keyword()) :: {:ok, [[map()]]} | {:error, term()}
  def predict_many(%__MODULE__{} = serving, texts, opts \\ []) when is_list(texts) do
    {:ok, Enum.map(texts, fn text -> serving |> predict(text, opts) |> elem(1) end)}
  end
end

defimpl Inspect, for: Obscura.Recognizer.NER.FakeServing do
  import Inspect.Algebra

  def inspect(_serving, _opts),
    do: concat(["#Obscura.Recognizer.NER.FakeServing<", "redacted", ">"])
end
