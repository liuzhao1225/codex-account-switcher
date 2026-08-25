## Codex Account Switcher for macOS

Codex Account Switcher is an open-source native macOS menu bar app for switching between multiple personal, work, and client Codex accounts. It compares each saved profile's weekly usage and reset time, switches Codex Desktop, and updates authentication for newly started Codex CLI sessions.

This arm64 GitHub build requires macOS 14 or later. It is ad-hoc signed and is not notarized by Apple.

### Core workflow

- Save multiple authorized Codex authentication profiles locally.
- Check weekly usage and reset times from the macOS menu bar.
- Confirm a profile switch and reopen Codex Desktop with the selected account.
- Keep shared local Codex configuration and sessions in place.

### What's new

- Add a **Launch at Login** setting backed by macOS Service Management.
- Show direct guidance when the Login Item requires approval or is unavailable.
- Add localized accessibility labels for Settings toggles.

### Install

1. Download and unzip the `Codex-Account-Switcher-*-macos-arm64.zip` asset.
2. Drag `Codex Account Switcher.app` to Applications.
3. Control-click the app and choose **Open**. If macOS still blocks it, open **System Settings → Privacy & Security** and choose **Open Anyway**.

The release includes a SHA-256 checksum file for verifying the downloaded ZIP.

Codex Account Switcher is independent open-source software and is not affiliated with or endorsed by OpenAI.
