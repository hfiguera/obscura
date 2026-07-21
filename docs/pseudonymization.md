# Pseudonymization

Pseudonymization replaces detected values with deterministic vault tokens. It
is reversible only when the caller has access to the vault. It is tokenization,
not encryption: the vault retains the original values in memory or ETS until
the caller clears or stops it.

```elixir
{:ok, vault} = Obscura.Vault.Memory.start_link()

{:ok, result} =
  Obscura.redact("Email jane@example.com",
    entities: [:email],
    operators: %{email: %{type: :pseudonymize}},
    vault: vault
  )

result.text
#=> "Email <<EMAIL_001>>"
```

The same entity/value pair reuses the same token within one vault session:

```elixir
Obscura.Vault.get_or_create(vault, :email, "jane@example.com")
#=> {:ok, "<<EMAIL_001>>"}
```

## Token Format

Default tokens are ASCII and entity-scoped:

```text
<<EMAIL_001>>
<<PHONE_001>>
<<CREDIT_CARD_001>>
```

Token formatting supports options such as `:token_prefix`, `:token_suffix`, `:token_separator`, `:token_width`, and `:token_case`.

The vault and token options are validated before any replacement starts.
Missing or unavailable vaults and malformed token options return
`{:error, %Obscura.Anonymizer.Error{}}` without including the source value.

## Structured Data

Structured redaction can use pseudonymization because structured leaf strings flow through the anonymizer:

```elixir
Obscura.redact(%{message: "Email jane@example.com"},
  entities: [:email],
  operators: %{email: %{type: :pseudonymize}},
  vault: vault
)
```
