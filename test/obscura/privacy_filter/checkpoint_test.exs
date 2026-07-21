defmodule Obscura.PrivacyFilter.CheckpointTest do
  use ExUnit.Case, async: true

  alias Obscura.PrivacyFilter.Checkpoint

  test "returns a clear error for missing checkpoint directory" do
    assert {:error, {:checkpoint_dir_not_found, "missing/privacy-filter"}} =
             Checkpoint.validate("missing/privacy-filter")
  end

  test "fails before inference when safetensors files are missing" do
    path = tmp_dir!()
    File.write!(Path.join(path, "config.json"), Jason.encode!(config()))

    assert {:error, {:missing_safetensors_files, ^path}} = Checkpoint.validate(path)
  end

  test "fails clearly when Python original files are passed as native layout" do
    path = tmp_dir!()
    File.write!(Path.join(path, "config.json"), Jason.encode!(config()))
    File.write!(Path.join(path, "model.safetensors"), "")
    File.write!(Path.join(path, "dtypes.json"), "{}")

    assert {:error, {:python_original_layout_requires_explicit_opt_in, ^path}} =
             Checkpoint.validate(path)
  end

  defp tmp_dir! do
    path =
      Path.join(
        System.tmp_dir!(),
        "obscura-privacy-filter-checkpoint-#{System.unique_integer([:positive])}-#{System.system_time(:nanosecond)}"
      )

    File.mkdir_p!(path)
    path
  end

  defp config do
    %{
      model_type: "privacy_filter",
      encoding: "o200k_base",
      num_hidden_layers: 1,
      num_experts: 1,
      experts_per_token: 1,
      vocab_size: 10,
      num_labels: 5,
      hidden_size: 2,
      intermediate_size: 2,
      head_dim: 2,
      num_attention_heads: 2,
      num_key_value_heads: 1,
      sliding_window: 3,
      bidirectional_context: true,
      bidirectional_left_context: 1,
      bidirectional_right_context: 1,
      initial_context_length: 16,
      rope_theta: 10_000.0,
      rope_scaling_factor: 1.0,
      rope_ntk_alpha: 1.0,
      rope_ntk_beta: 32.0,
      param_dtype: "bfloat16",
      ner_class_names: [
        "O",
        "B-private_person",
        "I-private_person",
        "E-private_person",
        "S-private_person"
      ]
    }
  end
end
