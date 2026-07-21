defmodule Obscura.DocumentedExamplesTest do
  use ExUnit.Case, async: false

  alias Obscura.Analyzer.Result
  alias Obscura.Anonymizer.Operator
  alias Obscura.Operator.Hash
  alias Obscura.Phoenix.Plug
  alias Obscura.Recognizer.NER
  alias Obscura.Recognizer.NER.FakeServing
  alias Obscura.Recognizer.PatternDefinition
  alias Obscura.Stream.Rehydrator, as: StreamRehydrator
  alias Obscura.Structured.Result, as: StructuredResult

  @registry_path "priv/obscura/documented_examples.exs"
  {registry, _binding} = Code.eval_file(@registry_path)
  @registry registry

  defmodule TicketRecognizer do
    @behaviour Obscura.Recognizer

    @impl Obscura.Recognizer
    def name, do: :ticket

    @impl Obscura.Recognizer
    def supported_entities, do: [:ticket]

    @impl Obscura.Recognizer
    def analyze(text, _opts) do
      for [{start, length}] <- Regex.scan(~r/TKT-\d{4}/, text, return: :index) do
        %Result{
          entity: :ticket,
          start: start,
          end: start + length,
          byte_start: start,
          byte_end: start + length,
          score: 0.8,
          text: binary_part(text, start, length),
          source_entity: "TICKET",
          recognizer: :ticket,
          metadata: %{}
        }
      end
    end
  end

  defmodule CustomOperator do
    @behaviour Obscura.Operator.Custom

    @impl Obscura.Operator.Custom
    def apply(value, %{entity: entity}, options) do
      {:ok, "<#{options.prefix}:#{entity}:#{byte_size(value)}>", %{format: :custom}}
    end
  end

  defmodule LanguageDetector do
    @behaviour Obscura.Language.Detector

    @impl Obscura.Language.Detector
    def detect(_text, _opts), do: {:ok, :en}
  end

  defmodule ContractUser do
    @derive {Obscura.Redactable,
             fields: [email: {:entity, :email}, password_hash: :drop, profile: :traverse]}
    defstruct [:email, :password_hash, :profile]
  end

  test "every executable ExDoc guide section has automated or justified opt-in evidence" do
    extras = Mix.Project.config() |> Keyword.fetch!(:docs) |> Keyword.fetch!(:extras)

    actual =
      extras
      |> Enum.flat_map(fn file ->
        Enum.map(executable_sections(file), &{file, &1})
      end)
      |> MapSet.new()

    registered =
      @registry
      |> Enum.flat_map(fn {file, sections} ->
        Enum.map(Map.keys(sections), &{file, &1})
      end)
      |> MapSet.new()

    assert actual == registered
  end

  test "every documented-example evidence reference exists and opt-in evidence is tagged" do
    Enum.each(@registry, fn {_file, sections} ->
      Enum.each(sections, fn {_section, evidence_rows} ->
        assert evidence_rows != []

        Enum.each(evidence_rows, fn
          {:test, test_file} ->
            assert File.regular?(test_file), "missing documented-example test #{test_file}"

          {:opt_in, test_file, reason} ->
            assert File.regular?(test_file), "missing opt-in test #{test_file}"
            assert is_binary(reason) and byte_size(reason) > 20

            source = File.read!(test_file)

            assert source =~ ~r/@(?:module)?tag :(?:real_model|gliner_ortex)/,
                   "#{test_file} is not an explicitly tagged opt-in test"
        end)
      end)
    end)
  end

  test "README installation and dependency-light profile examples remain valid" do
    assert Mix.Project.config()[:app] == :obscura
    assert Version.match?("0.1.0", "~> 0.1")

    assert {:ok, [%Result{entity: :email}]} =
             Obscura.analyze("Contact user@example.test", profile: :fast, entities: [:email])
  end

  test "README analyze, anonymize, and redact examples produce documented results" do
    text = "Contact user@example.test"

    assert {:ok, [%Result{entity: :email, start: 8, end: 25}] = detections} =
             Obscura.analyze(text, entities: [:email])

    assert {:ok, anonymized} =
             Obscura.anonymize(text, detections,
               operators: %{email: %{type: :replace, value: "[EMAIL]"}}
             )

    assert anonymized.text == "Contact [EMAIL]"

    assert {:ok, redacted} =
             Obscura.redact("Call 202-555-0188", entities: [:phone])

    assert redacted.text == "Call [PHONE]"

    input = %{email: "user@example.test", password: "synthetic-secret"}

    assert {:ok, structured} =
             Obscura.redact(input,
               entities: [:email],
               field_policies: %{password: :drop}
             )

    assert structured.data == %{email: "[EMAIL]"}
  end

  test "recognizer, pattern, deny-list, and allow-list examples remain executable" do
    assert {:ok, [%Result{entity: :ticket, text: "TKT-1234"}]} =
             Obscura.analyze("Ticket TKT-1234",
               entities: [:ticket],
               recognizers: [TicketRecognizer]
             )

    employee_id =
      PatternDefinition.new!(
        name: :employee_id,
        entity: :employee_id,
        patterns: [%{name: :employee_id_v1, regex: ~r/EMP-\d{6}/, score: 0.65}],
        context: ["employee"]
      )

    assert {:ok, [%Result{entity: :employee_id}]} =
             Obscura.analyze("employee EMP-123456",
               entities: [:employee_id],
               recognizers: [employee_id],
               context: ["employee"],
               explain: true
             )

    assert {:ok, [%Result{entity: :project_codename}]} =
             Obscura.analyze("Project ORCHID",
               entities: [:project_codename],
               deny_lists: [
                 %{entity: :project_codename, values: ["orchid"], case_sensitive: false}
               ]
             )

    assert {:ok, [%Result{text: "person@example.test"}]} =
             Obscura.analyze("support@example.test person@example.test",
               entities: [:email],
               allow_list: [%{entity: :email, values: ["support@example.test"]}]
             )
  end

  test "fake NER and batch examples preserve labels and input order" do
    serving =
      FakeServing.new(%{
        "Alice works at Acme." => [
          %{label: "PER", start: 0, end: 5, score: 0.94},
          %{label: "ORG", start: 15, end: 19, score: 0.91}
        ],
        "Alice" => [%{label: "PER", start: 0, end: 5, score: 0.9}],
        "Denver" => [%{label: "LOC", start: 0, end: 6, score: 0.9}]
      })

    assert {:ok, [%Result{entity: :person}, %Result{entity: :organization}]} =
             Obscura.analyze("Alice works at Acme.",
               entities: [:person, :organization],
               recognizers: [{NER, serving: serving}]
             )

    assert {:ok, [[%Result{entity: :person}], [%Result{entity: :location}]]} =
             Obscura.analyze_many(["Alice", "Denver"],
               entities: [:person, :location],
               recognizers: [{NER, serving: serving}]
             )
  end

  test "structured derive, Logger, and Plug option examples remain valid" do
    user = %ContractUser{
      email: "user@example.test",
      password_hash: "synthetic-hash",
      profile: %{}
    }

    assert {:ok, %StructuredResult{data: redacted_user}} =
             Obscura.redact(user, entities: [:email])

    assert %ContractUser{email: "[EMAIL]", password_hash: nil} = redacted_user

    assert {:ok, metadata} =
             Obscura.Logger.redact_metadata(
               [user: "user@example.test", password: "synthetic-secret"],
               entities: [:email]
             )

    assert metadata[:user] == "[EMAIL]"
    assert is_binary(elem(Obscura.Logger.safe_inspect(metadata, entities: [:email]), 1))

    assert Plug.init(
             fields: [:params],
             mode: :assign_redacted,
             entities: [:email]
           ) == [fields: [:params], mode: :assign_redacted, entities: [:email]]
  end

  test "operator guide examples match their schemas" do
    assert {:replace, "[EMAIL]", %{}} =
             Operator.apply("value", %{type: :replace, value: "[EMAIL]"})

    assert {:redact, "", %{}} = Operator.apply("value", %{type: :redact})

    assert {:mask, "*****0188", %{}} =
             Operator.apply("202550188", %{type: :mask, char: "*", keep_last: 4})

    assert {:hash, secure_hash, %{mode: :secure}} =
             Operator.apply("value", %{type: :hash, mode: :secure, algorithm: :sha256})

    assert Hash.verify("value", secure_hash)

    deterministic = %{
      type: :hash,
      mode: :deterministic,
      algorithm: :sha256,
      salt: "application-salt"
    }

    assert {:hash, first, %{mode: :deterministic}} = Operator.apply("value", deterministic)
    assert {:hash, second, %{mode: :deterministic}} = Operator.apply("value", deterministic)
    assert first == second

    assert {:custom, "<private:email:5>", %{format: :custom, custom_module: CustomOperator}} =
             Operator.apply(
               "value",
               %{type: :custom, module: CustomOperator, options: %{prefix: "private"}},
               %{entity: :email}
             )
  end

  test "vault, pseudonymization, structured rehydration, LLM, and stream examples work together" do
    {:ok, vault} = start_supervised(Obscura.Vault.Memory)

    assert {:ok, token} =
             Obscura.Vault.get_or_create(vault, :email, "user@example.test")

    assert token == "<<EMAIL_001>>"
    assert {:ok, %Obscura.Vault.Entry{entity: :email}} = Obscura.Vault.lookup_token(vault, token)

    assert {:ok, result} =
             Obscura.redact("Email user@example.test",
               entities: [:email],
               operators: %{email: %{type: :pseudonymize}},
               vault: vault
             )

    assert result.text == "Email <<EMAIL_001>>"
    assert {:ok, "Email user@example.test"} = Obscura.rehydrate(result.text, vault: vault)

    assert {:ok, structured} =
             Obscura.redact(%{message: "Email user@example.test"},
               entities: [:email],
               operators: %{email: %{type: :pseudonymize}},
               vault: vault
             )

    assert {:ok, %{message: "Email user@example.test"}} =
             Obscura.rehydrate(structured.data, vault: vault)

    messages = [
      %{role: "system", content: "Be concise."},
      %{role: "user", content: "Email another@example.test"}
    ]

    assert {:ok, safe_messages, llm_vault} =
             Obscura.LLM.redact_messages(messages, vault: :memory, entities: [:email])

    assert Enum.at(safe_messages, 1).content == "Email <<EMAIL_001>>"

    assert {:ok, "Contact another@example.test"} =
             Obscura.LLM.rehydrate_response("Contact <<EMAIL_001>>", vault: llm_vault)

    assert {:ok, stream} = StreamRehydrator.new(vault: vault)
    assert {:ok, "Hello ", stream} = StreamRehydrator.feed(stream, "Hello <<EMA")

    assert {:ok, "user@example.test", stream} =
             StreamRehydrator.feed(stream, "IL_001>>")

    assert {:ok, ""} = StreamRehydrator.flush(stream)
  end

  test "runtime diagnostics and language detector examples stay dependency-light" do
    assert {:ok, %{status: :ready}} = Obscura.Profile.preflight(:fast)

    result = Obscura.Profile.preflight(:balanced, backend: :emily)

    assert match?({:ok, _report}, result) or
             match?({:error, %Obscura.Diagnostic{}, _report}, result)

    assert Obscura.Language.supported() == [:en, :es, :fr, :de, :pt, :it, :unknown]

    assert {:ok, [%Result{entity: :email}]} =
             Obscura.analyze("user@example.test",
               entities: [:email],
               detect_language: true,
               language_detector: LanguageDetector
             )
  end

  test "context and structured guide examples preserve documented behavior" do
    assert {:ok, [%Result{entity: :phone, explanation: explanation}]} =
             Obscura.analyze("Phone 202-555-0188",
               entities: [:phone],
               profile: :context,
               context: ["phone"],
               explain: true
             )

    assert explanation.score >= 0.4

    input = %{
      user: %{email: "user@example.test", password: "synthetic-secret"},
      phones: ["202-555-0188"]
    }

    assert {:ok, structured} =
             Obscura.redact(input,
               entities: [:email, :phone],
               field_policies: %{password: :drop}
             )

    assert structured.data == %{
             user: %{email: "[EMAIL]"},
             phones: ["[PHONE]"]
           }
  end

  defp executable_sections(file) do
    file
    |> File.read!()
    |> String.split("\n")
    |> Enum.reduce({nil, MapSet.new()}, fn line, {heading, sections} ->
      cond do
        Regex.match?(~r/^#+\s+/, line) ->
          {String.replace(line, ~r/^#+\s+/, ""), sections}

        Regex.match?(~r/^```(?:elixir|sh|bash|console)$/, line) or
            String.starts_with?(line, "<pre><code>") ->
          {heading, MapSet.put(sections, heading)}

        true ->
          {heading, sections}
      end
    end)
    |> elem(1)
  end
end
