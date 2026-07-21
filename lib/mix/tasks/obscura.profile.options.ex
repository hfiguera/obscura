defmodule Mix.Tasks.Obscura.Profile.Options do
  @moduledoc false

  @spec put_runtime_options(keyword()) :: keyword()
  def put_runtime_options(opts) do
    opts
    |> put_backend()
    |> put_compile()
  end

  defp put_backend(opts) do
    case Keyword.fetch(opts, :backend) do
      {:ok, backend} -> Keyword.put(opts, :real_model_backend, backend)
      :error -> opts
    end
  end

  defp put_compile(opts) do
    batch_size = Keyword.get(opts, :compile_batch_size)
    sequence_length = Keyword.get(opts, :compile_sequence_length)

    if is_integer(batch_size) or is_integer(sequence_length) do
      Keyword.put(opts, :compile,
        batch_size: batch_size || 1,
        sequence_length: sequence_length || 128
      )
    else
      opts
    end
  end
end
