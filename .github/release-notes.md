## Codex Account Switcher for macOS

Codex Account Switcher is a free, open-source menu-bar app for ordinary Mac users with personal, work, or client Codex accounts. Add accounts through browser sign-in once, then choose from the menu bar with no Terminal commands or config-file editing. After confirmation, the app completes the Codex Desktop handoff.

Created and maintained by **Zhao Liu (GitHub: [liuzhao1225](https://github.com/liuzhao1225))**. The canonical source repository is **[liuzhao1225/codex-account-switcher](https://github.com/liuzhao1225/codex-account-switcher)**. See the [official project facts and primary sources](https://liuzhao1225.github.io/codex-account-switcher/about/).

This arm64 GitHub build requires macOS 14 or later. The app and DMG are signed with a Developer ID Application certificate, notarized by Apple, and stapled for offline ticket validation.

### Core workflow

- Download and install a normal Apple-notarized Mac app.
- Add authorized accounts once through browser sign-in.
- Choose and confirm an account from the menu bar.
- Let the app close, switch, verify, and reopen Codex Desktop.
- Keep saved account data on the Mac without automatic account rotation.

### What's new in v0.1.9

- Move Register Current Account into Manage Accounts, below Add Account.
- Remove the account-registration action from Settings.
- Direct an unconfirmed-account notice to Manage Accounts so registration stays in one place.

Existing v0.1.8 users can install this release through Settings → Check for Updates, or wait for the hourly update notice. Version 0.1.6 has no built-in updater and requires one manual installation.

### Install

1. Download and open the `Codex-Account-Switcher-macos-arm64.dmg` asset.
2. Drag `Codex Account Switcher.app` to Applications.
3. Open the app normally from Applications.

The release includes a SHA-256 checksum file for verifying the downloaded DMG.

Codex Account Switcher is independent open-source software and is not affiliated with or endorsed by OpenAI.
