defmodule Obscura.Recognizer.GLiNER.LabelMap do
  @moduledoc """
  Explicit GLiNER label profiles and Obscura entity mapping.
  """

  @generated_large_pii [
    {"person", :person},
    {"street address", :street_address},
    {"location", :location},
    {"organization", :organization},
    {"credit card number", :credit_card},
    {"date time", :date_time},
    {"title", :title},
    {"phone number", :phone},
    {"age", :age},
    {"nationality", :nationality},
    {"email address", :email},
    {"zip code", :zip_code},
    {"domain name", :domain},
    {"url", :url},
    {"iban code", :iban},
    {"social security number", :us_ssn},
    {"ip address", :ip_address},
    {"driver license", :us_driver_license}
  ]

  @hybrid_core [
    {"person", :person},
    {"organization", :organization},
    {"location", :location},
    {"email address", :email},
    {"phone number", :phone},
    {"credit card number", :credit_card},
    {"iban code", :iban},
    {"social security number", :us_ssn},
    {"ip address", :ip_address},
    {"domain name", :domain},
    {"url", :url}
  ]

  @open_class [
    {"person", :person},
    {"organization", :organization},
    {"location", :location}
  ]

  @edge_open_class [
    {"name", :person},
    {"organization", :organization},
    {"location", :location},
    {"location address", :location},
    {"location city", :location},
    {"location state", :location},
    {"location country", :location}
  ]

  @nvidia_nemotron_core [
    {"first_name", :person},
    {"last_name", :person},
    {"city", :location},
    {"country", :location},
    {"county", :location},
    {"state", :location},
    {"coordinate", :location},
    {"credit_debit_card", :credit_card},
    {"cvv", :credit_card},
    {"email", :email},
    {"ipv4", :ip_address},
    {"ipv6", :ip_address},
    {"phone_number", :phone},
    {"fax_number", :phone},
    {"url", :url},
    {"ssn", :us_ssn}
  ]

  @profiles %{
    edge_open_class: @edge_open_class,
    generated_large_pii: @generated_large_pii,
    hybrid_core: @hybrid_core,
    nvidia_nemotron_core: @nvidia_nemotron_core,
    open_class: @open_class
  }

  @doc """
  Returns all known profile names.
  """
  @spec profiles() :: [atom()]
  def profiles, do: Map.keys(@profiles) |> Enum.sort()

  @doc """
  Returns ordered GLiNER labels for a profile.
  """
  @spec labels(atom()) :: {:ok, [String.t()]} | {:error, term()}
  def labels(profile) do
    with {:ok, pairs} <- profile_pairs(profile) do
      {:ok, Enum.map(pairs, &elem(&1, 0))}
    end
  end

  @doc """
  Returns Obscura entities supported by a profile.
  """
  @spec supported_entities(atom()) :: [atom()]
  def supported_entities(profile) do
    case profile_pairs(profile) do
      {:ok, pairs} -> pairs |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.sort()
      {:error, _reason} -> []
    end
  end

  @doc """
  Maps a GLiNER label into an Obscura entity.
  """
  @spec to_entity(atom(), String.t()) :: atom() | nil
  def to_entity(profile, label) when is_binary(label) do
    normalized = normalize_label(label)

    profile
    |> profile_pairs()
    |> case do
      {:ok, pairs} -> Map.get(Map.new(pairs), normalized)
      {:error, _reason} -> nil
    end
  end

  @doc """
  Normalizes label profile input.
  """
  @spec normalize_profile(atom() | String.t()) :: {:ok, atom()} | {:error, term()}
  def normalize_profile(profile) when is_atom(profile) do
    if Map.has_key?(@profiles, profile),
      do: {:ok, profile},
      else: {:error, {:unknown_gliner_label_profile, profile}}
  end

  def normalize_profile(profile) when is_binary(profile) do
    profile
    |> String.trim()
    |> String.to_existing_atom()
    |> normalize_profile()
  rescue
    ArgumentError -> {:error, {:unknown_gliner_label_profile, profile}}
  end

  def normalize_profile(profile), do: {:error, {:unknown_gliner_label_profile, profile}}

  defp profile_pairs(profile) do
    with {:ok, normalized} <- normalize_profile(profile) do
      {:ok, Map.fetch!(@profiles, normalized)}
    end
  end

  defp normalize_label(label) do
    label
    |> String.trim()
    |> String.downcase()
  end
end
