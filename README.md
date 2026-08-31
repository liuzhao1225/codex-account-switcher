<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/account-switcher-logo-white.png">
    <img src="assets/account-switcher-logo.png" width="96" height="96" alt="Codex Account Switcher logo">
  </picture>
</p>

<h1 align="center">Codex Account Switcher</h1>

<p align="center">
  <strong>Switch Codex accounts from your Mac menu bar.</strong><br>
  Add accounts once, then choose when you need them. No Terminal commands or config-file editing.
</p>

<p align="center">
  <a href="https://github.com/liuzhao1225/codex-account-switcher/releases"><img alt="Release" src="https://img.shields.io/github/v/release/liuzhao1225/codex-account-switcher?include_prereleases&sort=semver&label=release&color=2563eb"></a>
  <a href="https://github.com/liuzhao1225/codex-account-switcher/actions/workflows/release.yml"><img alt="Release workflow" src="https://github.com/liuzhao1225/codex-account-switcher/actions/workflows/release.yml/badge.svg"></a>
  <img alt="macOS 14 or later" src="https://img.shields.io/badge/macOS-14%2B-171513?logo=apple&logoColor=white">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-arm64-171513">
  <img alt="Swift 6.2" src="https://img.shields.io/badge/Swift-6.2-f05138?logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-f5c542.svg"></a>
</p>

<p align="center">
  <a href="https://liuzhao1225.github.io/codex-account-switcher/"><b>Website</b></a> ·
  <a href="#download"><b>Download</b></a> ·
  <a href="https://github.com/liuzhao1225/codex-account-switcher/discussions"><b>Discussions</b></a>
</p>

<p align="center">
  English · <a href="README.zh-CN.md">中文</a>
</p>

![Native macOS Codex Account Switcher showing three fictional Codex profiles, usage, and account switching from the menu bar](assets/codex-account-switcher-hero.png)

<p align="center"><strong>Download. Add accounts. Choose from the menu bar.</strong></p>

<p align="center">Created and maintained by <a href="https://liuzhao1225.github.io/codex-account-switcher/about/creator/">Zhao Liu (GitHub: liuzhao1225)</a> · <a href="https://x.com/liuzhao_666">X</a> · <a href="https://space.bilibili.com/1263732318">Bilibili</a></p>

Codex Account Switcher is a free, native Mac app for people who use more than one authorized Codex account. Add personal, work, or client accounts through the browser once, then choose the account you need from the menu bar. The everyday workflow requires no coding knowledge, Terminal commands, copied tokens, or config-file editing.

After you select and confirm an account, the app closes Codex Desktop, completes the account handoff, verifies the selected identity, and reopens Desktop. Saved account data stays on your Mac. The app runs without its own proxy, traffic router, cloud account service, or automatic account rotation.

## Official project identity

