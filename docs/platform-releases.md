# Platform Releases

## Unified Version Sources

Push a `v<major>.<minor>.<patch>` tag pointing to a commit on the fork's `main` to publish macOS and Windows together. Before building, `scripts/validate-release-tag.mjs` checks that all three build version definitions match the tag:

1. `Sources/SwitcherCore/Models.swift` (`SwitcherVersion.current`)
2. `scripts/package-local-app.sh` (`APP_VERSION=${RELEASE_VERSION:-...}`)
3. `windows/Directory.Build.props` (`<Version>...</Version>`)

## Release Pipeline (`.github/workflows/release.yml`)

1. **`validate`** checks the tag format, version definitions, and commit ancestry on `main`, then runs the release script tests.
2. **`macos`** runs the Swift tests and packages the app and Apple Silicon DMG with ad hoc signatures. It verifies the app inside, writes the checksum, and signs both the DMG for Sparkle and its `appcast.xml`.
3. **`windows`** calls the Windows workflow to test and package the self-contained x64 EXE and its SHA-256 checksum.
4. **`publish`** signs `windows-update.json`, verifies both installers and update signatures, then publishes both packages, checksums, and signed update files in a single fork release.

## In-app updates

The apps read `appcast.xml` and `windows-update.json` from this fork's `releases/latest/download` URLs. Each update file points to the installer for its specific version. The macOS DMG continues to use ad hoc signing. macOS may ask users to confirm the first launch in Privacy & Security.

The workflow uses the `SPARKLE_PRIVATE_KEY` and `WINDOWS_UPDATE_PRIVATE_KEY` repository secrets. Keep secure backups of both keys. The public keys are built into the apps, so keep the same key pairs for future releases.

Install a fork release newer than `v0.2.2` manually once to switch the update source. After that, use the in-app update check.
