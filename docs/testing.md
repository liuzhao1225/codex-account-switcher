# Testing

## 1. Philosophy

The MVP test suite should prove two things:

1. the direct happy path works;
2. failures stop exactly where they occur and remain visible while bounded credential and provider restoration preserves account consistency.

It should test the documented verification/commit restoration and confirm that no general rollback state machine, retry, credential backup file, journal, or startup recovery exists.

### Local toolchains

Xcode and GitHub-hosted macOS runners use SwiftPM's normal `Testing` module discovery. Some standalone Command Line Tools distributions place `Testing.framework` and `lib_TestingInterop.dylib` outside SwiftPM's default search paths. For that CLT layout, `Package.swift` derives the selected toolchain root from `xcrun --find swift` and adds only the required framework and runtime search paths when both files exist. The repository contains no fixed developer-directory path.

## 2. Unit tests

### 2.1 Usage windows

Test:

- `used=0` → `100% left`;
- `used=24` → `76% left`;
- `used=58` → `42% left`;
- `used=100` → `0% left`;
- values below 0 and above 100 are clamped;
- a six-to-eight-day window is selected from either `primary` or `secondary` buckets;
- exactly 300 minutes is accepted as the optional 5-hour window;
- 4-hour and 6-hour windows are not labeled as 5-hour Usage;
- absence of a six-to-eight-day window returns `Usage unavailable`;
- absence of a 5-hour window preserves valid weekly Usage;
- weekly-only cache entries from older versions still decode.

### 2.2 Profile repository

Test:

- load empty repository;
- create profile;
- save active credential into profile;
- activate profile credential;
- delete inactive profile;
- reject deleting active profile;
- persist normalized Usage with mode `0600`;
- load old settings without `showsFiveHourUsage` as false and persist later changes;
- remove cached Usage with its inactive profile;
- surface read, write, atomic replacement, and delete errors.

### 2.3 Identity matching

Test:

- matching account IDs succeed;
- differing account IDs fail;
- normalized matching emails succeed when account ID is unavailable;
- differing emails fail;
- missing ID and email fails.

### 2.4 Provider configuration

Test:

- custom provider identifiers and configured names are read from `config/read`;
- missing provider names receive a readable label derived from the identifier;
- the built-in `openai` provider is not duplicated in the custom-provider list;
- unknown providers are rejected before a write;
- `config/value/write` changes only `model_provider` and the result is verified with a fresh read.

## 3. Switch-flow tests

Use fakes for Desktop, account storage, and Codex identity.

Expected call order:

```text
closeDesktop
saveCurrent
activateTarget
activateOpenAIProvider
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
- provider activation failure restores both the original credential and provider;
- configured-provider switching runs close, activate, and reopen in order;
- a provider write followed by verification failure restores the original provider.

Use both the fake store and the real `AccountStore` so call ordering, atomic credential installation, registry-write failure, and on-disk bytes are covered.

## 4. App-server fixture tests

Create a fake JSON-RPC child process that returns:

- identity success;
- identity mismatch;
- 5-hour and weekly rate-limit success from one response;
- response with both `primary` and `secondary`;
- response with `primary` only;
- malformed JSON;
- process exit;
- request timeout.

Assert that the client does not retry, makes one rate-limit request per read, and does not convert one duration into another Usage window.

## 5. UI tests

Verify:

- current row is highlighted;
- configured providers appear in a separate section and expose selected state;
- no checkmark or `Current` label exists;
- reset text remains on the name line in the default compact layout;
- enabled 5-hour display shows separate 5h and 7d rows with percentages and reset times;
- enabled 5-hour display omits the 5h row when data is absent;
- English and Simplified Chinese Usage labels remain fully visible;
- progress-bar accessibility value equals `NN% left`;
- footer contains equal-width Manage Accounts, Settings, and Quit actions;
- Manage Accounts and Settings navigate inside the popover;
- reopening after closing a secondary page starts on the account list;
- Settings contains Launch at Login, Show Percentage in Menu Bar, Show 5-hour Usage, and Language in that order;
- Login Item status maps `notRegistered`, `enabled`, `requiresApproval`, and `notFound` to disabled, enabled, approval-required, and unavailable UI states;
- all three Settings toggles expose localized accessibility labels;
- switch confirmation describes Desktop and CLI consequences;
- canceling switch or removal keeps the popover open and performs no mutation;
- closing the browser during Add Account leaves the rest of the popover interactive, and Cancel Adding Account stops the pending login;
- account rows display cached Usage while refresh runs;
- a short-interval timer test proves that a manual refresh postpones the previous deadline and cancellation stops later rounds;
- active profile remove button is disabled;
- disabling Show 5-hour Usage restores the existing weekly row layout;
- the menu-bar percentage remains weekly when 5-hour display is enabled;
- the menu-bar percentage is hidden while a custom provider is active;
- provider confirmation explains that existing conversations keep their original provider.

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
3. open menu and confirm the existing weekly layout for both;
4. enable Show 5-hour Usage and confirm available 5h and 7d rows, then verify an account without 5-hour data omits only the 5h row;
5. confirm the menu-bar percentage still matches weekly Usage;
6. start a Codex CLI under A;
7. switch A → B;
8. with an active local chat, confirm the switcher closes Desktop without visual automation or manual interaction;
9. confirm Desktop reopens as B without manual confirmation or restart;
10. confirm the existing CLI was not terminated;
11. start a new CLI and confirm it uses B;
12. switch B → A;
13. disconnect network and confirm cached Usage remains visible with a warning;
14. remove the cache, disconnect network, and confirm Usage unavailable appears;
15. close the popover, wait five minutes, and confirm `usage-cache.json` receives a newer successful value;
16. force identity mismatch and confirm the original `auth.json` is restored while the mismatch remains visible;
17. make `accounts.json` unwritable and confirm the original `auth.json` is restored while the state-write failure remains visible;
18. make restoration fail and confirm both errors are shown.
19. configure a custom provider, confirm it appears by configured name, and switch to it;
20. confirm only `model_provider` changes and the provider's credential configuration is untouched;
21. confirm a new conversation uses the selected provider and an existing conversation remains on its original provider;
22. select a saved ChatGPT account and confirm the built-in `openai` provider is restored before identity verification.

## 7. Repository checks

Before release:

```text
only main branch remains
5-hour Usage defaults off and affects account rows only
4-hour and 6-hour windows are never labeled as 5-hour Usage
only the bounded verification/commit credential restoration exists
no general rollback state machine
no credential backup file
no transaction journal
no Keychain implementation
launch-at-login state comes from macOS Service Management
no account-rename UI or model operation
```

## 8. Release automation checks

The release workflow runs only on `v*` tag pushes under one repository-wide release concurrency group. Static validation should confirm:

- ordinary `main` pushes do not start the release workflow and the workflow never creates or pushes a tag;
- `CITATION.cff`, the package default, and CodexClient declare the same semantic version;
- the derived `RELEASE_TAG` identifies the GitHub Release, while the DMG and checksum use fixed asset names compatible with `releases/latest/download/...`;
- tag events require the event tag, repository version, checked-out commit, and `origin/main` commit to match;
- an existing GitHub Release sets `SHOULD_RELEASE=false` and all tests, signing, notarization, packaging, and publication steps skip successfully;
- a missing Release sets `SHOULD_RELEASE=true`, then the tag workflow runs tests, signing, notarization, packaging, checksum generation, and `gh release create --latest --verify-tag`;
- conflicting tags and API failures stop with the original values visible.
