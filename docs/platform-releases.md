# Platform Releases

## Unified Version Sources

macOS and Windows publish together from a single `v<major>.<minor>.<patch>` tag on `main`. Before building, `scripts/validate-release-tag.mjs` checks that all three build version definitions match the tag:

1. `Sources/SwitcherCore/Models.swift` (`SwitcherVersion.current`)
2. `scripts/package-local-app.sh` (`APP_VERSION=${RELEASE_VERSION:-...}`)
3. `windows/Directory.Build.props` (`<Version>...</Version>`)

## Release Pipeline (`.github/workflows/release.yml`)

1. **`validate`** — Verifies tag format, commit ancestry on `main`, absence of an existing release for that tag, and script tests.
2. **`macos`** — Runs `./scripts/run-tests.sh`, packages `Codex Account Switcher.app`, signs with Developer ID, notarizes and staples both the app and `Codex-Account-Switcher-macos-arm64.dmg`, generates `.sha256`, and signs `appcast.xml` for Sparkle.
3. **`windows`** — Runs Windows process-tree checks, shared-core Swift tests, host integration checks, WPF UI checks, builds self-contained `Codex-Account-Switcher-windows-x64.exe` with embedded `SwiftRuntime.zip`, and verifies `--self-test`.
4. **`publish`** — Verifies all artifacts and checksums via `scripts/verify-release-artifacts.mjs` and publishes one GitHub Release, triggering `.github/workflows/pages.yml` to update the hosted Sparkle `appcast.xml`.
