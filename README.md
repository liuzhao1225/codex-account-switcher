# Codex Account Switcher Lite

A deliberately small macOS menu-bar switcher for Codex Desktop.

It keeps the normal shared `~/.codex` directory for Codex configuration, projects, and local history, while saving multiple ChatGPT authentication snapshots and copying the selected snapshot into `~/.codex/auth.json`.

## Product rules

- The main menu shows saved accounts, **weekly Usage only**, reset time, `Manage accounts`, and `Settings`.
- The 5-hour window is never displayed and is not configurable.
- Selecting another account opens one normal confirmation, switches the auth file, and reopens Codex Desktop.
- Existing Codex CLI processes keep the credentials they already loaded. New processes use the newly selected account.
- Settings contains only language selection.
- There is no automatic rotation, failover, retry loop, rollback transaction, recovery journal, or hidden fallback.
- An error is shown as an error. The app stops the current operation instead of pretending it succeeded.

## Prototype

The interactive prototype is available at [`prototype/index.html`](prototype/index.html).

Run it locally:

```bash
python3 -m http.server 8765 --directory prototype
```

Then open <http://127.0.0.1:8765/>.

## Documentation

- [Product decisions](docs/product-decisions.md)
- [Product requirements](docs/product-requirements.md)
- [System design](docs/system-design.md)
- [Testing and release](docs/testing-and-release.md)
- [ADR: direct MVP switching](docs/adr/0001-direct-mvp-switching.md)
