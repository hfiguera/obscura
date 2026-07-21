defmodule Obscura.PrivacyFilter.LabelMapTest do
  use ExUnit.Case, async: true

  alias Obscura.PrivacyFilter.LabelMap

  @nemotron_span_labels [
    "account_number",
    "age",
    "api_key",
    "bank_routing_number",
    "biometric_identifier",
    "blood_type",
    "certificate_license_number",
    "city",
    "company_name",
    "coordinate",
    "country",
    "county",
    "credit_debit_card",
    "customer_id",
    "cvv",
    "date",
    "date_of_birth",
    "date_time",
    "device_identifier",
    "education_level",
    "email",
    "employee_id",
    "employment_status",
    "fax_number",
    "first_name",
    "gender",
    "health_plan_beneficiary_number",
    "http_cookie",
    "ipv4",
    "ipv6",
    "language",
    "last_name",
    "license_plate",
    "mac_address",
    "medical_record_number",
    "national_id",
    "occupation",
    "password",
    "phone_number",
    "pin",
    "political_view",
    "postcode",
    "race_ethnicity",
    "religious_belief",
    "sexuality",
    "ssn",
    "state",
    "street_address",
    "swift_bic",
    "tax_id",
    "time",
    "unique_id",
    "url",
    "user_name",
    "vehicle_identifier"
  ]

  test "covers every OpenMed privacy-filter Nemotron span label" do
    uncovered = @nemotron_span_labels -- LabelMap.known_labels()

    assert uncovered == []
  end

  test "maps Nemotron labels that fit Obscura's current taxonomy" do
    assert {:ok, :person} = LabelMap.map_label("first_name")
    assert {:ok, :person} = LabelMap.map_label("last_name")
    assert {:ok, :organization} = LabelMap.map_label("company_name")
    assert {:ok, :location} = LabelMap.map_label("city")
    assert {:ok, :street_address} = LabelMap.map_label("street_address")
    assert {:ok, :zip_code} = LabelMap.map_label("postcode")
    assert {:ok, :phone} = LabelMap.map_label("phone_number")
    assert {:ok, :credit_card} = LabelMap.map_label("credit_debit_card")
    assert {:ok, :us_ssn} = LabelMap.map_label("ssn")
    assert {:ok, :ip_address} = LabelMap.map_label("ipv4")
    assert {:ok, :patient_id} = LabelMap.map_label("medical_record_number")
    assert {:ok, :secret} = LabelMap.map_label("api_key")
  end

  test "intentionally ignores sensitive attribute labels outside current scoring taxonomy" do
    for label <- Map.keys(LabelMap.ignored()) do
      assert :ignore = LabelMap.map_label(label)
    end

    assert Map.fetch!(LabelMap.ignored(), "gender") =~ "sensitive attribute"
  end

  test "builds a label map restricted to supported entities" do
    label_map = LabelMap.for_entities([:person, :organization])

    assert label_map["first_name"] == :person
    assert label_map["last_name"] == :person
    assert label_map["company_name"] == :organization
    refute Map.has_key?(label_map, "city")
    refute Map.has_key?(label_map, "phone_number")
  end

  test "provides a Presidio-Research benchmark taxonomy for date-like labels" do
    label_map = LabelMap.presidio_research()

    assert {:ok, :date} = LabelMap.map_label("date")
    assert {:ok, :date_time} = LabelMap.map_label("date", label_map: label_map)
    assert {:ok, :date_time} = LabelMap.map_label("private_date", label_map: label_map)
    assert {:ok, :date_time} = LabelMap.map_label("personal_date", label_map: label_map)
    assert {:ok, :date_time} = LabelMap.map_label("other_date", label_map: label_map)
  end
end
