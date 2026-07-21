defmodule Obscura.Profile.RuntimeTest do
  use ExUnit.Case, async: true

  alias Obscura.Analyzer.Options
  alias Obscura.Diagnostic
  alias Obscura.Profile
  alias Obscura.Profile.Runtime
  alias Obscura.Recognizer.GLiNER
  alias Obscura.Recognizer.NER.FakeServing
  alias Obscura.Recognizer.NER.OutputAwareCascade

  test "fast runs the deterministic plus implementation without assets" do
    assert {:ok, results} =
             Obscura.analyze("Email jane@example.com", profile: :fast, entities: [:email])

    assert [%{entity: :email, text: "jane@example.com"}] = results

    assert {:ok, options} = Options.new(profile: :fast)
    assert options.requested_profile == :fast
    assert options.profile == :deterministic_plus
  end

  test "balanced runs deterministic recognizers plus a reusable NER serving" do
    text = "Alice works at Acme in Denver."

    serving =
      FakeServing.new(%{
        text => [
          %{label: "PERSON", start: 0, end: 5, score: 0.99},
          %{label: "ORG", start: 15, end: 19, score: 0.999},
          %{label: "GPE", start: 23, end: 29, score: 0.99}
        ]
      })

    assert {:ok, results} = Obscura.analyze(text, profile: :balanced, serving: serving)

    assert Enum.any?(results, &(&1.entity == :person and &1.text == "Alice"))
    assert Enum.any?(results, &(&1.entity == :organization and &1.text == "Acme"))
    assert Enum.any?(results, &(&1.entity == :location and &1.text == "Denver"))

    assert {:ok, redacted} = Obscura.redact(text, profile: :balanced, serving: serving)
    assert redacted.text == "[REDACTED] works at [REDACTED] in [REDACTED]."
  end

  test "stable accurate routes primary and location reusable servings" do
    text = "Alice moved to Denver."

    primary =
      FakeServing.new(%{text => [%{label: "PERSON", start: 0, end: 5, score: 0.99}]})

    location =
      FakeServing.new(%{text => [%{label: "LOC", start: 15, end: 21, score: 0.999}]})

    assert {:ok, results} =
             Obscura.analyze(text,
               profile: :accurate,
               servings: %{primary: primary, location: location}
             )

    assert Enum.any?(results, &(&1.entity == :person and &1.text == "Alice"))
    assert Enum.any?(results, &(&1.entity == :location and &1.text == "Denver"))
  end

  test "stable accurate locks the output-aware cascade policy" do
    primary = FakeServing.new([])
    location = FakeServing.new([])

    assert {:ok, opts} =
             Profile.configure_options(
               profile: :accurate,
               servings: %{primary: primary, location: location},
               cascade_trigger: :missing_or_uncertain,
               cascade_secondary_threshold: 0.5,
               cascade_context_policy: :strong,
               location_threshold: 0.5
             )

    assert [:default, {OutputAwareCascade, cascade_opts}] = opts[:recognizers]
    assert cascade_opts[:cascade_trigger] == :missing
    assert cascade_opts[:cascade_secondary_threshold] == 0.999
    assert cascade_opts[:cascade_context_policy] == :none
    assert cascade_opts[:primary_opts][:entities] == [:location, :organization, :person]

    assert cascade_opts[:secondary_opts][:per_label_thresholds] == %{
             "LOC" => 0.999
           }
  end

  test "stable accurate skips Jean when TNER already returns location" do
    text = "Alice moved to Denver from Aspen."

    primary =
      FakeServing.new(%{text => [%{label: "GPE", start: 15, end: 21, score: 0.99}]})

    location =
      FakeServing.new(%{text => [%{label: "LOC", start: 27, end: 32, score: 0.999}]})

    assert {:ok, results} =
             Obscura.analyze(text,
               profile: :accurate,
               entities: [:location],
               servings: %{primary: primary, location: location}
             )

    assert Enum.any?(results, &(&1.entity == :location and &1.text == "Denver"))
    refute Enum.any?(results, &(&1.text == "Aspen"))
  end

  test "prepared runtime options override the runtime without rebuilding assets" do
    runtime = %Runtime{
      profile: :fast,
      implementation_profile: :deterministic_plus,
      resources: %{},
      analyzer_options: [profile: :fast, entities: [:email]],
      prepared_at: DateTime.utc_now(),
      backend_metadata: %{}
    }

    assert {:ok, [%{entity: :phone}]} =
             Obscura.analyze("Call 202-555-0188", profile: runtime, entities: [:phone])
  end

  test "prepared model runtimes return only request-scoped entities" do
    text = "Alice works at Acme in Denver."

    primary =
      FakeServing.new(%{
        text => [
          %{label: "PERSON", start: 0, end: 5, score: 0.99},
          %{label: "ORG", start: 15, end: 19, score: 0.999},
          %{label: "GPE", start: 23, end: 29, score: 0.99}
        ]
      })

    location =
      FakeServing.new(%{text => [%{label: "LOC", start: 23, end: 29, score: 0.999}]})

    assert {:ok, balanced} =
             Runtime.build(:balanced, ner_serving_builder: fn _opts -> {:ok, primary} end)

    assert {:ok, accurate} =
             Runtime.build(:accurate,
               ner_serving_builder: fn opts ->
                 case Keyword.fetch!(opts, :model) do
                   :tner_roberta_large_ontonotes5 -> {:ok, primary}
                   :jean_baptiste_roberta_large_ner_english -> {:ok, location}
                 end
               end
             )

    for runtime <- [balanced, accurate], entity <- [:person, :organization, :location] do
      assert {:ok, results} = Obscura.analyze(text, profile: runtime, entities: [entity])
      assert results != []
      assert Enum.all?(results, &(&1.entity == entity))
    end
  end

  test "prepare is explicit and builds a reusable balanced runtime once" do
    parent = self()
    serving = FakeServing.new([])

    builder = fn opts ->
      send(parent, {:build, Keyword.fetch!(opts, :model)})
      {:ok, serving}
    end

    assert {:ok, runtime} =
             Profile.prepare(:balanced,
               allow_download: true,
               ner_serving_builder: builder
             )

    assert runtime.profile == :balanced
    assert runtime.resources.primary == serving
    assert_received {:build, :tner_roberta_large_ontonotes5}

    assert {:error, %Diagnostic{code: :serving_build_failed}} =
             Profile.prepare(:balanced,
               allow_download: true,
               ner_serving_builder: fn _ -> {:error, :bad_model} end
             )
  end

  test "prepare builds the experimental Urchade profile with frozen CPU policy" do
    parent = self()

    builder = fn opts ->
      send(parent, {:gliner_options, opts})
      {:ok, :gliner_serving}
    end

    assert {:ok, runtime} =
             Profile.prepare(:hybrid_gliner_urchade,
               gliner_serving_builder: builder,
               dependency_checker: fn _dependency -> true end
             )

    assert runtime.profile == :hybrid_gliner_urchade
    assert runtime.implementation_profile == :hybrid_gliner_urchade
    assert runtime.resources.gliner == :gliner_serving
    assert runtime.backend_metadata.backend == :test_or_custom

    assert_receive {:gliner_options, opts}
    assert opts[:model] == :urchade_gliner_multi_pii_v1
    assert opts[:label_profile] == :open_class
    assert opts[:execution_providers] == [:cpu]

    assert opts[:per_label_thresholds] == %{
             "person" => 0.5,
             "organization" => 0.9,
             "location" => 0.5
           }

    assert [:default, {GLiNER, recognizer_opts}] = runtime.analyzer_options[:recognizers]
    assert recognizer_opts[:serving] == :gliner_serving
    assert recognizer_opts[:label_profile] == :open_class
  end

  test "Urchade product configuration requires a reusable serving" do
    assert {:error, %Diagnostic{code: :missing_model_asset, asset: :gliner_serving}} =
             Profile.configure_options(profile: :hybrid_gliner_urchade)

    assert {:ok, opts} =
             Profile.configure_options(
               profile: :hybrid_gliner_urchade,
               gliner_serving: :prepared_serving
             )

    assert [:default, {GLiNER, recognizer_opts}] = opts[:recognizers]
    assert recognizer_opts[:serving] == :prepared_serving
  end

  test "stable aliases propagate through structured and LLM redaction" do
    runtime = %Runtime{
      profile: :fast,
      implementation_profile: :deterministic_plus,
      resources: %{},
      analyzer_options: [profile: :fast, entities: [:email]],
      prepared_at: DateTime.utc_now(),
      backend_metadata: %{}
    }

    assert {:ok, structured} =
             Obscura.redact(%{email: "jane@example.com"}, profile: runtime)

    assert structured.data.email == "[EMAIL]"

    assert {:ok, messages, vault} =
             Obscura.LLM.redact_messages(
               [%{role: "user", content: "Email jane@example.com"}],
               profile: runtime,
               vault: :memory
             )

    assert [%{content: "Email <<EMAIL_001>>"}] = messages
    GenServer.stop(vault)
  end

  test "CLI forwards caller-provided stable profile resources" do
    text = "Alice"
    serving = FakeServing.new(%{text => [%{label: "PERSON", start: 0, end: 5, score: 0.99}]})

    assert {:ok, output} = Obscura.CLI.detect(text, profile: :balanced, serving: serving)
    assert output.profile == "balanced"
    assert [%{entity: "person"}] = output.results
  end

  test "stable and experimental aliases never build assets during analysis" do
    assert {:error, %Diagnostic{code: :missing_model_asset, profile: :balanced}} =
             Obscura.analyze("Alice", profile: :balanced)

    assert {:error, %Diagnostic{code: :missing_model_asset, profile: :accurate}} =
             Obscura.analyze("Alice", profile: :accurate)

    assert {:error, %Diagnostic{code: :missing_model_asset, profile: :openmed_pii}} =
             Obscura.analyze("Alice", profile: :openmed_pii)

    assert {:error, %Diagnostic{code: :missing_model_asset, profile: :hybrid_gliner_urchade}} =
             Obscura.analyze("Alice", profile: :hybrid_gliner_urchade)
  end

  test "unknown analyzer profiles fail instead of using fallback entities" do
    assert {:error, %Diagnostic{code: :unknown_profile}} =
             Obscura.analyze("jane@example.com", profile: :profile_typo)
  end

  test "evaluation profile parser accepts stable and experimental aliases" do
    assert Obscura.Eval.Profile.from_string("fast") == {:ok, :fast}
    assert Obscura.Eval.Profile.from_string("balanced") == {:ok, :balanced}
    assert Obscura.Eval.Profile.from_string("accurate") == {:ok, :accurate}
    assert Obscura.Eval.Profile.from_string("openmed_pii") == {:ok, :openmed_pii}

    assert Obscura.Eval.Profile.from_string("hybrid_gliner_urchade") ==
             {:ok, :hybrid_gliner_urchade}
  end

  test "experimental openmed alias configures clean model-only recognition" do
    assert {:ok, opts} =
             Profile.configure_options(profile: :openmed_pii, serving: :prepared_serving)

    refute Keyword.fetch!(opts, :built_ins)

    assert [{Obscura.Recognizer.PrivacyFilter.Native, [serving: :prepared_serving]}] =
             Keyword.fetch!(opts, :recognizers)
  end

  test "openmed runtime defaults to measured long-sequence optimizations" do
    parent = self()

    builder = fn opts ->
      send(parent, {:privacy_filter_options, opts})
      {:ok, %{backend: :test, backend_metadata: %{}}}
    end

    assert {:ok, _runtime} =
             Profile.prepare(:openmed_pii,
               privacy_filter_checkpoint: "checkpoint",
               privacy_filter_serving_builder: builder
             )

    assert_receive {:privacy_filter_options, opts}
    assert opts[:sequence_length_buckets] == [192, 256, 384, 512, 768]
    assert opts[:sequence_length_bucket_threshold] == 129
    assert opts[:logprob_conversion] == :raw_logits
  end

  test "openmed runtime retains reference log probabilities when scores are required" do
    parent = self()

    builder = fn opts ->
      send(parent, {:privacy_filter_options, opts})
      {:ok, %{backend: :test, backend_metadata: %{}}}
    end

    assert {:ok, _runtime} =
             Profile.prepare(:openmed_pii,
               privacy_filter_checkpoint: "checkpoint",
               privacy_filter_min_span_logprob: -0.5,
               privacy_filter_serving_builder: builder
             )

    assert_receive {:privacy_filter_options, opts}
    assert opts[:logprob_conversion] == :reference
    assert opts[:min_span_logprob] == -0.5
  end

  test "openmed runtime retains reference log probabilities for argmax decoding" do
    parent = self()

    builder = fn opts ->
      send(parent, {:privacy_filter_options, opts})
      {:ok, %{backend: :test, backend_metadata: %{}}}
    end

    assert {:ok, _runtime} =
             Profile.prepare(:openmed_pii,
               privacy_filter_checkpoint: "checkpoint",
               privacy_filter_decoder: :argmax,
               privacy_filter_serving_builder: builder
             )

    assert_receive {:privacy_filter_options, opts}
    assert opts[:decoder] == :argmax
    assert opts[:logprob_conversion] == :reference
  end

  test "openmed default and explicit optimized settings resolve identically" do
    parent = self()

    builder = fn opts ->
      send(parent, {:privacy_filter_options, opts})
      {:ok, %{backend: :test, backend_metadata: %{}}}
    end

    base = [
      privacy_filter_checkpoint: "checkpoint",
      privacy_filter_serving_builder: builder
    ]

    assert {:ok, _runtime} = Profile.prepare(:openmed_pii, base)
    assert_receive {:privacy_filter_options, defaults}

    explicit =
      base ++
        [
          privacy_filter_decoder: :viterbi,
          privacy_filter_sequence_length_buckets: [192, 256, 384, 512, 768],
          privacy_filter_sequence_length_bucket_threshold: 129,
          privacy_filter_logprob_conversion: :raw_logits
        ]

    assert {:ok, _runtime} = Profile.prepare(:openmed_pii, explicit)
    assert_receive {:privacy_filter_options, configured}

    keys = [
      :decoder,
      :sequence_length_buckets,
      :sequence_length_bucket_threshold,
      :logprob_conversion,
      :min_span_logprob
    ]

    assert Keyword.take(defaults, keys) == Keyword.take(configured, keys)
  end
end
