# Product decisions

## Product principle

Codex Account Switcher Lite is a simple switcher. The primary flow is:

1. Open the menu-bar popover.
2. Read account usage and reset time.
3. Select an account.
4. Confirm the expected switching effects.

Every persistent control must directly support account selection or account maintenance.

## Main menu

Each saved account shows:

- Account name and avatar.
- Usage percentage and a linked progress bar.
- Reset time.
- A row highlight for the currently selected account.

The footer contains only:

- `Manage accounts`
- `Settings`

## Switching confirmation

Selecting another account always opens the normal confirmation step. It explains the fixed product behavior:

- Codex Desktop restarts with the selected account.
- Existing Terminal Codex sessions keep their current account.
- New Codex sessions use the selected account.

These behaviors are product invariants. They are not optional Settings toggles.

## Manage accounts

`Manage accounts` owns account lifecycle operations:

- View locally saved accounts.
- Add an account.
- Remove an account with confirmation.

Removing an account deletes only its locally saved login state. The final implementation must prevent removing the active account until another account is selected.

## Settings

Settings contains only long-lived user preferences:

- `Launch at login`
- `Language` with `System Default`, `English`, and `简体中文`

The following items are intentionally excluded:

- Restart Codex automatically.
- Use the selected account for new CLI sessions.
- Confirm active task interruption.
- Credentials or Keychain status.
- Usage details.

The first three are fixed switching semantics and belong in the confirmation flow. Credential storage is an implementation and diagnostics concern unless the user can choose a storage method.

## Non-goals for the lightweight version

- Automatic account rotation.
- Failover or round-robin routing.
- Transparent multi-account reverse proxying.
- Modifying or injecting the Codex Desktop frontend.
- Interrupting already running Terminal sessions when another account is selected.
