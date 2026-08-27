# Testing

## 1. Philosophy

The MVP test suite should prove two things:

1. the direct happy path works;
2. failures stop exactly where they occur and remain visible while the bounded pre-commit credential restoration preserves account consistency.

It should test the documented verification/commit restoration and confirm that no general rollback state machine, retry, credential backup file, journal, or startup recovery exists.

### Local toolchains

Xcode and GitHub-hosted macOS runners use SwiftPM's normal `Testing` module discovery. Some standalone Command Line Tools distributions place `Testing.framework` and `lib_TestingInterop.dylib` outside SwiftPM's default search paths. For that CLT layout, `Package.swift` derives the selected toolchain root from `xcrun --find swift` and adds only the required framework and runtime search paths when both files exist. The repository contains no fixed developer-directory path.

## 2. Unit tests

### 2.1 Weekly Usage

Test:

- `used=0` → `100% left`;
- `used=24` → `76% left`;
- `used=58` → `42% left`;
- `used=100` → `0% left`;
- values below 0 and above 100 are clamped;
- a six-to-eight-day window is selected from either `primary` or `secondary` buckets;
- short-duration windows are ignored;
- absence of a six-to-eight-day window returns `Usage unavailable`;
- no product type or UI string contains `5-hour`.

### 2.2 Profile repository

Test:

- load empty repository;
- create profile;
- save active credential into profile;
- activate profile credential;
- delete inactive profile;
- reject deleting active profile;
- persist weekly Usage with mode `0600`;
- remove cached Usage with its inactive profile;
- surface read, write, atomic replacement, and delete errors.

### 2.3 Identity matching

Test:

- matching account IDs succeed;
- differing account IDs fail;
- normalized matching emails succeed when account ID is unavailable;
- differing emails fail;
- missing ID and email fails.

## 3. Switch-flow tests

Use fakes for Desktop, account storage, and Codex identity.

Expected call order:

```text
closeDesktop
saveCurrent
activateTarget
readActiveIdentity
commitActiveAccountID
openDesktop
```

Inject an error at each call and assert:

- the error reports the correct `SwitchStage`;
- no later call occurs;
- no retry occurs;
- `isMutating` returns to false after presentation.

Specific partial-state assertions:

- the registry is read and `originalActiveID` is validated before saving or replacing credentials;
- activation error before replacement leaves state metadata unchanged and runs no restoration;
- verification error restores the original active credential and leaves the original metadata active;
- state-write error restores the original active credential and leaves the original metadata active;
- a retry after restoration cannot overwrite the original profile with target credentials;
- a restoration failure reports both the original and restoration errors;
- Desktop-open error leaves target auth and target metadata active.

Use both the fake store and the real `AccountStore` so call ordering, atomic credential installation, registry-write failure, and on-disk bytes are covered.

## 4. App-server fixture tests

Create a fake JSON-RPC child process that returns:

- identity success;
- identity mismatch;
- weekly rate-limit success;
- response with both `primary` and `secondary`;
- response with `primary` only;
- malformed JSON;
- process exit;
- request timeout.

Assert that the client does not retry and does not convert a short-duration window into weekly Usage.

## 5. UI tests

Verify:

- current row is highlighted;
- no checkmark or `Current` label exists;
- reset text is on the name line;
- progress-bar accessibility value equals `NN% left`;
- footer contains equal-width Manage Accounts, Settings, and Quit actions;
- Manage Accounts and Settings navigate inside the popover;
- reopening after closing a secondary page starts on the account list;
- Settings contains Launch at Login, Show Percentage in Menu Bar, and Language;
- Login Item status maps `notRegistered`, `enabled`, `requiresApproval`, and `notFound` to disabled, enabled, approval-required, and unavailable UI states;
- both Settings toggles expose localized accessibility labels;
- switch confirmation describes Desktop and CLI consequences;
- canceling switch or removal keeps the popover open and performs no mutation;
- account rows display cached Usage while refresh runs;
- a short-interval timer test proves that a manual refresh postpones the previous deadline and cancellation stops later rounds;
- active profile remove button is disabled;
- no 5-hour control or text exists.

## 6. Manual test matrix

With the packaged application:

1. open Settings and enable Launch at Login;
2. confirm `sfltool dumpbtm` contains `com.liuzhao.codex-account-switcher`;
3. if macOS reports approval required, use the displayed System Settings link, approve the item, and confirm the Toggle becomes enabled after reopening Settings;
4. quit the app, sign out and back in, and confirm the menu-bar item appears automatically;
5. disable Launch at Login and confirm the system registration is removed.

With two real test accounts:

1. add Account A;
2. add Account B;
3. open menu and confirm weekly Usage for both;
4. start a Codex CLI under A;
5. switch A → B;
6. with an active local chat, confirm the switcher closes Desktop without visual automation or manual interaction;
7. confirm Desktop reopens as B without manual confirmation or restart;
8. confirm the existing CLI was not terminated;
9. start a new CLI and confirm it uses B;
10. switch B → A;
11. disconnect network and confirm cached Usage remains visible with a warning;
12. remove the cache, disconnect network, and confirm Usage unavailable appears;
13. close the popover, wait five minutes, and confirm `usage-cache.json` receives a newer successful value;
14. force identity mismatch and confirm the original `auth.json` is restored while the mismatch remains visible;
15. make `accounts.json` unwritable and confirm the original `auth.json` is restored while the state-write failure remains visible;
16. make restoration fail and confirm both errors are shown.

## 7. Repository checks

Before release:

```text
only main branch remains
no 5-hour UI strings
only the bounded verification/commit credential restoration exists
no general rollback state machine
no credential backup file
no transaction journal
no Keychain implementation
launch-at-login state comes from macOS Service Management
no account-rename UI or model operation
```
