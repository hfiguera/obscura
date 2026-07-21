defmodule Obscura.Recognizer.GLiNER.ModelRegistry do
  @moduledoc """
  Local metadata for GLiNER models supported by the optional Ortex adapter.
  """

  defmodule ModelSpec do
    @moduledoc "Describes a GLiNER model and its required local assets."
    @enforce_keys [:id, :hf_repo, :default_onnx, :config_file, :tokenizer_file]
    defstruct [
      :id,
      :hf_repo,
      :default_onnx,
      :default_onnx_variant,
      :onnx_variants,
      :config_file,
      :tokenizer_file,
      :native_weights_file,
      :license,
      :architecture,
      prompt_joiner: " ",
      accepted_model_types: ["gliner"],
      default_max_width: 12,
      default_max_length: 2048,
      default_label_profile: :hybrid_core
    ]

    @type t :: %__MODULE__{}
  end

  @spec fetch(atom()) :: {:ok, ModelSpec.t()} | {:error, term()}
  def fetch(:knowledgator_gliner_pii_base_v1) do
    {:ok,
     %ModelSpec{
       id: :knowledgator_gliner_pii_base_v1,
       hf_repo: "knowledgator/gliner-pii-base-v1.0",
       default_onnx: "onnx/model.onnx",
       default_onnx_variant: :full,
       onnx_variants: %{
         full: "onnx/model.onnx",
         quantized: "onnx/model_quint8.onnx",
         fp16: "onnx/model_fp16.onnx"
       },
       config_file: "gliner_config.json",
       tokenizer_file: "tokenizer.json",
       native_weights_file: nil,
       license: "Apache-2.0",
       architecture: "GLiNER UniEncoder span model"
     }}
  end

  def fetch(:knowledgator_gliner_pii_edge_v1) do
    {:ok,
     %ModelSpec{
       id: :knowledgator_gliner_pii_edge_v1,
       hf_repo: "knowledgator/gliner-pii-edge-v1.0",
       default_onnx: "onnx/model.onnx",
       default_onnx_variant: :full,
       onnx_variants: %{
         full: "onnx/model.onnx",
         quantized: "onnx/model_quint8.onnx",
         fp16: "onnx/model_fp16.onnx"
       },
       config_file: "gliner_config.json",
       tokenizer_file: "tokenizer.json",
       native_weights_file: nil,
       license: "Apache-2.0",
       architecture: "GLiNER PII Edge UniEncoder span model"
     }}
  end

  def fetch(:urchade_gliner_multi_pii_v1) do
    {:ok,
     %ModelSpec{
       id: :urchade_gliner_multi_pii_v1,
       hf_repo: "urchade/gliner_multi_pii-v1",
       default_onnx: "model.onnx",
       default_onnx_variant: :full,
       onnx_variants: %{full: "model.onnx"},
       config_file: "gliner_config.json",
       tokenizer_file: "tokenizer.json",
       native_weights_file: "model.safetensors",
       license: "Apache-2.0",
       architecture: "GLiNER UniEncoder span model with mDeBERTa-v3-base encoder",
       accepted_model_types: [nil, "gliner"],
       default_max_width: 12,
       default_max_length: 384,
       default_label_profile: :open_class
     }}
  end

  def fetch(:nvidia_gliner_pii_v1) do
    {:ok,
     %ModelSpec{
       id: :nvidia_gliner_pii_v1,
       hf_repo: "nvidia/gliner-PII",
       default_onnx: "model.onnx",
       default_onnx_variant: :full,
       onnx_variants: %{full: "model.onnx"},
       config_file: "gliner_config.json",
       tokenizer_file: "tokenizer.json",
       native_weights_file: nil,
       license: "NVIDIA Open Model License",
       architecture: "GLiNER large-v2.1 PII/PHI span model with DeBERTa-v3-large encoder",
       prompt_joiner: "",
       accepted_model_types: [nil, "gliner"],
       default_max_width: 12,
       default_max_length: 384,
       default_label_profile: :open_class
     }}
  end

  def fetch(model), do: {:error, {:unknown_gliner_model, model}}

  @spec aliases() :: [atom()]
  def aliases do
    [
      :knowledgator_gliner_pii_base_v1,
      :knowledgator_gliner_pii_edge_v1,
      :urchade_gliner_multi_pii_v1,
      :nvidia_gliner_pii_v1
    ]
  end

  @spec metadata(atom()) :: {:ok, map()} | {:error, term()}
  def metadata(model) do
    with {:ok, spec} <- fetch(model) do
      {:ok,
       %{
         alias: spec.id,
         id: spec.hf_repo,
         architecture: spec.architecture,
         license: spec.license,
         default_onnx: spec.default_onnx,
         default_onnx_variant: spec.default_onnx_variant,
         onnx_variants: spec.onnx_variants,
         default_label_profile: spec.default_label_profile,
         accepted_model_types: spec.accepted_model_types
       }}
    end
  end

  @spec resolve_paths(ModelSpec.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def resolve_paths(%ModelSpec{} = spec, opts) do
    model_dir = Keyword.get(opts, :model_dir) || System.get_env("OBSCURA_GLINER_MODEL_DIR")

    paths = %{
      model_dir: model_dir,
      onnx_path:
        Keyword.get(opts, :onnx_path) ||
          System.get_env("OBSCURA_GLINER_ONNX_PATH") ||
          join(model_dir, onnx_file(spec, opts)),
      tokenizer_path: Keyword.get(opts, :tokenizer_path) || join(model_dir, spec.tokenizer_file),
      config_path: Keyword.get(opts, :config_path) || join(model_dir, spec.config_file)
    }

    validate_paths(paths)
  end

  @doc false
  @spec resolve_native_paths(ModelSpec.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def resolve_native_paths(%ModelSpec{native_weights_file: nil} = spec, _opts),
    do: {:error, {:native_gliner_not_supported, spec.id}}

  def resolve_native_paths(%ModelSpec{} = spec, opts) do
    model_dir =
      Keyword.get(opts, :model_dir) ||
        System.get_env("OBSCURA_GLINER_NATIVE_MODEL_DIR") ||
        System.get_env("OBSCURA_GLINER_MODEL_DIR")

    paths = %{
      model_dir: model_dir,
      weights_path: Keyword.get(opts, :weights_path) || join(model_dir, spec.native_weights_file),
      tokenizer_path: Keyword.get(opts, :tokenizer_path) || join(model_dir, spec.tokenizer_file),
      config_path: Keyword.get(opts, :config_path) || join(model_dir, spec.config_file),
      manifest_path:
        Keyword.get(opts, :manifest_path) || join(model_dir, "obscura_native_manifest.json")
    }

    validate_native_paths(paths)
  end

  defp validate_paths(%{model_dir: nil}), do: {:error, :missing_gliner_model_dir}

  defp validate_paths(paths) do
    [
      {:onnx_path, :missing_gliner_onnx},
      {:tokenizer_path, :missing_gliner_tokenizer},
      {:config_path, :missing_gliner_config}
    ]
    |> Enum.find(fn {key, _reason} -> not File.exists?(Map.fetch!(paths, key)) end)
    |> case do
      nil -> {:ok, paths}
      {key, reason} -> {:error, {reason, Map.fetch!(paths, key)}}
    end
  end

  defp validate_native_paths(%{model_dir: nil}), do: {:error, :missing_gliner_native_model_dir}

  defp validate_native_paths(paths) do
    [
      {:weights_path, :missing_gliner_native_weights},
      {:tokenizer_path, :missing_gliner_tokenizer},
      {:config_path, :missing_gliner_config},
      {:manifest_path, :missing_gliner_native_manifest}
    ]
    |> Enum.find(fn {key, _reason} -> not File.regular?(Map.fetch!(paths, key)) end)
    |> case do
      nil -> {:ok, paths}
      {key, reason} -> {:error, {reason, Map.fetch!(paths, key)}}
    end
  end

  defp join(nil, _path), do: nil
  defp join(root, path), do: Path.join(root, path)

  defp onnx_file(%ModelSpec{} = spec, opts) do
    variant =
      opts
      |> Keyword.get(:onnx_variant, System.get_env("OBSCURA_GLINER_ONNX_VARIANT"))
      |> normalize_variant(spec.default_onnx_variant)

    Map.get(spec.onnx_variants, variant, spec.default_onnx)
  end

  defp normalize_variant(nil, default), do: default
  defp normalize_variant(variant, _default) when is_atom(variant), do: variant

  defp normalize_variant(variant, default) when is_binary(variant) do
    case variant |> String.trim() |> String.downcase() do
      "full" -> :full
      "quantized" -> :quantized
      "quint8" -> :quantized
      "fp16" -> :fp16
      "" -> default
      _other -> default
    end
  end
end
