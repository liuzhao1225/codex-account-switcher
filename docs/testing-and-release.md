# Testing and release

## 1. Test philosophy

The MVP test suite verifies the direct behavior that users depend on.

It does not test rollback, journals, crash recovery, stale-cache fallback, 5-hour presentation, or account failover because those features do not exist.

The most important assertion is:

> When a step fails, the operation stops at that step and exposes the error.

## 2. Unit tests

### 2.1 Weekly Usage normalization

Test:

- a seven-day window is selected;
- a six-day window is accepted;
- an eight-day window is accepted;
- a five-hour window is ignored;
- a one-day window is ignored;
- a five-hour window alone produces `Usage unavailable`;
- `usedPercent = 58` becomes `42% left`;
- values are clamped to 0 through 100;
- reset timestamp is preserved;
- the bar width and percentage use the same value.

### 2.2 Account metadata

Test:

- registry encode and decode;
- active account ID persistence;
- rename trims whitespace;
- empty rename fails;
- duplicate display names are accepted;
- active account removal fails;
- inactive account removal deletes its profile and metadata.

### 2.3 Error mapping

Test each subprocess and filesystem error maps to a concrete user-facing stage.

Do not assert a generic fallback message.

## 3. Switch-service tests

Inject fakes for:

- `DesktopController`;
- `AccountStore`;
- `CodexClient`.

Verify the successful call order:

```text
closeDesktop
saveCurrentCredential
activateTargetCredential
verifyTargetIdentity
commitActiveAccountID
reopenDesktop
```

For each stage, inject one error and assert:

- no later method is called;
- no rollback method is called because none exists;
- the returned error identifies the failed stage;
- the UI does not receive success.

Specific failure cases:

1. Desktop termination timeout.
2. Missing active `auth.json`.
3. Current-profile write failure.
4. Target-profile read failure.
5. Active-auth temporary write failure.
6. Rename failure.
7. Codex app-server startup failure.
8. Account identity mismatch.
9. Registry write failure.
10. Desktop reopen failure.

For identity mismatch, assert that the target credential is not automatically replaced with the previous credential.

## 4. Codex app-server tests

Use a fake JSON-RPC process or test fixture.

Verify:

- initialize is sent before account methods;
- malformed JSON terminates the request with a visible error;
- account identity is decoded;
- rate-limit windows are decoded;
- stderr is captured for diagnostics but secrets are not copied into UI text;
- subprocess termination occurs after success or failure;
- request timeout returns a timeout error without retry.

## 5. Filesystem integration tests

Use a temporary directory as both application support and fake `CODEX_HOME`.

Verify:

- profile directories are created;
- profile `auth.json` is mode `0600`;
- current credential is copied into the active profile;
- target credential is written through a same-directory temporary file;
- final rename produces complete JSON for a concurrent reader;
- no backup, rollback, or journal file appears;
- a failed rename surfaces the operating-system error;
- registry write failure is not hidden.

## 6. UI tests

Verify the main popover:

- shows one row per account;
- highlights the active row;
- contains no checkmark and no `Current` text;
- places reset time next to the account name;
- uses the label `Usage`;
- links bar width to `% left`;
- contains no `5-hour`, `5 hr`, `five-hour`, or equivalent localized string;
- contains only `Manage Accounts…` and `Settings…` in the footer.

Verify Settings:

- contains only the language picker;
- contains no launch-at-login or switching options.

Verify Manage Accounts:

- active remove action is disabled;
- inactive remove action asks for confirmation;
- add and rename work;
- operation errors remain visible.

## 7. Manual test matrix

Before a release, test with at least two real accounts.

1. Launch with account A active.
2. Open the menu and verify weekly Usage for A and B.
3. Confirm that no 5-hour data appears.
4. Switch A to B.
5. Confirm Desktop closes and reopens.
6. Confirm Codex reports B.
7. Start a new CLI and confirm it uses B.
8. Keep a CLI running during B to A and confirm the switcher does not terminate it.
9. Add account C and confirm it is not automatically activated.
10. Rename C.
11. Remove inactive C.
12. Make Codex app-server unavailable and confirm `Usage unavailable` appears.
13. Make Desktop reopening fail and confirm the app reports that the account switched but Desktop did not open.
14. Force identity mismatch and confirm no rollback occurs.

## 8. Static checks

Release checks:

```text
swift format lint
swiftlint
swift test
xcodebuild test
```

Add a repository text scan that fails when production UI or localization files contain:

```text
5-hour
5 hour
5 hr
five-hour
```

Documentation may mention those terms only when stating that the feature is excluded.

Also scan source for forbidden MVP recovery artifacts:

```text
rollback
transactionJournal
recoveryState
backupCredential
```

A match requires explicit review and should normally fail CI.

## 9. Release process

1. Run unit, integration, and UI tests.
2. Run the real-account manual matrix on a test Mac.
3. Build the Release configuration.
4. Sign with Developer ID Application.
5. Submit for notarization.
6. Staple the notarization ticket.
7. Publish a DMG or ZIP and checksum.
8. Update release notes with known limitations.

## 10. Known MVP limitations

Release notes must state:

- only weekly Usage is displayed;
- existing CLI processes are not switched;
- switching restarts Codex Desktop;
- there is no rollback or automatic recovery;
- a failure after credential replacement can leave the new credential active before metadata is committed;
- the user resolves such a failure by retrying or selecting an account again;
- credentials are local to one Mac.

## 11. Release gate

Ship only when:

- weekly Usage works for the supported Codex version;
- the UI has no 5-hour display or setting;
- the direct switch order is covered by tests;
- every injected error stops later steps;
- no rollback or journal files are generated;
- add, rename, switch, and remove-inactive flows pass;
- the binary is signed and notarized.
