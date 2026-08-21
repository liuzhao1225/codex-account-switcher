# Product requirements

## 1. Goal

Allow a macOS user with multiple ChatGPT accounts to see each account's weekly Codex Usage and change which account Codex Desktop and newly started Codex CLI processes use.

The user should understand the product after opening the menu once. The main path should require no configuration.

## 2. Scope

### In scope

- macOS menu-bar application;
- saved local account profiles;
- one weekly Usage value per account;
- weekly reset time;
- account switching;
- add account;
- rename account locally;
- remove inactive account;
- English and Simplified Chinese UI.

### Out of scope

- 5-hour Usage display;
- multiple quota rows;
- quota-window selector;
- automatic rotation;
- failover;
- round-robin routing;
- account recommendation;
- automatic switching when Usage is low;
- rollback and recovery state machines;
- server-side session revocation;
- Windows and Linux releases;
- syncing profiles between Macs.

## 3. Primary user stories

### US-1: Inspect accounts

As a user, I can open the menu-bar popover and immediately see saved accounts, weekly Usage, and reset time.

### US-2: Switch accounts

As a user, I can select a different account, read the normal consequences, confirm once, and have Codex Desktop reopen under that account.

### US-3: Add an account

As a user, I can open Manage Accounts, add another ChatGPT account through Codex login, and save it as a selectable profile.

### US-4: Remove an account

As a user, I can remove an inactive local profile from Manage Accounts.

### US-5: Change language

As a user, I can choose System Default, English, or Simplified Chinese.

## 4. Menu-bar trigger

The menu-bar item should show a compact account indicator. Recommended content:

```text
<avatar> <short account name> · <remaining%>
```

Examples:

```text
ZL Personal · 42%
GW Work · 76%
```

When Usage is unavailable:

```text
ZL Personal
```

The trigger is not required to show reset time.

## 5. Account row

### 5.1 Layout

Each row contains:

```text
[avatar]  Display Name                     Resets Aug 25, 9:20 AM
          Usage  [================----]                 42% left
```

Constraints:

- reset time is on the name line;
- `Usage` is the only quota label;
- the percentage is remaining percentage;
- the progress bar width equals the displayed percentage;
- the current account is a row highlight;
- no checkmark is shown;
- no `Current` text is shown.

### 5.2 Weekly-only normalization

Input from Codex may include more than one rate-limit window. The product model keeps only the weekly window.

For the Codex app-server response:

```text
weekly = rateLimitsByLimitId["codex"].secondary
      ?? rateLimits.secondary
```

There is intentionally no fallback to `primary`.

If `secondary` is absent or invalid:

```text
Usage unavailable
```

The UI must not infer a weekly value from the short window.

### 5.3 Percentage

```text
usedPercent = weekly.usedPercent
remainingPercent = clamp(100 - usedPercent, 0, 100)
```

Examples:

| `usedPercent` | UI text | Bar width |
| ---: | ---: | ---: |
| 0 | `100% left` | 100% |
| 24 | `76% left` | 76% |
| 58 | `42% left` | 42% |
| 100 | `0% left` | 0% |

### 5.4 Reset formatting

If `resetsAt` is available, render it in the user's locale and timezone:

```text
Resets Aug 25, 9:20 AM
```

If it is absent:

```text
Reset unknown
```

## 6. Main-menu footer

The footer contains exactly two actions:

1. `Manage Accounts…`
2. `Settings…`

No other persistent controls belong in the main menu.

## 7. Switching flow

### 7.1 Selecting current account

Selecting the highlighted account closes the popover or does nothing. It does not restart Codex and does not show confirmation.

### 7.2 Selecting another account

Show a confirmation view with an information icon and this meaning:

> Switch to **{account name}**?
>
> Codex Desktop will close and reopen. A task currently running in Desktop may stop. Existing Codex CLI sessions continue with the account they started with. New CLI sessions use the selected account.

Actions:

- `Cancel`
- `Switch Account`

### 7.3 Progress

After confirmation, show the current stage:

- `Closing Codex Desktop…`
- `Saving current account…`
- `Activating selected account…`
- `Verifying selected account…`
- `Opening Codex Desktop…`

The stages are not configurable.

### 7.4 Success

On success:

- the selected row becomes highlighted;
- `activeProfileID` is updated;
- Codex Desktop is reopened;
- the popover may close.

### 7.5 Failure

On failure:

- stop immediately;
- do not continue to later stages;
- do not automatically restore the previous account;
- show the failed stage and the underlying error;
- offer `Close` and, when appropriate, `Try Again` as a fresh user action.

The message must not claim that the previous account was restored.

## 8. Manage Accounts

### 8.1 List

Show:

- avatar or initials;
- local display name;
- email when available;
- active-state highlight;
- remove action for inactive profiles.

### 8.2 Add account

`Add Account…` starts a Codex login using a new profile directory.

Expected flow:

```text
create profile directory
→ run Codex login with CODEX_HOME=<profile directory>
→ read account identity
→ create profile metadata
→ optionally switch to the new profile
```

No current-account backup or rollback flow is created.

If login fails, show the Codex login error and leave the incomplete profile directory removable.

### 8.3 Rename

Renaming changes only the local `displayName`. It does not modify the OpenAI account.

### 8.4 Remove

Removing an inactive profile:

```text
delete accounts/<profile-id>/
→ delete profile metadata
```

If deletion fails, show the filesystem error. Do not add a tombstone or deferred cleanup queue.

The active profile's remove control is disabled.

## 9. Settings

The Settings view contains one field:

```text
Language  [System Default ▾]
```

Options:

- System Default;
- English;
- 简体中文.

Changing language updates visible switcher UI immediately or after reopening the popover.

## 10. Accessibility

- account rows are keyboard-focusable buttons;
- current row exposes selected state through accessibility APIs;
- progress bars expose `remainingPercent`;
- buttons have explicit labels;
- color is not the only selected-state signal: selected state must also be exposed semantically;
- text remains readable at standard macOS accessibility text sizes.

## 11. Performance

- popover should appear immediately from local metadata;
- Usage refresh begins when the popover opens;
- each account refresh runs once; no automatic retry;
- one failed account does not prevent other rows from rendering;
- switch actions are disabled while one switch is in progress.

## 12. Acceptance criteria

The MVP is accepted when:

1. three saved accounts can be displayed in the popover;
2. each row shows only weekly `Usage` and weekly reset time;
3. no 5-hour string, row, toggle, or selector exists;
4. the progress bar exactly matches `NN% left`;
5. the current row is highlighted without a checkmark;
6. Settings contains only language;
7. account switching follows the documented seven-stage sequence;
8. a failure at any switch stage stops and is shown directly;
9. no rollback, backup, journal, retry, or startup-recovery code path runs;
10. existing CLI processes are not terminated;
11. newly started CLI processes observe the selected active `auth.json`;
12. only `main` is required for the repository's steady state.
