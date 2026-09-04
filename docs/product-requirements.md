# Product requirements

## 1. Goal

Allow an ordinary Mac user to choose either a saved ChatGPT account or an already-configured Codex model provider from the menu bar, without routine Terminal commands or config-file editing.

The user should understand the product after opening the menu once. The main path should require no configuration.

## 2. Scope

### In scope

- macOS menu-bar application;
- saved local account profiles;
- one weekly Usage value and an optional exact 5-hour Usage value per account;
- reset times for available Usage windows;
- account switching;
- discovery and selection of custom providers from Codex's effective `model_providers` configuration;
- add account;
- remove inactive account;
- English and Simplified Chinese UI.

### Out of scope

- quota-window selector;
- automatic rotation;
- failover;
- round-robin routing;
- account recommendation;
- automatic switching when Usage is low;
- general rollback and recovery state machines;
- server-side session revocation;
- Windows and Linux releases;
- syncing profiles between Macs;
- entering, copying, or storing custom-provider API keys;
- changing the provider of an existing Codex conversation.

## 3. Primary user stories

### US-1: Inspect accounts

As a user, I can open the menu-bar popover and immediately see saved accounts, weekly Usage, and reset time. I can optionally enable a 5-hour row.

### US-2: Switch accounts

As a user, I can select a different account, read the normal consequences, confirm once, and have Codex Desktop reopen under that account.

### US-3: Add an account

As a user, I can open Manage Accounts, add another ChatGPT account through Codex login, and save it as a selectable profile.

### US-4: Remove an account

As a user, I can remove an inactive local profile from Manage Accounts.

### US-5: Change language

As a user, I can choose System Default, English, or Simplified Chinese.

### US-6: Switch configured provider

As a user, I can see custom model providers already configured in Codex, select one, and have Codex Desktop reopen with that provider active. The switcher does not request or persist the provider's credentials.

## 4. Menu-bar trigger

The menu-bar item uses a compact account-group icon with an accessibility label. It does not wait for account or Usage data before appearing.

The popover content width is 326 points.

## 5. Account row

### 5.1 Layout

With `Show 5-hour Usage` disabled, each row keeps the compact layout:

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

With `Show 5-hour Usage` enabled and exact 5-hour data available, the row expands:

```text
[avatar]  Display Name
          5h   [==========------]  65%  Resets 2:20 PM
          7d   [========--------]  42%  Resets Aug 25, 9:20 AM
```

The 5-hour line is omitted when its data is absent. The UI does not show an unavailable placeholder for that line. English and Simplified Chinese window labels remain fully visible.

### 5.2 Usage-window normalization

Input from Codex may include more than one rate-limit window. One `account/rateLimits/read` response supplies both normalized windows.

Collect `primary` and `secondary` windows from the top-level rate limits and named rate-limit buckets, then choose the longest window whose duration is six through eight days:

```text
fiveHour = first(windows where windowDurationMins == 300)
weekly = max(windows where 8640 <= windowDurationMins <= 11520)
```

If no six-to-eight-day window exists:

```text
Usage unavailable
```

The UI must not infer a weekly value from a short window, regardless of whether Codex labels it `primary` or `secondary`. Four-hour and six-hour windows must not be labeled as five-hour Usage. Missing 5-hour data preserves valid weekly Usage.

### 5.3 Percentage

