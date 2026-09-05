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

### What's new in v0.1.7

- Check for Switcher updates hourly. A blue menu-bar dot and an update row above the footer announce a new version. Start installation from the notice or Settings; Sparkle downloads, validates, installs, and restarts Switcher. Account operations defer the final relaunch.
- Wait for Codex Desktop to exit normally before switching credentials. A canceled or timed-out exit leaves credentials unchanged.
- Keep local Codex history shared across all accounts. Switcher changes the active credential and does not rewrite history or patch Codex.
- Activate the first saved account from a signed-out state; a failed verification or account-list write returns to that signed-out state.
- Reject duplicate account identities, clean up incomplete login profiles, and register the current external login through Settings without overwriting another saved identity.
- Preserve credentials when account-list deletion cannot be saved. Check the original login identity before saving its credential.
- Correct Codex quota selection when multiple products report limits, handle extreme numbers safely, preserve final RPC responses, and expose subprocess diagnostics.

Version 0.1.6 has no built-in updater. Install this release manually once; subsequent releases can be installed from Switcher. Updating Switcher does not update or restart Codex Desktop. Codex's own history-reader issues are outside this release.

### Install

1. Download and open the `Codex-Account-Switcher-macos-arm64.dmg` asset.
2. Drag `Codex Account Switcher.app` to Applications.
3. Open the app normally from Applications.

The release includes a SHA-256 checksum file for verifying the downloaded DMG.

Codex Account Switcher is independent open-source software and is not affiliated with or endorsed by OpenAI.
