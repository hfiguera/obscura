defmodule Obscura.Fixtures.Phase3AdapterTest do
  use ExUnit.Case, async: true

  alias Obscura.Fixtures.LLMAdapter
  alias Obscura.Fixtures.Loader
  alias Obscura.Fixtures.StreamAdapter
  alias Obscura.Fixtures.VaultAdapter

  test "vault fixtures match expected tokens and rehydrated text" do
    assert {:ok, fixtures} = Loader.load_all(suite: :vault)

    for fixture <- fixtures do
      assert {:ok, result} = VaultAdapter.run(fixture)
      assert result.tokens == fixture.expected_tokens, fixture.id
      assert result.rehydrated == fixture.expected_rehydrated, fixture.id
    end
  end

  test "llm fixtures match expected messages and rehydrated response" do
    assert {:ok, fixtures} = Loader.load_all(suite: :llm)

    for fixture <- fixtures do
      assert {:ok, result} = LLMAdapter.run(fixture)
      assert result.messages == fixture.expected_messages, fixture.id
      assert result.rehydrated_response == fixture.expected_rehydrated_response, fixture.id
    end
  end

  test "stream fixtures match expected emitted chunks and output" do
    assert {:ok, fixtures} = Loader.load_all(suite: :stream)

    for fixture <- fixtures do
      assert {:ok, result} = StreamAdapter.run(fixture)
      assert result.chunks == fixture.expected_chunks, fixture.id
      assert result.output == fixture.expected_output, fixture.id
    end
  end
end
