# Codex Account Switcher Lite

A lightweight macOS menu-bar switcher for Codex Desktop accounts.

The product deliberately does one thing: show each saved account's **weekly Usage** and switch the active Codex login with a small, predictable workflow.

## Product rules

- The menu shows account name, weekly Usage, a percentage-linked progress bar, and weekly reset time.
- The UI does **not** show the 5-hour window and does not provide a setting to enable it.
- The selected account is represented by row highlighting, not a checkmark or a `Current` label.
- The footer contains only `Manage Accounts…` and `Settings…`.
- Settings contains only language selection.
- Switching is direct: close Codex Desktop, save the current credential, activate the target credential, verify it through Codex, save the active account ID, and reopen Codex Desktop.
- The MVP has no rollback copy, transaction journal, automatic recovery, silent retry, or fallback account selection. Errors stop the flow and remain visible.
- Existing Codex CLI processes are not stopped. New CLI processes use the newly active credential.

## Prototype

The interactive menu-bar prototype is available in [`prototype/index.html`](prototype/index.html).

Run it locally:

```bash
python3 -m http.server 8765 --directory prototype
```

Then open <http://127.0.0.1:8765/>.

The editable visualization fragment lives at [`prototype/codex-account-menu.fragment.html`](prototype/codex-account-menu.fragment.html).

## Documentation

- [Product decisions](docs/product-decisions.md)
- [Product requirements](docs/product-requirements.md)
- [System design](docs/system-design.md)
- [Testing and release](docs/testing-and-release.md)
