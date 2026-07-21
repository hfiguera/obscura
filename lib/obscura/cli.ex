defmodule Obscura.CLI do
  @moduledoc """
  Shared helpers for Phase 5 Mix task workflows.
  """

  alias Obscura.Anonymizer.Error, as: AnonymizerError
  alias Obscura.Diagnostic
  alias Obscura.Eval.Profile
  alias Obscura.Telemetry

  @config_example """
  # Obscura is library-first. Stable profiles are local and never download
  # model assets during analysis.

  import Config

  config :obscura,
    default_profile: :fast,
    profiles: %{
      fast: [
        entities: [:email, :phone, :credit_card, :us_ssn, :iban, :ip_address, :url, :domain]
      ],
      balanced: [
        entities: [:person, :location, :organization, :email, :phone]
      ]
    }
  """

  @doc """
  Runs detection and returns a safe map for CLI output.
  """
  @spec detect(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def detect(text, opts) when is_binary(text) and is_list(opts) do
    profile = Keyword.get(opts, :profile, :regex_only)
    start = System.monotonic_time()

    analyze_opts =
      opts
      |> analyzer_opts(profile)
      |> Keyword.put(:include_text, Keyword.get(opts, :include_text, false))

    with {:ok, results} <- Obscura.analyze(text, analyze_opts) do
      output = %{
        status: "ok",
        profile: Atom.to_string(profile),
        results: Enum.map(results, &safe_result(&1, Keyword.get(opts, :include_text, false))),
        latency_ms: elapsed_ms(start)
      }

      emit(:detect, opts, output)
      {:ok, output}
    end
  end

  @doc """
  Runs redaction and returns the redacted text plus safe item metadata.
  """
  @spec redact(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def redact(text, opts) when is_binary(text) and is_list(opts) do
    profile = Keyword.get(opts, :profile, :regex_only)
    start = System.monotonic_time()

    redact_opts =
      opts
      |> analyzer_opts(profile)
      |> Keyword.put(:include_text, Keyword.get(opts, :include_text, false))

    with {:ok, result} <- Obscura.redact(text, redact_opts) do
      output = %{
        status: "ok",
        profile: Atom.to_string(profile),
        text: result.text,
        items: Enum.map(result.items, &safe_item/1),
        latency_ms: elapsed_ms(start)
      }

      emit(:redact, opts, output)
      {:ok, output}
    end
  end

  @doc """
  Returns a safe config example.
  """
  @spec config_example() :: String.t()
  def config_example, do: @config_example

  @doc """
  Reads CLI input from stdin or a file path.
  """
  @spec read_input!(String.t() | nil, keyword()) :: String.t()
  def read_input!(path, opts) do
    if Keyword.get(opts, :stdin, false) do
      IO.read(:stdio, :eof)
    else
      read_file!(path)
    end
  end

  @doc """
  Parses a profile string for Mix tasks.
  """
  @spec profile!(String.t()) :: atom()
  def profile!(profile) do
    case Profile.from_string(profile) do
      {:ok, profile} -> profile
      {:error, {:unknown_profile, _other}} -> Mix.raise("Unknown profile.")
    end
  end

  @doc """
  Builds analyzer options from CLI flags.
  """
  @spec analyzer_opts(keyword(), atom()) :: keyword()
  def analyzer_opts(opts, profile) do
    [
      profile: profile,
      entities: Keyword.get(opts, :entities, Profile.supported_entities(profile)),
      recognizer_timeout: Keyword.get(opts, :timeout, 5_000),
      telemetry: Keyword.get(opts, :telemetry, true)
    ]
    |> Keyword.merge(
      Keyword.take(opts, [
        :profile_runtime,
        :serving,
        :servings,
        :primary_serving,
        :location_serving,
        :privacy_filter_serving,
        :ner,
        :built_ins,
        :recognizers,
        :parallel_recognizers,
        :phone_parser,
        :phone_validator,
        :phone_regions,
        :nlp_engine,
        :nlp_engine_opts
      ])
    )
  end

  @doc """
  Formats a structured diagnostic or legacy reason for Mix task output.
  """
  @spec format_error(term()) :: String.t()
  def format_error(%Diagnostic{} = diagnostic), do: Diagnostic.format(diagnostic)
  def format_error(%AnonymizerError{} = error), do: Exception.message(error)
  def format_error(reason) when is_atom(reason), do: Atom.to_string(reason)

  def format_error(reason) when is_tuple(reason) and tuple_size(reason) > 0 do
    case elem(reason, 0) do
      code when is_atom(code) -> Atom.to_string(code)
      _value -> "operation_failed"
    end
  end

  def format_error(_reason), do: "operation_failed"

  defp read_file!(nil), do: Mix.raise("Expected a file path or --stdin")

  defp read_file!(path) do
    case File.read(path) do
      {:ok, text} -> text
      {:error, reason} -> Mix.raise("Could not read input file: #{reason}")
    end
  end

  defp safe_result(result, include_text?) do
    %{
      entity: Atom.to_string(result.entity),
      start: result.byte_start,
      end: result.byte_end,
      score: result.score,
      recognizer: stringify(result.recognizer),
      source_entity: result.source_entity
    }
    |> maybe_put_text(result.text, include_text?)
  end

  defp safe_item(item) do
    %{
      entity: Atom.to_string(item.entity),
      operator: Atom.to_string(item.operator),
      source_byte_start: item.source_byte_start,
      source_byte_end: item.source_byte_end,
      replacement_byte_start: item.replacement_byte_start,
      replacement_byte_end: item.replacement_byte_end,
      replacement: item.replacement
    }
  end

  defp maybe_put_text(map, text, true), do: Map.put(map, :text, text)
  defp maybe_put_text(map, _text, false), do: map

  defp stringify(nil), do: nil
  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value), do: to_string(value)

  defp emit(kind, opts, output) do
    Telemetry.execute(
      Keyword.get(opts, :telemetry, true),
      [:obscura, :cli, kind, :stop],
      %{latency_ms: output.latency_ms},
      %{
        status: :ok,
        profile: output.profile,
        result_count: length(Map.get(output, :results, Map.get(output, :items, [])))
      }
    )
  end

  defp elapsed_ms(start) do
    System.monotonic_time()
    |> Kernel.-(start)
    |> System.convert_time_unit(:native, :microsecond)
    |> Kernel./(1000)
  end
end
