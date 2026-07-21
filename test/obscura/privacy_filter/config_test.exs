defmodule Obscura.PrivacyFilter.ConfigTest do
  use ExUnit.Case, async: true

  alias Obscura.PrivacyFilter.Config

  test "parses internal privacy-filter config shape" do
    assert {:ok, config} = Config.from_map(internal_config())
    assert config.model_type == "privacy_filter"
    assert config.encoding == "o200k_base"
    assert config.num_experts == 128
    assert config.experts_per_token == 4
    assert config.sliding_window == 257
    assert config.category_version == "custom"
  end

  test "normalizes Hugging Face openai/privacy-filter config shape" do
    assert {:ok, config} = Config.from_map(hf_config())

    assert config.model_type == "privacy_filter"
    assert config.encoding == "o200k_base"
    assert config.num_experts == 128
    assert config.experts_per_token == 4
    assert config.num_labels == 5
    assert config.bidirectional_context == true
    assert config.bidirectional_left_context == 2
    assert config.bidirectional_right_context == 2
    assert config.sliding_window == 5
    assert config.max_position_embeddings == 131_072
    assert config.rope_theta == 150_000.0
    assert config.rope_scaling_factor == 32.0
    assert config.rope_ntk_alpha == 1.0
    assert config.rope_ntk_beta == 32.0
    assert config.param_dtype == "bfloat16"

    assert config.ner_class_names == [
             "O",
             "B-private_person",
             "I-private_person",
             "E-private_person",
             "S-private_person"
           ]
  end

  test "normalizes OpenMed privacy-filter Nemotron 221-label Hugging Face config shape" do
    assert {:ok, config} =
             hf_config()
             |> Map.put("id2label", nemotron_id2label())
             |> Map.put("num_labels", 221)
             |> Config.from_map()

    assert config.model_type == "privacy_filter"
    assert config.num_labels == 221
    assert Enum.count(config.ner_class_names) == 221
    assert Enum.count(config.span_class_names -- ["O"]) == 55
    assert "first_name" in config.span_class_names
    assert "company_name" in config.span_class_names
    assert "street_address" in config.span_class_names
    assert "S-vehicle_identifier" in config.ner_class_names
  end

  test "allows explicit encoding override for Hugging Face configs" do
    assert {:ok, config} =
             Config.from_map(Map.delete(hf_config(), "pad_token_id"), encoding: "o200k_harmony")

    assert config.encoding == "o200k_harmony"
  end

  test "rejects experts_per_token greater than available experts" do
    config = Map.merge(internal_config(), %{"num_experts" => 2, "experts_per_token" => 4})

    assert {:error, {:invalid_experts_per_token, 4, 2}} = Config.from_map(config)
  end

  test "rejects attention heads that cannot be grouped by key-value heads" do
    config =
      Map.merge(internal_config(), %{
        "num_attention_heads" => 13,
        "num_key_value_heads" => 2
      })

    assert {:error, {:invalid_grouped_query_heads, 13, 2}} = Config.from_map(config)
  end

  test "rejects odd head_dim before RoPE reshape math" do
    config = Map.put(internal_config(), "head_dim", 63)

    assert {:error, {:invalid_head_dim, 63}} = Config.from_map(config)
  end

  test "rejects num_labels that disagree with resolved token labels" do
    config = Map.put(internal_config(), "num_labels", 4)

    assert {:error, {:num_labels_mismatch, "privacy-filter config", 4, 5}} =
             Config.from_map(config)
  end

  test "rejects non-positive RoPE and YaRN numeric parameters" do
    for {field, value} <- [
          {"rope_theta", 0.0},
          {"rope_scaling_factor", -1.0},
          {"rope_ntk_alpha", 0.0},
          {"rope_ntk_beta", -32.0}
        ] do
      assert {:error, {:invalid_config_positive_number, "privacy-filter config", ^field, ^value}} =
               internal_config()
               |> Map.put(field, value)
               |> Config.from_map()
    end
  end

  test "validates optional MoE runtime knobs" do
    invalid_cases = [
      {"swiglu_limit", 0.0,
       {:invalid_config_positive_number, "privacy-filter config", "swiglu_limit", 0.0}},
      {"packed_geglu", "true",
       {:invalid_config_bool, "privacy-filter config", "packed_geglu", "true"}},
      {"torch_ops_batch", 0,
       {:invalid_config_positive_integer, "privacy-filter config", "torch_ops_batch", 0}}
    ]

    for {field, value, reason} <- invalid_cases do
      assert {:error, ^reason} =
               internal_config()
               |> Map.put(field, value)
               |> Config.from_map()
    end
  end

  test "parses valid optional MoE runtime knobs" do
    assert {:ok, config} =
             internal_config()
             |> Map.merge(%{
               "swiglu_limit" => 6.5,
               "packed_geglu" => true,
               "torch_ops_batch" => 8
             })
             |> Config.from_map()

    assert config.swiglu_limit == 6.5
    assert config.packed_geglu == true
    assert config.torch_ops_batch == 8
  end

  defp internal_config do
    %{
      "model_type" => "privacy_filter",
      "encoding" => "o200k_base",
      "num_hidden_layers" => 1,
      "num_experts" => 128,
      "experts_per_token" => 4,
      "vocab_size" => 200_064,
      "num_labels" => 5,
      "hidden_size" => 640,
      "intermediate_size" => 640,
      "head_dim" => 64,
      "num_attention_heads" => 14,
      "num_key_value_heads" => 2,
      "sliding_window" => 257,
      "bidirectional_context" => true,
      "bidirectional_left_context" => 128,
      "bidirectional_right_context" => 128,
      "initial_context_length" => 4096,
      "rope_theta" => 150_000.0,
      "rope_scaling_factor" => 32.0,
      "rope_ntk_alpha" => 1.0,
      "rope_ntk_beta" => 32.0,
      "param_dtype" => "bfloat16",
      "ner_class_names" => [
        "O",
        "B-private_person",
        "I-private_person",
        "E-private_person",
        "S-private_person"
      ]
    }
  end

  defp hf_config do
    %{
      "model_type" => "openai_privacy_filter",
      "pad_token_id" => 199_999,
      "max_position_embeddings" => 131_072,
      "num_hidden_layers" => 1,
      "num_local_experts" => 128,
      "num_experts_per_tok" => 4,
      "vocab_size" => 200_064,
      "hidden_size" => 640,
      "intermediate_size" => 640,
      "head_dim" => 64,
      "num_attention_heads" => 14,
      "num_key_value_heads" => 2,
      "sliding_window" => 2,
      "dtype" => "bfloat16",
      "rope_parameters" => %{
        "beta_fast" => 32.0,
        "beta_slow" => 1.0,
        "factor" => 32.0,
        "original_max_position_embeddings" => 4096,
        "rope_theta" => 150_000.0
      },
      "id2label" => %{
        "0" => "O",
        "1" => "B-private_person",
        "2" => "I-private_person",
        "3" => "E-private_person",
        "4" => "S-private_person"
      }
    }
  end

  defp nemotron_id2label do
    span_labels = [
      "account_number",
      "age",
      "api_key",
      "bank_routing_number",
      "biometric_identifier",
      "blood_type",
      "certificate_license_number",
      "city",
      "company_name",
      "coordinate",
      "country",
      "county",
      "credit_debit_card",
      "customer_id",
      "cvv",
      "date",
      "date_of_birth",
      "date_time",
      "device_identifier",
      "education_level",
      "email",
      "employee_id",
      "employment_status",
      "fax_number",
      "first_name",
      "gender",
      "health_plan_beneficiary_number",
      "http_cookie",
      "ipv4",
      "ipv6",
      "language",
      "last_name",
      "license_plate",
      "mac_address",
      "medical_record_number",
      "national_id",
      "occupation",
      "password",
      "phone_number",
      "pin",
      "political_view",
      "postcode",
      "race_ethnicity",
      "religious_belief",
      "sexuality",
      "ssn",
      "state",
      "street_address",
      "swift_bic",
      "tax_id",
      "time",
      "unique_id",
      "url",
      "user_name",
      "vehicle_identifier"
    ]

    ["O" | for(label <- span_labels, prefix <- ["B", "I", "E", "S"], do: "#{prefix}-#{label}")]
    |> Enum.with_index()
    |> Map.new(fn {label, index} -> {to_string(index), label} end)
  end
end
