defmodule RedactEvaluation.ObscuraWorker do
  @profiles %{"fast" => :fast, "efficient" => :efficient, "balanced" => :balanced}

  def main([profile_name]) do
    profile = Map.fetch!(@profiles, profile_name)
    Application.ensure_all_started(:jason)
    Application.ensure_all_started(:obscura)
    began = System.monotonic_time(:microsecond)
    allow_download = System.get_env("REDACT_EVAL_PREPARE") == "1"

    engine =
      if profile == :balanced do
        {:ok, _} = Application.ensure_all_started(:exla)
        client = EXLA.Client.fetch!(:host)
        if client.platform != :host, do: raise("CPU client was not selected")
        Nx.global_default_backend({EXLA.Backend, client: :host})

        %{
          backend: :exla,
          device: :cpu,
          client: client.name,
          platform: client.platform,
          device_count: client.device_count,
          default_device_id: client.default_device_id
        }
      else
        %{backend: if(profile == :efficient, do: :native_spacy, else: :beam), device: :cpu}
      end

    prepare_opts = [allow_download: allow_download, offline: not allow_download]

    prepare_opts =
      if profile == :balanced do
        prepare_opts ++
          [
            real_model_backend: :exla,
            defn_options: [compiler: EXLA, client: :host],
            compile: [batch_size: 1, sequence_length: 128]
          ]
      else
        prepare_opts
      end

    {:ok, runtime} = Obscura.Profile.prepare(profile, prepare_opts)
    {:ok, descriptor} = Obscura.Profile.fetch(profile)

    emit(%{
      event: :ready,
      profile: profile,
      obscura: Application.spec(:obscura, :vsn) |> to_string(),
      elixir: System.version(),
      otp: System.otp_release(),
      engine: engine,
      preparation_ms: elapsed(began),
      supported_entities: descriptor.supported_entities,
      pid: System.pid(),
      schedulers: :erlang.system_info(:schedulers_online)
    })

    try do
      IO.stream(:stdio, :line)
      |> Enum.each(fn line ->
        request = Jason.decode!(line)
        started = System.monotonic_time(:microsecond)
        entities = if is_list(request["entities"]), do: Enum.filter(descriptor.supported_entities, &(Atom.to_string(&1) in request["entities"])), else: descriptor.supported_entities

        result =
          case Obscura.analyze(request["text"],
                 profile: runtime,
                 entities: entities,
                 include_text: false
               ) do
            {:ok, predictions} ->
              %{
                id: request["id"],
                predictions:
                  Enum.map(predictions, fn p ->
                    %{entity: p.entity, byte_start: p.byte_start, byte_end: p.byte_end}
                  end),
                inference_ms: elapsed(started)
              }

            {:error, diagnostic} ->
              %{id: request["id"], error: error_code(diagnostic), inference_ms: elapsed(started)}
          end

        emit(result)
      end)
    after
      if runtime.resources[:spacy], do: Obscura.Spacy.Serving.stop(runtime.resources.spacy)
    end
  end

  defp error_code(%{code: code}), do: to_string(code)
  defp error_code(_), do: "analyzer_error"
  defp elapsed(started), do: (System.monotonic_time(:microsecond) - started) / 1000
  defp emit(value), do: IO.puts(Jason.encode!(value))
end

RedactEvaluation.ObscuraWorker.main(System.argv())
