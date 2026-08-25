## Codex Account Switcher for macOS

Codex Account Switcher is an open-source native macOS menu bar app for switching between multiple personal, work, and client Codex accounts. It compares each saved profile's weekly usage and reset time, switches Codex Desktop, and updates authentication for newly started Codex CLI sessions.

This arm64 GitHub build requires macOS 14 or later. It is signed with a Developer ID Application certificate and is not yet notarized by Apple.

### Core workflow

- Save multiple authorized Codex authentication profiles locally.
- Check weekly usage and reset times from the macOS menu bar.
- Confirm a profile switch and reopen Codex Desktop with the selected account.
- Keep shared local Codex configuration and sessions in place.

### What's new

- Package the app as a Developer ID signed DMG.
- Replace the previous ZIP asset with a DMG and its SHA-256 checksum.
- Keep Apple notarization explicitly pending.

### Install

1. Download and open the `Codex-Account-Switcher-*-macos-arm64.dmg` asset.
2. Drag `Codex Account Switcher.app` to Applications.
3. Control-click the app and choose **Open**. If macOS still blocks it, open **System Settings → Privacy & Security** and choose **Open Anyway**.

The release includes a SHA-256 checksum file for verifying the downloaded DMG.

Codex Account Switcher is independent open-source software and is not affiliated with or endorsed by OpenAI.
