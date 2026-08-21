# Product decisions

## Product principle

Codex Account Switcher Lite is a simple switcher, not an account platform.

The primary flow is:

1. Open the menu-bar popover.
2. Read weekly Usage and reset time.
3. Select another account.
4. Confirm the normal switching effects.
5. Switch and reopen Codex Desktop.

Every persistent control must directly support account selection, account maintenance, or language selection.

## Main menu

Each saved account row shows:

- avatar or initials;
- account name;
- `Resets …` on the same line as the account name;
- the label `Usage`;
- one progress bar;
- one percentage such as `42% left`.

The percentage and progress-bar width are driven by the same `remainingPercent` value.

The active account is represented by a highlighted row. The UI does not use a checkmark, a right-side status icon, or a `Current` label.

The footer contains only:

- `Manage Accounts…`
- `Settings…`

## Weekly Usage only

`Usage` means the remaining **weekly Codex quota**.

The following rules are fixed:

- Do not render the 5-hour Usage window.
- Do not add a `Show 5-hour Usage` setting.
- Do not show two quota rows.
- Do not fall back to the 5-hour window when weekly data is unavailable.
- When weekly data cannot be read, show `Usage unavailable` for that account.

The backend adapter may receive several rate-limit windows, but the presentation layer receives only the normalized weekly value.

## Switching confirmation

Selecting another account opens a normal confirmation dialog. It is not a danger warning.

The dialog explains fixed behavior:

- Codex Desktop will close and reopen with the selected account.
- A currently running Desktop task can be interrupted by the restart.
- Existing Terminal or CLI sessions are not restarted and can continue using the account they already loaded.
- New CLI sessions use the selected active credential.

These are product semantics, not Settings toggles.

## Direct MVP switch

The switch pipeline is intentionally straightforward:

1. Close Codex Desktop.
2. Save the current account's latest `auth.json` into its local profile.
3. Atomically replace the active `~/.codex/auth.json` with the target profile's `auth.json`.
4. Ask Codex to report the active account and compare it with the target profile.
5. Save the target profile as the active profile.
6. Reopen Codex Desktop.

The MVP explicitly does not implement:

- rollback credentials;
- backup copies for switching;
- transaction journals;
- crash recovery state machines;
- automatic retries;
- automatic selection of another account;
- silent fallback to stale Usage or another quota window;
- broad preflight checks unrelated to the next required operation.

If a step fails, the pipeline stops immediately and shows the failed stage and error. The application does not hide the failure by restoring an earlier state.

## Manage Accounts

`Manage Accounts…` owns account lifecycle operations:

- list saved accounts;
- add an account through Codex login;
- rename the local display name;
- remove an inactive saved account.

Removing an account deletes only the locally saved profile. It does not claim to revoke every remote session.

The active account cannot be removed. The user switches to another account first. This is a necessary product invariant because the active Codex credential must continue to have a corresponding local profile.

## Settings

Settings contains only:

- `Language`
  - `System Default`
  - `English`
  - `简体中文`

There is no `Launch at Login`, `Restart Codex automatically`, credential-storage selector, Keychain status, Usage detail switch, CLI behavior switch, or confirmation preference.

## Error philosophy

Errors are part of the MVP's visible behavior:

- no silent catch-and-continue;
- no success message before the final required step finishes;
- no generic `Something went wrong` when a concrete stage is known;
- no automatic repair of mismatched active metadata;
- no stale data presented as fresh.

A typical error is presented as:

> Could not verify the selected account. The target credential has already been written. Codex Desktop was not reopened.

The user can retry the same account or choose another account.

## Non-goals

- automatic account rotation;
- failover or round-robin routing;
- transparent multi-account proxying;
- cloud credential sync;
- changing accounts inside already running CLI processes;
- modifying or injecting the Codex Desktop frontend;
- detailed quota analytics;
- 5-hour Usage display;
- enterprise policy management;
- a generalized credential manager.
