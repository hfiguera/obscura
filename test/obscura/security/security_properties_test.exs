defmodule Obscura.Security.PropertiesTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Obscura.Anonymizer.Error
  alias Obscura.Stream.Rehydrator
  alias Obscura.Vault
  alias Obscura.Vault.ETS
  alias Obscura.Vault.Memory

  @canary "OBSCURA-PROPERTY-CANARY@example.test"
  @unicode_segments [
    "ASCII",
    "é",
    "e\u0301",
    "界",
    "👩‍💻",
    "مرحبا",
    "שלום",
    "\u0000",
    "\r\n",
    "\t"
  ]
  @invalid_utf8 [
    <<0xFF>>,
    <<0xC3>>,
    <<0xE2, 0x28, 0xA1>>,
    <<0xF0, 0x28, 0x8C, 0xBC>>,
    <<0x80>>,
    <<0xC0, 0xAF>>
  ]

  property "valid Unicode preserves exact byte spans and produces safe inspections" do
    check all(segments <- list_of(member_of(@unicode_segments), max_length: 30), max_runs: 80) do
      prefix = Enum.join(segments)
      text = prefix <> " | " <> @canary
      start = byte_size(prefix) + 3

      assert String.valid?(text)
      assert {:ok, results} = Obscura.analyze(text, entities: [:email])
      assert [result] = results
      assert result.byte_start == start
      assert result.byte_end == byte_size(text)
      assert binary_part(text, result.byte_start, result.byte_end - result.byte_start) == @canary

      assert {:ok, redacted} = Obscura.anonymize(text, results)
      assert String.valid?(redacted.text)
      refute inspect(results) =~ @canary
      refute inspect(redacted) =~ @canary
    end
  end

  property "invalid UTF-8 returns controlled errors at stable text boundaries" do
    check all(input <- member_of(@invalid_utf8), max_runs: 30) do
      refute String.valid?(input)
      assert {:error, :invalid_utf8} = Obscura.analyze(input)
      assert {:error, :invalid_utf8} = Obscura.Analyzer.analyze(input)
      assert {:error, :invalid_utf8} = Obscura.Analyzer.analyze_many([input])
      assert {:error, :invalid_utf8} = Obscura.anonymize(input, [])
      assert {:error, :invalid_utf8} = Obscura.redact(input)
      assert {:error, :invalid_utf8} = Obscura.Structured.redact(%{value: input})
      assert {:error, :invalid_utf8} = Obscura.rehydrate(input, vault: self())
    end
  end

  property "malformed operators and spans return value-safe errors without raises" do
    configs = [
      %{type: :unknown, secret: @canary},
      %{type: :mask, char: @canary},
      %{type: :mask, keep_last: @canary},
      %{type: :hash, mode: :secure, salt: @canary},
      %{type: :hash, algorithm: @canary},
      %{type: :custom, module: @canary},
      %{type: :pseudonymize, vault: @canary}
    ]

    malformed_spans = [
      nil,
      %{},
      %{entity: @canary, byte_start: 0, byte_end: 1},
      %{entity: :email, byte_start: @canary, byte_end: 1},
      %{entity: :email, byte_start: -1, byte_end: 1},
      %{entity: :email, byte_start: 0, byte_end: 10_000}
    ]

    check all(
            config <- member_of(configs),
            malformed_span <- member_of(malformed_spans),
            max_runs: 80
          ) do
      assert {:error, %Error{} = operator_error} =
               Obscura.anonymize(@canary, [span(@canary)], operators: %{email: config})

      refute inspect(operator_error) =~ @canary

      assert {:error, {:invalid_span, span_error}} =
               Obscura.anonymize(@canary, [malformed_span])

      refute inspect(span_error) =~ @canary
    end
  end

  property "bounded nested maps and lists either redact or stop at the depth limit" do
    check all(
            depth <- integer(0..32),
            containers <-
              list_of(member_of([:map, :list]), min_length: depth, max_length: depth),
            max_runs: 70
          ) do
      nested =
        Enum.reduce(containers, @canary, fn
          :map, acc -> %{payload: acc}
          :list, acc -> [acc]
        end)

      case Obscura.Structured.redact(nested, max_depth: 20, entities: [:email]) do
        {:ok, result} ->
          refute inspect(result) =~ @canary
          refute contains_binary?(result.data, @canary)

        {:error, :max_depth_exceeded} ->
          assert depth > 20
      end
    end
  end

  property "deep opaque tuples and structs stop traversal without leaking through inspection" do
    check all(
            depth <- integer(0..32),
            containers <-
              list_of(member_of([:map, :list]), min_length: depth, max_length: depth),
            leaf <- member_of([{@canary}, %URI{path: @canary}]),
            max_runs: 60
          ) do
      nested =
        Enum.reduce(containers, leaf, fn
          :map, acc -> %{payload: acc}
          :list, acc -> [acc]
        end)

      case Obscura.Structured.redact(nested, max_depth: 20, entities: [:email]) do
        {:ok, result} ->
          assert result.data == nested
          refute inspect(result) =~ @canary

        {:error, :max_depth_exceeded} ->
          assert depth > 20
      end
    end
  end

  property "malformed and adversarial tokens never appear in lookup errors" do
    token_generator =
      one_of([
        map(binary(max_length: 256), fn suffix ->
          @canary <> Base.url_encode64(suffix, padding: false)
        end),
        map(integer(0..2_048), fn count ->
          "<<" <> @canary <> String.duplicate("A", count) <> ">>"
        end),
        member_of(["<<", ">>", "<<UNKNOWN_999>>", "<<A B>>", @canary])
      ])

    check all(token <- token_generator, max_runs: 100) do
      assert {:ok, vault} = Memory.start_link()
      result = Vault.lookup_token(vault, token)

      assert match?({:error, _reason}, result)

      if String.valid?(token) do
        if String.contains?(token, @canary), do: refute(inspect(result) =~ @canary)
      else
        assert result == {:error, :invalid_utf8}
      end

      GenServer.stop(vault)
    end
  end

  property "concurrent vault access remains isolated and clear removes accessible entries" do
    check all(worker_count <- integer(2..12), max_runs: 30) do
      assert {:ok, vault} = Memory.start_link()

      results =
        1..worker_count
        |> Task.async_stream(
          fn _index -> Vault.get_or_create(vault, :email, @canary) end,
          max_concurrency: worker_count,
          ordered: false
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.uniq(results) == [{:ok, "<<EMAIL_001>>"}]

      restored =
        1..worker_count
        |> Task.async_stream(
          fn _index -> Obscura.rehydrate("prefix <<EMAIL_001>>", vault: vault) end,
          max_concurrency: worker_count,
          ordered: false
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.uniq(restored) == [{:ok, "prefix " <> @canary}]
      assert :ok = Vault.clear(vault)
      assert {:error, {:token_not_found, _shape}} = Vault.lookup_token(vault, "<<EMAIL_001>>")

      GenServer.stop(vault)
      assert {:error, {:vault_unavailable, _reason}} = Vault.lookup_token(vault, "<<EMAIL_001>>")
    end
  end

  test "improper structures and malformed structured options fail without recursion or value leaks" do
    improper = [@canary | :invalid_tail]

    assert {:error, :improper_list} = Obscura.Structured.redact(improper)

    for opts <- [
          [max_depth: -1],
          [max_depth: @canary],
          [dry_run: @canary],
          [traverse_structs: @canary],
          [preserve_structs: @canary],
          [field_policies: improper]
        ] do
      assert {:error, %Error{} = error} = Obscura.Structured.redact(%{value: @canary}, opts)
      refute inspect(error) =~ @canary
    end

    tuple = {@canary, %{value: @canary}}
    assert {:ok, result} = Obscura.Structured.redact(tuple)
    assert result.data == tuple
    refute inspect(result) =~ @canary
  end

  test "ETS vault tables are private, unnamed, cleared, and destroyed with their owner" do
    assert {:ok, vault} = ETS.start_link(table: :security_private_vault)
    assert {:ok, token} = Vault.get_or_create(vault, :email, @canary)
    state = :sys.get_state(vault)

    assert :ets.info(state.by_value, :named_table) == false
    assert :ets.info(state.by_token, :named_table) == false

    assert_raise ArgumentError, fn ->
      :ets.lookup(state.by_value, {:email, @canary})
    end

    assert_raise ArgumentError, fn ->
      :ets.lookup(state.by_token, token)
    end

    assert :ok = Vault.clear(vault)
    assert {:error, {:token_not_found, _shape}} = Vault.lookup_token(vault, token)

    GenServer.stop(vault)
    assert :ets.info(state.by_value) == :undefined
    assert :ets.info(state.by_token) == :undefined

    assert {:ok, crashing_vault} = ETS.start_link()
    crashing_state = :sys.get_state(crashing_vault)
    Process.unlink(crashing_vault)
    reference = Process.monitor(crashing_vault)
    Process.exit(crashing_vault, :kill)

    assert_receive {:DOWN, ^reference, :process, ^crashing_vault, :killed}
    assert :ets.info(crashing_state.by_value) == :undefined
    assert :ets.info(crashing_state.by_token) == :undefined
  end

  test "malformed vault startup configurations fail without exposing values" do
    improper = [{:name, :vault} | @canary]

    for {module, opts} <- [
          {Memory, @canary},
          {Memory, improper},
          {Memory, [name: @canary]},
          {Memory, [unknown: @canary]},
          {Memory, [token_width: @canary]},
          {ETS, [name: @canary]},
          {ETS, [table: @canary]},
          {ETS, [token_prefix: 1]}
        ] do
      assert {:error, reason} = module.start_link(opts)
      refute inspect(reason) =~ @canary
    end
  end

  test "stream token limits and unknown-token failures expose shape, not token content" do
    assert {:ok, vault} = Memory.start_link()
    assert {:ok, stream} = Rehydrator.new(vault: vault, max_token_length: 16, unknown: :error)

    assert {:error, {:token_not_found, shape} = reason} =
             Rehydrator.feed(stream, "<<UNKNOWN_001>>")

    assert shape == %{bytes: 15, token_like: true}
    refute inspect(reason) =~ "UNKNOWN"

    assert {:ok, bounded} = Rehydrator.new(vault: vault, max_token_length: 8)
    assert {:error, {:token_too_long, 8}} = Rehydrator.feed(bounded, "<<AAAAAAAA")
  end

  defp span(value) do
    %{entity: :email, byte_start: 0, byte_end: byte_size(value), value: value}
  end

  defp contains_binary?(value, target) when is_binary(value), do: value == target

  defp contains_binary?(value, target) when is_map(value),
    do: Enum.any?(value, &contains_pair?(&1, target))

  defp contains_binary?(value, target) when is_list(value),
    do: Enum.any?(value, &contains_binary?(&1, target))

  defp contains_binary?(_value, _target), do: false

  defp contains_pair?({key, value}, target) do
    contains_binary?(key, target) or contains_binary?(value, target)
  end
end
