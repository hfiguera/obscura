defmodule Obscura.Tiktoken.BPETest do
  use ExUnit.Case, async: true

  alias Obscura.Tiktoken.BPE

  test "merges lowest-rank byte pairs until stable" do
    ranks = %{
      "a" => 0,
      "b" => 1,
      "c" => 2,
      "ab" => 3,
      "bc" => 4,
      "abc" => 5
    }

    assert {:ok, [5]} = BPE.encode_piece("abc", ranks)
  end

  test "keeps lower-priority alternatives split" do
    ranks = %{
      "a" => 0,
      "b" => 1,
      "c" => 2,
      "ab" => 3,
      "bc" => 4
    }

    assert {:ok, [3, 2]} = BPE.encode_piece("abc", ranks)
  end
end
