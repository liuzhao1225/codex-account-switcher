# Product requirements

## 1. Product summary

Codex Account Switcher Lite is a native macOS menu-bar application for people who use several ChatGPT accounts with Codex Desktop.

It provides three capabilities:

1. display the remaining weekly Codex Usage for every saved account;
2. switch the active Codex credential;
3. add, rename, and remove local account profiles.

The MVP optimizes for low interaction cost and transparent failure, not for automated recovery or policy management.

## 2. Target user

The target user:

- uses Codex Desktop on one Mac;
- has two or more ChatGPT accounts;
- wants to compare weekly quota before switching;
- accepts a Desktop restart during switching;
- does not expect existing CLI processes to change account in place.

## 3. Primary user story

> I open the menu-bar popover, see which account has weekly Usage left, select it, confirm the restart, and continue in Codex Desktop with that account.

## 4. Main popover

### 4.1 Account row

Each account row contains:

- a 32-point avatar or initials;
- local display name;
- weekly reset time on the same line as the name;
- `Usage` label;
- a horizontal progress bar;
- remaining percentage text.

Example:

```text
ZL  Zhao Liu                    Resets Aug 25, 9:20 AM
    Usage  ████████░░░░░░░░░░░  42% left
```

The percentage and bar width must use the same normalized integer from 0 through 100.

### 4.2 Current account

The current account uses a full-row selection highlight.

Do not show:

- a checkmark;
- `Current`;
- a separate selected-status column.

### 4.3 Footer

The footer contains exactly two actions:

- `Manage Accounts…`
- `Settings…`

### 4.4 Loading and errors

While weekly Usage is loading, the row shows `Loading…`.

When it cannot be loaded, the row shows `Usage unavailable` and no fabricated percentage or reset time.

The MVP does not persist stale Usage to disk.

## 5. Weekly Usage definition

The UI displays one quota window: weekly Codex Usage.

Requirements:

- ignore rate-limit windows shorter than six days;
- accept a weekly window whose duration is between six and eight days;
- calculate `remainingPercent = 100 - usedPercent`;
- clamp the final number to 0 through 100;
- use the weekly window's reset timestamp;
- render reset time in the user's locale and timezone;
- never render the 5-hour window;
- never use the 5-hour window as fallback data;
- never expose a setting for 5-hour Usage.

When no weekly window exists, the result is unavailable.

## 6. Select-account interaction

Clicking the active row closes the popover without doing anything.

Clicking another row opens a normal confirmation dialog.

The dialog contains:

- selected account name;
- a short explanation that Codex Desktop will close and reopen;
- a note that a running Desktop task can be interrupted;
- a note that existing CLI sessions are not restarted;
- `Cancel` and `Switch Account` buttons.

`Switch Account` starts the fixed switch pipeline. There are no switching preferences.

## 7. Switching behavior

The required order is:

1. close Codex Desktop;
2. save the current account's latest active credential;
3. activate the target credential with a same-directory temporary file and rename;
4. verify the target account through Codex;
5. write the active account ID;
6. reopen Codex Desktop.

A later step must not execute after an earlier step fails.

The MVP has no rollback. A failure after credential replacement is shown exactly as that: the credential may already have changed while the active-profile marker has not been committed.

The user can retry. The app does not automatically choose or restore another account.

## 8. CLI behavior

The switcher never terminates or restarts Terminal processes.

Expected behavior:

- an existing CLI process can continue with credentials already loaded in memory;
- a new CLI process reads the newly active `~/.codex/auth.json`;
- the confirmation dialog explains this distinction.

The product does not promise to mutate authentication inside an already running CLI process.

## 9. Manage Accounts

### 9.1 Account list

The window shows:

- avatar or initials;
- display name;
- email when available;
- active status;
- rename and remove actions for inactive profiles.

### 9.2 Add account

`Add Account` starts a Codex login using a profile-specific `CODEX_HOME`.

On successful login:

1. read the created `auth.json`;
2. ask Codex for account identity;
3. create the local profile metadata;
4. show the new account in the list.

Adding an account does not automatically switch to it.

On failure, show the underlying login or identity error. Do not import an incomplete account.

### 9.3 Rename account

Rename changes only the local display name. It does not modify ChatGPT identity.

Names must be non-empty after trimming. Duplicate local names are allowed because account ID, not name, is the identity key.

### 9.4 Remove account

Only inactive accounts can be removed.

Removal deletes:

- the profile directory;
- its metadata entry.

The confirmation text says that removal affects only the saved local profile.

## 10. Settings

Settings contains only language selection:

- `System Default`;
- `English`;
- `简体中文`.

Changing language updates the open UI immediately and persists the selected language.

## 11. Accessibility

- Every account row is a single keyboard-focusable control.
- Progress bars expose the weekly remaining percentage through accessibility value text.
- Current selection is conveyed through `aria-selected` or the SwiftUI accessibility equivalent, not color alone.
- All buttons have explicit accessibility labels.
- Dynamic Type is not required, but the layout must tolerate the macOS larger-text accessibility setting without truncating the percentage.

## 12. Performance

- Popover opening should complete in under 100 ms before network data returns.
- Weekly Usage requests run concurrently across accounts.
- UI interaction remains responsive while Codex subprocesses run.
- The app performs no periodic background polling in MVP.

## 13. Explicit exclusions

The MVP excludes:

- 5-hour Usage display;
- quota-history charts;
- automatic account rotation;
- automatic failover;
- background refresh timers;
- cloud synchronization;
- Keychain configuration UI;
- backup and rollback UI;
- transaction recovery screens;
- advanced diagnostics;
- launch-at-login settings;
- custom switch behavior.

## 14. Acceptance criteria

1. The popover shows every saved account in a compact list.
2. The active row is highlighted and has no checkmark or `Current` text.
3. Reset time appears on the account-name line.
4. The row uses the label `Usage`.
5. The bar width equals the displayed `% left` value.
6. Only weekly Usage is rendered.
7. No UI string or setting mentions the 5-hour window.
8. Missing weekly data produces `Usage unavailable`, not 5-hour data.
9. The footer contains only `Manage Accounts…` and `Settings…`.
10. Settings contains only language selection.
11. Selecting another account opens the normal confirmation dialog.
12. Switching executes the six required steps in order.
13. The first thrown error stops the operation and is shown to the user.
14. No rollback file, journal, or automatic recovery path is created.
15. Existing CLI processes are never terminated by the switcher.
16. New CLI processes use the selected active credential.
17. An inactive account can be added, renamed, and removed.
18. The active account cannot be removed.
