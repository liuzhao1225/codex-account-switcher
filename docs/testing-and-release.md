# Testing and release

## 1. Testing principle

The MVP test suite should prove the direct happy path and make failures obvious.

It should not become a simulation of every possible crash or a proof of automatic recovery, because the product intentionally has no rollback or recovery subsystem.

## 2. Unit tests

### 2.1 AccountStore

Test with a temporary directory:

- saves and loads `accounts.json`;
- creates a profile directory;
- writes and reads a snapshot;
- renames metadata;
- removes metadata and profile files;
- clears `activeAccountID` when the selected profile is removed;
- preserves duplicate display names as separate UUID profiles.

### 2.2 Weekly window selection

Required cases:

| Windows returned | Expected |
| --- | --- |
| 5 hours only | no weekly Usage |
| 7 days only | select 7-day window |
| 5 hours + 7 days | select 7-day window |
| 1 day + 7 days | select 7-day window |
| 6.5 days + 7 days | select value closest to 7 days |
| 8.1 days | no weekly Usage |
| missing durations | no weekly Usage |

Also test:

- `usedPercent = 0` → `100% left`;
- `usedPercent = 58` → `42% left`;
- values below 0 and above 100 are clamped;
- reset timestamp decodes correctly.

### 2.3 UsageService

Use `URLProtocol` stubs to test:

- authorization and account-ID headers;
- successful decode;
- 200 without weekly window;
- 401 mapping to `Sign in again`;
- non-2xx mapping to a visible error;
- malformed JSON mapping to a visible error;
- no retry after failure.

### 2.4 SwitchService

Use temporary active and profile paths plus a fake Desktop controller.

Test the exact order:

```text
stop Desktop
→ save current snapshot
→ write target auth
→ update active profile
→ launch Desktop
```

Required failure assertions:

- when stopping Desktop throws, later steps do not run;
- when saving current auth throws, target is not written;
- when target read throws, active metadata does not update;
- when active write throws, active metadata does not update;
- when metadata write throws, no rollback is attempted;
- when Desktop launch throws, no rollback is attempted;
- the original error reaches the caller.

The last two tests are important: they prevent a future contributor from silently adding recovery behavior that contradicts the MVP decision.

### 2.5 AddAccountService

Test:

- current profile is saved before active auth removal;
- Desktop is stopped before removal;
- Desktop is launched after removal;
- a new auth file creates a new UUID profile;
- cancellation stops observation;
- cancellation does not restore prior auth;
- malformed new auth can still be saved under a local name, while Usage remains unavailable.

## 3. View tests

Use SwiftUI previews and targeted snapshot tests for:

- 42%, 76%, and 100% remaining;
- long account name with reset time;
- selected-row highlight;
- weekly Usage unavailable;
- sign-in-again state;
- switching state;
- English and Simplified Chinese;
- increased text size.

Do not snapshot every pixel of the window chrome. Focus on layout decisions that are easy to regress.

## 4. Manual test checklist

Before a release:

- [ ] Import the currently logged-in account.
- [ ] Add a second account through Desktop login.
- [ ] Switch from account A to account B.
- [ ] Confirm Desktop reopens using B.
- [ ] Confirm a previously running CLI process is not terminated.
- [ ] Start a new CLI process and confirm it uses B.
- [ ] Switch back to A.
- [ ] Confirm refreshed A credentials were saved when leaving A.
- [ ] Remove an inactive saved profile.
- [ ] Remove the selected saved profile and confirm active auth remains untouched.
- [ ] Rename a profile.
- [ ] Change language.
- [ ] Confirm Settings contains no other controls.
- [ ] Confirm only the weekly window appears.
- [ ] Confirm 5-hour data never appears in the menu or any secondary view.
- [ ] Disconnect the network and confirm Usage failure is visible without retry.
- [ ] Make the active auth path unwritable and confirm the write error is visible.

## 5. Build configuration

Use two configurations:

- Debug;
- Release.

No separate staging backend is required because the application talks to the user's normal local Codex files and current Usage endpoint.

Debug builds may include a menu item to reveal Application Support and print non-secret diagnostics to Console. This item should not become a permanent Settings section.

## 6. CI

A minimal GitHub Actions workflow should run:

```text
swift format lint
swift test
xcodebuild build -scheme CodexAccountSwitcherLite -configuration Release
```

When UI tests require a macOS runner, keep them small enough to finish predictably.

The project does not need a multi-platform matrix.

## 7. Release

### 7.1 Versioning

Use semantic versions:

- `0.1.0` for the first usable MVP;
- patch releases for bug fixes;
- minor releases for additive product features.

Do not promise backward compatibility for unpublished pre-1.0 metadata formats. A migration should be added only when users actually have persisted data that must survive.

### 7.2 Packaging

Release artifacts:

- notarized `.app` inside a ZIP or DMG;
- SHA-256 checksum;
- release notes;
- installation and uninstall instructions.

### 7.3 Release notes

Release notes must state:

- the app changes `~/.codex/auth.json`;
- Codex Desktop restarts during a switch;
- existing CLI sessions are not changed;
- only weekly Usage is displayed;
- 5-hour Usage is intentionally omitted;
- failures are surfaced directly and are not automatically rolled back.

## 8. Exit criteria for 0.1.0

The release is ready when:

- two real accounts can be added and switched repeatedly;
- weekly Usage is correct for both accounts when tokens are valid;
- 5-hour Usage is never rendered;
- language selection works;
- the direct switch sequence passes unit and manual tests;
- common IO and HTTP failures produce understandable errors;
- no rollback, retry, failover, stale cache, or recovery journal exists in the codebase.
