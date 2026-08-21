# Product decisions

## Product principle

Codex Account Switcher Lite is a switcher, not an account platform.

The primary flow is:

1. Open the menu-bar popover.
2. Read each account's weekly Usage and reset time.
3. Select another account.
4. Confirm the ordinary switching effects.
5. Let the app copy the selected credentials and reopen Codex Desktop.

Every permanent control must directly support that flow.

## Main menu

Each saved account row contains:

- avatar or initials;
- account display name;
- weekly reset time on the same line as the name;
- the label `Usage`;
- a progress bar;
- a percentage such as `42% left`.

The percentage and progress-bar width use the same `remainingPercent` value.

The selected account is represented by row highlighting. There is no `Current` label and no checkmark consuming horizontal space.

The footer contains only:

- `Manage accounts`;
- `Settings`.

## Weekly Usage only

The product displays one quota window: the weekly window.

- The 5-hour window is never shown.
- There is no toggle to reveal it.
- There is no secondary details page containing it.
- The app does not fall back to the 5-hour window when weekly data is missing.
- When no weekly window is present, the row shows `Usage unavailable`.

`remainingPercent` is calculated as:

```text
remainingPercent = clamp(100 - usedPercent, 0, 100)
```

The reset label comes from the weekly window's reset timestamp.

## Switching confirmation

Selecting a non-active account opens one normal confirmation sheet. This is not styled as a dangerous or destructive warning.

It explains the fixed behavior:

- Codex Desktop will close and reopen with the selected account.
- A running Desktop task can be interrupted by the restart.
- Existing Terminal Codex processes keep their already loaded account.
- New Codex processes use the selected account.

These are product semantics, not Settings toggles.

## Direct switching behavior

The implementation performs a direct sequence:

```text
Confirm
→ close Codex Desktop
→ save the current auth snapshot
→ replace ~/.codex/auth.json with the selected snapshot
→ record the selected profile ID
→ reopen Codex Desktop
```

There is deliberately:

- no rollback copy;
- no transaction journal;
- no post-switch identity verification gate;
- no retry loop;
- no automatic repair;
- no alternate credential backend fallback.

If a step fails, the app displays the error and stops. It does not claim that the switch succeeded.

## Manage accounts

`Manage accounts` owns all account lifecycle actions:

- list saved accounts;
- add an account;
- rename an account;
- remove an account.

Removing a saved account deletes its local snapshot only. It does not revoke server sessions or log the account out on other devices.

Removing the selected saved profile is allowed. The currently active `~/.codex/auth.json` remains untouched until the next switch or login. This avoids a special-case safety gate in the MVP.

A remove action uses one compact confirmation because the deletion is intentional and local. There is no second confirmation or typed account name.

## Add account

Adding an account uses the normal Codex Desktop sign-in experience:

1. Save the current selected profile's latest `auth.json`, when available.
2. Close Codex Desktop.
3. Delete the active `~/.codex/auth.json`.
4. Reopen Codex Desktop.
5. Let the user sign in.
6. Detect the newly written `auth.json`.
7. Ask for a local display name and save the new snapshot.

If login is canceled or fails, the app leaves the failure visible. The user can select any previously saved account to continue.

## Settings

Settings contains only language:

- `System Default`;
- `English`;
- `简体中文`.

The following are intentionally absent:

- launch at login;
- restart behavior;
- CLI switching behavior;
- confirmation behavior;
- Keychain or credential storage status;
- Usage-window selection;
- automatic rotation;
- recovery or retry options.

## Non-goals

- 5-hour Usage display;
- automatic account rotation;
- failover or round-robin routing;
- account pooling;
- transparent reverse proxying;
- running multiple Codex Desktop instances;
- changing credentials inside already running CLI processes;
- editing or injecting the Codex Desktop frontend;
- cross-device synchronization;
- enterprise policy management;
- rollback and crash recovery machinery.
