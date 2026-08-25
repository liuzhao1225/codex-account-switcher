## Codex Account Switcher for macOS

Codex Account Switcher is an open-source native macOS menu bar app for switching between multiple personal, work, and client Codex accounts. It compares each saved profile's weekly usage and reset time, switches Codex Desktop, and updates authentication for newly started Codex CLI sessions.

This arm64 GitHub build requires macOS 14 or later. The app and DMG are signed with a Developer ID Application certificate, notarized by Apple, and stapled for offline ticket validation.

### Core workflow

- Save multiple authorized Codex authentication profiles locally.
- Check weekly usage and reset times from the macOS menu bar.
- Confirm a profile switch and reopen Codex Desktop with the selected account.
- Keep shared local Codex configuration and sessions in place.

### What's new

- Add the native application icon to the packaged app and Finder.
- Notarize and staple the signed app before placing it in the DMG.
- Notarize and staple the signed DMG, then verify both artifacts with Gatekeeper.

### Install

1. Download and open the `Codex-Account-Switcher-*-macos-arm64.dmg` asset.
2. Drag `Codex Account Switcher.app` to Applications.
3. Open the app normally from Applications.

The release includes a SHA-256 checksum file for verifying the downloaded DMG.

Codex Account Switcher is independent open-source software and is not affiliated with or endorsed by OpenAI.
