defmodule Obscura.Recognizer.PrivacyFilter.Native do
  @moduledoc """
  Optional native privacy-filter recognizer.

  This recognizer is never part of the default deterministic profile. Callers
  must pass a reusable `Obscura.PrivacyFilter.Serving` or enough checkpoint
  options for the serving to be built explicitly.
  """

  @behaviour Obscura.Recognizer

  alias Obscura.PrivacyFilter.LabelMap
  alias Obscura.PrivacyFilter.Serving

  @impl true
  def name, do: :privacy_filter_native

  @impl true
  def supported_entities, do: LabelMap.supported_entities()

  @doc """
  Builds a reusable native privacy-filter serving.
  """
  @spec new(keyword()) :: {:ok, Serving.t()} | {:error, term()}
  def new(opts), do: Serving.build(opts)

  @impl true
  def analyze(text, opts) when is_binary(text) and is_list(opts) do
    with {:ok, serving} <- serving(opts) do
      case Serving.run_with_timings(serving, text, opts) do
        {:ok, results, timings} ->
          emit_timings(opts, timings)
          {:ok, results}

        {:error, reason, timings} ->
          emit_timings(opts, timings)
          {:error, reason}
      end
    end
  end

  @impl true
  def analyze_many(texts, opts) when is_list(texts) and is_list(opts) do
    with {:ok, serving} <- serving(opts) do
      analyze_texts(texts, serving, opts)
    end
  end

  defp analyze_texts(texts, serving, opts) do
    texts
    |> Enum.reduce_while({:ok, []}, fn text, {:ok, acc} ->
      case Serving.run(serving, text, opts) do
        {:ok, results} -> {:cont, {:ok, [results | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> reverse_rows()
  end

  defp reverse_rows({:ok, rows}), do: {:ok, Enum.reverse(rows)}
  defp reverse_rows({:error, reason}), do: {:error, reason}

  defp serving(opts) do
    case Keyword.get(opts, :serving) do
      %Serving{} = serving -> {:ok, serving}
      nil -> Serving.build(opts)
      _other -> {:error, :unsupported_privacy_filter_serving}
    end
  end

  defp emit_timings(opts, timings) do
    recipient = Keyword.get(opts, :timing_recipient)
    ref = Keyword.get(opts, :timing_ref)

    if is_pid(recipient) and not is_nil(ref) do
      send(recipient, {:privacy_filter_serving_timings, ref, timings})
    end

    :ok
  end
end
