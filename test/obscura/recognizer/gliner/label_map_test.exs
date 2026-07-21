defmodule Obscura.Recognizer.GLiNER.LabelMapTest do
  use ExUnit.Case, async: true

  alias Obscura.Recognizer.GLiNER.LabelMap

  test "hybrid_core preserves Python reference label order" do
    assert {:ok,
            [
              "person",
              "organization",
              "location",
              "email address",
              "phone number",
              "credit card number",
              "iban code",
              "social security number",
              "ip address",
              "domain name",
              "url"
            ]} = LabelMap.labels(:hybrid_core)
  end

  test "maps GLiNER labels to Obscura entities" do
    assert LabelMap.to_entity(:hybrid_core, "Person") == :person
    assert LabelMap.to_entity(:hybrid_core, "phone number") == :phone
    assert LabelMap.to_entity(:hybrid_core, "unknown") == nil
  end

  test "open_class profile restricts GLiNER to model-backed open-class entities" do
    assert {:ok, ["person", "organization", "location"]} = LabelMap.labels(:open_class)

    assert LabelMap.supported_entities(:open_class) == [
             :location,
             :organization,
             :person
           ]

    assert LabelMap.to_entity(:open_class, "person") == :person
    assert LabelMap.to_entity(:open_class, "phone number") == nil
    assert LabelMap.to_entity(:open_class, "credit card number") == nil
    assert LabelMap.to_entity(:open_class, "domain name") == nil
  end

  test "edge_open_class uses Edge PII label wording for open-class entities" do
    assert {:ok,
            [
              "name",
              "organization",
              "location",
              "location address",
              "location city",
              "location state",
              "location country"
            ]} = LabelMap.labels(:edge_open_class)

    assert LabelMap.supported_entities(:edge_open_class) == [
             :location,
             :organization,
             :person
           ]

    assert LabelMap.to_entity(:edge_open_class, "name") == :person
    assert LabelMap.to_entity(:edge_open_class, "location city") == :location
    assert LabelMap.to_entity(:edge_open_class, "location country") == :location
    assert LabelMap.to_entity(:edge_open_class, "phone number") == nil
  end

  test "nvidia_nemotron_core uses the checkpoint's exact source labels" do
    assert {:ok,
            [
              "first_name",
              "last_name",
              "city",
              "country",
              "county",
              "state",
              "coordinate",
              "credit_debit_card",
              "cvv",
              "email",
              "ipv4",
              "ipv6",
              "phone_number",
              "fax_number",
              "url",
              "ssn"
            ]} = LabelMap.labels(:nvidia_nemotron_core)

    assert LabelMap.supported_entities(:nvidia_nemotron_core) == [
             :credit_card,
             :email,
             :ip_address,
             :location,
             :person,
             :phone,
             :url,
             :us_ssn
           ]

    assert LabelMap.to_entity(:nvidia_nemotron_core, "first_name") == :person
    assert LabelMap.to_entity(:nvidia_nemotron_core, "county") == :location
    assert LabelMap.to_entity(:nvidia_nemotron_core, "cvv") == :credit_card
  end
end
