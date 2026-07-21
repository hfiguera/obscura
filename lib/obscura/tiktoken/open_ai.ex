defmodule Obscura.Tiktoken.OpenAI do
  @moduledoc false

  alias Obscura.Tiktoken.Encoding
  alias Obscura.Tiktoken.Loader

  @endoftext "<|endoftext|>"
  @fim_prefix "<|fim_prefix|>"
  @fim_middle "<|fim_middle|>"
  @fim_suffix "<|fim_suffix|>"
  @endofprompt "<|endofprompt|>"

  @r50k_pat_str ~S<'(?:[sdmt]|ll|ve|re)| ?\p{L}++| ?\p{N}++| ?[^\s\p{L}\p{N}]++|\s++$|\s+(?!\S)|\s>

  @cl100k_pat_str ~S<'(?i:[sdmt]|ll|ve|re)|[^\r\n\p{L}\p{N}]?+\p{L}++|\p{N}{1,3}+| ?[^\s\p{L}\p{N}]++[\r\n]*+|\s++$|\s*[\r\n]|\s+(?!\S)|\s>

  @o200k_pat_str Enum.join(
                   [
                     ~S<[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]*[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?>,
                     ~S<[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]+[\p{Ll}\p{Lm}\p{Lo}\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?>,
                     ~S<\p{N}{1,3}>,
                     ~S< ?[^\s\p{L}\p{N}]+[\r\n/]*>,
                     ~S<\s*[\r\n]+>,
                     ~S<\s+(?!\S)>,
                     ~S<\s+>
                   ],
                   "|"
                 )

  @spec gpt2() :: {:ok, Encoding.t()} | {:error, term()}
  def gpt2 do
    build(
      name: "gpt2",
      explicit_n_vocab: 50_257,
      pat_str: @r50k_pat_str,
      bpe_file: "r50k_base.tiktoken",
      expected_hash: "306cd27f03c1a714eca7108e03d66b7dc042abe8c258b44c199a7ed9838dd930",
      special_tokens: %{@endoftext => 50_256}
    )
  end

  @spec r50k_base() :: {:ok, Encoding.t()} | {:error, term()}
  def r50k_base do
    build(
      name: "r50k_base",
      explicit_n_vocab: 50_257,
      pat_str: @r50k_pat_str,
      bpe_file: "r50k_base.tiktoken",
      expected_hash: "306cd27f03c1a714eca7108e03d66b7dc042abe8c258b44c199a7ed9838dd930",
      special_tokens: %{@endoftext => 50_256}
    )
  end

  @spec p50k_base() :: {:ok, Encoding.t()} | {:error, term()}
  def p50k_base do
    build(
      name: "p50k_base",
      explicit_n_vocab: 50_281,
      pat_str: @r50k_pat_str,
      bpe_file: "p50k_base.tiktoken",
      expected_hash: "94b5ca7dff4d00767bc256fdd1b27e5b17361d7b8a5f968547f9f23eb70d2069",
      special_tokens: %{@endoftext => 50_256}
    )
  end

  @spec p50k_edit() :: {:ok, Encoding.t()} | {:error, term()}
  def p50k_edit do
    build(
      name: "p50k_edit",
      pat_str: @r50k_pat_str,
      bpe_file: "p50k_base.tiktoken",
      expected_hash: "94b5ca7dff4d00767bc256fdd1b27e5b17361d7b8a5f968547f9f23eb70d2069",
      special_tokens: %{
        @endoftext => 50_256,
        @fim_prefix => 50_281,
        @fim_middle => 50_282,
        @fim_suffix => 50_283
      }
    )
  end

  @spec cl100k_base() :: {:ok, Encoding.t()} | {:error, term()}
  def cl100k_base do
    build(
      name: "cl100k_base",
      pat_str: @cl100k_pat_str,
      bpe_file: "cl100k_base.tiktoken",
      expected_hash: "223921b76ee99bde995b7ff738513eef100fb51d18c93597a113bcffe865b2a7",
      special_tokens: %{
        @endoftext => 100_257,
        @fim_prefix => 100_258,
        @fim_middle => 100_259,
        @fim_suffix => 100_260,
        @endofprompt => 100_276
      }
    )
  end

  @spec o200k_base() :: {:ok, Encoding.t()} | {:error, term()}
  def o200k_base do
    build(
      name: "o200k_base",
      pat_str: @o200k_pat_str,
      bpe_file: "o200k_base.tiktoken",
      expected_hash: "446a9538cb6c348e3516120d7c08b09f57c36495e2acfffe59a5bf8b0cfb1a2d",
      special_tokens: %{@endoftext => 199_999, @endofprompt => 200_018}
    )
  end

  @spec o200k_harmony() :: {:ok, Encoding.t()} | {:error, term()}
  def o200k_harmony do
    reserved =
      200_013..201_087
      |> Map.new(fn index -> {"<|reserved_#{index}|>", index} end)

    special_tokens =
      Map.merge(
        %{
          "<|startoftext|>" => 199_998,
          @endoftext => 199_999,
          "<|reserved_200000|>" => 200_000,
          "<|reserved_200001|>" => 200_001,
          "<|return|>" => 200_002,
          "<|constrain|>" => 200_003,
          "<|reserved_200004|>" => 200_004,
          "<|channel|>" => 200_005,
          "<|start|>" => 200_006,
          "<|end|>" => 200_007,
          "<|message|>" => 200_008,
          "<|reserved_200009|>" => 200_009,
          "<|reserved_200010|>" => 200_010,
          "<|reserved_200011|>" => 200_011,
          "<|call|>" => 200_012
        },
        reserved
      )

    build(
      name: "o200k_harmony",
      pat_str: @o200k_pat_str,
      bpe_file: "o200k_base.tiktoken",
      expected_hash: "446a9538cb6c348e3516120d7c08b09f57c36495e2acfffe59a5bf8b0cfb1a2d",
      special_tokens: special_tokens
    )
  end

  defp build(opts) do
    with {:ok, ranks} <-
           opts
           |> Keyword.fetch!(:bpe_file)
           |> asset_path()
           |> Loader.load_tiktoken_bpe(expected_hash: Keyword.fetch!(opts, :expected_hash)) do
      Encoding.new(
        name: Keyword.fetch!(opts, :name),
        explicit_n_vocab: Keyword.get(opts, :explicit_n_vocab),
        pat_str: Keyword.fetch!(opts, :pat_str),
        mergeable_ranks: ranks,
        special_tokens: Keyword.fetch!(opts, :special_tokens)
      )
    end
  end

  defp asset_path(filename) do
    case :code.priv_dir(:obscura) do
      path when is_list(path) -> Path.join([to_string(path), "tiktoken", filename])
      {:error, _reason} -> Path.expand(Path.join(["priv", "tiktoken", filename]))
    end
  end
end
