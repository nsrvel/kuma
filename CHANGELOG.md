# Changelog

All notable releases are documented here and on [GitHub Releases](https://github.com/nsrvel/kuma/releases).

## 1.0.0 — 2026-09-30

First public release.

- Workspaces, service deck (cards/table), groups, favorites, inspector-driven configuration
- Providers: Kubernetes (pattern matching + live pod display), Docker/Podman, shell, SSH, HTTP health checks, tunnels, process monitor
- Per-provider **auto reconnect** (Kubernetes, SSH, Shell) with bounded retries
- Unified DataPort backup/import/export; demo workspace JSON in `docs/samples/`
- CI on macOS 15 / Xcode 16; DMG builds via GitHub Actions on version tags

History on `main` was squashed for readability; full pre-squash git graph is preserved in the maintainer’s private archive (not public).
