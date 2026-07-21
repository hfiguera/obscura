defmodule Mix.Tasks.Obscura.Operational.Benchmark do
  @moduledoc """
  Runs authoritative operational benchmarks for measured product profiles.

      mix obscura.operational.benchmark --profiles fast,balanced
  """

  use Mix.Task

  alias Obscura.Eval.Operational.Benchmark
  alias Obscura.Eval.Operational.Dataset
  alias Obscura.Profile

  @shortdoc "Runs product-profile operational benchmarks"
  @cold_keys ~w(status fresh_os_process assets_preprovisioned network_downloads_allowed application_start_ms runtime_preparation_ms first_inference_ms total_ready_ms stages stage_counts compile_timing)a

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    opts = parse(args)

    Enum.each(opts[:profiles], &run_profile(&1, opts))
  end

  defp run_profile(profile, opts) do
    cold = run_cold_process(profile, List.first(opts[:datasets]), opts)

    case Benchmark.run(
           profile,
           datasets: opts[:datasets],
           repetitions: opts[:repetitions],
           sustained_duration_ms: opts[:sustained_duration_ms],
           sustained_request_count: opts[:sustained_request_count],
           sustained_concurrency: opts[:sustained_concurrency],
           request_timeout: opts[:request_timeout],
           output_root: opts[:output_root],
           cold_lifecycle: cold,
           privacy_filter_checkpoint: opts[:privacy_filter_checkpoint]
         ) do
      {:ok, reports} -> Enum.each(reports, &report_written/1)
      {:error, reason} -> Mix.raise("Operational benchmark failed: #{inspect(reason)}")
    end
  end

  defp report_written(result),
    do: Mix.shell().info("Wrote #{result.paths.json} and #{result.paths.markdown}")

  defp run_cold_process(profile, dataset, opts) do
    path =
      Path.join(
        System.tmp_dir!(),
        "obscura-operational-cold-#{System.unique_integer([:positive])}.json"
      )

    args = [
      "obscura.operational.cold",
      "--profile",
      Atom.to_string(profile),
      "--dataset",
      Atom.to_string(dataset),
      "--out",
      path
    ]

    started = System.monotonic_time()

    case System.cmd(System.find_executable("mix"), args,
           stderr_to_stdout: true,
           env: cold_environment(opts)
         ) do
      {_output, 0} ->
        elapsed = elapsed_ms(started)
        cold = path |> File.read!() |> Jason.decode!() |> atomize_cold_keys()
        File.rm(path)

        cold
        |> Map.put(:mix_task_ready_ms, cold.total_ready_ms)
        |> Map.put(:total_ready_ms, elapsed)
        |> Map.put(:os_process_total_ready_ms, elapsed)

      {output, status} ->
        File.rm(path)
        Mix.raise("Cold process failed with status #{status}: #{safe_process_output(output)}")
    end
  end

  defp cold_environment(opts) do
    operational_backend_environment()
    |> maybe_env(
      "OBSCURA_PRIVACY_FILTER_CHECKPOINT",
      opts[:privacy_filter_checkpoint] ||
        System.get_env("OBSCURA_PRIVACY_FILTER_CHECKPOINT")
    )
  end

  defp operational_backend_environment do
    case :os.type() do
      {:unix, :darwin} ->
        [
          {"OBSCURA_REAL_MODEL_BACKEND", "emily"},
          {"OBSCURA_PRIVACY_FILTER_BACKEND", "emily"},
          {"OBSCURA_EMILY_DEVICE", "gpu"},
          {"OBSCURA_EMILY_FALLBACK", "raise"}
        ]

      {:unix, :linux} ->
        [
          {"OBSCURA_REAL_MODEL_BACKEND", "exla"},
          {"OBSCURA_PRIVACY_FILTER_BACKEND", "exla"}
        ]

      _other ->
        []
    end
  end

  defp parse(args) do
    {parsed, remaining, invalid} =
      OptionParser.parse(args,
        strict: [
          profiles: :string,
          datasets: :string,
          repetitions: :integer,
          sustained_duration_ms: :integer,
          sustained_request_count: :integer,
          sustained_concurrency: :integer,
          request_timeout: :integer,
          output_root: :string,
          privacy_filter_checkpoint: :string
        ]
      )

    if remaining != [] or invalid != [], do: Mix.raise("Invalid operational benchmark options.")

    [
      profiles: parse_profiles(Keyword.get(parsed, :profiles, "fast,balanced")),
      datasets:
        parse_datasets(
          Keyword.get(
            parsed,
            :datasets,
            "generated_large_template_heldout,synth_dataset_v2_all,nemotron_pii_test_subset_all"
          )
        ),
      repetitions: Keyword.get(parsed, :repetitions, 2),
      sustained_duration_ms: Keyword.get(parsed, :sustained_duration_ms, 60_000),
      sustained_request_count: Keyword.get(parsed, :sustained_request_count),
      sustained_concurrency: Keyword.get(parsed, :sustained_concurrency, 4),
      request_timeout: Keyword.get(parsed, :request_timeout, 300_000),
      output_root: Keyword.get(parsed, :output_root, "eval/reports/operational"),
      privacy_filter_checkpoint: Keyword.get(parsed, :privacy_filter_checkpoint)
    ]
  end

  defp parse_profiles(value) do
    allowed = Profile.names() ++ Profile.experimental_names()

    value
    |> split()
    |> Enum.map(fn profile ->
      case Enum.find(allowed, &(Atom.to_string(&1) == profile)) do
        nil -> Mix.raise("Unknown benchmark profile: #{profile}")
        found -> found
      end
    end)
  end

  defp parse_datasets(value) do
    allowed = Dataset.names()

    value
    |> split()
    |> Enum.map(fn dataset ->
      case Enum.find(allowed, &(Atom.to_string(&1) == dataset)) do
        nil -> Mix.raise("Unknown operational dataset: #{dataset}")
        found -> found
      end
    end)
  end

  defp split(value), do: value |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

  defp atomize_cold_keys(map) do
    known = Map.new(@cold_keys, &{Atom.to_string(&1), &1})
    Map.new(map, fn {key, value} -> {Map.fetch!(known, key), value} end)
  end

  defp safe_process_output(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.reverse()
    |> Enum.take(5)
    |> Enum.reverse()
    |> Enum.map_join("\n", &String.slice(&1, 0, 300))
  end

  defp maybe_env(env, _key, nil), do: env
  defp maybe_env(env, key, value), do: [{key, value} | env]

  defp elapsed_ms(started) do
    System.monotonic_time()
    |> Kernel.-(started)
    |> System.convert_time_unit(:native, :microsecond)
    |> Kernel./(1_000)
  end
end
