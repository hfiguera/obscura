defmodule Obscura.Analyzer.BinaryOwnershipTest do
  use ExUnit.Case, async: true

  alias Obscura.Analyzer.Result
  alias Obscura.Phoenix.Plug, as: ObscuraPlug
  alias Obscura.Recognizer.Address
  alias Obscura.Recognizer.DenyList
  alias Obscura.Recognizer.Domain
  alias Obscura.Recognizer.Email
  alias Obscura.Recognizer.Location
  alias Obscura.Recognizer.PatternDefinition
  alias Obscura.Recognizer.PersonName

  defmodule BorrowingRecognizer do
    @behaviour Obscura.Recognizer

    @impl true
    def name, do: :borrowing_test_recognizer

    @impl true
    def supported_entities, do: [:url]

    @impl true
    def analyze(text, _opts) do
      {start, length} = :binary.match(text, "https://")
      value = binary_part(text, start, byte_size(text) - start)

      [
        %Result{
          entity: :url,
          start: start,
          end: start + byte_size(value),
          byte_start: start,
          byte_end: start + byte_size(value),
          score: 0.9,
          text: value,
          source_entity: "URL",
          recognizer: :borrowing_test_recognizer,
          metadata: %{matched_prefix_bytes: length}
        }
      ]
    end
  end

  defmodule OffsetOnlyRecognizer do
    @behaviour Obscura.Recognizer

    @impl true
    def name, do: :offset_only_test_recognizer

    @impl true
    def supported_entities, do: [:person]

    @impl true
    def analyze(_text, _opts) do
      [
        %Result{
          entity: :person,
          start: 0,
          end: 5,
          byte_start: 0,
          byte_end: 5,
          score: 0.9,
          text: nil,
          source_entity: "PERSON",
          recognizer: :offset_only_test_recognizer,
          metadata: %{}
        }
      ]
    end
  end

  test "final text does not retain an unrelated large source binary" do
    text = long_url_text()

    assert {:ok, [%Result{} = result]} =
             Obscura.analyze(text,
               profile: :fast,
               entities: [:url],
               include_text: true,
               telemetry: false
             )

    assert result.text ==
             binary_part(text, result.byte_start, result.byte_end - result.byte_start)

    assert byte_size(text) > byte_size(result.text) * 100
    assert :binary.referenced_byte_size(result.text) == byte_size(result.text)
  end

  test "analyze_many owns final text independently" do
    text = long_url_text()

    assert {:ok, [[%Result{} = result]]} =
             Obscura.Analyzer.analyze_many([text],
               profile: :fast,
               entities: [:url],
               include_text: true,
               telemetry: false
             )

    assert :binary.referenced_byte_size(result.text) == byte_size(result.text)
  end

  test "custom recognizer borrowed text is normalized to owned final text" do
    text = safe_padding(200_000) <> "https://" <> String.duplicate("custom-path/", 64)

    assert {:ok, [%Result{} = result]} =
             Obscura.analyze(text,
               profile: :fast,
               built_ins: false,
               entities: [:url],
               recognizers: [BorrowingRecognizer],
               include_text: true,
               telemetry: false
             )

    assert :binary.referenced_byte_size(result.text) == byte_size(result.text)
    assert result.metadata.matched_prefix_bytes == 8
  end

  test "include_text false removes custom borrowed values" do
    text = safe_padding(200_000) <> "https://" <> String.duplicate("custom-path/", 64)

    assert {:ok, [%Result{text: nil}]} =
             Obscura.analyze(text,
               profile: :fast,
               built_ins: false,
               entities: [:url],
               recognizers: [BorrowingRecognizer],
               include_text: false,
               telemetry: false
             )
  end

  test "pattern validation metadata and explanations do not retain the source" do
    captured = String.duplicate("A", 1_024)
    text = safe_padding(200_000) <> captured <> safe_padding(200_000)

    definition =
      PatternDefinition.new!(
        name: :metadata_ownership_test,
        entity: :person,
        patterns: [%{name: :captured, regex: ~r/A{1024}/, score: 0.9}],
        validate: fn value -> {:ok, %{nested: [%{captured: value}]}} end
      )

    assert {:ok, [%Result{} = result]} =
             Obscura.analyze(text,
               profile: :fast,
               built_ins: false,
               entities: [:person],
               recognizers: [definition],
               include_text: false,
               explain: true,
               telemetry: false
             )

    assert result.text == nil
    assert result.metadata.nested == [%{captured: captured}]
    assert result.explanation.metadata.nested == [%{captured: captured}]

    assert :binary.referenced_byte_size(result.metadata.nested |> hd() |> Map.fetch!(:captured)) ==
             byte_size(captured)

    assert :binary.referenced_byte_size(
             result.explanation.metadata.nested
             |> hd()
             |> Map.fetch!(:captured)
           ) == byte_size(captured)
  end

  test "parser-backed phone metadata remains explicit PII but owns its binaries" do
    if Code.ensure_loaded?(ExPhoneNumber) do
      assert {:ok, [%Result{text: nil} = result]} =
               Obscura.analyze("Call +44 20 7946 0958",
                 profile: :fast,
                 entities: [:phone],
                 include_text: false,
                 phone_parser: Obscura.Recognizer.Phone.ExPhoneNumberValidator,
                 phone_regions: ["GB"],
                 telemetry: false
               )

      assert result.metadata.phone_e164 == "+442079460958"

      assert :binary.referenced_byte_size(result.metadata.phone_e164) ==
               byte_size(result.metadata.phone_e164)
    end
  end

  test "include_text true preserves an offset-only custom recognizer result" do
    assert {:ok, [%Result{text: nil}]} =
             Obscura.analyze("Alice",
               profile: :fast,
               built_ins: false,
               entities: [:person],
               recognizers: [OffsetOnlyRecognizer],
               include_text: true,
               telemetry: false
             )
  end

  test "built-in recognizers avoid result text materialization when disabled" do
    assert [%Result{text: nil, entity: :email}] =
             Email.analyze("probe@example.test",
               include_text: false,
               explain: false
             )

    assert [%Result{text: nil, entity: :person}] =
             PersonName.analyze("My name is Rachel Green,",
               profile: :deterministic_plus,
               include_text: false
             )

    assert Enum.all?(
             Address.analyze("address: 12 Main Street, Denver",
               profile: :deterministic_plus,
               include_text: false
             ),
             &is_nil(&1.text)
           )

    assert Enum.all?(
             Location.analyze("address: 12 Main Street, Denver",
               profile: :deterministic_plus,
               include_text: false
             ),
             &is_nil(&1.text)
           )

    assert Enum.all?(
             Domain.analyze("Just posted a photo https://example.test/",
               include_text: false
             ),
             &is_nil(&1.text)
           )

    assert [%Result{text: nil, entity: :url}] =
             DenyList.analyze(
               "block-this-value",
               [%{entity: :url, values: ["block-this-value"]}],
               include_text: false
             )
  end

  test "allow lists derive temporary values from offsets when text is disabled" do
    url = "https://example.test/" <> String.duplicate("segment/", 64)
    text = safe_padding(100_000) <> " " <> url <> " " <> safe_padding(100_000)

    assert {:ok, []} =
             Obscura.analyze(text,
               profile: :fast,
               entities: [:url],
               allow_list: [%{entity: :url, values: [url]}],
               include_text: false,
               telemetry: false
             )
  end

  test "include_text changes only the documented text field" do
    text =
      "Contact probe@example.test or +1 202-555-0188. " <>
        "Card 4111 1111 1111 1111."

    opts = [
      profile: :fast,
      entities: [:email, :phone, :credit_card],
      telemetry: false
    ]

    assert {:ok, with_text} = Obscura.analyze(text, Keyword.put(opts, :include_text, true))
    assert {:ok, without_text} = Obscura.analyze(text, Keyword.put(opts, :include_text, false))

    assert Enum.map(with_text, &Map.put(&1, :text, nil)) == without_text
    assert Enum.all?(with_text, &is_binary(&1.text))
    assert Enum.all?(without_text, &is_nil(&1.text))
  end

  test "returned boundary object graphs do not retain borrowed source binaries" do
    operations = [
      fn ->
        text = padded_text(400_000, "credit card 4111 1111 1111 1111")

        {:ok, [result]} =
          Obscura.analyze(text,
            profile: :fast,
            entities: [:credit_card],
            include_text: false,
            explain: true,
            telemetry: false
          )

        result
      end,
      fn ->
        text = padded_text(400_000, "probe@example.test")

        {:ok, results} =
          Obscura.analyze(text,
            profile: :fast,
            entities: [:email],
            include_text: false,
            telemetry: false
          )

        {:ok, result} = Obscura.anonymize(text, results, telemetry: false)
        result
      end,
      fn ->
        text = padded_text(400_000, "probe@example.test")

        {:ok, result} =
          Obscura.Structured.redact(%{nested: [%{payload: text}]},
            profile: :fast,
            entities: [:email],
            telemetry: false
          )

        result
      end,
      fn ->
        text = padded_text(400_000, "probe@example.test")

        {:ok, result} =
          Obscura.Logger.redact_term(%{payload: text},
            profile: :fast,
            entities: [:email],
            telemetry: false
          )

        result
      end,
      fn ->
        text = padded_text(400_000, "probe@example.test")

        :post
        |> Plug.Test.conn("/", %{})
        |> Map.put(:params, %{"payload" => text})
        |> ObscuraPlug.call(
          fields: [:params],
          mode: :replace,
          profile: :fast,
          entities: [:email],
          telemetry: false
        )
      end
    ]

    for operation <- operations do
      result = run_isolated(operation)
      assert borrowed_binary_paths(result) == []
    end
  end

  defp long_url_text do
    url = "https://example.test/" <> String.duplicate("segment/", 64)
    safe_padding(200_000) <> " " <> url <> " " <> safe_padding(200_000)
  end

  defp padded_text(target_bytes, match) do
    remaining = max(target_bytes - byte_size(match), 0)
    prefix_bytes = div(remaining, 2)
    suffix_bytes = remaining - prefix_bytes
    safe_padding(prefix_bytes) <> match <> safe_padding(suffix_bytes)
  end

  defp run_isolated(operation) do
    parent = self()

    {pid, monitor} =
      spawn_monitor(fn ->
        result = operation.()
        send(parent, {:ownership_result, self(), result})
      end)

    receive do
      {:ownership_result, ^pid, result} ->
        receive do
          {:DOWN, ^monitor, :process, ^pid, :normal} -> result
        end

      {:DOWN, ^monitor, :process, ^pid, reason} ->
        flunk("ownership worker failed: #{inspect(reason)}")
    after
      5_000 -> flunk("ownership worker timed out")
    end
  end

  defp borrowed_binary_paths(term), do: inspect_binaries(term, [], [])

  defp inspect_binaries(value, path, acc) when is_binary(value) do
    if :binary.referenced_byte_size(value) > byte_size(value), do: [path | acc], else: acc
  end

  defp inspect_binaries(value, path, acc) when is_map(value) do
    value
    |> Map.delete(:__struct__)
    |> Enum.reduce(acc, fn {key, nested}, paths ->
      paths = inspect_binaries(key, [:map_key | path], paths)
      inspect_binaries(nested, [safe_path_part(key) | path], paths)
    end)
  end

  defp inspect_binaries(value, path, acc) when is_list(value) do
    value
    |> Stream.with_index()
    |> Enum.reduce(acc, fn {nested, index}, paths ->
      inspect_binaries(nested, [index | path], paths)
    end)
  end

  defp inspect_binaries(value, path, acc) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> inspect_binaries(path, acc)
  end

  defp inspect_binaries(_value, _path, acc), do: acc

  defp safe_path_part(value) when is_atom(value), do: value
  defp safe_path_part(value) when is_integer(value), do: value
  defp safe_path_part(_value), do: :dynamic_key

  defp safe_padding(bytes) do
    pattern = "safe text "
    repeats = div(bytes, byte_size(pattern))
    rest = rem(bytes, byte_size(pattern))
    String.duplicate(pattern, repeats) <> binary_part(pattern, 0, rest)
  end
end