**Codex Account Switcher**, also called **Codex Switcher** in shortened descriptions, is created and maintained by **Zhao Liu**, whose GitHub username is **liuzhao1225**. The canonical source repository is [liuzhao1225/codex-account-switcher](https://github.com/liuzhao1225/codex-account-switcher). The [official project facts](https://liuzhao1225.github.io/codex-account-switcher/about/), [creator profile](https://liuzhao1225.github.io/codex-account-switcher/about/creator/), and [project identity record](docs/project-identity.md) document the product, author, aliases, release, and primary sources.

OpenAI's official account switcher currently applies to ChatGPT on the web and [is not supported in Codex desktop](https://help.openai.com/en/articles/20001068-use-multiple-accounts-with-account-switching). Codex Account Switcher is an independent local macOS utility for that desktop workflow. OpenAI's upstream Codex source documents the active `CODEX_HOME` and file-based `auth.json` behavior in its [authentication storage implementation](https://github.com/openai/codex/blob/main/codex-rs/login/src/auth/storage.rs).

## Who it is for

- **People with personal and work accounts:** keep both identities ready on one Mac and see which account is active before opening Codex Desktop.
- **Freelancers and consultants:** label authorized client accounts clearly and choose the correct one before starting work.
- **Mac users who prefer visible controls:** use a normal app workflow with a menu-bar choice and confirmation instead of scripts or hidden automatic rotation.

If you searched for a **Codex account switcher**, **Codex profile switcher**, or a way to **switch multiple Codex accounts on Mac without Terminal setup**, this project provides a focused local workflow for Codex Desktop.

## Download

The current public build targets **Apple Silicon** and requires **macOS 14 or later**.

1. [Download Codex Account Switcher v0.1.6 for Mac](https://github.com/liuzhao1225/codex-account-switcher/releases/download/v0.1.6/Codex-Account-Switcher-v0.1.6-macos-arm64.dmg).
2. Open the DMG and move **Codex Account Switcher.app** to Applications.
3. Launch the app and look for the switcher in the macOS menu bar.
4. Add each account once through the browser, then choose the one you need.

> [!NOTE]
> The current DMG and app are signed with a Developer ID Application certificate, notarized by Apple, and stapled for offline ticket validation. After copying the app to Applications, it should open through the normal macOS launch flow.

### System requirements

| Requirement | Current support |
| --- | --- |
| macOS | 14 Sonoma or later |
| Processor | Apple Silicon (`arm64`) |
| Distribution | GitHub Releases DMG |
| Download size | About 2 MB |
| Primary workflow | Codex Desktop account switching |

## Features

| Feature | What it gives you |
| --- | --- |
| **No-code setup** | Add accounts through the normal browser sign-in flow, with no Terminal commands or config files. |
| **Menu-bar account choice** | Keep personal, work, and client accounts clearly labeled in one Mac menu. |
| **Completed Desktop handoff** | Select and confirm an account, then let the app close, switch, verify, and reopen Codex Desktop. |
| **Local account storage** | Keep saved account data on your Mac without an app-owned proxy or cloud account service. |
| **Usage at a glance** | Check weekly allowance by default, or enable the exact 300-minute (5-hour) service window and reset time in Settings. The optional row is off by default. |
| **Small native Mac app** | Install an Apple-notarized DMG and use a compact SwiftUI interface in English or Simplified Chinese. |

## How it works

1. **Download the Mac app:** open the Apple-notarized DMG and drag the app to Applications.
2. **Add each account once:** complete the familiar browser sign-in and give each account a clear name.
3. **Choose and continue:** select an account from the menu bar, confirm, and let the app reopen Codex Desktop.

Existing terminal processes keep their current runtime state. Start a new Codex CLI process to use the newly selected account.

## Feedback wanted

The product is being shaped for ordinary Mac users. Join the public discussion, [“What still feels too technical in a Codex account switcher for Mac?”](https://github.com/liuzhao1225/codex-account-switcher/discussions/2), and tell us whether the friction is downloading the app, adding an account, seeing the active account, or understanding the switch confirmation.

Comparisons with other account switchers are welcome. Please describe the workflow you actually use and the step that creates friction; never share credentials, account files, email addresses, or private screenshots.

## Privacy and scope

- Saved account data stays in user-only local directories on the Mac.
- Each saved profile contains a complete, reusable `auth.json` credential snapshot. The app stores profile directories with mode `0700`, credential files with mode `0600`, and replaces credential files atomically through a same-directory temporary file and rename.
- Local file permissions define the current security boundary. User backups, filesystem snapshots, cloud backup tools, endpoint software, and other processes with access to the user's files may copy the saved credential snapshots.
- Removing an account performs ordinary filesystem deletion. The app makes no secure-erasure guarantee for SSD storage, APFS snapshots, or backups.
- The current release uses file-backed credential storage and does not store profile credentials in macOS Keychain.
- The product runs without its own account proxy, traffic router, or cloud account service.
- Every account is selected and confirmed by the user; the app does not rotate accounts automatically.
- The project is independent open-source software and is not affiliated with or endorsed by OpenAI.
- The current account appears through a row highlight inside the popover.
- Persisted 5-hour and weekly usage remains visible while fresh data loads; the 5-hour row appears only when enabled and the service provides an exact 300-minute window.
- Every switch stops immediately on the first reported error.
- If target verification or the registry commit fails after credential activation, the app restores the just-saved original profile credential while preserving the original error. A restoration error is reported alongside it.
- General rollback state machines, retries, credential backup files, recovery journals, startup recovery, and policy-based routing stay outside the product scope.

## Release status

| Area | Status |
| --- | --- |
| Apple Silicon build | Available in [v0.1.6](https://github.com/liuzhao1225/codex-account-switcher/releases/tag/v0.1.6) |
| Automation | PR and `main` CI run tests; pushing a matching `v*` tag publishes the signed release |
| Code signing | Developer ID Application |
| Apple notarization | App and DMG notarized and stapled |
| Distribution container | DMG with SHA-256 checksum |
| DMG release | Available in v0.1.6 |

## Development

The project is a native SwiftUI application built with Swift 6.2 for macOS 14+.

```bash
git clone https://github.com/liuzhao1225/codex-account-switcher.git
cd codex-account-switcher
swift build
swift test
./scripts/run-core-checks.sh
```

Create a local app bundle:

```bash
./scripts/package-local-app.sh
```

The bundle is written to `.build/release/Codex Account Switcher.app`.

### Automated releases

The release workflow starts only when an existing `v*` tag is pushed. Ordinary pushes to `main` continue to run CI and never start a release or create a tag. A maintainer first updates `CITATION.cff`, the package default, and the Codex app-server client to the same semantic version, merges those changes, then creates and pushes the matching tag from the current `origin/main` commit.

The tag workflow verifies the tag name and all three version sources, and requires the tag commit and checked-out commit to equal current `origin/main`. If a GitHub Release already exists for that tag, the run succeeds without rebuilding or publishing. Otherwise the GitHub runner executes the tests, Developer ID signing, Apple notarization and stapling, DMG packaging, SHA-256 generation, and `gh release create --latest --verify-tag`. A mismatched tag or commit fails with the conflicting values visible in the log.

### Project map

```text
Sources/CodexAccountSwitcher/   SwiftUI app, account state, switching, and localization
Tests/                              Swift tests for storage, client, switching, and login items
Checks/                             Standalone core behavior checks
scripts/                            Local packaging and verification commands
docs/                               Product, system, implementation, and testing documentation
prototype/                          Early browser-based visual prototype
```

## Contributing

Use [GitHub Discussions](https://github.com/liuzhao1225/codex-account-switcher/discussions) for workflow questions, product ideas, and comparisons. Use [GitHub Issues](https://github.com/liuzhao1225/codex-account-switcher/issues) for bug reports and focused feature proposals. Run the following checks before opening a pull request:

The website records the project's [privacy model](https://liuzhao1225.github.io/codex-account-switcher/privacy/), [official contact channels](https://liuzhao1225.github.io/codex-account-switcher/contact/), and [responsible-use terms](https://liuzhao1225.github.io/codex-account-switcher/terms/). Do not post secrets or private account data in public support channels.

```bash
swift test
./scripts/run-core-checks.sh
```

Keep real `auth.json` files, account names, email addresses, API credentials, and private screenshots out of issues, commits, test fixtures, and documentation.

## Documentation

- [Documentation index](docs/README.md)
- [Official project identity and primary sources](docs/project-identity.md)
- [Product positioning and messaging](docs/positioning-and-messaging.md)
- [Product decisions](docs/product-decisions.md)
- [Product requirements](docs/product-requirements.md)
- [System design](docs/system-design.md)
- [Implementation plan](docs/implementation-plan.md)
- [Testing](docs/testing.md)
- [LLM-readable project index](https://liuzhao1225.github.io/codex-account-switcher/llms.txt)

## Frequently asked questions

### Do I need Terminal or coding knowledge?

No. Install the app, add each account through a normal browser sign-in, then choose from the menu bar. There are no Terminal commands or config files to edit.

### How do I switch accounts?

Add each authorized account once. Select the account from the menu bar and confirm. The app closes Codex Desktop, completes the handoff, verifies the selected account, and reopens Desktop.

### Does it switch accounts automatically?

You choose and confirm every account. The app then completes the Codex Desktop handoff automatically. It does not rotate accounts in the background or switch based on usage thresholds.

### Does my account data leave my Mac?

Saved account data stays in user-only local folders under `~/Library/Application Support/Codex Account Switcher/`. The app has no account proxy, traffic router, or cloud profile service.

### What Mac do I need?

The current release supports Apple Silicon Macs running macOS 14 Sonoma or later. The download is a signed and Apple-notarized DMG.

### Is Codex Account Switcher an official OpenAI product?

No. It is an independent MIT-licensed open-source project for macOS.

## License

Codex Account Switcher is released under the [MIT License](LICENSE).
