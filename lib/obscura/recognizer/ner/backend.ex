defmodule Obscura.Recognizer.NER.Backend do
  @moduledoc """
  Opt-in runtime backend configuration for real local NER serving.

  Obscura's default path stays dependency-light. This module only configures
  accelerator backends when a caller explicitly selects one through options or
  environment variables.
  """

  @supported_backends [:default, :binary, :exla, :emily]
  @supported_fallback_modes [:silent, :warn, :raise]

  @type backend :: :default | :binary | :exla | :emily

  @doc """
  Applies backend configuration and returns serving options.
  """
  @spec configure(keyword()) :: {:ok, keyword()} | {:error, term()}
  def configure(opts) do
    case selected_backend(opts) do
      {:ok, :default} ->
        {:ok, Keyword.put_new(opts, :backend, :default)}

      {:ok, :binary} ->
        {:ok, opts |> Keyword.put(:backend, :binary) |> Keyword.delete(:defn_options)}

      {:ok, :exla} ->
        configure_exla(opts)

      {:ok, :emily} ->
        configure_emily(opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns telemetry/report-safe backend metadata.
  """
  @spec metadata(keyword()) :: map()
  def metadata(opts) do
    case selected_backend(opts) do
      {:ok, backend} ->
        Map.merge(
          %{
            requested_backend: backend,
            source: backend_source(opts),
            emily_fallback: fallback_mode(opts),
            emily_device: emily_device(opts),
            exla_enabled: backend == :exla
          },
          actual_runtime(backend, opts)
        )

      {:error, _reason} ->
        %{
          requested_backend: :unsupported,
          reason: :unsupported_backend,
          source: backend_source(opts)
        }
    end
  end

  @doc """
  Normalizes a user-provided backend name.
  """
  @spec normalize(String.t() | atom() | nil) :: {:ok, backend()} | {:error, term()}
  def normalize(nil), do: {:ok, :default}
  def normalize(""), do: {:ok, :default}
  def normalize(:default), do: {:ok, :default}
  def normalize(:binary), do: {:ok, :binary}
  def normalize(:exla), do: {:ok, :exla}
  def normalize(:emily), do: {:ok, :emily}

  def normalize(value) when is_binary(value) do
    case value |> String.downcase() |> String.replace("-", "_") do
      "default" -> {:ok, :default}
      "binary" -> {:ok, :binary}
      "exla" -> {:ok, :exla}
      "emily" -> {:ok, :emily}
      _other -> {:error, {:unsupported_real_model_backend, @supported_backends}}
    end
  end

  def normalize(_other),
    do: {:error, {:unsupported_real_model_backend, @supported_backends}}

  defp selected_backend(opts) do
    opts
    |> Keyword.get(:real_model_backend)
    |> Kernel.||(System.get_env("OBSCURA_REAL_MODEL_BACKEND"))
    |> Kernel.||(legacy_exla_backend())
    |> normalize()
  end

  defp legacy_exla_backend do
    if System.get_env("OBSCURA_EVAL_EXLA") == "1", do: :exla
  end

  defp configure_exla(opts) do
    compiler = Module.concat(["EXLA"])

    with :ok <- ensure_loaded(compiler, :exla, opts),
         {:ok, _started} <- start_application(:exla, opts) do
      {:ok,
       opts
       |> Keyword.put(:backend, :exla)
       |> put_defn_compiler(compiler)}
    else
      {:error, {:missing_optional_dependency, _dep} = reason} -> {:error, reason}
      {:error, reason} -> {:error, {:compiler_start_failed, :exla, reason}}
    end
  end

  defp configure_emily(opts) do
    emily = Module.concat(["Emily"])
    backend = Module.concat(["Emily", "Backend"])
    compiler = Module.concat(["Emily", "Compiler"])
    nx = Module.concat(["Nx"])
    nx_defn = Module.concat(["Nx", "Defn"])

    with :ok <- ensure_loaded(emily, :emily, opts),
         :ok <- ensure_loaded(backend, :emily, opts),
         :ok <- ensure_loaded(compiler, :emily, opts),
         :ok <- ensure_loaded(nx, :nx, opts),
         :ok <- ensure_loaded(nx_defn, :nx, opts),
         :ok <- put_emily_fallback(opts),
         {:ok, _started} <- start_application(:emily, opts),
         :ok <- set_nx_backend({backend, device: emily_device(opts)}, opts),
         :ok <- set_nx_defn_options([compiler: compiler], opts) do
      {:ok,
       opts
       |> Keyword.put(:backend, :emily)
       |> put_defn_compiler(compiler)}
    else
      {:error, {:missing_optional_dependency, _dep} = reason} -> {:error, reason}
      {:error, reason} -> {:error, {:backend_configuration_failed, :emily, reason}}
    end
  end

  defp ensure_loaded(module, dependency, opts) do
    checker = Keyword.get(opts, :dependency_checker, &Code.ensure_loaded?/1)

    if checker.(module) do
      :ok
    else
      {:error, {:missing_optional_dependency, dependency}}
    end
  end

  defp start_application(app, opts) do
    opts
    |> Keyword.get(:application_starter, &Application.ensure_all_started/1)
    |> then(& &1.(app))
  end

  defp put_emily_fallback(opts) do
    mode = fallback_mode(opts)
    putter = Keyword.get(opts, :application_env_putter, &Application.put_env/3)
    putter.(:emily, :fallback, mode)
    :ok
  end

  defp set_nx_backend(backend, opts) do
    case Keyword.get(opts, :nx_backend_setter) do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      nil -> apply(Module.concat(["Nx"]), :global_default_backend, [backend])
      setter -> setter.(backend)
    end

    :ok
  rescue
    error -> {:error, {:backend_configuration_failed, error.__struct__}}
  end

  defp set_nx_defn_options(defn_options, opts) do
    case Keyword.get(opts, :nx_defn_options_setter) do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      nil -> apply(Module.concat(["Nx", "Defn"]), :global_default_options, [defn_options])
      setter -> setter.(defn_options)
    end

    :ok
  rescue
    error -> {:error, {:defn_configuration_failed, error.__struct__}}
  end

  defp put_defn_compiler(opts, compiler) do
    defn_options =
      opts
      |> Keyword.get(:defn_options, [])
      |> Keyword.put(:compiler, compiler)

    Keyword.put(opts, :defn_options, defn_options)
  end

  defp fallback_mode(opts) do
    value = Keyword.get(opts, :emily_fallback, System.get_env("OBSCURA_EMILY_FALLBACK", "raise"))

    value
    |> normalize_fallback_mode()
    |> case do
      {:ok, mode} -> mode
      {:error, _reason} -> :raise
    end
  end

  defp normalize_fallback_mode(value) when is_atom(value) and value in @supported_fallback_modes,
    do: {:ok, value}

  defp normalize_fallback_mode(value) when is_binary(value) do
    case String.downcase(value) do
      "silent" -> {:ok, :silent}
      "warn" -> {:ok, :warn}
      "raise" -> {:ok, :raise}
      _other -> {:error, {:unsupported_emily_fallback, @supported_fallback_modes}}
    end
  end

  defp normalize_fallback_mode(_value),
    do: {:error, {:unsupported_emily_fallback, @supported_fallback_modes}}

  defp emily_device(opts) do
    opts
    |> Keyword.get(:emily_device, System.get_env("OBSCURA_EMILY_DEVICE", "gpu"))
    |> normalize_device()
  end

  defp normalize_device(device) when device in [:gpu, :cpu], do: device
  defp normalize_device("gpu"), do: :gpu
  defp normalize_device("cpu"), do: :cpu
  defp normalize_device(_other), do: :gpu

  defp backend_source(opts) do
    cond do
      Keyword.has_key?(opts, :real_model_backend) -> :option
      System.get_env("OBSCURA_REAL_MODEL_BACKEND") not in [nil, ""] -> :env
      System.get_env("OBSCURA_EVAL_EXLA") == "1" -> :legacy_exla_env
      true -> :default
    end
  end

  defp actual_runtime(requested_backend, opts) do
    inspector = Keyword.get(opts, :backend_inspector, &default_backend/0)

    case inspector.() do
      {backend_module, backend_opts} ->
        actual_backend = normalize_actual_backend(backend_module)

        %{
          actual_backend: actual_backend,
          actual_device: actual_device(actual_backend, backend_opts),
          backend_proven: actual_backend != :unknown,
          fallback_occurred: fallback_occurred?(requested_backend, actual_backend)
        }

      _other ->
        %{
          actual_backend: :unknown,
          actual_device: :unknown,
          backend_proven: false,
          fallback_occurred: :unknown
        }
    end
  rescue
    _error ->
      %{
        actual_backend: :unknown,
        actual_device: :unknown,
        backend_proven: false,
        fallback_occurred: :unknown
      }
  end

  defp default_backend do
    if Code.ensure_loaded?(Nx), do: Nx.default_backend()
  end

  defp normalize_actual_backend(module) do
    case Atom.to_string(module) do
      "Elixir.Emily.Backend" -> :emily
      "Elixir.EXLA.Backend" -> :exla
      "Elixir.Nx.BinaryBackend" -> :binary
      _other -> :unknown
    end
  end

  defp actual_device(:binary, _opts), do: :cpu

  defp actual_device(_backend, opts) when is_list(opts),
    do: Keyword.get(opts, :device, :unknown)

  defp actual_device(_backend, _opts), do: :unknown

  defp fallback_occurred?(:default, _actual), do: false
  defp fallback_occurred?(_requested, :unknown), do: :unknown
  defp fallback_occurred?(requested, actual), do: requested != actual
end
