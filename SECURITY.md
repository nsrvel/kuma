# Security

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security-sensitive reports.

Use [GitHub Private Vulnerability Reporting](https://github.com/nsrvel/kuma/security/advisories/new) for this repository, or contact the maintainer through GitHub with details to coordinate a private advisory.

## Scope

Kuma is a **local** macOS application. It stores workspace and service configuration in SQLite on your machine. SSH passwords, ngrok tokens, and similar fields are encrypted at rest via the app vault (`CryptoVault`).

Reports are welcome for issues such as:

- Credential leakage in exports, logs, or crash reports
- Sandbox or process isolation weaknesses in runners (`kubectl`, `ssh`, shell, Docker/Podman)
- Import/export (DataPort) parsing or path handling that could lead to unintended file access

Out of scope: social engineering, physical access to an unlocked Mac, or vulnerabilities in third-party CLIs (`kubectl`, Docker, etc.) themselves.

## Supported versions

Security fixes are intended for the **latest release** on [GitHub Releases](https://github.com/nsrvel/kuma/releases). Build from `main` at your own risk between releases.
