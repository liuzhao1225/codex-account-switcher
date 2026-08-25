# Codex Account Switcher Lite

<p align="center">
  <img src="assets/codex-account-switcher-lite-hero.png" alt="Codex Account Switcher Lite showing three demo accounts, weekly usage, and fast switching from the macOS menu bar" width="100%">
</p>

<p align="center">
  <strong>Switch accounts. Keep your flow.</strong><br>
  A lightweight native macOS menu-bar switcher for Codex Desktop and newly started Codex CLI sessions.
</p>

<p align="center">
  <a href="https://github.com/liuzhao1225/codex-account-switcher-lite/releases">Download</a>
  ·
  <a href="docs/README.md">Documentation</a>
  ·
  <a href="https://github.com/liuzhao1225/codex-account-switcher-lite/issues">Issues</a>
</p>

## Your Codex accounts, one menu away

Codex Account Switcher Lite is built for people who use more than one ChatGPT account with Codex. It turns account switching, weekly allowance checks, and local profile management into a compact menu-bar workflow.

Open the menu, see every saved account, check the remaining weekly allowance, and choose where you want to work next. The app handles the credential handoff and restarts Codex Desktop so the next session opens on the selected account.

No proxy. No account routing service. Saved account snapshots stay on your Mac.

## Highlights

| | Feature | What it gives you |
| --- | --- | --- |
| 📊 | **Weekly usage at a glance** | See the remaining weekly allowance and reset time for every saved account. |
| ⚡️ | **Fast account switching** | Select an account, confirm the change, and let the app complete the Desktop handoff. |
| 🗂️ | **Local account library** | Add, retain, and remove independent local account snapshots. |
| 💻 | **Codex Desktop + CLI** | Switch Codex Desktop and the authentication used by newly started CLI processes. |
| 🚀 | **Launch at login** | Keep the switcher ready from the moment you sign in to macOS. |
| 🌐 | **Native and localized** | Use a compact SwiftUI interface in English, Simplified Chinese, or the system language. |

## A focused three-step workflow

1. **Save your accounts** — import the current Codex login or add another account from the account manager.
2. **Check before you switch** — compare weekly usage and reset times directly from the menu bar.
3. **Continue on the selected account** — confirm the switch; the app closes Codex Desktop, replaces the active credentials, and opens Desktop again.

Newly started Codex CLI processes use the same selected authentication. Existing terminal processes keep their current runtime state.

## Download

The current GitHub build targets **Apple Silicon** and requires **macOS 14 or later**.

1. Open [GitHub Releases](https://github.com/liuzhao1225/codex-account-switcher-lite/releases).
2. Download the latest `macos-arm64.zip` asset.
3. Unzip it and move **Codex Account Switcher Lite.app** to Applications.
4. Launch the app and look for the switcher in the macOS menu bar.

> [!IMPORTANT]
> The current public build is ad-hoc signed and has not yet been notarized by Apple. On first launch, Control-click the app and choose **Open**. If macOS still blocks it, use **System Settings → Privacy & Security → Open Anyway**.

## Built to stay out of the way

- The popover opens directly on the account list.
- The current account uses a quiet row highlight.
- Persisted weekly usage remains visible while fresh data loads.
- Background refresh runs on a reschedulable five-minute timer.
- Manage Accounts and Settings stay inside the same compact popover.
- Errors stop the switch immediately and remain visible.

The app deliberately concentrates on one weekly allowance, local profiles, and a predictable Desktop restart handoff. It does not introduce a proxy, router, credential recovery layer, or background account policy.

## Build from source

The repository contains a native SwiftUI application for macOS 14+.

```bash
swift build
./scripts/run-core-checks.sh
```

Create a local app bundle:

```bash
./scripts/package-local-app.sh
```

The bundle is written to `.build/release/Codex Account Switcher Lite.app`.

## Release automation

Pushing a `v*` tag runs the GitHub release workflow. The current workflow builds and verifies an arm64 app, packages a versioned ZIP, publishes its SHA-256 checksum, and creates a GitHub prerelease.

Developer ID signing, Apple notarization, and DMG distribution are the next release-hardening steps.

## Product principles

- Show one weekly `Usage` value and its reset time per account.
- Keep account snapshots in independent local `CODEX_HOME` profile directories.
- Ask for confirmation before changing the active account.
- Stop on the first switching error.
- Keep automatic rollback, retries, credential backups, and recovery journals outside the product scope.

## Documentation

- [Documentation index](docs/README.md)
- [Product decisions](docs/product-decisions.md)
- [Product requirements](docs/product-requirements.md)
- [System design](docs/system-design.md)
- [Implementation plan](docs/implementation-plan.md)
- [Testing](docs/testing.md)
