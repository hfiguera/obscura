defmodule Obscura.Recognizer.NER.ServingBuildTest do
  use ExUnit.Case, async: true

  alias Obscura.Recognizer.NER.Serving

  defmodule FakeBumblebee do
    def load_model({:hf, "dslim/bert-base-NER"}, []), do: {:ok, :model_info}
    def load_tokenizer({:hf, "google-bert/bert-base-cased"}, []), do: {:ok, :tokenizer}
  end

  defmodule FakeBumblebeeText do
    def token_classification(:model_info, :tokenizer, opts) do
      {:fake_serving, opts}
    end
  end

  defmodule OfflineMissBumblebee do
    def load_model(_repository, _opts) do
      {:error, "could not find file in local cache and outgoing traffic is disabled"}
    end
  end

  defmodule InterruptedBumblebee do
    def load_model(_repository, _opts) do
      {:error, "failed to make an HTTP request, reason: download failed"}
    end
  end

  defmodule RetryBumblebee do
    def load_model(_repository, _opts), do: {:ok, :model_info}

    def load_tokenizer(_repository, _opts) do
      attempts = Process.get({__MODULE__, :attempts}, 0) + 1
      Process.put({__MODULE__, :attempts}, attempts)

      if attempts == 1,
        do: {:error, "temporary repository failure"},
        else: {:ok, :tokenizer}
    end
  end

  test "missing Nx.Serving returns safe optional dependency error" do
    assert {:error, {:missing_optional_dependency, :nx}} =
             Serving.build(
               model: :dslim_bert_base_ner,
               dependency_checker: fn _module -> false end,
               telemetry: false
             )
  end

  test "missing Bumblebee returns safe optional dependency error" do
    assert {:error, {:missing_optional_dependency, :bumblebee}} =
             Serving.build(
               model: :dslim_bert_base_ner,
               dependency_checker: fn
                 Nx.Serving -> true
                 _module -> false
               end,
               telemetry: false
             )
  end

  test "unknown model alias returns safe error" do
    assert {:error, {:unsupported_model, :unknown_model}} =
             Serving.build(model: :unknown_model, telemetry: false)
  end

  test "builds a wrapped serving with fake optional modules" do
    assert {:ok, serving} =
             Serving.build(
               model: :dslim_bert_base_ner,
               dependency_checker: fn _module -> true end,
               bumblebee_module: FakeBumblebee,
               bumblebee_text_module: FakeBumblebeeText,
               compile: [batch_size: 1, sequence_length: 128],
               telemetry: false
             )

    assert %Serving{} = serving
    assert serving.model_spec.id == :dslim_bert_base_ner
    assert {:fake_serving, opts} = serving.serving
    assert opts[:aggregation] == :same
    assert opts[:compile] == [batch_size: 1, sequence_length: 128]
  end

  test "configures explicit Emily backend without mandatory dependency side effects" do
    assert {:ok, serving} =
             Serving.build(
               model: :dslim_bert_base_ner,
               real_model_backend: :emily,
               dependency_checker: fn _module -> true end,
               application_env_putter: fn :emily, :fallback, :raise -> :ok end,
               application_starter: fn :emily -> {:ok, [:emily]} end,
               nx_backend_setter: fn {Emily.Backend, device: :gpu} -> :ok end,
               nx_defn_options_setter: fn compiler: Emily.Compiler -> :ok end,
               bumblebee_module: FakeBumblebee,
               bumblebee_text_module: FakeBumblebeeText,
               telemetry: false
             )

    assert serving.backend == :emily
    assert {:fake_serving, opts} = serving.serving
    assert opts[:defn_options] == [compiler: Emily.Compiler]
  end

  test "explicit Emily backend fails safely when Emily is unavailable" do
    assert {:error, {:missing_optional_dependency, :emily}} =
             Serving.build(
               model: :dslim_bert_base_ner,
               real_model_backend: :emily,
               dependency_checker: fn
                 Emily -> false
                 _module -> true
               end,
               telemetry: false
             )
  end

  test "backend metadata distinguishes requested and proven runtime backend" do
    metadata =
      Obscura.Recognizer.NER.Backend.metadata(
        real_model_backend: :emily,
        emily_fallback: :raise,
        backend_inspector: fn -> {Emily.Backend, device: :gpu} end
      )

    assert metadata.requested_backend == :emily
    assert metadata.actual_backend == :emily
    assert metadata.actual_device == :gpu
    assert metadata.backend_proven == true
    assert metadata.fallback_occurred == false
  end

  test "classifies offline cache misses without retaining dependency text" do
    assert {:error, {:missing_model_asset, :model_cache}} =
             Serving.build(
               model: :dslim_bert_base_ner,
               dependency_checker: fn _module -> true end,
               bumblebee_module: OfflineMissBumblebee,
               telemetry: false
             )
  end

  test "classifies interrupted downloads without retaining dependency text" do
    assert {:error, {:model_download_interrupted, :model}} =
             Serving.build(
               model: :dslim_bert_base_ner,
               asset_load_retry_delay: 0,
               dependency_checker: fn _module -> true end,
               bumblebee_module: InterruptedBumblebee,
               telemetry: false
             )
  end

  test "retries one transient online tokenizer load and reports the retry stage" do
    Process.delete({RetryBumblebee, :attempts})
    parent = self()

    assert {:ok, %Serving{}} =
             Serving.build(
               model: :dslim_bert_base_ner,
               asset_load_retry_delay: 0,
               dependency_checker: fn _module -> true end,
               bumblebee_module: RetryBumblebee,
               bumblebee_text_module: FakeBumblebeeText,
               stage_observer: fn event -> send(parent, {:stage, event}) end,
               telemetry: false
             )

    assert Process.get({RetryBumblebee, :attempts}) == 2
    assert_received {:stage, %{stage: :tokenizer_load_retry, status: :started}}
    assert_received {:stage, %{stage: :tokenizer_load_retry, status: :ok}}
  end

  test "offline mode never retries dependency failures" do
    Process.delete({RetryBumblebee, :attempts})

    assert {:error, {:tokenizer_load_failed, :dependency_error}} =
             Serving.build(
               model: :dslim_bert_base_ner,
               offline: true,
               dependency_checker: fn _module -> true end,
               bumblebee_module: RetryBumblebee,
               bumblebee_text_module: FakeBumblebeeText,
               telemetry: false
             )

    assert Process.get({RetryBumblebee, :attempts}) == 1
  end
end
