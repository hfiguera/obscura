defmodule Ortex.Model do
  @moduledoc """
  A model for running Ortex inference with.

  Implements a human-readable representation of a model including the name, dimension, and
  type of each input and output

  ```
  #Ortex.Model<
  inputs: [{"x", "Int32", [nil, 100]}, {"y", "Float32", [nil, 100]}]
  outputs: [
    {"9", "Float32", [nil, 10]},
    {"onnx::Add_7", "Float32", [nil, 10]},
    {"onnx::Add_8", "Float32", [nil, 10]}
  ]>
  ```

  `nil` values represent dynamic dimensions
  """

  @enforce_keys [:reference]
  defstruct [:reference, :execution_provider_options, :profile_prefix]

  @doc false
  def load(path, eps \\ [:cpu], opt \\ 3) do
    case Ortex.Native.init(path, eps, opt) do
      {:error, msg} ->
        raise msg

      model ->
        %Ortex.Model{reference: model}
    end
  end

  @doc false
  def load_with_options(path, providers, opts \\ []) do
    optimization_level = Keyword.get(opts, :optimization_level, 3)
    profile_prefix = Keyword.get(opts, :profile_prefix)
    normalized = normalize_providers(providers)

    case Ortex.Native.init_with_options(
           path,
           normalized,
           optimization_level,
           profile_prefix
         ) do
      {:error, msg} ->
        raise msg

      model ->
        %Ortex.Model{
          reference: model,
          execution_provider_options: providers,
          profile_prefix: profile_prefix
        }
    end
  end

  @doc false
  def end_profiling(%Ortex.Model{profile_prefix: nil}) do
    raise ArgumentError, "profiling was not enabled for this Ortex model"
  end

  def end_profiling(%Ortex.Model{reference: model}) do
    case Ortex.Native.end_profiling(model) do
      {:error, msg} -> raise msg
      path -> path
    end
  end

  @doc false
  def run(%Ortex.Model{} = model, tensor) when not is_tuple(tensor) do
    run(model, {tensor})
  end

  @doc false
  def run(%Ortex.Model{reference: model}, tensors) do
    # Move tensors into Ortex backend and pass the reference to the Ortex NIF
    output =
      case Ortex.Native.run(
             model,
             tensors
             |> Tuple.to_list()
             |> Enum.map(fn x -> x |> Nx.backend_transfer(Ortex.Backend) end)
             |> Enum.map(fn %Nx.Tensor{data: %Ortex.Backend{ref: x}} -> x end)
           ) do
        {:error, msg} -> raise msg
        output -> output
      end

    # Pack the output into new Ortex.Backend tensor(s)
    output
    |> Enum.map(fn {ref, shape, dtype_atom, dtype_bits} ->
      %Nx.Tensor{
        data: %Ortex.Backend{ref: ref},
        shape: shape |> List.to_tuple(),
        type: {dtype_atom, dtype_bits},
        names: List.duplicate(nil, length(shape))
      }
    end)
    |> List.to_tuple()
  end

  defp normalize_providers(providers) when is_list(providers) do
    Enum.map(providers, fn
      {:coreml, options} when is_list(options) ->
        {"coreml", normalize_coreml_options(options)}

      provider when provider in [:cpu] ->
        {Atom.to_string(provider), []}

      {provider, options} ->
        raise ArgumentError,
              "unsupported structured Ortex provider: #{inspect({provider, options})}"

      provider ->
        raise ArgumentError, "unsupported structured Ortex provider: #{inspect(provider)}"
    end)
  end

  defp normalize_coreml_options(options) do
    allowed = [
      :model_format,
      :compute_units,
      :require_static_input_shapes,
      :enable_on_subgraphs
    ]

    unknown = Keyword.keys(options) -- allowed

    if unknown != [] do
      raise ArgumentError, "unknown CoreML options: #{inspect(unknown)}"
    end

    Enum.map(options, fn
      {:model_format, :ml_program} ->
        {"ModelFormat", "MLProgram"}

      {:model_format, :neural_network} ->
        {"ModelFormat", "NeuralNetwork"}

      {:compute_units, :all} ->
        {"MLComputeUnits", "ALL"}

      {:compute_units, :cpu_only} ->
        {"MLComputeUnits", "CPUOnly"}

      {:compute_units, :cpu_and_gpu} ->
        {"MLComputeUnits", "CPUAndGPU"}

      {:compute_units, :cpu_and_neural_engine} ->
        {"MLComputeUnits", "CPUAndNeuralEngine"}

      {:require_static_input_shapes, value} when is_boolean(value) ->
        {"RequireStaticInputShapes", boolean_option(value)}

      {:enable_on_subgraphs, value} when is_boolean(value) ->
        {"EnableOnSubgraphs", boolean_option(value)}

      option ->
        raise ArgumentError, "invalid CoreML option: #{inspect(option)}"
    end)
  end

  defp boolean_option(true), do: "1"
  defp boolean_option(false), do: "0"
end

defimpl Inspect, for: Ortex.Model do
  import Inspect.Algebra

  def inspect(%Ortex.Model{reference: model}, inspect_opts) do
    case Ortex.Native.show_session(model) do
      {:error, msg} ->
        raise msg

      {inputs, outputs} ->
        force_unfit(
          concat([
            color("#Ortex.Model<", :map, inspect_opts),
            line(),
            nest(concat(["  inputs: ", Inspect.Algebra.to_doc(inputs, inspect_opts)]), 2),
            line(),
            nest(concat(["  outputs: ", Inspect.Algebra.to_doc(outputs, inspect_opts)]), 2),
            color(">", :map, inspect_opts)
          ])
        )
    end
  end
end
