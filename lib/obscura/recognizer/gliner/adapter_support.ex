defmodule Obscura.Recognizer.GLiNER.AdapterSupport do
  @moduledoc false

  alias Obscura.Recognizer.GLiNER.Config

  @spec merge_config(Config.t(), keyword()) :: Config.t()
  def merge_config(config, []), do: config

  def merge_config(config, opts) do
    {:ok, override} =
      opts
      |> Keyword.put_new(:model, config.model)
      |> Keyword.put_new(:label_profile, config.label_profile)
      |> Keyword.put_new(:threshold, config.threshold)
      |> Keyword.put_new(:max_width, config.max_width)
      |> Keyword.put_new(:max_length, config.max_length)
      |> Keyword.put_new(:per_label_thresholds, config.per_label_thresholds)
      |> Keyword.put_new(:flat_ner, config.flat_ner)
      |> Keyword.put_new(:multi_label, config.multi_label)
      |> Keyword.put_new(:class_token_index, config.class_token_index)
      |> Keyword.put_new(:embed_ent_token, config.embed_ent_token)
      |> Config.new()

    override
  end
end
