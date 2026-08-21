# Codex Account Switcher Lite

A lightweight macOS menu-bar switcher for changing the ChatGPT account used by Codex Desktop and newly started Codex CLI processes.

The product is intentionally narrow:

- show saved accounts;
- show one weekly `Usage` value and its reset time;
- switch the active Codex authentication file;
- add and remove local account snapshots;
- choose the UI language.

It is not an account router, proxy, recovery manager, or policy layer.

## Current prototype

The interactive prototype is available at [`prototype/index.html`](prototype/index.html).

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
- The footer contains only `Manage Accounts…` and `Settings…`.
- Settings contains only language selection.
- Switching follows one direct sequence and stops on the first error.
- There is no automatic rollback, retry, transaction journal, credential backup, or crash recovery workflow.

## Documentation

- [Documentation index](docs/README.md)
- [Product decisions](docs/product-decisions.md)
- [Product requirements](docs/product-requirements.md)
- [System design](docs/system-design.md)
- [Implementation plan](docs/implementation-plan.md)
- [Testing](docs/testing.md)
