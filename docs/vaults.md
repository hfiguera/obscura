# Vaults

Vaults are explicit, session-scoped processes that map original values to pseudonym tokens and tokens back to original values.

```elixir
{:ok, vault} = Obscura.Vault.Memory.start_link()

{:ok, token} = Obscura.Vault.get_or_create(vault, :email, "jane@example.com")
token
#=> "<<EMAIL_001>>"

{:ok, entry} = Obscura.Vault.lookup_token(vault, token)
entry.entity
#=> :email

:ok = Obscura.Vault.clear(vault)
```

## Backends

Obscura includes:

- `Obscura.Vault.Memory`: a GenServer-backed in-memory vault.
- `Obscura.Vault.ETS`: a GenServer-owned ETS vault.

Neither backend persists across process termination. Both intentionally retain raw values in memory because rehydration requires reverse lookup.

## Session Isolation

Obscura does not create a global vault. Callers must start or supervise a vault and pass it explicitly to pseudonymization or rehydration functions.

```elixir
children = [
  {Obscura.Vault.ETS, name: MyApp.PiiVault}
]
```

Independent vaults do not share mappings. Clearing one vault does not clear another.

## Safety

Vault access is sensitive because it can restore PII. Applications should:

- keep vault refs scoped to the request, chat, or support session
- avoid logging vault state
- clear vaults when rehydration is no longer needed
- stop session vault processes promptly after their final lookup
- keep VM administration, tracing, crash dumps, and process inspection restricted

The ETS backend uses unnamed `:private` tables owned by its GenServer. Other
ordinary processes cannot read those tables directly; access goes through the
vault process. This is process isolation, not encryption. A process with VM
administration capabilities can still inspect process state or memory.

The legacy `table:` startup option remains accepted as an atom for `0.1.x`
configuration compatibility, but it no longer creates or names an ETS table.
Code which accessed those tables directly must migrate to the
`Obscura.Vault` API. This intentional behavior change closes an unauthorized
read path and is treated as an urgent security fix.

`clear/1` deletes live mappings and stopping the vault removes its accessible
state, but neither operation guarantees cryptographic memory erasure. The BEAM
garbage collector may retain copied binaries until reclamation, and Obscura
cannot zero every copy made by callers, callbacks, schedulers, or backends.

`Inspect` for vault entries hides both the token and raw value. Explicit fields
such as `entry.value`, `entry.token`, and GenServer system state remain
sensitive by design. Memory and ETS vaults are suitable only for trusted,
session-scoped in-VM storage. They are not encrypted persistent stores or
boundaries against a compromised VM.
