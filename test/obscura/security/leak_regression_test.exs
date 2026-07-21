defmodule Obscura.Security.LeakRegressionTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Obscura.Analyzer.Result
  alias Obscura.Anonymizer.Error
  alias Obscura.Diagnostic
  alias Obscura.NLP.Artifacts
  alias Obscura.PrivacyFilter.DetectedSpan
  alias Obscura.PrivacyFilter.SequenceLabeling
  alias Obscura.PrivacyFilter.Serving
  alias Obscura.Recognizer.PatternDefinition
  alias Obscura.Stream.Rehydrator
  alias Obscura.Vault
  alias Obscura.Vault.Memory

  @canary "OBSCURA-CANARY-7F4A@example.test"
  @derived_canary "derived-OBSCURA-CANARY-7F4A"

  defmodule LeakyRecognizer do
    @behaviour Obscura.Recognizer

    @impl Obscura.Recognizer
    def name, do: :leaky_recognizer

    @impl Obscura.Recognizer
    def supported_entities, do: [:email]

    @impl Obscura.Recognizer
    def analyze(_text, _opts), do: {:error, "OBSCURA-CANARY-7F4A@example.test"}
  end

  defmodule MalformedRecognizer do
    @behaviour Obscura.Recognizer

    @impl Obscura.Recognizer
    def name, do: :malformed_recognizer

    @impl Obscura.Recognizer
    def supported_entities, do: [:email]

    @impl Obscura.Recognizer
    def analyze(_text, _opts), do: {:ok, ["OBSCURA-CANARY-7F4A@example.test"]}

    @impl Obscura.Recognizer
    def analyze_many(_texts, _opts), do: {:ok, [["OBSCURA-CANARY-7F4A@example.test"]]}
  end

  defmodule LeakyLanguageDetector do
    @behaviour Obscura.Language.Detector

    @impl Obscura.Language.Detector
    def detect(_text, _opts), do: {:ok, "OBSCURA-CANARY-7F4A@example.test"}
  end

  defmodule LeakyCustomOperator do
    @behaviour Obscura.Operator.Custom

    @impl Obscura.Operator.Custom
    def apply(_value, _context, _opts) do
      raise "OBSCURA-CANARY-7F4A@example.test"
    end
  end

  defmodule LeakyFailureOperator do
    @behaviour Obscura.Operator.Custom

    @impl Obscura.Operator.Custom
    def apply(_value, _context, %{mode: :error}),
      do: {:error, "OBSCURA-CANARY-7F4A@example.test"}

    def apply(_value, _context, %{mode: :invalid}),
      do: {:invalid, "derived-OBSCURA-CANARY-7F4A"}

    def apply(_value, _context, %{mode: :throw}),
      do: throw("OBSCURA-CANARY-7F4A@example.test")

    def apply(_value, _context, %{mode: :exit}),
      do: exit("OBSCURA-CANARY-7F4A@example.test")
  end

  defmodule CanaryReplacementOperator do
    @behaviour Obscura.Operator.Custom

    @impl Obscura.Operator.Custom
    def apply(_value, _context, _opts), do: {:ok, "derived-OBSCURA-CANARY-7F4A"}
  end

  test "errors, diagnostics, callback failures, and CLI formatting reject canaries" do
    assert {:error, {:recognizer_failed, :leaky_recognizer, :callback_error} = reason} =
             Obscura.analyze(@canary,
               built_ins: false,
               entities: [:email],
               recognizers: [LeakyRecognizer]
             )

    refute_canaries(reason)

    assert {:error, %Error{} = callback_error} =
             Obscura.anonymize(@canary, [span(@canary)],
               operators: %{
                 email: %{type: :custom, module: LeakyCustomOperator}
               }
             )

    refute_canaries(callback_error)
    refute_canaries(Exception.message(callback_error))
    refute_canaries(Obscura.CLI.format_error({:provider_failure, @canary}))

    diagnostic =
      Diagnostic.new(:model_load_failed,
        profile: @canary,
        message: @canary,
        remediation: @derived_canary,
        path: "/tmp/#{@canary}",
        cause: {:provider_failure, @canary},
        metadata: %{@canary => @derived_canary, detail: @canary}
      )

    assert diagnostic.path == nil
    assert diagnostic.profile == nil
    refute_canaries(diagnostic)
    refute_canaries(Diagnostic.format(diagnostic))
    refute_canaries(Diagnostic.to_map(diagnostic))
  end

  test "all custom callback failure modes and task errors reject canaries" do
    for mode <- [:error, :invalid, :throw, :exit] do
      assert {:error, %Error{} = error} =
               Obscura.anonymize(@canary, [span(@canary)],
                 operators: %{
                   email: %{
                     type: :custom,
                     module: LeakyFailureOperator,
                     options: %{mode: mode}
                   }
                 }
               )

      refute_canaries(error)
      refute_canaries(Exception.message(error))
    end

    for task <- [
          Mix.Tasks.Obscura.Benchmarks.Promote,
          Mix.Tasks.Obscura.Benchmarks.Verify,
          Mix.Tasks.Obscura.Detect,
          Mix.Tasks.Obscura.Eval,
          Mix.Tasks.Obscura.Export.Predictions,
          Mix.Tasks.Obscura.Fixtures,
          Mix.Tasks.Obscura.Gen.Config,
          Mix.Tasks.Obscura.PrivacyFilter.Checkpoint,
          Mix.Tasks.Obscura.PrivacyFilter.Setup,
          Mix.Tasks.Obscura.Profile.Check,
          Mix.Tasks.Obscura.Redact
        ] do
      exception =
        assert_raise Mix.Error, fn ->
          task.run(["--#{@canary}"])
        end

      refute_canaries(exception)
      refute_canaries(Exception.message(exception))
    end
  end

  test "malformed recognizer result payloads fail safely for single and batch analysis" do
    opts = [built_ins: false, entities: [:email], recognizers: [MalformedRecognizer]]

    assert {:error,
            {:recognizer_failed, :malformed_recognizer, :invalid_callback_result} = single} =
             Obscura.analyze(@canary, opts)

    assert {:error, {:recognizer_failed, :malformed_recognizer, :invalid_callback_result} = batch} =
             Obscura.Analyzer.analyze_many([@canary], opts)

    refute_canaries(single)
    refute_canaries(batch)

    assert {:error, :unsupported_language = language_error} =
             Obscura.analyze(@canary,
               detect_language: true,
               language_detector: LeakyLanguageDetector
             )

    refute_canaries(language_error)
  end

  test "logs and telemetry reject direct and nested canary values" do
    log =
      capture_log(fn ->
        assert {:error, %Error{}} =
                 Obscura.anonymize(@canary, [span(@canary)],
                   operators: %{
                     email: %{type: :custom, module: LeakyCustomOperator}
                   }
                 )
      end)

    refute_canaries(log)

    definition =
      PatternDefinition.new!(
        name: :leaky_validation,
        entity: :email,
        patterns: [%{name: :canary, regex: ~r/OBSCURA-CANARY/u, score: 0.5}],
        validate: fn _value -> raise @canary end
      )

    assert {:ok, []} =
             Obscura.analyze(@canary,
               built_ins: false,
               entities: [:email],
               recognizers: [definition]
             )

    event = [:obscura, :security, :canary, :stop]
    handler = "obscura-security-#{System.unique_integer([:positive])}"
    test_pid = self()

    :telemetry.attach(
      handler,
      event,
      fn received_event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, received_event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    Obscura.Telemetry.execute(
      true,
      event,
      %{duration: 1, input: @canary, nested: %{value: @canary}},
      %{
        status: :error,
        profile: @canary,
        reason: @canary,
        nested: %{password: @derived_canary}
      }
    )

    assert_receive {:telemetry, ^event, measurements, metadata}
    assert measurements == %{duration: 1}
    assert metadata == %{profile: :redacted, status: :error}
    refute_canaries({measurements, metadata})
  end

  test "Inspect implementations hide raw text, replacements, tokens, paths, and stream buffers" do
    assert {:ok, detections} = Obscura.analyze(@canary, entities: [:email], explain: true)
    assert [%Result{text: @canary}] = detections
    refute_canaries(detections)
    refute_canaries(hd(detections).explanation)

    assert {:ok, anonymized} =
             Obscura.anonymize(@canary, detections,
               operators: %{
                 email: %{type: :custom, module: CanaryReplacementOperator}
               }
             )

    assert anonymized.text == @derived_canary
    refute_canaries(anonymized)
    refute_canaries(anonymized.items)

    assert {:ok, structured} =
             Obscura.Structured.redact(%{@canary => @canary},
               field_policies: %{@canary => :keep}
             )

    refute_canaries(structured)

    artifacts = Artifacts.build("prefix #{@canary} suffix")
    refute_canaries(artifacts)

    detected_span = %DetectedSpan{
      label: "private_person",
      start: 0,
      end: byte_size(@canary),
      byte_start: 0,
      byte_end: byte_size(@canary),
      text: @canary
    }

    refute_canaries(detected_span)

    assert {:ok, vault} = Memory.start_link()
    assert {:ok, token} = Vault.get_or_create(vault, :email, @canary)
    assert {:ok, entry} = Vault.lookup_token(vault, token)
    refute_canaries(entry)
    refute inspect(entry) =~ token

    stream = %Rehydrator{vault: vault, buffer: "#{@canary}#{token}"}
    refute_canaries(stream)
    refute inspect(stream) =~ token
  end

  test "model execution failures omit exception messages and model input" do
    assert {:ok, serving} =
             Serving.build(
               config: privacy_filter_config(),
               decoder: :argmax,
               model_fun: fn _token_ids, _attention_mask ->
                 raise @canary
               end
             )

    assert {:error, {:privacy_filter_model_forward_failed, RuntimeError} = error} =
             Serving.run(serving, @canary)

    refute_canaries(error)

    aggregation = SequenceLabeling.new_aggregation()

    assert {:ok, aggregation} =
             SequenceLabeling.record_token_id(aggregation, 0, 1, @canary)

    assert {:error, {:conflicting_token_id, 0} = conflict} =
             SequenceLabeling.record_token_id(aggregation, 0, 2, @canary)

    refute_canaries(conflict)
  end

  defp span(value) do
    %{entity: :email, byte_start: 0, byte_end: byte_size(value), value: value}
  end

  defp privacy_filter_config do
    %{
      encoding: "cl100k_base",
      ner_class_names: [
        "O",
        "B-private_person",
        "I-private_person",
        "E-private_person",
        "S-private_person"
      ]
    }
  end

  defp refute_canaries(term) do
    rendered = inspect(term, printable_limit: :infinity, limit: :infinity)
    refute rendered =~ @canary
    refute rendered =~ @derived_canary
  end
end
