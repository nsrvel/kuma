# Golden `kuma.sqlite` (DT-DAT-05)

## File

- `golden_1x_v8.sqlite` — fully migrated schema (`v1_production_schema` … `v8_provider_auto_reconnect`), synthetic user rows (no secrets).

## Expected counts (after `StoreHandle::open`)

| Table | Rows |
|-------|------|
| `workspace` | 1 |
| `service` | 1 |

## Regenerate

From `daemon/`:

```bash
cargo test -p kuma-store write_golden_fixture -- --ignored --exact
```

Commit the updated binary only after verifying `cargo test -p kuma-store dt_dat_05` passes.

## Sanity check

```bash
sqlite3 crates/kuma-store/tests/fixtures/golden_1x_v8.sqlite \
  "SELECT identifier FROM grdb_migrations ORDER BY rowid;"
```
