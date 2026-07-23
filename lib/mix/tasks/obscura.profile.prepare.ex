defmodule Mix.Tasks.Obscura.Profile.Prepare do
  @moduledoc """
  Explicitly prepares and validates a reusable Obscura profile runtime.

      mix obscura.profile.prepare --profile balanced --backend emily --allow-download
      mix obscura.profile.prepare --profile balanced --backend emily --offline --json

  Downloads require `--allow-download`; otherwise preparation is cache-only.
  `--offline` always forbids remote asset access. The task reports the effective
  cache directory, model index, observed download bytes, stage transitions,
  elapsed time, and final readiness. JSON mode emits one object per line and
  disables Bumblebee's terminal progress bar.

  Before preparing an asset with a known commercial-use requirement, the task
  emits an `asset_license_notice`. `--allow-download` permits network access;
  it does not accept model terms or establish deployment authorization.

  Online preparation retries one transient model or tokenizer load failure.
  Recovery quarantines unreferenced partial cache files before downloading a
  clean replacement. Quarantined files remain on disk for operator review.
  """

  use Mix.Task

  alias Mix.Tasks.Obscura.Profile.Options
  alias Obscura.Diagnostic
  alias Obscura.Profile
  alias Obscura.Profile.Cache

  @shortdoc "Prepares a reusable profile runtime with progress"

  @switches [
    profile: :string,
    backend: :string,
    allow_download: :boolean,
    offline: :boolean,
    timeout: :integer,
    inactivity_timeout: :integer,
    json: :boolean,
    compile_batch_size: :integer,
    compile_sequence_length: :integer
  ]

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    opts = parse_args(args)
    profile = Keyword.fetch!(opts, :profile)
    json? = Keyword.get(opts, :json, false)
    {cache_dir, cache_source} = Cache.effective_directory(opts)

    render_setup(profile, cache_dir, cache_source, opts)

    progress = fn event -> render_progress(event, json?) end
    opts = Keyword.put(opts, :progress, progress)

    with_bumblebee_progress_disabled(fn ->
      case Profile.prepare(profile, opts) do
        {:ok, runtime} ->
          render_result(:ok, profile, runtime.backend_metadata, nil, json?)

        {:error, %Diagnostic{} = diagnostic} ->
          render_result(:error, profile, %{}, diagnostic, json?)
          Mix.raise(Diagnostic.format(diagnostic))
      end
    end)
  end

  defp parse_args(args) do
    {parsed, remaining, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [] or remaining != [], do: Mix.raise("Invalid options.")
    if is_nil(parsed[:profile]), do: Mix.raise("Expected --profile")

    parsed
    |> Keyword.update!(:profile, &normalize_profile/1)
    |> Options.put_runtime_options()
  end

  defp normalize_profile(profile) do
    case Profile.normalize(profile) do
      {:ok, %{requested: normalized}} -> normalized
      {:error, diagnostic} -> Mix.raise(Diagnostic.format(diagnostic))
    end
  end

  defp render_setup(profile, cache_dir, cache_source, opts) do
    {:ok, requirements} = Profile.requirements(profile)

    record = %{
      type: :setup,
      profile: profile,
      models: requirements.default_models,
      model_count: length(requirements.default_models),
      asset_licensing: requirements.asset_licensing,
      cache_directory: cache_dir,
      cache_directory_source: cache_source,
      allow_download: Keyword.get(opts, :allow_download, false),
      offline: Keyword.get(opts, :offline, false)
    }

    if Keyword.get(opts, :json, false) do
      Mix.shell().info(Jason.encode!(record))
    else
      models = Enum.map_join(record.models, ", ", &to_string/1)

      Mix.shell().info(
        "profile=#{profile} models=#{if(models == "", do: "none", else: models)} " <>
          "model_count=#{record.model_count} cache=#{cache_dir} " <>
          "allow_download=#{record.allow_download} offline=#{record.offline}"
      )
    end
  end

  defp render_progress(event, true) do
    Mix.shell().info(Jason.encode!(Map.put(event, :type, :progress)))
  end

  defp render_progress(%{event: :asset_license_notice} = event, false) do
    Mix.shell().info(
      "license_notice asset=#{event.asset} commercial_use=#{event.commercial_use}: #{event.message}"
    )
  end

  defp render_progress(event, false) do
    details =
      [
        event[:model] && "model=#{event.model}",
        event[:model_index] && "model_index=#{event.model_index}/#{event.model_count}",
        event[:stage] && "stage=#{event.stage}",
        event[:cache_status] && "cache=#{event.cache_status}",
        event[:bytes_received] && "bytes=#{event.bytes_received}",
        "elapsed_ms=#{event.elapsed_ms}"
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    Mix.shell().info("#{event.event} #{details}")
  end

  defp render_result(status, profile, metadata, diagnostic, true) do
    Mix.shell().info(
      Jason.encode!(%{
        type: :result,
        status: status,
        profile: profile,
        runtime: metadata,
        diagnostic: diagnostic && Diagnostic.to_map(diagnostic)
      })
    )
  end

  defp render_result(:ok, profile, _metadata, _diagnostic, false) do
    Mix.shell().info("profile=#{profile} status=ready runtime=reusable")
  end

  defp render_result(:error, _profile, _metadata, diagnostic, false) do
    Mix.shell().error("status=error #{Diagnostic.format(diagnostic)}")
  end

  defp with_bumblebee_progress_disabled(fun) do
    previous = Application.get_env(:bumblebee, :progress_bar_enabled, :not_set)
    Application.put_env(:bumblebee, :progress_bar_enabled, false)

    try do
      fun.()
    after
      case previous do
        :not_set -> Application.delete_env(:bumblebee, :progress_bar_enabled)
        value -> Application.put_env(:bumblebee, :progress_bar_enabled, value)
      end
    end
  end
end
