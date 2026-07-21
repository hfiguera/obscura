defmodule Obscura.Language.Detector do
  @moduledoc """
  Behaviour for optional language detectors.
  """

  @callback detect(String.t(), keyword()) :: {:ok, atom() | String.t()} | {:error, term()}
end