```text
usedPercent = window.usedPercent
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

### 5.5 Provider row

Custom providers returned by Codex appear below the account list under **Configured Providers**. Each row shows the provider's configured display name, falls back to a human-readable form of its identifier, exposes selected state, and does not show ChatGPT Usage.

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

After confirmation, disable additional actions while the seven-stage account operation runs:

- `Closing Codex Desktop…`
- `Saving current account…`
- `Activating selected account…`
- `Activating OpenAI provider…`
- `Verifying selected account…`
- `Saving selected account…`
- `Opening Codex Desktop…`

If Codex Desktop displays its `Quit ChatGPT?` warning for active local chats, the switcher force-quits the `com.openai.codex` Desktop process after a two-second normal-exit grace period and continues the switch. The user does not manually confirm or restart Desktop.

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
- show the failed stage and the underlying error;
- keep the error visible until the user dismisses it.

If target activation completed and target verification or registry persistence fails, restore the active `auth.json` from the validated original profile saved earlier in the attempt. Keep the original failure visible. If restoration fails, show both the original and restoration errors. Do not restore after an activation failure that did not replace the credential, and keep the target account active when Desktop reopening fails after a successful registry commit.

This bounded repair does not add a general rollback state machine, credential backup file, retry, journal, or startup recovery.

### 7.6 Selecting a configured provider

Provider switching is a separate three-stage operation:

```text
close Codex Desktop
→ set model_provider through config/value/write
→ reopen Codex Desktop
```

The app reads providers through `config/read` and writes only `model_provider`; it does not read environment-variable values or store custom-provider credentials. Selecting a saved ChatGPT account restores the built-in `openai` provider before identity verification.

Codex persists a provider on each conversation. Switching providers therefore affects new conversations, while an existing conversation remains on the provider it was created with and must be created again or forked in Codex to change providers.

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

Adding an account creates no current-account credential backup or rollback flow.

The browser sign-in wait is tracked separately from profile mutations so the account list, Settings, and existing account actions remain interactive. While sign-in is pending, Manage Accounts shows a direct cancel action. Canceling stops the app-server login session without presenting an operation error.

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

The in-popover Settings page contains four fields:

```text
Launch at Login                [toggle]
Show Percentage in Menu Bar   [toggle]
Show 5-hour Usage             [toggle]
Language  [System Default ▾]
```

Launch at Login reads and writes the main app's macOS Login Item registration. It shows a direct approval message and System Settings link for `requiresApproval`, and an unavailable message for `notFound`. The macOS status is the only source of truth and is not persisted in `settings.json`.

Show Percentage in Menu Bar, Show 5-hour Usage, and Language persist in `settings.json`. The 5-hour setting defaults to false when the field is absent from an older file. Language options are:

- System Default;
- English;
- 简体中文.

Changing any persisted setting updates the visible switcher UI immediately. Show 5-hour Usage affects account rows only; the menu-bar percentage continues to show weekly Usage.

## 10. Accessibility

- account rows are keyboard-focusable buttons;
- current row exposes selected state through accessibility APIs;
- progress bars expose `remainingPercent`;
- buttons have explicit labels;
- color is not the only selected-state signal: selected state must also be exposed semantically;
- text remains readable at standard macOS accessibility text sizes.

## 11. Performance

- popover should appear immediately from local metadata;
- persisted weekly and optional 5-hour Usage is rendered before refresh subprocesses complete;
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
2. each row keeps the current weekly layout while Show 5-hour Usage is disabled;
3. enabling Show 5-hour Usage displays separate 5h and 7d lines when both values exist, and omits the 5h line when it is absent;
4. the progress bar exactly matches `NN% left`;
5. the current row is highlighted without a checkmark;
6. the footer contains equal-width Manage Accounts, Settings, and Quit actions;
7. the popover is 326 points wide and all secondary pages navigate inside it;
8. Settings contains launch-at-login, menu-bar percentage, 5-hour Usage, and language controls inside the popover;
9. every popover opening starts on the account list;
10. canceling switch or removal performs no mutation and keeps the popover open;
11. Quit and Command-Q terminate the application and remain available during mutations;
12. account switching follows the documented seven-stage sequence and selects the built-in OpenAI provider;
13. a failure at any switch stage stops and is shown directly;
14. verification and registry-commit failures restore the validated original credential, with no general rollback state machine, backup file, journal, retry, or startup-recovery path;
15. existing CLI processes are not terminated;
16. newly started CLI processes observe the selected active `auth.json`;
17. cached Usage stays visible during refresh and is replaced after success;
18. closing the popover does not stop the pending five-minute background cache refresh;
19. inactive accounts can be added and removed; active accounts cannot be removed;
20. launch-at-login registration reflects the current macOS Login Item status and exposes approval requirements directly;
21. configured custom providers appear in a separate section and can be selected without exposing their credentials;
22. provider switching writes only `model_provider`, restarts Codex Desktop, and does not claim to migrate existing conversations;
23. only `main` is required for the repository's steady state.
