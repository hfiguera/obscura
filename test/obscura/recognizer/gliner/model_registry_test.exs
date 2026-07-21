defmodule Obscura.Recognizer.GLiNER.ModelRegistryTest do
  use ExUnit.Case, async: true

  alias Obscura.Recognizer.GLiNER.ModelRegistry

  test "metadata exposes full ONNX as the default accuracy artifact" do
    assert {:ok, metadata} = ModelRegistry.metadata(:knowledgator_gliner_pii_base_v1)

    assert metadata.default_onnx == "onnx/model.onnx"
    assert metadata.default_onnx_variant == :full
    assert metadata.onnx_variants.quantized == "onnx/model_quint8.onnx"
  end

  test "metadata exposes Edge as an experimental selectable model without changing defaults" do
    assert ModelRegistry.aliases() == [
             :knowledgator_gliner_pii_base_v1,
             :knowledgator_gliner_pii_edge_v1,
             :urchade_gliner_multi_pii_v1,
             :nvidia_gliner_pii_v1
           ]

    assert {:ok, metadata} = ModelRegistry.metadata(:knowledgator_gliner_pii_edge_v1)

    assert metadata.alias == :knowledgator_gliner_pii_edge_v1
    assert metadata.id == "knowledgator/gliner-pii-edge-v1.0"
    assert metadata.license == "Apache-2.0"
    assert metadata.default_onnx == "onnx/model.onnx"
    assert metadata.default_onnx_variant == :full
    assert metadata.onnx_variants.fp16 == "onnx/model_fp16.onnx"
    assert metadata.onnx_variants.quantized == "onnx/model_quint8.onnx"
  end

  test "metadata exposes the locally exported Urchade model contract" do
    assert {:ok, metadata} = ModelRegistry.metadata(:urchade_gliner_multi_pii_v1)

    assert metadata.id == "urchade/gliner_multi_pii-v1"
    assert metadata.license == "Apache-2.0"
    assert metadata.default_onnx == "model.onnx"
    assert metadata.default_label_profile == :open_class
    assert metadata.accepted_model_types == [nil, "gliner"]
  end

  test "metadata exposes the NVIDIA GLiNER PII export contract" do
    assert {:ok, metadata} = ModelRegistry.metadata(:nvidia_gliner_pii_v1)

    assert metadata.id == "nvidia/gliner-PII"
    assert metadata.license == "NVIDIA Open Model License"
    assert metadata.default_onnx == "model.onnx"
    assert metadata.default_label_profile == :open_class
    assert metadata.accepted_model_types == [nil, "gliner"]
  end

  test "resolves full ONNX by default and quantized ONNX when requested" do
    root = temp_model_dir!()
    assert {:ok, spec} = ModelRegistry.fetch(:knowledgator_gliner_pii_base_v1)

    assert {:ok, full_paths} = ModelRegistry.resolve_paths(spec, model_dir: root)
    assert full_paths.onnx_path == Path.join(root, "onnx/model.onnx")

    assert {:ok, quantized_paths} =
             ModelRegistry.resolve_paths(spec, model_dir: root, onnx_variant: :quantized)

    assert quantized_paths.onnx_path == Path.join(root, "onnx/model_quint8.onnx")
  end

  test "resolves Edge ONNX variants" do
    root = temp_model_dir!()
    assert {:ok, spec} = ModelRegistry.fetch(:knowledgator_gliner_pii_edge_v1)

    assert {:ok, full_paths} = ModelRegistry.resolve_paths(spec, model_dir: root)
    assert full_paths.onnx_path == Path.join(root, "onnx/model.onnx")

    assert {:ok, fp16_paths} =
             ModelRegistry.resolve_paths(spec, model_dir: root, onnx_variant: :fp16)

    assert fp16_paths.onnx_path == Path.join(root, "onnx/model_fp16.onnx")
  end

  test "resolves the locally exported Urchade ONNX bundle" do
    root = temp_urchade_model_dir!()
    assert {:ok, spec} = ModelRegistry.fetch(:urchade_gliner_multi_pii_v1)

    assert {:ok, paths} = ModelRegistry.resolve_paths(spec, model_dir: root)
    assert paths.onnx_path == Path.join(root, "model.onnx")
  end

  test "resolves the locally exported NVIDIA ONNX bundle" do
    root = temp_urchade_model_dir!()
    assert {:ok, spec} = ModelRegistry.fetch(:nvidia_gliner_pii_v1)

    assert {:ok, paths} = ModelRegistry.resolve_paths(spec, model_dir: root)
    assert paths.onnx_path == Path.join(root, "model.onnx")
  end

  test "resolves the native Urchade Safetensors bundle independently from ONNX" do
    root = temp_urchade_native_model_dir!()
    assert {:ok, spec} = ModelRegistry.fetch(:urchade_gliner_multi_pii_v1)

    assert {:ok, paths} = ModelRegistry.resolve_native_paths(spec, model_dir: root)
    assert paths.weights_path == Path.join(root, "model.safetensors")
    assert paths.manifest_path == Path.join(root, "obscura_native_manifest.json")
  end

  test "falls back to full ONNX for unknown variants" do
    root = temp_model_dir!()
    assert {:ok, spec} = ModelRegistry.fetch(:knowledgator_gliner_pii_base_v1)

    assert {:ok, paths} =
             ModelRegistry.resolve_paths(spec, model_dir: root, onnx_variant: :unknown)

    assert paths.onnx_path == Path.join(root, "onnx/model.onnx")
  end

  defp temp_model_dir! do
    root = Path.join(System.tmp_dir!(), "obscura-gliner-model-#{System.unique_integer()}")
    File.mkdir_p!(Path.join(root, "onnx"))

    for path <- [
          "onnx/model.onnx",
          "onnx/model_quint8.onnx",
          "onnx/model_fp16.onnx",
          "tokenizer.json",
          "gliner_config.json"
        ] do
      File.write!(Path.join(root, path), "")
    end

    root
  end

  defp temp_urchade_model_dir! do
    root = Path.join(System.tmp_dir!(), "obscura-gliner-urchade-#{System.unique_integer()}")
    File.mkdir_p!(root)

    for path <- ["model.onnx", "tokenizer.json", "gliner_config.json"] do
      File.write!(Path.join(root, path), "")
    end

    root
  end

  defp temp_urchade_native_model_dir! do
    root = Path.join(System.tmp_dir!(), "obscura-gliner-native-#{System.unique_integer()}")
    File.mkdir_p!(root)

    for path <- [
          "model.safetensors",
          "tokenizer.json",
          "gliner_config.json",
          "obscura_native_manifest.json"
        ] do
      File.write!(Path.join(root, path), "")
    end

    root
  end
end
