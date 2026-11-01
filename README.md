# Kuma

[![CI](https://github.com/nsrvel/kuma/actions/workflows/ci.yml/badge.svg)](https://github.com/nsrvel/kuma/actions/workflows/ci.yml)

Native macOS app for managing local development services — Kubernetes port-forwards, Docker/Podman, shell, SSH tunnels, health checks, and more — organized by workspace.

![Kuma service deck with inspector](docs/images/kuma-deck-screenshot.png)

**Distribution:** [GitHub Releases](https://github.com/nsrvel/kuma/releases) (not the Mac App Store). DMGs are **not** committed to git (`dist/` is ignored); download binaries from the Releases page.

**Demo workspace for screenshots:** import [`docs/samples/Kuma-Screenshot-Demo.json`](docs/samples/Kuma-Screenshot-Demo.json) via drag-and-drop or deck import (all provider types, fake hosts).

## Requirements

- **macOS 14** (Sonoma) or later
- For building from source: **Xcode 16+** with Swift 6

Optional CLI tools (detected at runtime): `kubectl`, `docker`, `podman`, `ssh`, etc.

## Install (recommended)

1. Open [Releases](https://github.com/nsrvel/kuma/releases) and download the latest `Kuma-x.y.dmg`.
2. Open the DMG and drag **Kuma** to **Applications**.
3. First launch: official releases from tags with signing secrets configured should open without Gatekeeper warnings. Ad-hoc CI/local DMGs may still require **Open Anyway** in **System Settings → Privacy & Security**.

## Build from source

```bash
git clone https://github.com/nsrvel/kuma.git
cd Kuma
open Kuma.xcodeproj
# Run (⌘R) or:
xcodebuild -scheme Kuma -destination 'platform=macOS' build
```

### Run tests

```bash
xcodebuild -scheme Kuma -destination 'platform=macOS' test
```

### Build a DMG locally

```bash
make dmg
# or: ./Scripts/make-dmg.sh
# Output: dist/Kuma-<version>.dmg (ad-hoc signed unless MACOS_SIGN_IDENTITY is set)
```

### Publish a GitHub Release (maintainers)

CI runs on every push/PR to `main` (build + test on **macOS 15** with **Xcode 16**).

To ship a DMG to [Releases](https://github.com/nsrvel/kuma/releases), push a version tag:

```bash
git tag v1.0.0   # match CFBundleShortVersionString when possible
git push origin v1.0.0
```

The **Release** workflow (`.github/workflows/release.yml`) builds `dist/Kuma-*.dmg` and attaches it to the new GitHub Release with auto-generated notes.

#### Signed & notarized releases (maintainers)

**Not free:** distributing outside the App Store with no Gatekeeper warning requires the [Apple Developer Program](https://developer.apple.com/programs/) (**USD 99/year**). A free Apple ID only gives **Apple Development** signing (local/Xcode), not **Developer ID Application** + notarization.

1. In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/list), create **Developer ID Application** (or via Xcode → Settings → Accounts → Manage Certificates).
2. Export the cert + private key as a `.p12` for CI.
3. Create an [app-specific password](https://appleid.apple.com) for `notarytool`.
4. Add repository **Secrets** (Settings → Secrets and variables → Actions):

| Secret | Example / notes |
|--------|------------------|
| `BUILD_CERTIFICATE_BASE64` | `base64 -i Certificates.p12 \| pbcopy` |
| `P12_PASSWORD` | Password used when exporting the `.p12` |
| `MACOS_SIGN_IDENTITY` | `Developer ID Application: Your Name (UX2S427FB9)` — run `security find-identity -v -p codesigning` |
| `APPLE_TEAM_ID` | `UX2S427FB9` (10-character Team ID) |
| `APPLE_ID` | Apple ID email used for notarization |
| `APPLE_NOTARIZATION_PASSWORD` | App-specific password (not your login password) |

Without these secrets, release builds still ship as **ad-hoc** DMGs (same as before). With secrets, `make-dmg.sh` signs with hardened runtime and notarizes the DMG.

Local signed build (after installing the Developer ID cert in your login keychain):

```bash
export MACOS_SIGN_IDENTITY='Developer ID Application: …'
export APPLE_TEAM_ID=UX2S427FB9
# Optional notarization:
export APPLE_ID=you@example.com
export APPLE_NOTARIZATION_PASSWORD=xxxx-xxxx-xxxx-xxxx
./Scripts/make-dmg.sh
```

## Project layout

| Path | Purpose |
|------|---------|
| `Kuma/` | App source (Domain, Core, Stores, Presentation) |
| `KumaTests/` | Swift Testing suites |
| `docs/specs/` | Feature specs & invariants |
| `docs/testing/` | Test matrices |
| `docs/samples/` | Importable demo workspace JSON |
| `Scripts/` | DMG packaging & maintainer utilities |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). For larger changes, read the relevant file under `docs/specs/`.

## License

MIT — see [LICENSE](LICENSE).
