defmodule Obscura.StructuredTest do
  use ExUnit.Case, async: true

  defmodule User do
    @derive {Obscura.Redactable,
             fields: [
               email: {:entity, :email},
               password_hash: :drop,
               profile: :traverse
             ]}
    defstruct [:email, :password_hash, :profile]
  end

  test "redacts nested maps, lists, keyword lists, and field policies" do
    input = %{
      user: %{email: "jane@example.com", password: "secret"},
      phones: ["202-555-0188"],
      metadata: [contact: "admin@example.com"]
    }

    assert {:ok, result} =
             Obscura.Structured.redact(input,
               entities: [:email, :phone],
               field_policies: %{password: :drop}
             )

    assert result.data.user == %{email: "[EMAIL]"}
    assert result.data.phones == ["[PHONE]"]
    assert result.data.metadata == [contact: "[EMAIL]"]
    assert Enum.any?(result.items, &(&1.path == [:user, :email]))
    assert Enum.any?(result.items, &(&1.path == [:phones, 0]))
    assert Enum.any?(result.items, &(&1.path == [:metadata, :contact]))
  end

  test "redacts derived structs and preserves opaque structs" do
    user = %User{
      email: "jane@example.com",
      password_hash: "hash",
      profile: %{phone: "202-555-0188"}
    }

    assert {:ok, result} = Obscura.redact(user, entities: [:email, :phone])

    assert %User{} = result.data
    assert result.data.email == "[EMAIL]"
    assert result.data.password_hash == nil
    assert result.data.profile.phone == "[PHONE]"

    today = ~D[2026-06-06]
    assert {:ok, date_result} = Obscura.Structured.redact(today, traverse_structs: true)
    assert date_result.data == today
  end
end
