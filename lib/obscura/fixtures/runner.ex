defmodule Obscura.Fixtures.Runner do
  @moduledoc """
  Runs fixtures against real Obscura adapters or explicit placeholder adapters.
  """

  alias Obscura.Eval.Metrics
  alias Obscura.Eval.Offset
  alias Obscura.Eval.Report
  alias Obscura.Fixtures.ContextAdapter
  alias Obscura.Fixtures.LLMAdapter
  alias Obscura.Fixtures.Loader
  alias Obscura.Fixtures.NERAdapter
  alias Obscura.Fixtures.NLPAdapter
  alias Obscura.Fixtures.ObscuraAnalyzerAdapter
  alias Obscura.Fixtures.ObscuraOperatorAdapter
  alias Obscura.Fixtures.PlaceholderAnalyzer
  alias Obscura.Fixtures.PlaceholderOperator
  alias Obscura.Fixtures.StreamAdapter
  alias Obscura.Fixtures.StructuredAdapter
  alias Obscura.Fixtures.VaultAdapter

  @doc """
  Runs fixtures and returns a report map.
  """
  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) do
    suite = Keyword.get(opts, :suite)
    profile = Keyword.get(opts, :profile) || default_profile(suite)

    with {:ok, fixtures} <- Loader.load_all(suite: suite),
         fixtures <- filter_fixtures(fixtures, opts),
         results <- execute(fixtures, opts),
         metrics <- metrics(results, profile),
         report <- build_report(fixtures, metrics, profile, opts) do
      {:ok, report}
    end
  end

  @doc """
  Runs fixtures and writes the Phase 3 fixture smoke reports.
  """
  @spec write_smoke_report(keyword()) :: :ok | {:error, term()}
  def write_smoke_report(opts \\ []) do
    with {:ok, report} <- run(opts) do
      run_id = report.run_id

      Report.write_pair(
        report,
        "eval/reports/#{run_id}.json",
        "eval/reports/#{run_id}.md"
      )
    end
  end

  defp filter_fixtures(fixtures, opts) do
    fixtures
    |> filter_by_entity(Keyword.get(opts, :entity))
    |> filter_by_tag(Keyword.get(opts, :tag))
  end

  defp filter_by_entity(fixtures, nil), do: fixtures

  defp filter_by_entity(fixtures, entity) do
    Enum.filter(fixtures, fn
      %{kind: :analyzer, entities: entities} -> Enum.any?(entities, &match_filter?(&1, entity))
      %{kind: :operator, spans: spans} -> Enum.any?(spans, &match_filter?(&1.entity, entity))
      %{kind: :context, entities: entities} -> Enum.any?(entities, &match_filter?(&1, entity))
      %{kind: :structured} -> false
      %{kind: :vault} -> false
      %{kind: :llm} -> false
      %{kind: :stream} -> false
      %{kind: :nlp, entities: entities} -> Enum.any?(entities, &match_filter?(&1, entity))
      %{kind: :ner, entities: entities} -> Enum.any?(entities, &match_filter?(&1, entity))
    end)
  end

  defp filter_by_tag(fixtures, nil), do: fixtures

  defp filter_by_tag(fixtures, tag),
    do:
      Enum.filter(
        fixtures,
        &Enum.any?(&1.tags, fn fixture_tag -> match_filter?(fixture_tag, tag) end)
      )

  defp match_filter?(value, filter) when is_atom(value) and is_binary(filter),
    do: Atom.to_string(value) == filter

  defp match_filter?(value, filter), do: value == filter

  defp execute(fixtures, opts) do
    Enum.map(fixtures, fn
      %{kind: :analyzer} = fixture -> execute_analyzer(fixture, opts)
      %{kind: :operator} = fixture -> execute_operator(fixture, opts)
      %{kind: :structured} = fixture -> execute_structured(fixture)
      %{kind: :context} = fixture -> execute_context(fixture)
      %{kind: :vault} = fixture -> execute_vault(fixture)
      %{kind: :llm} = fixture -> execute_llm(fixture)
      %{kind: :stream} = fixture -> execute_stream(fixture)
      %{kind: :nlp} = fixture -> execute_nlp(fixture)
      %{kind: :ner} = fixture -> execute_ner(fixture)
    end)
  end

  defp execute_analyzer(fixture, opts) do
    adapter = analyzer_adapter(opts)
    start = System.monotonic_time()

    {:ok, predictions} =
      adapter.analyze(fixture.text, entities: fixture.entities, profile: fixture.profile)

    elapsed = elapsed_ms(start)

    %{
      fixture: fixture,
      expected: fixture.expected,
      predicted: predictions,
      latency_ms: elapsed,
      status: :ran
    }
  end

  defp execute_operator(fixture, opts) do
    adapter = operator_adapter(opts)
    start = System.monotonic_time()
    {:ok, result} = adapter.anonymize(fixture.text, fixture.spans, fixture.operators, [])
    elapsed = elapsed_ms(start)

    %{
      fixture: fixture,
      expected: [],
      predicted: [],
      operator_result: result,
      latency_ms: elapsed,
      status: Map.get(result, :status, :ran)
    }
  end

  defp execute_structured(fixture) do
    start = System.monotonic_time()
    {:ok, result} = StructuredAdapter.redact(fixture.input, fixture.opts)
    elapsed = elapsed_ms(start)

    %{
      fixture: fixture,
      expected: [],
      predicted: [],
      structured_result: result,
      latency_ms: elapsed,
      status: if(result.data == fixture.expected_data, do: :ran, else: :failed)
    }
  end

  defp execute_context(fixture) do
    start = System.monotonic_time()
    {:ok, result} = ContextAdapter.run(fixture)
    elapsed = elapsed_ms(start)

    %{
      fixture: fixture,
      expected: [expected_context_span(fixture)],
      predicted:
        if(is_nil(result.with_context),
          do: [],
          else: [to_span(fixture.text_with_context, result.with_context)]
        ),
      context_result: result,
      latency_ms: elapsed,
      status: context_status(fixture, result)
    }
  end

  defp execute_vault(fixture) do
    start = System.monotonic_time()
    {:ok, result} = VaultAdapter.run(fixture)
    elapsed = elapsed_ms(start)

    %{
      fixture: fixture,
      expected: [],
      predicted: [],
      vault_result: Map.drop(result, [:vault]),
      latency_ms: elapsed,
      status:
        if(
          result.tokens == fixture.expected_tokens and
            result.rehydrated == fixture.expected_rehydrated,
          do: :ran,
          else: :failed
        )
    }
  end

  defp execute_llm(fixture) do
    start = System.monotonic_time()
    {:ok, result} = LLMAdapter.run(fixture)
    elapsed = elapsed_ms(start)

    %{
      fixture: fixture,
      expected: [],
      predicted: [],
      llm_result: Map.drop(result, [:vault]),
      latency_ms: elapsed,
      status:
        if(
          result.messages == fixture.expected_messages and
            result.rehydrated_response == fixture.expected_rehydrated_response,
          do: :ran,
          else: :failed
        )
    }
  end

  defp execute_stream(fixture) do
    start = System.monotonic_time()
    {:ok, result} = StreamAdapter.run(fixture)
    elapsed = elapsed_ms(start)

    %{
      fixture: fixture,
      expected: [],
      predicted: [],
      stream_result: Map.drop(result, [:vault]),
      latency_ms: elapsed,
      status:
        if(result.chunks == fixture.expected_chunks and result.output == fixture.expected_output,
          do: :ran,
          else: :failed
        )
    }
  end

  defp execute_nlp(fixture) do
    start = System.monotonic_time()
    {:ok, result} = NLPAdapter.run(fixture)
    elapsed = elapsed_ms(start)

    %{
      fixture: fixture,
      expected: fixture.expected,
      predicted: result.predicted,
      nlp_result: Map.drop(result, [:predicted]),
      latency_ms: elapsed,
      status: :ran
    }
  end

  defp execute_ner(fixture) do
    start = System.monotonic_time()
    {:ok, result} = NERAdapter.run(fixture)
    elapsed = elapsed_ms(start)

    %{
      fixture: fixture,
      expected: fixture.expected,
      predicted: result.predicted,
      ner_result: Map.drop(result, [:predicted]),
      latency_ms: elapsed,
      status: :ran
    }
  end

  defp metrics(results, profile) do
    Metrics.score_results(results, profile)
  end

  defp build_report(fixtures, metrics, profile, opts) do
    suite = Keyword.get(opts, :suite) || :all
    adapter = Keyword.get(opts, :adapter, :obscura)

    Report.build(
      run_id: run_id(adapter, suite),
      phase: phase(adapter, suite),
      adapter: adapter_name(adapter, suite),
      profile: profile,
      dataset: %{
        name: "#{phase(adapter, suite)}_fixtures",
        source: "fixtures",
        version: phase(adapter, suite),
        sample_count: length(fixtures),
        smoke: true,
        suite: to_string(suite)
      },
      metrics: metrics,
      limitations: limitations(adapter, suite)
    )
  end

  defp analyzer_adapter(opts), do: Keyword.get(opts, :analyzer_adapter, default_analyzer(opts))
  defp operator_adapter(opts), do: Keyword.get(opts, :operator_adapter, default_operator(opts))

  defp default_analyzer(opts) do
    if Keyword.get(opts, :adapter, :obscura) == :placeholder do
      PlaceholderAnalyzer
    else
      ObscuraAnalyzerAdapter
    end
  end

  defp default_operator(opts) do
    if Keyword.get(opts, :adapter, :obscura) == :placeholder do
      PlaceholderOperator
    else
      ObscuraOperatorAdapter
    end
  end

  defp run_id(:placeholder, _suite), do: "phase_0_fixture_smoke"
  defp run_id(_adapter, :nlp), do: "phase_4_nlp_smoke"
  defp run_id(_adapter, :ner), do: "phase_4_ner_smoke"
  defp run_id(_adapter, :vault), do: "phase_3_vault_smoke"
  defp run_id(_adapter, :llm), do: "phase_3_llm_smoke"
  defp run_id(_adapter, :stream), do: "phase_3_stream_smoke"
  defp run_id(_adapter, :accuracy), do: "phase_4_accuracy_fixture_smoke"
  defp run_id(_adapter, _suite), do: "phase_4_fixture_smoke"

  defp phase(:placeholder, _suite), do: "phase_0"
  defp phase(_adapter, suite) when suite in [:vault, :llm, :stream], do: "phase_3"
  defp phase(_adapter, _suite), do: "phase_4"

  defp adapter_name(:placeholder, _suite), do: "Obscura.Fixtures.PlaceholderAnalyzer"
  defp adapter_name(_adapter, _suite), do: "Obscura.Fixtures.ObscuraAnalyzerAdapter"

  defp default_profile(suite) when suite in [:vault, :llm, :stream], do: :regex_only
  defp default_profile(:accuracy), do: :deterministic_plus
  defp default_profile(_suite), do: :nlp

  defp limitations(:placeholder, _suite) do
    [
      "Results generated by placeholder adapters.",
      "Phase 0 reports harness behavior, not product accuracy."
    ]
  end

  defp limitations(_adapter, suite) when suite in [:vault, :llm, :stream] do
    [
      "Phase 3 uses deterministic recognizers plus vault-backed pseudonymization.",
      "Vaults intentionally hold raw values in memory for explicit rehydration.",
      "Unsupported NER/open-class entities are reported separately for deterministic profiles."
    ]
  end

  defp limitations(_adapter, :accuracy) do
    [
      "Accuracy fixtures exercise real deterministic recognizers, not fake NER outputs.",
      "The deterministic_plus profile is context-limited and is not broad Presidio parity.",
      "External-service recognizers, image, document, and full PHI features are out of scope."
    ]
  end

  defp limitations(_adapter, _suite) do
    [
      "Phase 4 uses deterministic recognizers, vault-backed pseudonymization, and fake-serving NER fixtures.",
      "Phase 4 NER fixture reports use deterministic fake serving, not real model accuracy.",
      "Vaults intentionally hold raw values in memory for explicit rehydration.",
      "External-service recognizers, image, document, and full PHI features are out of scope."
    ]
  end

  defp expected_context_span(fixture) do
    {byte_start, _length} = :binary.match(fixture.text_with_context, fixture.expected_value)

    %{
      entity: fixture.expected_entity,
      byte_start: byte_start,
      byte_end: byte_start + byte_size(fixture.expected_value),
      value: fixture.expected_value,
      source_entity: Atom.to_string(fixture.expected_entity),
      metadata: %{}
    }
  end

  defp to_span(text, result) do
    {:ok, char_start} = Offset.byte_to_char(text, result.byte_start)
    {:ok, char_end} = Offset.byte_to_char(text, result.byte_end)

    %{
      entity: result.entity,
      byte_start: result.byte_start,
      byte_end: result.byte_end,
      char_start: char_start,
      char_end: char_end,
      value: result.text,
      source_entity: result.source_entity,
      metadata: result.metadata
    }
  end

  defp context_status(fixture, result) do
    with false <- is_nil(result.with_context),
         false <- is_nil(result.without_context),
         true <- result.with_context.score > result.without_context.score,
         true <- context_words_recorded?(fixture, result.with_context) do
      :ran
    else
      _other -> :failed
    end
  end

  defp context_words_recorded?(fixture, result) do
    recorded =
      result.explanation
      |> Map.get(:context_words, [])
      |> Enum.map(&String.downcase/1)

    fixture.expected_context_words
    |> Enum.map(&String.downcase/1)
    |> Enum.all?(&(&1 in recorded))
  end

  defp elapsed_ms(start) do
    System.monotonic_time()
    |> Kernel.-(start)
    |> System.convert_time_unit(:native, :microsecond)
    |> Kernel./(1000)
  end
end
