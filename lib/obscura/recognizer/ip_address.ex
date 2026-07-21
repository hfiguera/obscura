defmodule Obscura.Recognizer.IPAddress do
  @moduledoc false
  @behaviour Obscura.Recognizer

  alias Obscura.Recognizer.Pattern

  @ipv4 ~r/(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])/
  @ipv6 ~r/(?<![0-9A-Fa-f:])(?:[0-9A-Fa-f]{0,4}:){1,7}[0-9A-Fa-f]{0,4}(?![0-9A-Fa-f:])/

  @impl true
  def name, do: :ip_address

  @impl true
  def supported_entities, do: [:ip_address]

  @impl true
  def entity, do: :ip_address

  @impl true
  def analyze(text, opts) do
    explain? = Keyword.get(opts, :explain, false)

    Pattern.scan(text, @ipv4,
      entity: :ip_address,
      source_entity: "IP_ADDRESS",
      recognizer: :ip_address,
      pattern: :ipv4,
      score: 0.8,
      explain: explain?,
      validate: &validate/1
    ) ++
      Pattern.scan(text, @ipv6,
        entity: :ip_address,
        source_entity: "IP_ADDRESS",
        recognizer: :ip_address,
        pattern: :ipv6,
        score: 0.8,
        explain: explain?,
        validate: &validate/1
      )
  end

  defp validate(value) do
    value
    |> String.to_charlist()
    |> :inet.parse_address()
    |> case do
      {:ok, _address} -> {:ok, %{}}
      {:error, _reason} -> {:error, :invalid_ip_address}
    end
  end
end
