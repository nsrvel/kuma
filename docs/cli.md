# Kuma CLI

Standalone Go CLI client for Kuma, in `apps/cli`. It talks to the same daemon
as the Mac app, with a lipgloss table view and an IPC socket, and aims for
1:1 parity with the Mac app across all 11 modules.

## Build and install

```bash
make cli          # build to apps/cli/bin/kuma
make cli-test     # run the CLI unit tests
make cli-install  # build and install to ~/.local/bin/kuma
```

## Modules

- `service` — get, create, update, delete and list services (by 8-char short ID or name)
- `workspace` — list and switch workspaces (`use`), with an active indicator
- `daemon` — `ping`, `status`, `shutdown`
- `data` — export / import (including import-preview) and factory-reset
- `group`, `k8s`, `provider`, `settings`, `env`, `logs` — the remaining modules,
  mirroring the Mac app

Run `kuma --help` for the full command list.
