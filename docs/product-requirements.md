# Product requirements

## 1. Summary

Codex Account Switcher Lite is a native macOS menu-bar application for people who use more than one ChatGPT account with Codex.

The application gives the user a compact view of **weekly** Codex usage and lets the user switch which authentication snapshot is active at `~/.codex/auth.json`.

The MVP optimizes for clarity and implementation speed. It does not attempt to make every intermediate failure recoverable.

## 2. Goals

The product must:

1. list locally saved Codex accounts in a compact menu;
2. show weekly Usage, remaining percentage, and weekly reset time;
3. switch accounts with one predictable confirmation;
4. reopen Codex Desktop after a switch;
5. provide a small account-management view;
6. provide language selection;
7. surface operational errors without silently retrying or falling back.

## 3. Non-goals

The MVP does not provide:

- a 5-hour Usage view;
- a Usage-window selector;
- automatic rotation or failover;
- a local reverse proxy;
- multiple simultaneous Desktop profiles;
- credential synchronization across devices;
- enterprise team administration;
- automatic credential repair;
- transaction rollback;
- a recovery journal;
- background retry queues;
- configurable switching semantics;
- a Keychain settings page.

## 4. Target user

The target user:

- uses Codex Desktop on macOS;
- has two or more ChatGPT accounts with Codex access;
- is comfortable with a local utility changing `~/.codex/auth.json`;
- prefers a fast explicit switch over repeated browser login;
- understands that restarting Desktop may interrupt an active Desktop task.

## 5. Information architecture

The application has three surfaces:

1. Main account menu.
2. Manage Accounts.
3. Settings.

No separate dashboard, onboarding wizard, diagnostics center, or advanced preferences screen is required.

## 6. Main account menu

### 6.1 Trigger

The menu-bar item shows:

```text
<active account short name> · <weekly percent left>
```

Example:

```text
Personal · 42%
```

When weekly Usage is unavailable:

```text
Personal · —
```

### 6.2 Account row

Each row displays:

```text
[avatar]  Account Name                         Resets Aug 25, 9:20 AM
          Usage  [==================------]                 42% left
```

Requirements:

- account name truncates before reset time;
- reset time remains on the same line as the account name;
- the progress bar fills to `remainingPercent`;
- the percentage text uses the same value;
- the selected row is highlighted;
- no checkmark is displayed;
- no `Current` label is displayed;
- clicking the selected row does nothing;
- clicking another row opens the switch confirmation.

### 6.3 Weekly-only rule

The account row displays only a weekly window.

A returned window is treated as weekly only when its duration is within the accepted weekly range:

```text
6 days <= duration <= 8 days
```

This range tolerates minor backend representation differences while excluding 5-hour and daily windows.

When multiple weekly candidates exist, use the candidate whose duration is closest to seven days.

When no candidate qualifies:

- text: `Usage unavailable`;
- no percentage;
- empty neutral progress track;
- reset time: `Reset unavailable`.

The application must not substitute a shorter window.

### 6.4 Footer

The footer contains exactly:

- `Manage accounts`;
- `Settings`.

## 7. Switch confirmation

### 7.1 Copy

Title:

```text
Switch account?
```

Body:

```text
Switch to <Account Name>

• Codex Desktop will restart.
• A running Desktop task may be interrupted.
• Existing Terminal sessions keep their current account.
• New Codex sessions use <Account Name>.
```

Actions:

- `Cancel`;
- `Switch account`.

### 7.2 Behavior

After confirmation, the app performs the switch immediately.

While switching:

- disable all account rows;
- show an inline spinner or change the primary action to `Switching…`;
- do not present additional permission or safety dialogs created by the app.

macOS may still display system dialogs when required by the operating system.

### 7.3 Failure

On failure:

- stop the sequence;
- show the operation that failed;
- show the underlying error description;
- keep the menu usable after the alert closes;
- do not automatically retry;
- do not automatically restore a previous snapshot;
- do not report success.

Example:

```text
Could not switch account

Writing ~/.codex/auth.json failed:
Permission denied
```

## 8. Manage Accounts

### 8.1 List

Each saved account displays:

- avatar or initials;
- local display name;
- email when available;
- `Rename` action;
- `Remove` action.

### 8.2 Add account

The bottom action is `Add account`.

On selection:

1. show a single informational confirmation that Desktop will restart and the user will sign in;
2. save the current profile's latest auth file when the current profile is known;
3. close Desktop;
4. remove the active auth file;
5. reopen Desktop;
6. wait for a newly created auth file;
7. ask for a display name;
8. store it as a saved profile and mark it selected.

The wait is canceled when the user closes the add-account flow. Cancellation does not restore the previous auth file.

### 8.3 Rename

Rename changes local metadata only. It does not change the ChatGPT account name.

Validation:

- trimmed name must not be empty;
- duplicate display names are allowed because profile ID is the identity.

### 8.4 Remove

Remove uses one confirmation:

```text
Remove <Account Name> from this Mac?
```

Removal deletes the saved snapshot and metadata.

If the removed profile was selected:

- clear `activeAccountID` in app metadata;
- do not delete or modify `~/.codex/auth.json`;
- show the active auth as an unsaved session until another account is selected or saved.

## 9. Settings

Settings contains one field:

```text
Language: System Default | English | 简体中文
```

Changing language applies immediately to the switcher UI.

No other setting is included in the MVP.

## 10. Usage refresh

Weekly Usage refreshes:

- when the menu opens;
- when an account is added;
- after an account switch completes;
- when the user presses a small retry icon shown only after a Usage failure.

The MVP does not run a periodic background refresh timer.

Requests for different accounts may run concurrently.

Rules:

- one request per account per refresh action;
- no automatic retry;
- no stale-value fallback after failure;
- a 401 response becomes `Sign in again`;
- other failures become `Usage unavailable` with an accessible error description.

## 11. Accessibility

- All controls have VoiceOver labels.
- Progress values expose `Weekly usage, 42 percent remaining`.
- Selection is exposed through the row's selected state, not color alone.
- Keyboard focus follows normal macOS menu and sheet behavior.
- Reset timestamps use locale-aware date formatting.

## 12. Localization

The application ships with:

- English;
- Simplified Chinese.

`System Default` selects the best supported locale from macOS.

Account names, email addresses, file-system errors, and backend-provided error text are not translated by the application.

## 13. Acceptance criteria

### Main menu

- [ ] Main menu opens from the macOS menu bar.
- [ ] Selected account is highlighted without a checkmark.
- [ ] Reset time is on the account-name line.
- [ ] Progress-bar width equals the displayed remaining percentage.
- [ ] Footer contains only Manage Accounts and Settings.

### Weekly Usage

- [ ] Weekly data is displayed when a 6–8 day window is returned.
- [ ] A 5-hour window is ignored.
- [ ] A daily window is ignored.
- [ ] Missing weekly data produces `Usage unavailable`.
- [ ] No screen or setting exposes the 5-hour window.

### Switching

- [ ] Selecting another account opens one confirmation.
- [ ] Desktop closes before auth replacement.
- [ ] Current selected snapshot is updated from the active auth file when possible.
- [ ] Target snapshot replaces the active auth file.
- [ ] Selected profile metadata updates after the write succeeds.
- [ ] Desktop reopens.
- [ ] Existing CLI processes are not terminated.
- [ ] A failed step displays its error and is not retried or rolled back.

### Account management

- [ ] Add Account enters normal Codex sign-in.
- [ ] Rename changes local metadata only.
- [ ] Remove deletes one local snapshot after one confirmation.
- [ ] Removing the selected snapshot does not modify active Codex auth.

### Settings

- [ ] Settings contains only language selection.
