# Rehydration

`Obscura.rehydrate/2` restores vault tokens to original values through explicit vault access.

```elixir
{:ok, text} = Obscura.rehydrate("Email <<EMAIL_001>>", vault: vault)
```

Missing vaults return an explicit error:

```elixir
Obscura.rehydrate("Email <<EMAIL_001>>")
#=> {:error, :missing_vault}
```

Unknown token-like text is kept by default:

```elixir
Obscura.rehydrate("Email <<EMAIL_999>>", vault: vault)
#=> {:ok, "Email <<EMAIL_999>>"}
```

Use `unknown: :error` to fail on unknown tokens.

Structured data is supported for maps, lists, keyword lists, and traversed structs:

```elixir
Obscura.rehydrate(%{message: "Email <<EMAIL_001>>"}, vault: vault)
```

Keys are not rehydrated by default. Only binary values are rehydrated.
