# Implementation plan

## 1. Delivery strategy

Build the smallest native macOS app that can complete one real A → B account switch. Add Usage and account-management polish only after that path works.

The implementation should remain on one code path. Do not build recovery architecture in parallel with the MVP.

## 2. Milestone 1 — native shell and static UI

Deliver:

- SwiftUI app target;
- `MenuBarExtra`;
- account-list popover;
- highlighted current row;
- one `Usage` bar per row;
- Manage Accounts view;
- Settings with language only;
- switch confirmation view.

Use fixture data matching the HTML prototype.

Exit criteria:

- UI matches the accepted layout;
- no 5-hour content exists;
- progress bars are bound to percentage values;
- current state uses row highlight, not a checkmark.

## 3. Milestone 2 — profile files

Implement:

- `Paths`;
- `ProfileRepository`;
- `profiles.json` load/save;
- `state.json` load/save;
- profile-directory creation;
- copy active credential into a profile;
- activate profile credential into `~/.codex/auth.json`;
- user-only file permissions.

Exit criteria:

- two fixture auth files can be saved and activated;
- activation uses temp file plus rename;
- no backup, rollback, journal, or Keychain code exists.

## 4. Milestone 3 — Codex identity integration

Implement:

- Codex executable discovery;
- app-server process wrapper;
- initialize handshake;
- account identity read;
- identity normalization;
- target verification.

Exit criteria:

- a saved profile can be identified by account ID or email;
- an identity mismatch produces a direct error;
- the implementation does not restore the old credential after mismatch.

## 5. Milestone 4 — direct switch flow

Implement `AccountSwitcher` in the documented order:

```text
preflight
close Desktop
save current
activate target
verify target
commit state
open Desktop
```

Use one `isSwitching` flag and one in-memory `SwitchStage`.

Exit criteria:

- successful A → B and B → A switches;
- running CLI processes are not touched;
- failure injection at every stage stops immediately;
- no later stage executes after a failure;
- no automatic recovery action executes.

## 6. Milestone 5 — weekly Usage

Implement:

- profile-specific `CODEX_HOME` app-server calls;
- rate-limit RPC;
- `secondary` weekly-window extraction;
- `remainingPercent` calculation;
- reset-time formatting;
- `Usage unavailable` errors.

Exit criteria:

- `primary` is ignored even when present;
- absent `secondary` does not fall back to another window;
- no 5-hour UI or model field exists;
- each account row refreshes independently.

## 7. Milestone 6 — account management

Implement:

- add account using a new profile `CODEX_HOME`;
- read identity after login;
- local rename;
- remove inactive profile;
- disable removal of active profile.

Exit criteria:

- added account appears in the main menu;
- removing a profile deletes its directory and metadata;
- filesystem errors are shown directly;
- no deferred cleanup queue exists.

## 8. Milestone 7 — localization and packaging

Implement:

- English strings;
- Simplified Chinese strings;
- System Default language selection;
- app icon and menu-bar icon;
- signed local build;
- basic release archive.

Launch at login is not part of this milestone.

## 9. Suggested first implementation order

```text
AccountProfile
→ Paths
→ ProfileRepository
→ static AppModel
→ AccountMenuView
→ CodexDesktopController
→ CodexAppServerClient identity
→ AccountSwitcher
→ UsageService
→ Manage Accounts
→ localization
```

## 10. Code-review checklist

Before merging MVP code, verify:

- switching function is readable top-to-bottom;
- no automatic rollback branch exists;
- no transaction journal exists;
- no catch-and-continue behavior exists;
- `primary` rate-limit window is not presented;
- Settings contains only language;
- active account is a row highlight;
- CLI processes are not enumerated or killed;
- errors include the failed stage;
- auth contents are never logged.
