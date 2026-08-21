# Codex Account Switcher Lite

A lightweight macOS menu-bar switcher for changing the ChatGPT account used by Codex Desktop and newly started Codex CLI processes.

The product is intentionally narrow:

- show saved accounts;
- show one weekly `Usage` value and its reset time;
- switch the active Codex authentication file;
- add and remove local account snapshots;
- choose the UI language.

It is not an account router, proxy, recovery manager, or policy layer.

## Native application

The repository includes the macOS 14+ SwiftUI application. It provides:

- a compact native menu-bar popover with one weekly Usage row per account;
- persisted weekly Usage that remains visible while launch, a reschedulable five-minute background timer, and popover openings refresh it;
- independent `CODEX_HOME` profile directories and local account metadata;
- first-launch import of an existing `~/.codex/auth.json` account;
- Codex app-server integration for identity, login, and rate limits;
- the fixed six-stage Desktop account switch pipeline;
- add and remove account flows;
- English, Simplified Chinese, and system-default UI language choices.

Build and check it from Terminal:

```bash
swift build
./scripts/run-core-checks.sh
```

Create a local development app bundle:

```bash
./scripts/package-local-app.sh
```

The bundle is written to `.build/release/Codex Account Switcher Lite.app`.

## Signed GitHub releases

Pushing a `v*` tag runs the release workflow. It builds the arm64 app, signs it with Developer ID and hardened runtime, submits it to Apple notarization, staples the ticket, validates the installed-app signature, and creates the GitHub Release only after every check succeeds.

Configure the `appstore-production` GitHub Environment with these secrets:

- `CSC_NAME`
- `MACOS_CERTIFICATE_P12_BASE64`
- `MACOS_CERTIFICATE_PASSWORD`
- `APP_STORE_CONNECT_API_KEY_P8_BASE64`
- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`

Keep the `.p12`, its password, and the App Store Connect `.p8` outside the repository. The notarization credentials must use an App Store Connect Team API key with an Issuer ID.

## Visual prototype

The early visual prototype is available at [`prototype/index.html`](prototype/index.html). The native implementation and product documents define current behavior.

Run it locally:

```bash
python3 -m http.server 8765 --directory prototype
```

Then open <http://127.0.0.1:8765/>.

## Product constraints

- The main menu uses `Usage`, a percentage-linked progress bar, and `Resets …` beside the account name.
- Only the weekly Codex allowance is displayed.
- There is no 5-hour row, selector, detail panel, or setting.
- The current account is shown by row highlight rather than a checkmark or `Current` label.
- The footer contains equal-width `Manage Accounts`, `Settings`, and `Quit` actions.
- Manage Accounts and Settings replace the content inside the same popover.
- Settings contains only language selection.
- Every popover opening starts on the account-switching page.
- Persisted weekly Usage stays visible during refresh and is replaced after a successful response. Every refresh trigger schedules the next refresh for five minutes later, including while the popover is closed.
- Switching asks Codex Desktop to quit, force-quits it after a short grace period when an active-chat confirmation blocks shutdown, replaces the active credentials, and reopens Desktop. It stops on the first error.
- There is no automatic rollback, retry, transaction journal, credential backup, or crash recovery workflow.

## Documentation

- [Documentation index](docs/README.md)
- [Product decisions](docs/product-decisions.md)
- [Product requirements](docs/product-requirements.md)
- [System design](docs/system-design.md)
- [Implementation plan](docs/implementation-plan.md)
- [Testing](docs/testing.md)
