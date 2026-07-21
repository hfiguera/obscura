defmodule Obscura.OperatorHardeningTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Obscura.Anonymizer.Error
  alias Obscura.Anonymizer.Operator
  alias Obscura.Operator.Hash

  defmodule SuccessfulCustom do
    @behaviour Obscura.Operator.Custom

    @impl Obscura.Operator.Custom
    def apply(value, context, options) do
      send(options.test_pid, {:custom_called, context})
      {:ok, "<#{options.prefix}:#{byte_size(value)}>", %{source_length: byte_size(value)}}
    end
  end

  defmodule ErrorCustom do
    @behaviour Obscura.Operator.Custom
    @impl Obscura.Operator.Custom
    def apply(_value, _context, _options), do: {:error, "raw callback secret"}
  end

  defmodule InvalidReturnCustom do
    @behaviour Obscura.Operator.Custom
    @impl Obscura.Operator.Custom
    def apply(_value, _context, _options), do: {:ok, 123}
  end

  defmodule RaiseCustom do
    @behaviour Obscura.Operator.Custom
    @impl Obscura.Operator.Custom
    def apply(_value, _context, _options), do: raise("raw exception secret")
  end

  defmodule ThrowCustom do
    @behaviour Obscura.Operator.Custom
    @impl Obscura.Operator.Custom
    def apply(_value, _context, _options), do: throw("raw throw secret")
  end

  defmodule ExitCustom do
    @behaviour Obscura.Operator.Custom
    @impl Obscura.Operator.Custom
    def apply(_value, _context, _options), do: exit("raw exit secret")
  end

  defmodule MissingBehaviour do
    def apply(_value, _context, _options), do: {:ok, "unsafe"}
  end

  test "unknown operators return a structured error instead of deleting content" do
    text = "Email jane@example.com"

    assert {:error, %Error{} = error} =
             Obscura.anonymize(text, [span(:email, 6, 22)],
               operators: %{email: %{type: :unknown}}
             )

    assert error.code == :unsupported_operator
    assert error.operator == :unknown
    refute inspect(error) =~ "jane@example.com"
  end

  test "malformed operator collections and configs return structured errors" do
    assert_error(Operator.validate_configs(:invalid),
      code: :invalid_operator_collection,
      field: :operators
    )

    assert_error(Operator.validate_configs(%{"private" => %{type: :redact}}),
      code: :invalid_operator_collection,
      field: :operators
    )

    assert_error(Operator.validate_config(%{}),
      code: :missing_operator_option,
      field: :type
    )

    assert_error(Operator.validate_config("invalid"), code: :invalid_operator_config)

    assert_error(Operator.validate_config(%{type: "mask"}),
      code: :invalid_operator_option,
      field: :type
    )
  end

  test "engine validates reserved collection options" do
    text = "Email jane@example.com"
    spans = [span(:email, 6, 22)]

    assert {:error, %Error{field: :merge_whitespace}} =
             Obscura.anonymize(text, spans,
               operators: %{default: %{type: :redact}, merge_whitespace: :yes}
             )

    assert {:error, %Error{field: :conflict_strategy}} =
             Obscura.anonymize(text, spans,
               operators: %{default: %{type: :redact}, conflict_policy: :unknown}
             )
  end

  test "all configurations are validated before any callback can modify state" do
    text = "jane@example.com 202-555-0188"

    operators = %{
      email: %{
        type: :custom,
        module: SuccessfulCustom,
        options: %{prefix: "email", test_pid: self()}
      },
      phone: %{type: :unknown}
    }

    assert {:error, %Error{code: :unsupported_operator}} =
             Obscura.anonymize(text, [span(:email, 0, 16), span(:phone, 17, 29)],
               operators: operators
             )

    refute_receive {:custom_called, _context}
  end

  test "replace and redact validate options and preserve valid behavior" do
    assert {:replace, "[EMAIL]", %{}} =
             Operator.apply("jane@example.com", %{type: :replace, value: "[EMAIL]"})

    assert {:replace, "[REDACTED]", %{}} =
             Operator.apply("jane@example.com", %{type: :replace})

    assert {:redact, "", %{}} = Operator.apply("jane@example.com", %{type: :redact})

    assert_error(Operator.apply("value", %{type: :replace, value: 123}),
      code: :invalid_operator_option,
      operator: :replace,
      field: :value
    )

    assert_error(Operator.apply("value", %{type: :redact, value: "ignored"}),
      code: :unknown_operator_option,
      operator: :redact
    )
  end

  test "mask validates one grapheme and non-negative keep_last" do
    assert {:mask, "***0188", %{}} =
             Operator.apply("5550188", %{type: :mask, char: "*", keep_last: 4})

    assert {:mask, "short", %{}} =
             Operator.apply("short", %{type: :mask, char: "*", keep_last: 99})

    assert {:mask, "🛡️🛡️界", %{}} =
             Operator.apply("Ae\u0301界", %{type: :mask, char: "🛡️", keep_last: 1})

    for config <- [
          %{type: :mask, char: ""},
          %{type: :mask, char: "**"},
          %{type: :mask, char: 42},
          %{type: :mask, keep_last: -1},
          %{type: :mask, keep_last: "4"},
          %{type: :mask, unknown: true}
        ] do
      assert {:error, %Error{}} = Operator.apply("value", config)
    end

    assert_error(Operator.apply(<<255>>, %{type: :mask}),
      code: :invalid_operator_option,
      operator: :mask,
      field: :source
    )
  end

  test "deterministic hash is repeatable, separated by input, and verifiable" do
    config = %{
      type: :hash,
      mode: :deterministic,
      algorithm: :sha256,
      salt: "0123456789abcdef"
    }

    assert {:hash, first, metadata} = Operator.apply("alpha", config)
    assert {:hash, second, ^metadata} = Operator.apply("alpha", config)
    assert {:hash, other, _metadata} = Operator.apply("beta", config)

    assert first == second
    refute first == other
    assert metadata.deterministic
    assert metadata.mode == :deterministic
    assert Hash.verify("alpha", first)
    refute Hash.verify("beta", first)
  end

  test "secure hash uses fresh salts and remains verifiable" do
    config = %{type: :hash, mode: :secure, algorithm: :sha512}

    assert {:hash, first, first_metadata} = Operator.apply("alpha", config)
    assert {:hash, second, second_metadata} = Operator.apply("alpha", config)

    refute first == second
    refute first_metadata.salt == second_metadata.salt
    refute first_metadata.deterministic
    assert first_metadata.algorithm == :sha512
    assert first_metadata.version == 1
    assert Hash.verify("alpha", first)
    assert Hash.verify("alpha", second)
    refute Hash.verify("beta", first)
    refute Hash.verify("alpha", "malformed")
  end

  test "hash defaults to secure SHA-256 with a fresh salt" do
    assert {:hash, first, %{algorithm: :sha256, mode: :secure}} =
             Operator.apply("alpha", %{type: :hash})

    assert {:hash, second, %{algorithm: :sha256, mode: :secure}} =
             Operator.apply("alpha", %{type: :hash})

    refute first == second
  end

  test "hash rejects unsupported algorithms, modes, salts, options, and input types" do
    invalid_configs = [
      %{type: :hash, algorithm: :md5},
      %{type: :hash, mode: :legacy},
      %{type: :hash, mode: :deterministic},
      %{type: :hash, mode: :deterministic, salt: "short"},
      %{type: :hash, mode: :deterministic, salt: 123},
      %{type: :hash, mode: :secure, salt: "0123456789abcdef"},
      %{type: :hash, unknown: true}
    ]

    Enum.each(invalid_configs, fn config ->
      assert {:error, %Error{}} = Operator.apply("value", config)
    end)

    assert {:error, %Error{field: :source}} = Operator.apply(123, %{type: :hash})
  end

  test "custom operator behavior succeeds with explicit safe context" do
    config = %{
      type: :custom,
      module: SuccessfulCustom,
      options: %{prefix: "masked", test_pid: self()}
    }

    context = %{entity: :email, span: %{value: "hidden"}, opts: [secret: "hidden"]}

    assert {:custom, "<masked:16>", metadata} =
             Operator.apply("jane@example.com", config, context)

    assert metadata.custom_module == SuccessfulCustom
    assert metadata.source_length == 16
    assert_receive {:custom_called, %{entity: :email} = callback_context}
    refute Map.has_key?(callback_context, :span)
    refute Map.has_key?(callback_context, :opts)
  end

  test "custom operator validates module and options" do
    assert_error(Operator.apply("value", %{type: :custom}),
      code: :missing_operator_option,
      operator: :custom,
      field: :module
    )

    for config <- [
          %{type: :custom, module: MissingBehaviour},
          %{type: :custom, module: :module_that_does_not_exist},
          %{type: :custom, module: SuccessfulCustom, options: []},
          %{type: :custom, module: SuccessfulCustom, callback: "legacy"}
        ] do
      assert {:error, %Error{}} = Operator.apply("value", config)
    end
  end

  test "custom operator sanitizes callback errors and invalid returns" do
    expectations = [
      {ErrorCustom, :operator_failed, :callback_error},
      {InvalidReturnCustom, :invalid_operator_result, :invalid_callback_return},
      {RaiseCustom, :operator_failed, :exception},
      {ThrowCustom, :operator_failed, :throw},
      {ExitCustom, :operator_failed, :exit}
    ]

    Enum.each(expectations, fn {module, code, reason} ->
      assert {:error, %Error{code: ^code, reason: ^reason} = error} =
               Operator.apply("private value", %{type: :custom, module: module})

      rendered = inspect(error)
      refute rendered =~ "private value"
      refute rendered =~ "raw"
      refute rendered =~ "secret"
    end)
  end

  property "mask works on grapheme boundaries and preserves requested suffix" do
    grapheme = member_of(["a", "é", "e\u0301", "界", "👩‍💻"])

    check all(
            graphemes <- list_of(grapheme, max_length: 40),
            char <- member_of(["*", "█", "🛡️"]),
            keep_last <- integer(0..50)
          ) do
      value = Enum.join(graphemes)

      assert {:mask, replacement, %{}} =
               Operator.apply(value, %{type: :mask, char: char, keep_last: keep_last})

      replacement_graphemes = String.graphemes(replacement)
      masked_length = max(length(graphemes) - keep_last, 0)

      assert length(replacement_graphemes) == length(graphemes)

      assert Enum.take(replacement_graphemes, masked_length) ==
               List.duplicate(char, masked_length)

      assert Enum.drop(replacement_graphemes, masked_length) ==
               Enum.drop(graphemes, masked_length)
    end
  end

  property "deterministic hash is repeatable and separates distinct binary inputs" do
    check all(
            value <- binary(max_length: 128),
            salt <- binary(min_length: 16, max_length: 32),
            algorithm <- member_of([:sha256, :sha512])
          ) do
      config = %{type: :hash, mode: :deterministic, algorithm: algorithm, salt: salt}

      assert {:hash, first, _metadata} = Operator.apply(value, config)
      assert {:hash, second, _metadata} = Operator.apply(value, config)
      assert {:hash, different, _metadata} = Operator.apply(value <> <<0>>, config)

      assert first == second
      refute first == different
      assert Hash.verify(value, first)
      refute Hash.verify(value <> <<0>>, first)
    end
  end

  defp span(entity, start, end_offset) do
    %{entity: entity, byte_start: start, byte_end: end_offset}
  end

  defp assert_error(result, expected) do
    assert {:error, %Error{} = error} = result

    Enum.each(expected, fn {field, value} ->
      assert Map.fetch!(error, field) == value
    end)
  end
end
