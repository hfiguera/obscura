defmodule Obscura.PrivacyFilter.LabelMap do
  @moduledoc """
  Conservative mapping from privacy-filter labels to Obscura entities.

  `OpenMed/privacy-filter-nemotron` uses 55 fine-grained span labels expanded
  to BIOES token labels. Labels that fit Obscura's current Presidio-Research
  taxonomy are mapped here. Sensitive attributes that are not identifiers in the
  current benchmark taxonomy are intentionally ignored instead of being counted
  as supported entities without scoring evidence.
  """

  @default %{
    "account_number" => :account_number,
    "age" => :age,
    "api_key" => :secret,
    "bank_routing_number" => :financial_id,
    "biometric_identifier" => :id,
    "private_address" => :address,
    "private_date" => :date,
    "private_email" => :email,
    "private_person" => :person,
    "private_phone" => :phone,
    "private_url" => :url,
    "certificate_license_number" => :id,
    "city" => :location,
    "company_name" => :organization,
    "coordinate" => :location,
    "country" => :location,
    "county" => :location,
    "credit_debit_card" => :credit_card,
    "customer_id" => :id,
    "cvv" => :credit_card,
    "date_of_birth" => :date_time,
    "date_time" => :date_time,
    "device_identifier" => :device_id,
    "employee_id" => :employee_id,
    "fax_number" => :phone,
    "first_name" => :person,
    "health_plan_beneficiary_number" => :health_id,
    "http_cookie" => :secret,
    "ipv4" => :ip_address,
    "ipv6" => :ip_address,
    "last_name" => :person,
    "license_plate" => :vehicle_id,
    "mac_address" => :device_id,
    "medical_record_number" => :patient_id,
    "national_id" => :id,
    "password" => :secret,
    "phone_number" => :phone,
    "pin" => :secret,
    "postcode" => :zip_code,
    "secret" => :secret,
    "ssn" => :us_ssn,
    "state" => :location,
    "street_address" => :street_address,
    "swift_bic" => :financial_id,
    "tax_id" => :id,
    "time" => :date_time,
    "unique_id" => :id,
    "url" => :url,
    "user_name" => :handle,
    "vehicle_identifier" => :vehicle_id,
    "other_person" => :person,
    "personal_url" => :url,
    "other_url" => :url,
    "personal_location" => :location,
    "other_location" => :location,
    "personal_email" => :email,
    "other_email" => :email,
    "personal_phone" => :phone,
    "other_phone" => :phone,
    "personal_date" => :date,
    "other_date" => :date,
    "personal_id" => :id,
    "personal_name" => :person,
    "personal_handle" => :handle,
    "personal_org" => :organization,
    "personal_gov_id" => :id,
    "personal_fin_id" => :financial_id,
    "personal_health_id" => :health_id,
    "personal_device_id" => :device_id,
    "personal_vehicle_id" => :vehicle_id,
    "personal_property_id" => :property_id,
    "personal_edu_id" => :education_id,
    "personal_emp_id" => :employee_id,
    "personal_membership_id" => :membership_id,
    "personal_registry_id" => :registry_id,
    "secret_url" => :secret,
    "email" => :email,
    "phone" => :phone,
    "date" => :date,
    "account" => :account_number,
    "patient" => :person,
    "staff" => :person,
    "hospital" => :organization,
    "hosp" => :organization,
    "patorg" => :organization,
    "id" => :id
  }

  @ignored %{
    "blood_type" => "health attribute; not a current Obscura benchmark entity",
    "education_level" => "attribute; not a current Obscura benchmark entity",
    "employment_status" => "attribute; not a current Obscura benchmark entity",
    "gender" => "sensitive attribute; not a current Obscura benchmark entity",
    "language" => "attribute; not a current Obscura benchmark entity",
    "occupation" => "attribute; not a current Obscura benchmark entity",
    "political_view" => "sensitive attribute; not a current Obscura benchmark entity",
    "race_ethnicity" => "sensitive attribute; not a current Obscura benchmark entity",
    "religious_belief" => "sensitive attribute; not a current Obscura benchmark entity",
    "sexuality" => "sensitive attribute; not a current Obscura benchmark entity"
  }

  @spec default() :: %{String.t() => atom()}
  def default, do: @default

  @doc """
  Returns the Presidio-Research benchmark taxonomy map.

  Presidio-Research normalizes date-like source labels to `:date_time`, while
  Obscura's runtime default keeps generic `date` labels separate as `:date`.
  This map is intended for benchmark parity with the Python reference adapter,
  not as a replacement for the library runtime default.
  """
  @spec presidio_research() :: %{String.t() => atom()}
  def presidio_research do
    @default
    |> Map.put("date", :date_time)
    |> Map.put("private_date", :date_time)
    |> Map.put("personal_date", :date_time)
    |> Map.put("other_date", :date_time)
  end

  @spec for_entities([atom()]) :: %{String.t() => atom()}
  def for_entities(entities, label_map \\ @default) when is_list(entities) do
    allowed = MapSet.new(entities)

    label_map
    |> normalize_map()
    |> Enum.filter(fn {_label, entity} -> MapSet.member?(allowed, entity) end)
    |> Map.new()
  end

  @spec ignored() :: %{String.t() => String.t()}
  def ignored, do: @ignored

  @spec known_labels() :: [String.t()]
  def known_labels do
    (@default |> Map.keys()) ++ (@ignored |> Map.keys())
  end

  @spec map_label(String.t(), map() | keyword()) :: {:ok, atom()} | :ignore
  def map_label(label, opts \\ %{}) when is_binary(label) do
    label_map = label_map(opts)
    normalized = label |> String.trim() |> String.downcase()

    case Map.get(label_map, normalized) do
      nil -> :ignore
      entity -> {:ok, entity}
    end
  end

  @spec supported_entities() :: [atom()]
  def supported_entities do
    @default
    |> Map.values()
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp label_map(opts) when is_list(opts),
    do: opts |> Keyword.get(:label_map, @default) |> normalize_map()

  defp label_map(%{} = opts), do: opts |> Map.get(:label_map, @default) |> normalize_map()

  defp normalize_map(:default), do: normalize_map(@default)

  defp normalize_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {key |> to_string() |> String.downcase(), value} end)
  end
end
