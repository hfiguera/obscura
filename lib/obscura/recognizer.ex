defmodule Obscura.Recognizer do
  @moduledoc """
  Behaviour for Obscura recognizers.
  """

  @callback name() :: atom()
  @callback supported_entities() :: [atom()]
  @callback entity() :: atom()
  @callback analyze(String.t(), keyword()) ::
              [Obscura.Analyzer.Result.t()]
              | {:ok, [Obscura.Analyzer.Result.t()]}
              | {:error, term()}

  @callback analyze_many([String.t()], keyword()) ::
              [[Obscura.Analyzer.Result.t()]]
              | {:ok, [[Obscura.Analyzer.Result.t()]]}
              | {:error, term()}

  @optional_callbacks entity: 0, analyze_many: 2
end
