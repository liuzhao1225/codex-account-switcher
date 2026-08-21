# Product decisions

## 1. Product principle

Codex Account Switcher Lite is a simple switcher. Every persistent control must directly support one of three jobs:

1. inspect account Usage;
2. select an account;
3. maintain the saved account list.

Anything outside those jobs is excluded from the MVP.

## 2. Main menu

Each saved account row shows:

- avatar or initials;
- display name;
- `Resets …` on the same line as the name;
- the label `Usage`;
- one progress bar;
- one `NN% left` value.

The current account is represented by a highlighted row. It does not use:

- a checkmark;
- a `Current` label;
- a second status column.

The footer contains only:

- `Manage Accounts…`;
- `Settings…`.

## 3. Weekly Usage only

The product displays the weekly Codex allowance only.

There is no 5-hour row and no setting to enable one. If Codex returns both a short window and a weekly window, the short window is ignored by the UI and by the normalized product model.

The displayed percentage is remaining allowance:

```text
remainingPercent = clamp(100 - weekly.usedPercent, 0, 100)
```

The progress-bar width and text use the same `remainingPercent` value.

If the weekly window cannot be read, the row shows `Usage unavailable`. The application does not substitute another window or silently reuse a different quota type.

## 4. Switching confirmation

Selecting another account opens a normal confirmation view. It explains fixed behavior rather than exposing configuration switches:

- Codex Desktop will close and reopen;
- a Desktop task that is currently running may stop;
- existing Codex CLI processes are not restarted and continue with the account state they already loaded;
- newly started Codex CLI processes use the newly selected account.

These are product semantics, not Settings options.

## 5. Direct switching flow

The switch implementation is intentionally sequential:

```text
Preflight
→ close Codex Desktop
→ save current credentials
→ activate target credentials
→ verify target identity
→ commit active profile
→ reopen Codex Desktop
```

The MVP does not implement:

- rollback credentials;
- backup copies;
- a transaction journal;
- automatic retries;
- startup recovery;
- compensating actions;
- silent fallback to the previous account.

When a step fails, execution stops and the exact error is shown. The system does not hide the failure by restoring another state.

## 6. Credential storage

The MVP uses ordinary local files with user-only permissions.

- Codex active credential: `~/.codex/auth.json`
- Switcher metadata: `~/.codex-account-switcher/profiles.json`
- Switcher state: `~/.codex-account-switcher/state.json`
- Saved account credential: `~/.codex-account-switcher/accounts/<profile-id>/auth.json`

macOS Keychain is not used in the MVP. It adds implementation complexity without adding user-visible switching value.

## 7. Manage Accounts

`Manage Accounts…` owns account lifecycle operations:

- view saved accounts;
- add account;
- rename local display name;
- remove an inactive account.

The active account cannot be removed because the meaning of the active Codex authentication file would otherwise be ambiguous. The user first selects another account and then removes the old one.

Removing an account deletes only the switcher's local profile directory and metadata. It does not claim to revoke every OpenAI server session.

## 8. Settings

Settings contains only:

- `Language`: `System Default`, `English`, `简体中文`.

The following controls are intentionally absent:

- Launch at login;
- restart behavior;
- CLI behavior;
- confirmation behavior;
- credential storage selection;
- Keychain status;
- Usage-window selection;
- 5-hour Usage display;
- automatic rotation.

## 9. Architecture

The production client is a native SwiftUI menu-bar app.

It does not require:

- Electron;
- a local HTTP server;
- a daemon;
- a reverse proxy;
- a cloud service;
- modification of Codex Desktop;
- injection into Codex UI.

The HTML prototype is a visual reference, not the production runtime.

## 10. Error philosophy

Errors must be visible and attributable to a specific step.

The implementation should:

- use small typed operations;
- stop at the first failed operation;
- preserve the original system error where useful;
- avoid broad `catch` blocks that convert every failure into a generic message;
- avoid retry loops unless a later product requirement explicitly adds them.

A partially completed switch is an observable implementation failure, not a hidden condition to repair automatically.
