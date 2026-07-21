defmodule Obscura.Recognizer.GLiNER.ConfigTest do
  use ExUnit.Case, async: true

  alias Obscura.Recognizer.GLiNER.Config

  test "builds default hybrid_core config" do
    assert {:ok, config} = Config.new([])
    assert config.model == :knowledgator_gliner_pii_base_v1
    assert config.label_profile == :hybrid_core
    assert config.threshold == 0.5
    assert config.max_width == 12
  end

  test "validates supported model config file and copies model limits" do
    path =
      temp_config!(%{
        "model_type" => "gliner",
        "span_mode" => "markerV0",
        "words_splitter_type" => "whitespace",
        "max_width" => 8,
        "max_len" => 512
      })

    assert {:ok, config} = Config.new([])
    assert {:ok, updated} = Config.from_model_config_file(path, config)
    assert updated.max_width == 8
    assert updated.max_length == 512
  end

  test "validates token-level Edge model config file" do
    path =
      temp_config!(%{
        "model_type" => "gliner",
        "span_mode" => "token_level",
        "words_splitter_type" => "whitespace",
        "max_width" => 12,
        "max_len" => 2048
      })

    assert {:ok, config} = Config.new(model: :knowledgator_gliner_pii_edge_v1)
    assert {:ok, updated} = Config.from_model_config_file(path, config)
    assert updated.span_mode == :token_level
  end

  test "default GLiNER model remains the base model" do
    assert {:ok, config} = Config.new([])

    assert config.model == :knowledgator_gliner_pii_base_v1
  end

  test "rejects unsupported model config fields" do
    path =
      temp_config!(%{
        "model_type" => "other",
        "span_mode" => "markerV0",
        "words_splitter_type" => "whitespace"
      })

    assert {:ok, config} = Config.new([])

    assert {:error, {:unsupported_gliner_model_type, "other"}} =
             Config.from_model_config_file(path, config)
  end

  test "accepts the pinned Urchade export's legacy null model type" do
    path =
      temp_config!(%{
        "model_type" => nil,
        "span_mode" => "markerV0",
        "words_splitter_type" => "whitespace",
        "max_width" => 12,
        "max_len" => 384,
        "class_token_index" => 250_103,
        "embed_ent_token" => true
      })

    assert {:ok, config} = Config.new(model: :urchade_gliner_multi_pii_v1)
    assert {:ok, updated} = Config.from_model_config_file(path, config)
    assert updated.max_length == 384
    assert updated.class_token_index == 250_103
    assert updated.embed_ent_token
  end

  test "does not accept a null model type for other registered GLiNER models" do
    path =
      temp_config!(%{
        "model_type" => nil,
        "span_mode" => "markerV0",
        "words_splitter_type" => "whitespace"
      })

    assert {:ok, config} = Config.new(model: :knowledgator_gliner_pii_base_v1)

    assert {:error, {:unsupported_gliner_model_type, nil}} =
             Config.from_model_config_file(path, config)
  end

  defp temp_config!(map) do
    path = Path.join(System.tmp_dir!(), "obscura-gliner-config-#{System.unique_integer()}.json")
    File.write!(path, Jason.encode!(map))
    path
  end
end
