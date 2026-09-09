# Unified versions and releases

macOS and Windows share one product version, one immutable `v<major>.<minor>.<patch>` tag, and one GitHub Release. Every new release contains both platform packages built from the same tagged commit. The release title equals the tag, so the version is visible directly in the release list.

## Test and publish

1. Push changes and run platform CI on GitHub: shared Swift tests on both systems, macOS CoreChecks, Windows transport/WPF checks and self-contained EXE checks. Interface or account-switch changes also need appropriate real-system validation.
2. Set the same version in `CITATION.cff`, `scripts/package-local-app.sh`, `Sources/SwitcherCore/CodexClient.swift`, and `windows/Directory.Build.props`. Keep the host/client fallback versions in sync. Write only this release's changes in `.github/release-notes.md`.
3. After CI succeeds, create and push an annotated `v*` tag from the intended main commit. Ordinary main pushes run CI without publishing.
4. `.github/workflows/release.yml` validates all version sources and the tagged commit, then runs macOS and Windows builds in parallel. Windows uses the reusable `.github/workflows/windows.yml`; it never publishes independently.
5. macOS tests, signs, notarizes, staples and checks the DMG. Windows tests, packages and runs the EXE without SDK/runtime paths. The publish job waits for both jobs, verifies both SHA-256 files and the macOS feed, uploads everything to a draft, then publishes it as Latest.
6. Verify the public assets and the Pages update feed before announcing completion. A failed build prevents publication. Fix source errors with a new commit/tag; infrastructure failures can rerun the same immutable tag. An existing release is never silently replaced. Inspect and remove an incomplete draft before retrying its publishing step.

```sh
git tag -a v0.1.12 -m 'v0.1.12' origin/main
git push origin v0.1.12
```

## Assets and updates

Each release includes:

- `Codex-Account-Switcher-macos-arm64.dmg` and `.sha256`
- `Codex-Account-Switcher-windows-x64.exe` and `.sha256`
- The signed macOS `appcast.xml`

Both website download buttons use `/releases/latest/download/<asset>`. macOS uses the dedicated Pages feed; legacy Mac installations using `/releases/latest/download/appcast.xml` continue to work because every unified release includes that file. Pages refreshes after a successful unified release and preserves the signed feed contents.

Windows 0.1.12 and later select stable `v*` releases containing a Windows EXE. The initial Windows 0.1.11 preview only recognized `windows-v*`; it needs one manual upgrade to enter the unified channel. Windows opens the update download page and does not replace its running EXE automatically. The EXE remains unsigned.

The previous separate macOS/Windows release entries may be removed after verifying the unified replacement. Preserve their Git tags and commits. Old version-specific asset links stop working when their release entries are removed; current documentation and download buttons must point to the unified release.
