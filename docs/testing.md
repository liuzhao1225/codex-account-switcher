# Testing

## 1. Philosophy

The MVP test suite should prove two things:

1. the direct happy path works;
2. failures stop exactly where they occur and remain visible.

It should not test rollback or recovery behavior because those features do not exist.

## 2. Unit tests

### 2.1 Weekly Usage

Test:

- `used=0` → `100% left`;
- `used=24` → `76% left`;
- `used=58` → `42% left`;
- `used=100` → `0% left`;
- values below 0 and above 100 are clamped;
- `secondary` is used;
- `primary` is ignored;
- missing `secondary` returns `Usage unavailable`;
- no product type or UI string contains `5-hour`.

### 2.2 Profile repository

Test:

- load empty repository;
- create profile;
- rename profile;
- save active credential into profile;
- activate profile credential;
- delete inactive profile;
- reject deleting active profile;
- surface read, write, rename, and delete errors.

### 2.3 Identity matching

Test:

- matching account IDs succeed;
- differing account IDs fail;
- normalized matching emails succeed when account ID is unavailable;
- differing emails fail;
- missing ID and email fails.

## 3. Switch-flow tests

Use fakes for Desktop, repository, Codex identity, and state store.

Expected call order:

```text
closeDesktop
saveCurrent
activateTarget
readActiveIdentity
saveActiveProfileID
openDesktop
```

Inject an error at each call and assert:

- the error reports the correct `SwitchStage`;
- no later call occurs;
- no rollback call occurs;
- no retry occurs;
- `isSwitching` returns to false after presentation.

Specific partial-state assertions:

- activation error leaves state metadata unchanged;
- verification error leaves the activated target file in place;
- state-write error may leave target auth active and old metadata present;
- Desktop-open error leaves target auth and target metadata active.

These assertions intentionally document visible partial completion rather than hiding it.

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

Assert that the client does not retry and does not convert `primary` into weekly Usage.

## 5. UI tests

Verify:

- current row is highlighted;
- no checkmark or `Current` label exists;
- reset text is on the name line;
- progress-bar accessibility value equals `NN% left`;
- footer contains only Manage Accounts and Settings;
- Settings contains only Language;
- switch confirmation describes Desktop and CLI consequences;
- active profile remove button is disabled;
- no 5-hour control or text exists.

## 6. Manual test matrix

With two real test accounts:

1. add Account A;
2. add Account B;
3. open menu and confirm weekly Usage for both;
4. start a Codex CLI under A;
5. switch A → B;
6. confirm Desktop reopens as B;
7. confirm the existing CLI was not terminated;
8. start a new CLI and confirm it uses B;
9. switch B → A;
10. disconnect network and confirm Usage displays an error without substituting another window;
11. force identity mismatch and confirm no rollback message appears;
12. make `state.json` unwritable and confirm the state-write failure is shown directly.

## 7. Repository checks

Before release:

```text
only main branch remains
no 5-hour UI strings
no rollback implementation
no transaction journal
no Keychain implementation
no launch-at-login setting
```
