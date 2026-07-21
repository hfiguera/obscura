defmodule Obscura.PrivacyFilter.Checkpoint.Layout do
  @moduledoc """
  Explicit checkpoint layout handling for native privacy-filter loading.
  """

  alias Obscura.PrivacyFilter.Checkpoint.Files

  @supported [:native, :python_original]
  @python_original_files [
    "config.json",
    "dtypes.json",
    "model.safetensors",
    "viterbi_calibration.json"
  ]

  @type t :: :native | :python_original

  @spec supported() :: [t()]
  def supported, do: @supported

  @spec normalize(term()) :: {:ok, t()} | {:error, term()}
  def normalize(nil), do: {:ok, :native}
  def normalize(""), do: {:ok, :native}
  def normalize(:native), do: {:ok, :native}
  def normalize("native"), do: {:ok, :native}
  def normalize(:python_original), do: {:ok, :python_original}
  def normalize("python_original"), do: {:ok, :python_original}
  def normalize("python-original"), do: {:ok, :python_original}

  def normalize(other),
    do: {:error, {:unsupported_privacy_filter_checkpoint_layout, other, @supported}}

  @spec validate(Path.t(), t()) :: :ok | {:error, term()}
  def validate(path, layout) when is_binary(path) and layout in @supported do
    with :ok <- Files.validate_common(path), do: validate_layout(path, layout)
  end

  defp validate_layout(path, :native) do
    if File.exists?(Path.join(path, "dtypes.json")) do
      {:error, {:python_original_layout_requires_explicit_opt_in, path}}
    else
      :ok
    end
  end

  defp validate_layout(path, :python_original) do
    @python_original_files
    |> Enum.map(&Path.join(path, &1))
    |> Enum.reject(&File.exists?/1)
    |> case do
      [] -> :ok
      missing -> {:error, {:missing_python_original_checkpoint_files, path, missing}}
    end
  end
end
