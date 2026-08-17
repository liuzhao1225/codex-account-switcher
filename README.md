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

