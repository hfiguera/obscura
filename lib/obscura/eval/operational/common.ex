defmodule Obscura.Eval.Operational.Common do
  @moduledoc false

  alias Obscura.Eval.Operational.Dataset
  alias Obscura.Eval.Operational.Metadata
  alias Obscura.Eval.Operational.StageTracker
  alias Obscura.Profile

  @spec load_datasets([Dataset.name()], Profile.name()) :: {:ok, [map()]} | {:error, term()}
  def load_datasets(names, profile) do
    names
    |> Enum.reduce_while({:ok, []}, &load_dataset(&1, &2, profile))
    |> reverse_datasets()
  end

  @spec with_datasets_and_tracker(
          [Dataset.name()],
          Profile.name(),
          (list(), pid() -> term())
        ) :: term()
  def with_datasets_and_tracker(names, profile, fun) when is_function(fun, 2) do
    with {:ok, datasets} <- load_datasets(names, profile),
         {:ok, tracker} <- StageTracker.start_link() do
      try do
        fun.(datasets, tracker)
      after
        if Process.alive?(tracker), do: Agent.stop(tracker)
      end
    end
  end

  @spec replacement_host(pid()) :: pid()
  def replacement_host(supervisor) do
    supervisor
    |> Supervisor.which_children()
    |> List.first()
    |> elem(1)
  end

  @spec interleave_samples([map()]) :: [map()]
  def interleave_samples(datasets) do
    maximum = datasets |> Enum.map(&length(&1.samples)) |> Enum.max()

    0..(maximum - 1)
    |> Enum.flat_map(fn index ->
      Enum.flat_map(datasets, &sample_at(&1, index))
    end)
  end

  @spec pearson_coefficient([{number(), number()}]) ::
          {:ok, float()} | {:error, :zero_variance}
  def pearson_coefficient(points) do
    {left, right} = Enum.unzip(points)
    left_mean = Enum.sum(left) / length(left)
    right_mean = Enum.sum(right) / length(right)

    {covariance, left_variance, right_variance} =
      Enum.reduce(points, {0.0, 0.0, 0.0}, fn {x, y}, {cov, x_var, y_var} ->
        x_delta = x - left_mean
        y_delta = y - right_mean

        {
          cov + x_delta * y_delta,
          x_var + x_delta * x_delta,
          y_var + y_delta * y_delta
        }
      end)

    if left_variance == 0 or right_variance == 0,
      do: {:error, :zero_variance},
      else: {:ok, covariance / :math.sqrt(left_variance * right_variance)}
  end

  @spec validate_resilience(map(), atom()) :: :ok | {:error, atom()}
  def validate_resilience(
        %{
          "timeout" => %{"status" => "passed"},
          "overload" => %{"status" => "passed"},
          "serving_crash_recovery" => %{"status" => "passed"},
          "privacy_check" => %{"status" => "passed"}
        },
        _error
      ),
      do: :ok

  def validate_resilience(_resilience, error), do: {:error, error}

  @spec prepare_runtime(Profile.name(), pid(), keyword()) ::
          {:ok, Profile.Runtime.t(), number()} | {:error, term()}
  def prepare_runtime(profile, tracker, opts) do
    started = System.monotonic_time()

    prepare_opts =
      [
        stage_observer: StageTracker.observer(tracker),
        real_model_backend: backend(profile),
        backend: backend(profile),
        emily_device: :gpu,
        emily_fallback: :raise,
        offline: true
      ]
      |> maybe_put(:privacy_filter_checkpoint, Keyword.get(opts, :privacy_filter_checkpoint))
      |> maybe_put(:sequence_length_buckets, Keyword.get(opts, :sequence_length_buckets))
      |> maybe_put(
        :sequence_length_bucket_threshold,
        Keyword.get(opts, :sequence_length_bucket_threshold)
      )
      |> maybe_put(:logprob_conversion, Keyword.get(opts, :logprob_conversion))

    case Profile.prepare(profile, prepare_opts) do
      {:ok, runtime} -> {:ok, runtime, elapsed_ms(started)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec dataset_metadata(map()) :: map()
  def dataset_metadata(dataset) do
    metadata = dataset.selection["dataset"]

    %{
      id: dataset.name,
      name: metadata["name"],
      split: get_in(metadata, ["template_split", "name"]),
      sample_count: metadata["sample_count"],
      sha256: metadata["sha256"],
      sample_ids_sha256: metadata["sample_ids_sha256"],
      selection_sha256: dataset.selection_sha256,
      entity_policy_sha256: get_in(dataset.selection, ["entity_policy", "sha256"]),
      scoring_sha256: get_in(dataset.selection, ["scoring", "sha256"])
    }
  end

  @spec environment(Profile.name(), map()) :: map()
  def environment(:fast, _backend_metadata) do
    Metadata.environment(:fast, %{})
    |> Map.merge(%{
      platform: platform(),
      requested_backend: :beam_cpu,
      requested_device: :cpu,
      emily_fallback: :not_applicable,
      backend_proven: true,
      fallback_occurred: false
    })
  end

  def environment(profile, backend_metadata) do
    proofs = backend_proofs(backend_metadata)
    selected_backend = backend(profile)

    Metadata.environment(profile, backend_metadata)
    |> Map.merge(%{
      platform: platform(),
      requested_backend: selected_backend,
      requested_device: requested_device(selected_backend),
      emily_fallback: fallback_policy(selected_backend),
      backend_proven: proofs != [] and Enum.all?(proofs, &(&1.backend_proven == true)),
      fallback_occurred: Enum.any?(proofs, &(&1.fallback_occurred != false))
    })
  end

  @spec request_timeout(Profile.name(), keyword()) :: pos_integer()
  def request_timeout(:openmed_pii, opts),
    do: Keyword.get(opts, :request_timeout, 300_000)

  def request_timeout(_profile, opts), do: Keyword.get(opts, :request_timeout, 120_000)

  @spec backend(Profile.name()) :: atom()
  def backend(:fast), do: :default
  def backend(_profile), do: platform_backend()

  @spec gpu?(Profile.name()) :: boolean()
  def gpu?(:fast), do: false
  def gpu?(_profile), do: platform_backend() == :emily

  @spec safe_reason(term()) :: atom()
  def safe_reason(%{code: code}) when is_atom(code), do: code
  def safe_reason({code, _detail}) when is_atom(code), do: code
  def safe_reason(reason) when is_atom(reason), do: reason
  def safe_reason(_reason), do: :unknown

  defp load_dataset(name, {:ok, acc}, profile) do
    case Dataset.load(name, profile: profile) do
      {:ok, dataset} -> {:cont, {:ok, [dataset | acc]}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp reverse_datasets({:ok, datasets}), do: {:ok, Enum.reverse(datasets)}
  defp reverse_datasets(error), do: error

  defp sample_at(dataset, index) do
    case Enum.at(dataset.samples, index) do
      nil -> []
      sample -> [Map.put(sample, :dataset_id, dataset.name)]
    end
  end

  defp backend_proofs(term) when is_map(term) do
    own = if Map.has_key?(term, :backend_proven), do: [term], else: []
    own ++ Enum.flat_map(Map.values(term), &backend_proofs/1)
  end

  defp backend_proofs(_term), do: []

  defp platform_backend do
    case :os.type() do
      {:unix, :darwin} -> :emily
      {:unix, :linux} -> :exla
      _other -> :default
    end
  end

  defp platform do
    case :os.type() do
      {:unix, :darwin} -> :apple_emily
      {:unix, :linux} -> :linux_exla
      _other -> :unsupported
    end
  end

  defp requested_device(:emily), do: :gpu
  defp requested_device(:exla), do: System.get_env("XLA_TARGET", "configured_by_runner")
  defp requested_device(_backend), do: :cpu
  defp fallback_policy(:emily), do: :raise
  defp fallback_policy(_backend), do: :not_applicable
  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)

  defp elapsed_ms(started) do
    System.monotonic_time()
    |> Kernel.-(started)
    |> System.convert_time_unit(:native, :microsecond)
    |> Kernel./(1_000)
  end
end
