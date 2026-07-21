defmodule Obscura.PublicAPIContractTest do
  use ExUnit.Case, async: true

  alias Obscura.Analyzer.Options, as: AnalyzerOptions
  alias Obscura.Analyzer.Result, as: AnalyzerResult
  alias Obscura.Anonymizer.Error
  alias Obscura.Anonymizer.Item, as: AnonymizerItem
  alias Obscura.Anonymizer.Operator
  alias Obscura.Anonymizer.Result, as: AnonymizerResult
  alias Obscura.Diagnostic
  alias Obscura.Structured.Item, as: StructuredItem
  alias Obscura.Structured.Result, as: StructuredResult
  alias Obscura.Vault.Token

  @manifest_path "priv/obscura/public_api.exs"
  {manifest, _binding} = Code.eval_file(@manifest_path)
  @manifest manifest

  test "the baseline is deterministic and has disjoint classifications" do
    assert @manifest.baseline_version == 1
    assert @manifest.release_line == "0.1.x"
    assert @manifest.internal_default
    assert @manifest.deprecated == %{}

    stable = @manifest.stable |> Map.keys() |> MapSet.new()
    experimental = @manifest.experimental |> Map.keys() |> MapSet.new()

    assert MapSet.disjoint?(stable, experimental)
    assert Enum.all?(stable, &Code.ensure_loaded?/1)
    assert Enum.all?(experimental, &Code.ensure_loaded?/1)
  end

  test "every application module has one effective classification and ExDoc exposes only supported modules" do
    filter = Mix.Project.config() |> Keyword.fetch!(:docs) |> Keyword.fetch!(:filter_modules)

    Application.spec(:obscura, :modules)
    |> Enum.each(fn module ->
      classification = classify(module)
      assert classification in [:stable, :experimental, :internal]
      assert filter.(module, %{}) == classification in [:stable, :experimental]
    end)
  end

  test "all stable functions remain exported" do
    Enum.each(@manifest.stable, fn {module, contract} ->
      assert Code.ensure_loaded?(module)

      Enum.each(Map.get(contract, :functions, []), fn {name, arity} ->
        assert function_exported?(module, name, arity),
               "#{inspect(module)}.#{name}/#{arity} is missing from the stable baseline"
      end)
    end)
  end

  test "all stable struct fields remain available" do
    Enum.each(@manifest.stable, fn {module, contract} ->
      case Map.fetch(contract, :fields) do
        {:ok, expected_fields} ->
          actual_fields =
            module
            |> struct()
            |> Map.keys()
            |> List.delete(:__struct__)
            |> MapSet.new()

          assert MapSet.subset?(MapSet.new(expected_fields), actual_fields),
                 "#{inspect(module)} removed a stable struct field"

        :error ->
          :ok
      end
    end)
  end

  test "stable behaviour callbacks remain declared" do
    Enum.each(@manifest.stable, fn {module, contract} ->
      case Map.fetch(contract, :callbacks) do
        {:ok, expected_callbacks} ->
          assert {:ok, callbacks} = Code.Typespec.fetch_callbacks(module)

          actual_callbacks =
            callbacks
            |> Enum.map(fn {{name, arity}, _specs} -> {name, arity} end)
            |> MapSet.new()

          assert MapSet.subset?(MapSet.new(expected_callbacks), actual_callbacks),
                 "#{inspect(module)} removed a stable callback"

        :error ->
          :ok
      end
    end)
  end

  test "stable profile names and classifications match the baseline" do
    assert Obscura.Profile.names() == @manifest.stable_profiles

    Enum.each(@manifest.stable_profiles, fn profile ->
      assert {:ok, :stable} = Obscura.Profile.classification(profile)
      assert {:ok, %Obscura.Profile{name: ^profile}} = Obscura.Profile.fetch(profile)
    end)
  end

  test "experimental profile names and classifications match the baseline" do
    assert Obscura.Profile.experimental_names() == @manifest.experimental_profiles

    Enum.each(@manifest.experimental_profiles, fn profile ->
      assert {:ok, :experimental} = Obscura.Profile.classification(profile)

      assert {:ok, %Obscura.Profile{name: ^profile, stability: :experimental}} =
               Obscura.Profile.fetch(profile)
    end)
  end

  test "operator schemas and defaults match the baseline" do
    Enum.each(@manifest.operators, fn {type, schema} ->
      config = Map.put(schema.optional, :type, type)

      if type in [:pseudonymize, :custom] do
        assert is_map(schema)
      else
        assert :ok = Operator.validate_config(config)
      end
    end)

    assert {:replace, "[REDACTED]", %{}} = Operator.apply("value", %{type: :replace})
    assert {:redact, "", %{}} = Operator.apply("value", %{type: :redact})
    assert {:mask, "*****", %{}} = Operator.apply("value", %{type: :mask})

    assert {:hash, replacement, %{algorithm: :sha256, mode: :secure}} =
             Operator.apply("value", %{type: :hash})

    assert String.starts_with?(replacement, "$obscura$v1$hash$sha256$secure$")
  end

  test "stable option defaults remain documented and observable" do
    assert {:ok, options} = AnalyzerOptions.new([])
    assert options.requested_profile == :regex_only
    assert options.profile == :regex_only
    assert options.language == :en
    assert options.score_threshold == 0.0
    refute options.explain
    assert options.include_text
    assert options.built_ins
    assert options.context == []
    assert options.context_window == 30
    assert options.context_prefix_count == 5
    assert options.context_suffix_count == 5
    assert options.context_boost == 0.15
    assert options.context_min_score == 0.4
    assert options.context_match == :whole_word
    assert options.batch_size == 8
    assert options.recognizer_timeout == 5_000
    refute options.parallel_recognizers
    assert options.phone_regions == []
    assert options.telemetry

    assert Token.default_options() == [
             token_prefix: "<<",
             token_suffix: ">>",
             token_separator: "_",
             token_width: 3,
             token_case: :upper,
             token_strategy: :sequential
           ]
  end

  test "structured anonymizer errors match the stable code and field contract" do
    assert MapSet.new(@manifest.anonymizer_error_codes) ==
             MapSet.new([
               :invalid_operator_collection,
               :invalid_operator_config,
               :unsupported_operator,
               :unknown_operator_option,
               :missing_operator_option,
               :invalid_operator_option,
               :operator_failed,
               :invalid_operator_result
             ])

    assert MapSet.new(Map.keys(%Error{code: :invalid_operator_config})) ==
             MapSet.new([
               :__exception__,
               :__struct__,
               :code,
               :field,
               :metadata,
               :operator,
               :reason
             ])

    assert {:error, %Error{code: :unsupported_operator, operator: :unknown}} =
             Obscura.redact("Contact user@example.test",
               entities: [:email],
               operators: %{email: %{type: :unknown}}
             )
  end

  test "diagnostic codes match the stable baseline" do
    assert Diagnostic.codes() == @manifest.diagnostic_codes

    diagnostic = Diagnostic.new(:unknown_profile, profile: :missing)
    assert %Diagnostic{code: :unknown_profile, profile: :missing} = diagnostic
    assert %{code: :unknown_profile, profile: :missing} = Diagnostic.to_map(diagnostic)
  end

  test "top-level return shapes and public result fields remain stable" do
    assert {:ok, [%AnalyzerResult{} = detection]} =
             Obscura.analyze("Contact user@example.test", entities: [:email])

    assert detection.entity == :email
    assert detection.start == detection.byte_start
    assert detection.end == detection.byte_end

    assert {:ok, %AnonymizerResult{} = redacted} =
             Obscura.redact("Contact user@example.test", entities: [:email])

    assert redacted.status == :ran
    assert [%AnonymizerItem{}] = redacted.items

    assert {:ok, %StructuredResult{} = structured} =
             Obscura.redact(%{email: "user@example.test"}, entities: [:email])

    assert structured.status == :ran
    assert [%StructuredItem{}] = structured.items
  end

  test "unknown options follow the documented strict and tolerant boundaries" do
    assert {:ok, %AnalyzerOptions{}} =
             AnalyzerOptions.new(unknown_future_option: true)

    assert {:error, %Error{code: :unknown_operator_option}} =
             Operator.validate_config(%{type: :mask, unknown: true})
  end

  test "optional runtime failures stay structured and dependency-light" do
    assert {:error, %Diagnostic{} = diagnostic} =
             Obscura.Profile.validate_runtime(:balanced, backend: :unsupported_backend)

    assert diagnostic.code in [
             :missing_optional_dependency,
             :missing_model_asset,
             :unsupported_backend,
             :backend_unavailable,
             :profile_requirements_unsatisfied
           ]
  end

  test "stable and experimental Mix tasks remain loadable" do
    Enum.each(@manifest.stable_mix_tasks ++ @manifest.experimental_mix_tasks, fn task ->
      assert Code.ensure_loaded?(task)
      assert function_exported?(task, :run, 1)
    end)
  end

  test "published module docs contain no unregistered executable examples" do
    documented_modules =
      Map.keys(@manifest.stable) ++ Map.keys(@manifest.experimental)

    Enum.each(documented_modules, fn module ->
      assert {:docs_v1, _, _, _, moduledoc, _, docs} = Code.fetch_docs(module)

      rendered_docs =
        [
          moduledoc
          | Enum.map(docs, fn {_kind_arity, _line, _signature, doc, _metadata} -> doc end)
        ]
        |> Enum.flat_map(&doc_strings/1)
        |> Enum.join("\n")

      refute rendered_docs =~ ~r/```(?:elixir|sh|bash|console)/,
             "#{inspect(module)} contains an executable example without registry evidence"

      refute rendered_docs =~ "iex>",
             "#{inspect(module)} contains an unregistered IEx example"
    end)
  end

  defp classify(module) do
    cond do
      Map.has_key?(@manifest.stable, module) -> :stable
      module in @manifest.stable_mix_tasks -> :stable
      Map.has_key?(@manifest.experimental, module) -> :experimental
      module in @manifest.experimental_mix_tasks -> :experimental
      true -> :internal
    end
  end

  defp doc_strings(%{"en" => value}) when is_binary(value), do: [value]
  defp doc_strings(value) when is_binary(value), do: [value]
  defp doc_strings(_value), do: []
end
