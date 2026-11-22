# Platform Releases

## Unified Version Sources

Push a `v<major>.<minor>.<patch>` tag pointing to a commit on the fork's `main` to publish macOS and Windows together. Before building, `scripts/validate-release-tag.mjs` checks that all three build version definitions match the tag:

1. `Sources/SwitcherCore/Models.swift` (`SwitcherVersion.current`)
2. `scripts/package-local-app.sh` (`APP_VERSION=${RELEASE_VERSION:-...}`)
3. `windows/Directory.Build.props` (`<Version>...</Version>`)

## Release Pipeline (`.github/workflows/release.yml`)

1. **`validate`** checks the tag format, version definitions, and commit ancestry on `main`, then runs the release script tests.
2. **`macos`** runs the Swift tests and packages the app and Apple Silicon DMG with ad hoc signatures. It mounts the image, verifies the app inside, and writes a SHA-256 checksum.
3. **`windows`** calls the Windows workflow to test and package the self-contained x64 EXE and its SHA-256 checksum.
4. **`publish`** verifies both checksums and attaches both packages and their checksums to a single GitHub Release in this fork.

The fork's macOS build uses ad hoc signing without Apple notarization. macOS may ask users to confirm the first launch in Privacy & Security. The apps still check the upstream update feeds.
