defmodule Obscura.PrivacyFilter.ServingTest do
  use ExUnit.Case, async: false

  alias Obscura.PrivacyFilter.LabelInfo
  alias Obscura.PrivacyFilter.Serving

  test "config-backed construction emits safe lifecycle stages" do
    parent = self()
    observer = fn event -> send(parent, {:stage, event}) end

    assert {:ok, _serving} = Serving.build(config: config(), stage_observer: observer)

    assert_receive {:stage, %{stage: :backend_configuration, status: :ok}}
    assert_receive {:stage, %{stage: :checkpoint_layout, status: :ok}}
    assert_receive {:stage, %{stage: :label_info_load, status: :ok}}
    assert_receive {:stage, %{stage: :serving_construction, status: :ok}}

    refute_receive {:stage, %{checkpoint: _path}}
  end

  test "postprocess converts BIOES logits into Obscura analyzer results" do
    assert {:ok, serving} = Serving.build(config: config())

    tokenization = %{
      text: "Ada Lovelace",
      token_ids: [10, 20],
      char_starts: [0, 4],
      char_ends: [3, 12]
    }

    logits =
      Nx.tensor([
        [
          [-10.0, 10.0, -10.0, -10.0, -10.0],
          [-10.0, -10.0, -10.0, 10.0, -10.0]
        ]
      ])

    assert {:ok, [result]} = Serving.postprocess(serving, tokenization, logits)
    assert result.entity == :person
    assert result.text == "Ada Lovelace"
    assert result.start == 0
    assert result.end == 12
    assert result.recognizer == :privacy_filter_native
    assert result.metadata.raw_label == "private_person"
    assert result.metadata.model_label == "private_person"
    assert result.metadata.recognizer == :privacy_filter_native
    assert result.metadata.encoding == "cl100k_base"
    assert result.metadata.decoder == :viterbi
    assert result.metadata.viterbi_calibration == :none
    assert result.metadata.pad_windows == false
    assert result.metadata.trim_span_whitespace == true
    assert result.metadata.discard_overlapping_spans == true
  end

  test "postprocess supports argmax decoder" do
    assert {:ok, serving} = Serving.build(config: config(), decoder: :argmax)

    tokenization = %{
      text: "Ada",
      token_ids: [10],
      char_starts: [0],
      char_ends: [3]
    }

    logits = Nx.tensor([[[-10.0, -10.0, -10.0, -10.0, 10.0]]])

    assert {:ok, [result]} = Serving.postprocess(serving, tokenization, logits)
    assert result.text == "Ada"
    assert result.entity == :person
  end

  test "postprocess can filter low-confidence decoded spans by mean token logprob" do
    assert {:ok, loose} =
             Serving.build(config: config(), decoder: :argmax, min_span_logprob: -0.5)

    assert {:ok, strict} =
             Serving.build(config: config(), decoder: :argmax, min_span_logprob: -0.05)

    tokenization = %{
      text: "Ada",
      token_ids: [10],
      char_starts: [0],
      char_ends: [3]
    }

    logits = Nx.tensor([[[0.0, 0.0, 0.0, 0.0, 2.0]]])

    assert {:ok, [%{text: "Ada"}]} = Serving.postprocess(loose, tokenization, logits)
    assert {:ok, []} = Serving.postprocess(strict, tokenization, logits)
  end

  test "postprocess rejects unsupported decoders" do
    assert {:ok, serving} = Serving.build(config: config(), decoder: :other)

    tokenization = %{
      text: "Ada",
      token_ids: [10],
      char_starts: [0],
      char_ends: [3]
    }

    logits = Nx.tensor([[[1.0, 0.0, 0.0, 0.0, 0.0]]])

    assert {:error, {:unsupported_privacy_filter_decoder, :other}} =
             Serving.postprocess(serving, tokenization, logits)
  end

  test "postprocess uses configured Viterbi calibration biases" do
    path = calibration_file!(transition_bias_end_to_background: 2.0)

    assert {:ok, uncalibrated} = Serving.build(config: config())
    assert {:ok, calibrated} = Serving.build(config: config(), viterbi_calibration_path: path)
    assert calibrated.viterbi_calibration == :explicit_path

    tokenization = %{
      text: "Ada Bob",
      token_ids: [10, 20],
      char_starts: [0, 4],
      char_ends: [3, 7]
    }

    rows = [
      [-0.1, -10.0, -10.0, -10.0, 0.0],
      [-0.1, -10.0, -10.0, -10.0, 0.0]
    ]

    assert {:ok, uncalibrated_results} =
             Serving.postprocess_logprobs(uncalibrated, tokenization, rows)

    assert {:ok, calibrated_results} =
             Serving.postprocess_logprobs(calibrated, tokenization, rows)

    assert Enum.map(uncalibrated_results, & &1.text) == ["Ada", "Bob"]
    assert Enum.map(calibrated_results, & &1.text) == ["Ada"]
  end

  test "build loads checkpoint-local Viterbi calibration when present" do
    checkpoint = tmp_dir!()

    write_calibration!(Path.join(checkpoint, "viterbi_calibration.json"), %{
      transition_bias_end_to_background: 1.25
    })

    assert {:ok, serving} = Serving.build(config: config(), checkpoint: checkpoint)
    assert serving.viterbi_biases.transition_bias_end_to_background == 1.25
    assert serving.viterbi_calibration == :checkpoint_file
  end

  test "build records explicit checkpoint layout metadata for config-backed serving" do
    assert {:ok, serving} = Serving.build(config: config(), layout: :python_original)

    assert serving.layout == :python_original
  end

  test "build rejects Python original checkpoint artifacts without explicit layout opt-in" do
    checkpoint = tmp_dir!()
    File.write!(Path.join(checkpoint, "config.json"), Jason.encode!(config()))
    File.write!(Path.join(checkpoint, "model.safetensors"), "")
    File.write!(Path.join(checkpoint, "dtypes.json"), "{}")

    assert {:error, {:python_original_layout_requires_explicit_opt_in, ^checkpoint}} =
             Serving.build(checkpoint: checkpoint)
  end

  test "build returns a clear error for missing checkpoint directories" do
    checkpoint = Path.join(tmp_dir!(), "missing")

    assert {:error, {:checkpoint_dir_not_found, ^checkpoint}} =
             Serving.build(checkpoint: checkpoint)
  end

  test "build returns a clear error for checkpoint directories without config" do
    checkpoint = tmp_dir!()

    assert {:error, {:missing_checkpoint_config, config_path}} =
             Serving.build(checkpoint: checkpoint)

    assert config_path == Path.join(checkpoint, "config.json")
  end

  test "build resolves default CPU n_ctx like the Python privacy-filter runtime" do
    assert {:ok, serving} = Serving.build(config: config())

    assert serving.n_ctx == 4096
  end

  test "build honors explicit n_ctx and rejects invalid n_ctx" do
    assert {:ok, serving} = Serving.build(config: config(), n_ctx: 128)
    assert serving.n_ctx == 128

    assert {:error, {:invalid_privacy_filter_n_ctx, 0}} =
             Serving.build(config: config(), n_ctx: 0)
  end

  test "build resolves non-CPU n_ctx from config fields" do
    config = Map.put(config(), :default_n_ctx, 32)

    assert {:ok, serving} = Serving.build(config: config, device: :gpu)

    assert serving.n_ctx == 32
  end

  test "build configures explicit EXLA backend before runtime use" do
    parent = self()

    assert {:ok, serving} =
             Serving.build(
               config: config(),
               backend: :exla,
               dependency_checker: fn module ->
                 send(parent, {:checked, module})
                 true
               end,
               application_starter: fn app ->
                 send(parent, {:started, app})
                 {:ok, [app]}
               end,
               nx_backend_setter: fn backend ->
                 send(parent, {:backend, backend})
                 :ok
               end
             )

    assert serving.backend == :exla
    assert_receive {:checked, EXLA}
    assert_receive {:checked, EXLA.Backend}
    assert_receive {:started, :exla}
    assert_receive {:backend, EXLA.Backend}
  end

  test "build configures explicit Emily backend before runtime use" do
    parent = self()

    assert {:ok, serving} =
             Serving.build(
               config: config(),
               backend: :emily,
               dependency_checker: fn module ->
                 send(parent, {:checked, module})
                 true
               end,
               application_env_putter: fn :emily, :fallback, :raise ->
                 send(parent, {:fallback, :raise})
                 :ok
               end,
               application_starter: fn app ->
                 send(parent, {:started, app})
                 {:ok, [app]}
               end,
               nx_backend_setter: fn backend ->
                 send(parent, {:backend, backend})
                 :ok
               end,
               nx_defn_options_setter: fn opts ->
                 send(parent, {:defn_options, opts})
                 :ok
               end
             )

    assert serving.backend == :emily
    assert serving.backend_metadata.requested_backend == :emily
    assert serving.backend_metadata.actual_backend == :emily
    assert serving.backend_metadata.actual_device == :gpu
    assert serving.backend_metadata.backend_proven == true
    assert serving.backend_metadata.fallback_occurred == false
    assert serving.backend_metadata.backend_source == :option
    assert serving.backend_metadata.emily_device == :gpu
    assert serving.backend_metadata.emily_fallback == :raise
    assert serving.backend_metadata.exla_enabled == false
    assert serving.backend_metadata.parity_warning == :python_original_bf16_qkv_backend_limited
    assert serving.backend_metadata.parity_warning_reason =~ "Emily GPU BF16 QKV"

    assert_receive {:checked, Emily}
    assert_receive {:checked, Emily.Backend}
    assert_receive {:checked, Emily.Compiler}
    assert_receive {:checked, Nx.Defn}
    assert_receive {:fallback, :raise}
    assert_receive {:started, :emily}
    assert_receive {:backend, {Emily.Backend, device: :gpu}}
    assert_receive {:defn_options, [compiler: Emily.Compiler]}
  end

  test "build configures Emily backend from environment" do
    parent = self()

    with_env(
      %{
        "OBSCURA_PRIVACY_FILTER_BACKEND" => "emily",
        "OBSCURA_EMILY_DEVICE" => "cpu",
        "OBSCURA_EMILY_FALLBACK" => "warn"
      },
      fn ->
        assert {:ok, serving} =
                 Serving.build(
                   config: config(),
                   dependency_checker: fn _module -> true end,
                   application_env_putter: fn :emily, :fallback, :warn ->
                     send(parent, {:fallback, :warn})
                     :ok
                   end,
                   application_starter: fn :emily -> {:ok, [:emily]} end,
                   nx_backend_setter: fn backend ->
                     send(parent, {:backend, backend})
                     :ok
                   end,
                   nx_defn_options_setter: fn opts ->
                     send(parent, {:defn_options, opts})
                     :ok
                   end
                 )

        assert serving.backend == :emily
        assert serving.backend_metadata.backend_source == :env
        assert serving.backend_metadata.actual_device == :cpu
        assert serving.backend_metadata.emily_device == :cpu
        assert serving.backend_metadata.emily_fallback == :warn

        assert serving.backend_metadata.parity_warning ==
                 :python_original_bf16_qkv_backend_limited

        assert_receive {:fallback, :warn}
        assert_receive {:backend, {Emily.Backend, device: :cpu}}
        assert_receive {:defn_options, [compiler: Emily.Compiler]}
      end
    )
  end

  test "build rejects explicit EXLA backend when optional dependency is missing" do
    assert {:error, {:missing_optional_dependency, :exla}} =
             Serving.build(
               config: config(),
               backend: :exla,
               dependency_checker: fn _module -> false end
             )
  end

  test "build rejects explicit Emily backend when optional dependency is missing" do
    assert {:error, {:missing_optional_dependency, :emily}} =
             Serving.build(
               config: config(),
               backend: :emily,
               dependency_checker: fn
                 Emily -> false
                 _module -> true
               end
             )
  end

  test "build rejects invalid Emily fallback and device values" do
    assert {:error, {:unsupported_emily_fallback, [:silent, :warn, :raise]}} =
             Serving.build(
               config: config(),
               backend: :emily,
               emily_fallback: "loud",
               dependency_checker: fn _module -> true end
             )

    assert {:error, {:unsupported_emily_device, [:gpu, :cpu]}} =
             Serving.build(
               config: config(),
               backend: :emily,
               emily_device: "neural",
               dependency_checker: fn _module -> true end
             )
  end

  test "build rejects unsupported privacy-filter backend names" do
    assert {:error, {:unsupported_privacy_filter_backend, [:default, :binary, :exla, :emily]}} =
             Serving.build(config: config(), backend: :other)
  end

  test "build accepts explicit label info that matches config label count" do
    assert {:ok, label_info} = LabelInfo.build(config().ner_class_names)

    assert {:ok, serving} = Serving.build(config: config(), label_info: label_info)

    assert serving.label_info == label_info
  end

  test "build rejects explicit label info that does not match config label count" do
    assert {:ok, label_info} =
             LabelInfo.build([
               "O",
               "B-private_person",
               "I-private_person",
               "E-private_person",
               "S-private_person",
               "B-private_email",
               "I-private_email",
               "E-private_email",
               "S-private_email"
             ])

    assert {:error, {:privacy_filter_label_info_mismatch, 5, 9}} =
             Serving.build(config: config(), label_info: label_info)
  end

  test "run splits inputs into fixed-size windows instead of rejecting long context" do
    parent = self()

    assert {:ok, serving} =
             Serving.build(
               config: config(),
               decoder: :argmax,
               n_ctx: 2,
               model_fun: fn token_ids, _attention_mask ->
                 flat_token_ids = Nx.to_flat_list(token_ids)
                 send(parent, {:window, flat_token_ids})
                 single_person_first_token_logits(length(flat_token_ids))
               end
             )

    assert {:ok, results} = Serving.run(serving, "Ada Alan Bob Eve Max Sue")

    assert_receive {:window, [96_447, 26_349]}
    assert_receive {:window, [14_596, 32_460]}
    assert_receive {:window, [7639, 48_749]}
    refute_receive {:window, _other}

    assert Enum.map(results, & &1.entity) == [:person, :person, :person]
    assert Enum.map(results, & &1.text) == ["Ada", "Bob", "Max"]
  end

  test "run pads the final fixed-size window and passes an attention mask" do
    parent = self()

    assert {:ok, serving} =
             Serving.build(
               config: config(),
               decoder: :argmax,
               n_ctx: 4,
               pad_windows: true,
               model_fun: fn token_ids, attention_mask ->
                 send(
                   parent,
                   {:window, Nx.to_flat_list(token_ids), Nx.to_flat_list(attention_mask)}
                 )

                 single_person_first_token_logits(length(Nx.to_flat_list(token_ids)))
               end
             )

    assert {:ok, results} = Serving.run(serving, "Ada Alan")

    assert_receive {:window, [96_447, 26_349, 100_257, 100_257], [1, 1, 0, 0]}
    refute_receive {:window, _tokens, _mask}

    assert Enum.map(results, & &1.text) == ["Ada"]
  end

  test "run keeps the final window unpadded by default" do
    parent = self()

    assert {:ok, serving} =
             Serving.build(
               config: config(),
               decoder: :argmax,
               model_fun: fn token_ids, attention_mask ->
                 send(
                   parent,
                   {:window, Nx.to_flat_list(token_ids), Nx.to_flat_list(attention_mask)}
                 )

                 single_person_first_token_logits(length(Nx.to_flat_list(token_ids)))
               end
             )

    assert serving.n_ctx == 4096
    assert serving.pad_windows == false
    assert {:ok, results} = Serving.run(serving, "Ada Alan")

    assert_receive {:window, [96_447, 26_349], [1, 1]}
    refute_receive {:window, _tokens, _mask}

    assert Enum.map(results, & &1.text) == ["Ada"]
  end

  test "run uses bounded sequence-length buckets with exact attention masks" do
    parent = self()

    assert {:ok, serving} =
             Serving.build(
               config: config(),
               decoder: :argmax,
               sequence_length_buckets: [2, 4],
               model_fun: fn token_ids, attention_mask ->
                 send(
                   parent,
                   {:window, Nx.to_flat_list(token_ids), Nx.to_flat_list(attention_mask)}
                 )

                 all_outside_logits(length(Nx.to_flat_list(token_ids)))
               end
             )

    assert {:ok, []} = Serving.run(serving, "Ada Alan Bob")
    assert_receive {:window, [_one, _two, _three, 100_257], [1, 1, 1, 0]}
    refute_receive {:window, _tokens, _mask}
  end

  test "run chunks bucketed inputs at the largest configured shape" do
    parent = self()

    assert {:ok, serving} =
             Serving.build(
               config: config(),
               decoder: :argmax,
               sequence_length_buckets: [2, 4],
               model_fun: fn token_ids, attention_mask ->
                 send(
                   parent,
                   {:shape, Nx.axis_size(token_ids, 1), Nx.to_flat_list(attention_mask)}
                 )

                 all_outside_logits(Nx.axis_size(token_ids, 1))
               end
             )

    assert {:ok, []} = Serving.run(serving, "Ada Alan Bob Eve Max Sue")
    assert_receive {:shape, 4, [1, 1, 1, 1]}
    assert_receive {:shape, 2, [1, 1]}
    refute_receive {:shape, _length, _mask}
  end

  test "build validates bounded sequence-length bucket policies" do
    assert {:error, {:invalid_privacy_filter_sequence_length_buckets, [4, 2]}} =
             Serving.build(config: config(), sequence_length_buckets: [4, 2])

    assert {:error, {:invalid_privacy_filter_sequence_length_buckets, []}} =
             Serving.build(config: config(), sequence_length_buckets: [])

    assert {:error, {:privacy_filter_sequence_length_bucket_exceeds_n_ctx, 8, 4}} =
             Serving.build(config: config(), n_ctx: 4, sequence_length_buckets: [2, 4, 8])

    assert {:error, {:privacy_filter_sequence_length_bucket_threshold_exceeds_maximum, 9, 8}} =
             Serving.build(
               config: config(),
               sequence_length_buckets: [4, 8],
               sequence_length_bucket_threshold: 9
             )

    assert {:error, {:invalid_privacy_filter_sequence_length_bucket_threshold, 4, nil}} =
             Serving.build(config: config(), sequence_length_bucket_threshold: 4)
  end

  test "run applies buckets only at or above the configured threshold" do
    parent = self()

    assert {:ok, serving} =
             Serving.build(
               config: config(),
               decoder: :argmax,
               sequence_length_buckets: [4, 8],
               sequence_length_bucket_threshold: 4,
               model_fun: fn token_ids, attention_mask ->
                 send(
                   parent,
                   {:shape, Nx.axis_size(token_ids, 1), Nx.to_flat_list(attention_mask)}
                 )

                 all_outside_logits(Nx.axis_size(token_ids, 1))
               end
             )

    assert {:ok, []} = Serving.run(serving, "Ada Alan Bob")
    assert_receive {:shape, 3, [1, 1, 1]}

    assert {:ok, []} = Serving.run(serving, "Ada Alan Bob Eve")
    assert_receive {:shape, 4, [1, 1, 1, 1]}
  end

  test "build validates log-probability conversion modes" do
    assert {:error, {:unsupported_privacy_filter_logprob_conversion, :other}} =
             Serving.build(config: config(), logprob_conversion: :other)

    assert {:ok, raw_logits} =
             Serving.build(config: config(), logprob_conversion: :raw_logits)

    assert raw_logits.logprob_conversion == :raw_logits

    assert {:error,
            {:privacy_filter_viterbi_logit_mode_requires_viterbi_without_span_threshold,
             :raw_logits, :argmax, nil}} =
             Serving.build(
               config: config(),
               decoder: :argmax,
               logprob_conversion: :raw_logits
             )
  end

  test "raw-logit Viterbi conversion preserves reference serving results" do
    model_fun = fn token_ids, _attention_mask ->
      token_ids
      |> Nx.to_flat_list()
      |> Enum.with_index()
      |> Enum.map(fn {_token, index} ->
        if rem(index, 2) == 0,
          do: [-2.0, -3.0, -4.0, -5.0, 2.0],
          else: [2.0, -3.0, -4.0, -5.0, -2.0]
      end)
      |> then(&Nx.tensor([&1]))
    end

    assert {:ok, reference} = Serving.build(config: config(), model_fun: model_fun)

    assert {:ok, raw_logits} =
             Serving.build(
               config: config(),
               model_fun: model_fun,
               logprob_conversion: :raw_logits
             )

    assert Serving.run(raw_logits, "Ada Alan Bob Eve") ==
             Serving.run(reference, "Ada Alan Bob Eve")
  end

  test "run_with_timings returns stage latency breakdown without changing results" do
    assert {:ok, serving} =
             Serving.build(
               config: config(),
               decoder: :argmax,
               model_fun: fn token_ids, _attention_mask ->
                 flat_token_ids = Nx.to_flat_list(token_ids)
                 single_person_first_token_logits(length(flat_token_ids))
               end
             )

    assert {:ok, run_results} = Serving.run(serving, "Ada Alan")
    assert {:ok, timed_results, timings} = Serving.run_with_timings(serving, "Ada Alan")

    assert Enum.map(timed_results, & &1.text) == Enum.map(run_results, & &1.text)

    assert Map.keys(timings) |> Enum.sort() == [
             :decode_ms,
             :model_ms,
             :tokenization_ms,
             :total_ms
           ]

    assert Enum.all?(timings, fn {_key, value} -> is_number(value) and value >= 0.0 end)
  end

  test "run rejects model output length mismatches per window" do
    assert {:ok, serving} =
             Serving.build(
               config: config(),
               decoder: :argmax,
               n_ctx: 2,
               model_fun: fn _token_ids, _attention_mask ->
                 single_person_first_token_logits(1)
               end
             )

    assert {:error, {:privacy_filter_logit_length_mismatch, 2, 1}} =
             Serving.run(serving, "Ada Alan")
  end

  test "postprocess rejects logits that are not one batched sequence" do
    assert {:ok, serving} = Serving.build(config: config(), decoder: :argmax)

    tokenization = %{
      text: "Ada",
      token_ids: [10],
      char_starts: [0],
      char_ends: [3]
    }

    logits = Nx.tensor([[1.0, 0.0, 0.0, 0.0, 0.0]])

    assert {:error, {:privacy_filter_logits_shape_mismatch, {1, 5}}} =
             Serving.postprocess(serving, tokenization, logits)
  end

  test "postprocess rejects logits whose label dimension does not match label info" do
    assert {:ok, serving} = Serving.build(config: config(), decoder: :argmax)

    tokenization = %{
      text: "Ada",
      token_ids: [10],
      char_starts: [0],
      char_ends: [3]
    }

    logits = Nx.tensor([[[1.0, 0.0, 0.0, 0.0]]])

    assert {:error, {:privacy_filter_logit_label_count_mismatch, 0, 5, 4}} =
             Serving.postprocess(serving, tokenization, logits)
  end

  test "run rejects model output label-count mismatches per window" do
    assert {:ok, serving} =
             Serving.build(
               config: config(),
               decoder: :argmax,
               model_fun: fn token_ids, _attention_mask ->
                 tokens = token_ids |> Nx.to_flat_list() |> length()
                 Nx.broadcast(Nx.tensor([[[1.0, 0.0, 0.0, 0.0]]]), {1, tokens, 4})
               end
             )

    assert {:error, {:privacy_filter_logit_label_count_mismatch, 0, 5, 4}} =
             Serving.run(serving, "Ada Alan")
  end

  test "run returns a controlled error when model execution raises" do
    assert {:ok, serving} =
             Serving.build(
               config: config(),
               decoder: :argmax,
               model_fun: fn _token_ids, _attention_mask ->
                 raise "native forward failed"
               end
             )

    assert {:error, {:privacy_filter_model_forward_failed, RuntimeError}} =
             Serving.run(serving, "Ada Alan")
  end

  test "run propagates explicit model execution error tuples" do
    assert {:ok, serving} =
             Serving.build(
               config: config(),
               decoder: :argmax,
               model_fun: fn _token_ids, _attention_mask ->
                 {:error, :checkpoint_not_ready}
               end
             )

    assert {:error, :checkpoint_not_ready} = Serving.run(serving, "Ada Alan")
  end

  test "run rejects invalid model execution outputs" do
    assert {:ok, serving} =
             Serving.build(
               config: config(),
               decoder: :argmax,
               model_fun: fn _token_ids, _attention_mask -> :not_logits end
             )

    assert {:error, :privacy_filter_model_output_invalid} =
             Serving.run(serving, "Ada Alan")
  end

  test "run_with_timings returns partial timings on errors" do
    assert {:ok, serving} =
             Serving.build(
               config: config(),
               decoder: :argmax,
               n_ctx: 2,
               model_fun: fn _token_ids, _attention_mask ->
                 single_person_first_token_logits(1)
               end
             )

    assert {:error, {:privacy_filter_logit_length_mismatch, 2, 1}, timings} =
             Serving.run_with_timings(serving, "Ada Alan")

    assert timings.tokenization_ms >= 0.0
    assert timings.model_ms >= 0.0
    assert timings.decode_ms == 0.0
    assert timings.total_ms >= 0.0
  end

  defp config do
    %{
      encoding: "cl100k_base",
      ner_class_names: [
        "O",
        "B-private_person",
        "I-private_person",
        "E-private_person",
        "S-private_person"
      ]
    }
  end

  defp single_person_first_token_logits(tokens) do
    rows =
      for index <- 0..(tokens - 1) do
        if index == 0 do
          [-10.0, -10.0, -10.0, -10.0, 10.0]
        else
          [10.0, -10.0, -10.0, -10.0, -10.0]
        end
      end

    Nx.tensor([rows])
  end

  defp all_outside_logits(tokens) do
    Nx.broadcast(Nx.tensor([[[10.0, -10.0, -10.0, -10.0, -10.0]]]), {1, tokens, 5})
  end

  defp calibration_file!(overrides) do
    path = Path.join(tmp_dir!(), "viterbi_calibration.json")

    write_calibration!(path, overrides)
    path
  end

  defp write_calibration!(path, overrides) do
    File.mkdir_p!(Path.dirname(path))

    biases =
      %{
        transition_bias_background_stay: 0.0,
        transition_bias_background_to_start: 0.0,
        transition_bias_inside_to_continue: 0.0,
        transition_bias_inside_to_end: 0.0,
        transition_bias_end_to_background: 0.0,
        transition_bias_end_to_start: 0.0
      }
      |> Map.merge(Map.new(overrides))
      |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)

    File.write!(path, Jason.encode!(%{operating_points: %{default: %{biases: biases}}}))
  end

  defp tmp_dir! do
    path =
      Path.join(
        System.tmp_dir!(),
        "obscura-privacy-filter-serving-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf(path) end)
    path
  end

  defp with_env(env, fun) when is_map(env) and is_function(fun, 0) do
    previous = Map.new(env, fn {key, _value} -> {key, System.get_env(key)} end)

    Enum.each(env, fn {key, value} -> System.put_env(key, value) end)

    try do
      fun.()
    after
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end
  end
end
