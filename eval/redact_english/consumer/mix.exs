defmodule RedactEvaluation.MixProject do
  use Mix.Project

  def project do
    [
      app: :redact_evaluation,
      version: "0.0.0",
      elixir: "~> 1.17",
      deps: [
        {:obscura, path: "../../.."},
        {:nx, "== 0.13.1", override: true},
        {:bumblebee, "== 0.7.1", override: true},
        {:exla, "== 0.13.1"}
      ]
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto]]
end
