defmodule Obscura.Eval.EntityMappingTest do
  use ExUnit.Case, async: true

  alias Obscura.Eval.EntityMapping

  test "covers all Presidio-Research entity names from synth_dataset_v2" do
    expected =
      ~w(PERSON STREET_ADDRESS ADDRESS GPE ORGANIZATION CREDIT_CARD DATE_TIME TITLE PHONE_NUMBER AGE NRP EMAIL_ADDRESS ZIP_CODE DOMAIN_NAME IBAN_CODE US_SSN IP_ADDRESS US_DRIVER_LICENSE)

    for entity <- expected do
      assert entity in EntityMapping.source_entities()
    end
  end

  test "maps Phase 0 supported entities without dynamic atom creation" do
    assert EntityMapping.to_obscura("EMAIL_ADDRESS") == {:ok, :email}
    assert EntityMapping.to_obscura("PHONE_NUMBER") == {:ok, :phone}
    assert EntityMapping.to_obscura("CREDIT_CARD") == {:ok, :credit_card}
    assert EntityMapping.to_obscura("IBAN_CODE") == {:ok, :iban}
    assert EntityMapping.to_obscura("US_SSN") == {:ok, :us_ssn}
    assert EntityMapping.to_obscura("IP_ADDRESS") == {:ok, :ip_address}
    assert EntityMapping.to_obscura("DOMAIN_NAME") == {:ok, :domain}
    assert EntityMapping.to_obscura("URL") == {:ok, :url}
    assert EntityMapping.to_obscura("ADDRESS") == {:ok, :street_address}
    assert EntityMapping.to_obscura("UNKNOWN") == {:error, {:unsupported_entity, "UNKNOWN"}}
  end

  test "covers all Nemotron-PII source labels observed in the test split" do
    expected =
      ~w(account_number age api_key bank_routing_number biometric_identifier blood_type certificate_license_number city company_name coordinate country county credit_debit_card customer_id cvv date date_of_birth date_time device_identifier education_level email employee_id employment_status fax_number first_name gender health_plan_beneficiary_number http_cookie ipv4 ipv6 language last_name license_plate mac_address medical_record_number national_id occupation password phone_number pin political_view postcode race_ethnicity religious_belief sexuality ssn state street_address swift_bic tax_id time unique_id url user_name vehicle_identifier)

    for entity <- expected do
      assert entity in EntityMapping.source_entities()
    end

    assert EntityMapping.to_obscura("first_name") == {:ok, :person}
    assert EntityMapping.to_obscura("company_name") == {:ok, :organization}
    assert EntityMapping.to_obscura("street_address") == {:ok, :street_address}
    assert EntityMapping.to_obscura("medical_record_number") == {:ok, :patient_id}
    assert EntityMapping.to_obscura("credit_debit_card") == {:ok, :credit_card}
  end
end
