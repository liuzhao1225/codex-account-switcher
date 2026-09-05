# Product decisions

## 1. Product principle

Codex Account Switcher is a simple switcher. Every persistent control must directly support one of four jobs:

1. inspect account Usage;
2. select an account;
3. maintain the saved account list;
4. exit the application.

The September 5 update adds one explicit maintenance job: keep Switcher current through a quiet update notice and user-initiated installation. Sparkle owns scheduling, downloading, validation, and relaunch. Other product expansion remains outside the MVP.

## 2. Main menu

The popover uses a compact 326-point content width. Account rows keep the density and visual hierarchy of the accepted HTML prototype.

With the default settings, each saved account row shows:

- avatar or initials;
- display name;
- `Resets …` on the same line as the name;
- the label `Usage`;
- one progress bar;
- one `NN% left` value.

When `Show 5-hour Usage` is enabled and an exact five-hour window is available, the row expands to separate `5h` and `7d` lines. Each line contains its own progress bar, remaining percentage, and reset time. If the 5-hour window is missing, the row shows only `7d` and does not show an unavailable placeholder.

The current account is represented by a highlighted row. It does not use:

- a checkmark;
- a `Current` label;
- a second status column.

The footer divides its width equally between:

- `Manage Accounts`;
- `Settings`;
- `Quit`.

Manage Accounts and Settings replace the popover content in place and provide a Back action. Closing the popover from either page resets the next opening to the account list.

Quit directly terminates the application, remains available during mutations, and has a Command-Q equivalent.

## 3. Optional 5-hour Usage with weekly Usage

The product always displays the weekly Codex allowance. A setting can additionally display the 5-hour allowance in account rows. The setting defaults to off so existing users keep the compact weekly layout after upgrading.

The normalizer accepts only `windowDurationMins == 300` as the 5-hour window. Four-hour and six-hour windows remain unrelated and are ignored for this field. The app parses and caches the optional 5-hour fields whether the display setting is on or off.

The displayed percentage is remaining allowance:

```text
remainingPercent = clamp(100 - window.usedPercent, 0, 100)
```

Each progress-bar width and text use the same `remainingPercent` value.

The last successful weekly value and optional 5-hour value are persisted per account. Older weekly-only cache entries remain decodable. App launch and every popover opening request one rate-limit response per account and normalize both windows from it. Each trigger replaces the pending background timer with one scheduled for five minutes after that trigger. Cached Usage remains visible while refresh runs, and a successful response replaces both display and cache. A refresh failure keeps cached Usage with a warning; without cached data the row shows `Usage unavailable`. Overlapping triggers share the active refresh round.

The application does not substitute another quota window.

## 4. Switching confirmation

Selecting another account opens a normal confirmation view. It explains fixed behavior rather than exposing configuration switches:

- Codex Desktop will close and reopen;
- a Desktop task that is currently running may stop;
- existing Codex CLI processes are not restarted and continue with the account state they already loaded;
- newly started Codex CLI processes use the newly selected account.

These are product semantics, not Settings options.

The confirmation renders inside the popover. Cancel returns to the account list, keeps the popover open, and starts no switch operation.

## 5. Direct switching flow

The switch implementation is intentionally sequential:

```text
Preflight target and original active profile
→ close Codex Desktop
→ save current credentials
→ activate target credentials
→ verify target identity
→ commit active profile
→ reopen Codex Desktop
```

Before any credential write, preflight reads the registry and validates `originalActiveID`. After target activation succeeds, a verification or registry-commit failure restores `~/.codex/auth.json` from the original profile snapshot saved earlier in the same attempt. An activation failure does not run restoration because replacement did not complete. A Desktop-reopen failure occurs after the registry commit and keeps the selected account active.

The MVP does not implement:

- a general rollback state machine;
- credential backup files;
- a transaction journal;
- automatic retries;
- startup recovery;
- silent fallback to the previous account.

When a step fails, execution stops and the exact original error is shown. If the bounded credential restoration also fails, the same error report contains both failures.

## 6. Credential storage

The MVP uses ordinary local files with user-only permissions.

- Codex active credential: `~/.codex/auth.json`
- Switcher registry: `~/Library/Application Support/Codex Account Switcher/accounts.json`
- Switcher settings: `~/Library/Application Support/Codex Account Switcher/settings.json`
- Usage cache: `~/Library/Application Support/Codex Account Switcher/usage-cache.json`
- Saved account credential: `~/Library/Application Support/Codex Account Switcher/accounts/<profile-id>/auth.json`

macOS Keychain is not used in the MVP. It adds implementation complexity without adding user-visible switching value.

## 7. Manage Accounts

`Manage Accounts` owns account lifecycle operations:

- view saved accounts;
- add account;
- remove an inactive account.

The active account cannot be removed because the meaning of the active Codex authentication file would otherwise be ambiguous. The user first selects another account and then removes the old one.

Removing an account deletes only the switcher's local profile directory and metadata. It does not claim to revoke every OpenAI server session.

Removal uses an in-popover confirmation page. Cancel and Back return to the account list, keep the popover open, and perform no deletion.

## 8. Settings

Settings contains:

- `Launch at Login`: register or unregister the main app through macOS Service Management;
- `Show Percentage in Menu Bar`: show or hide the active account's remaining percentage;
- `Show 5-hour Usage`: show or hide the optional 5-hour line in account rows;
- `Language`: `System Default`, `English`, `简体中文`.

`Show 5-hour Usage` defaults to off and persists immediately in `settings.json`. It affects account rows only. The menu-bar percentage remains the active account's weekly percentage.

The launch-at-login control reads the current macOS Login Item status directly. It does not duplicate that state in `settings.json`. A registered item that requires approval shows a direct link to the Login Items section in System Settings.

The following controls are intentionally absent:

- restart behavior;
- CLI behavior;
- confirmation behavior;
- credential storage selection;
- Keychain status;
- Usage-window selection;
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

A partially completed switch remains observable. The implementation performs only the documented pre-commit credential restoration and adds no generic repair, retry, or startup-recovery behavior.
