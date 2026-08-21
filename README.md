# Codex Account Switcher Lite

A lightweight macOS account switcher for Codex Desktop that keeps one shared
Codex configuration, project state, and local session history while switching
between saved ChatGPT authentication profiles.

## Initial goals

- Keep `~/.codex` as the shared source of configuration and local state.
- Store each authorized account session locally and securely.
- Switch the active authentication profile without repeating browser login.
- Relaunch Codex Desktop and verify the selected account after every switch.
- Keep automatic rotation disabled by default.

## Current prototype

The interactive menu-bar prototype is available in [`prototype/index.html`](prototype/index.html).

Run it locally:

```bash
python3 -m http.server 8765 --directory prototype
```

Then open <http://127.0.0.1:8765/>.

The editable visualization fragment lives at
[`prototype/codex-account-menu.fragment.html`](prototype/codex-account-menu.fragment.html).
Product decisions and interaction boundaries are recorded in
[`docs/product-decisions.md`](docs/product-decisions.md).
