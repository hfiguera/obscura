defmodule Obscura.Analyzer.BinaryOwnershipTest do
  use ExUnit.Case, async: true

  alias Obscura.Analyzer.Result

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

  test "built-in recognizers avoid result text materialization when disabled" do
    assert [%Result{text: nil, entity: :email}] =
             Obscura.Recognizer.Email.analyze("probe@example.test",
               include_text: false,
               explain: false
             )

    assert [%Result{text: nil, entity: :person}] =
             Obscura.Recognizer.PersonName.analyze("My name is Rachel Green,",
               profile: :deterministic_plus,
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

  defp long_url_text do
    url = "https://example.test/" <> String.duplicate("segment/", 64)
    safe_padding(200_000) <> " " <> url <> " " <> safe_padding(200_000)
  end

  defp safe_padding(bytes) do
    pattern = "safe text "
    repeats = div(bytes, byte_size(pattern))
    rest = rem(bytes, byte_size(pattern))
    String.duplicate(pattern, repeats) <> binary_part(pattern, 0, rest)
  end
end
