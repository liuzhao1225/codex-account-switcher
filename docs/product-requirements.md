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

The menu-bar item uses a compact account-group icon with an accessibility label. It does not wait for account or Usage data before appearing.

The popover content width is 326 points.

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

Collect `primary` and `secondary` windows from the top-level rate limits and named rate-limit buckets, then choose the longest window whose duration is six through eight days:

```text
weekly = max(windows where 8640 <= windowDurationMins <= 11520)
```

If no six-to-eight-day window exists:

```text
Usage unavailable
```

The UI must not infer a weekly value from a short window, regardless of whether Codex labels it `primary` or `secondary`.

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

The footer contains exactly three equal-width actions:

1. `Manage Accounts`
2. `Settings`
3. `Quit`

Manage Accounts and Settings open inside the current popover and provide a Back action. Every new popover opening starts on the account list, regardless of which secondary page was last visible.

Quit directly terminates the application, remains enabled while another operation runs, and is also available through Command-Q.

## 7. Switching flow

### 7.1 Selecting current account

Selecting the highlighted account closes the popover or does nothing. It does not restart Codex and does not show confirmation.

### 7.2 Selecting another account

Show a confirmation page inside the popover with this meaning:

> Switch to **{account name}**?
>
> Codex Desktop will close and reopen. A task currently running in Desktop may stop. Existing Codex CLI sessions continue with the account they started with. New CLI sessions use the selected account.

Actions:

- `Cancel`
- `Switch Account`

Cancel returns to the account list without closing the popover or starting the switch.

### 7.3 Progress

After confirmation, disable additional account actions while the six-stage operation runs:

- `Closing Codex Desktop…`
- `Saving current account…`
- `Activating selected account…`
- `Verifying selected account…`
- `Saving selected account…`
- `Opening Codex Desktop…`

The stages are not configurable. A failure banner identifies the failed stage and retains the underlying diagnostic message.

### 7.4 Success

On success:

- the selected row becomes highlighted;
- `activeAccountID` is updated;
- Codex Desktop is reopened;
- the popover remains available on the account list.

### 7.5 Failure

On failure:

- stop immediately;
- do not continue to later stages;
- do not automatically restore the previous account;
- show the failed stage and the underlying error;
- keep the error visible until the user dismisses it.

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

`Add Account` starts a Codex login using a new profile directory.

Expected flow:

```text
create profile directory
→ run Codex login with CODEX_HOME=<profile directory>
→ read account identity
→ create profile metadata
→ return to Manage Accounts
```

No current-account backup or rollback flow is created.

If login fails, show the Codex login error. The incomplete profile directory may remain on disk; the MVP does not hide the failure with automatic cleanup.

### 8.3 Remove

Removing an inactive profile:

```text
delete accounts/<profile-id>/
→ delete profile metadata
```

If deletion fails, show the filesystem error. Do not add a tombstone or deferred cleanup queue.

The active profile's remove control is disabled.

Remove first opens a confirmation page inside the popover. Cancel and the header Back action return to the account list without closing the popover or calling the remove operation.

## 9. Settings

The in-popover Settings page contains one field:

```text
Language  [System Default ▾]
```

Options:

- System Default;
- English;
- 简体中文.

Changing language updates the visible switcher UI immediately and persists the selected value.

## 10. Accessibility

- account rows are keyboard-focusable buttons;
- current row exposes selected state through accessibility APIs;
- progress bars expose `remainingPercent`;
- buttons have explicit labels;
- color is not the only selected-state signal: selected state must also be exposed semantically;
- text remains readable at standard macOS accessibility text sizes.

## 11. Performance

- popover should appear immediately from local metadata;
- persisted weekly Usage is rendered before refresh subprocesses complete;
- Usage refresh begins at application launch and whenever the popover opens;
- every refresh trigger replaces the pending timer with a refresh scheduled five minutes after that trigger;
- account refreshes run concurrently and overlapping triggers share the active refresh round;
- one app-owned timer remains active while the popover is closed;
- no automatic retry runs after an individual request fails;
- one failed account does not prevent other rows from rendering;
- switch actions are disabled while one switch is in progress.

## 12. Acceptance criteria

The MVP is accepted when:

1. three saved accounts can be displayed in the popover;
2. each row shows only weekly `Usage` and weekly reset time;
3. no 5-hour string, row, toggle, or selector exists;
4. the progress bar exactly matches `NN% left`;
5. the current row is highlighted without a checkmark;
6. the footer contains equal-width Manage Accounts, Settings, and Quit actions;
7. the popover is 326 points wide and all secondary pages navigate inside it;
8. Settings contains only language and opens inside the popover;
9. every popover opening starts on the account list;
10. canceling switch or removal performs no mutation and keeps the popover open;
11. Quit and Command-Q terminate the application and remain available during mutations;
12. account switching follows the documented six-stage sequence;
13. a failure at any switch stage stops and is shown directly;
14. no rollback, backup, journal, retry, or startup-recovery code path runs;
15. existing CLI processes are not terminated;
16. newly started CLI processes observe the selected active `auth.json`;
17. cached Usage stays visible during refresh and is replaced after success;
18. closing the popover does not stop the pending five-minute background cache refresh;
19. inactive accounts can be added and removed; active accounts cannot be removed;
20. only `main` is required for the repository's steady state.
