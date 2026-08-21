# System design

## 1. Design statement

Codex Account Switcher Lite is a single-process native macOS utility.

Its implementation strategy is intentionally direct:

- save each account as an `auth.json` snapshot;
- copy the selected snapshot into the normal `~/.codex/auth.json` location;
- reopen Codex Desktop;
- read and display only the weekly Usage window;
- stop and display the original error when an operation fails.

The design does not include rollback, retries, failover, stale-value fallback, transaction journaling, credential abstraction layers, or a recovery daemon.

## 2. Platform and technology

### 2.1 Target

- macOS 14 or later
- Apple silicon and Intel
- Swift 6
- SwiftUI application lifecycle
- `MenuBarExtra` presentation

### 2.2 Frameworks

| Framework | Use |
| --- | --- |
| SwiftUI | Menu, Manage Accounts, Settings, confirmations, error presentation. |
| AppKit | Find, terminate, force-terminate, and launch Codex Desktop. |
| Foundation | File IO, JSON metadata, JWT payload decoding, HTTP requests, dates. |
| OSLog | Local debug logging. |

### 2.3 Explicitly excluded dependencies

- Electron;
- browser runtime;
- local web server;
- SQLite;
- third-party networking;
- third-party Keychain wrapper;
- daemon or privileged helper;
- reverse proxy;
- embedded Codex fork.

## 3. Runtime architecture

```text
┌──────────────────────────────────────────────────────────┐
│ Codex Account Switcher Lite                              │
│                                                          │
│  ┌──────────────┐    ┌────────────────────────────────┐  │
│  │ SwiftUI UI   │───▶│ AppModel                       │  │
│  │ MenuBarExtra │    │ selected account + UI state    │  │
│  └──────────────┘    └──────┬──────────┬──────────────┘  │
│                              │          │                 │
│                      ┌───────▼───┐  ┌──▼──────────────┐  │
│                      │AccountStore│  │UsageService     │  │
│                      │JSON + files│  │weekly only      │  │
│                      └───────┬───┘  └──┬──────────────┘  │
│                              │          │                 │
│                      ┌───────▼──────────▼──────────────┐  │
│                      │ SwitchService / AddAccountFlow  │  │
│                      └──────────────┬──────────────────┘  │
└─────────────────────────────────────┼────────────────────┘
                                      │
                 ┌────────────────────┼────────────────────┐
                 │                    │                    │
       ~/.codex/auth.json      Saved snapshots      Codex Desktop
```

There is one application process and one serialized switch operation at a time.

## 4. Source layout

```text
CodexAccountSwitcherLite/
├── App/
│   ├── CodexAccountSwitcherLiteApp.swift
│   └── AppModel.swift
├── Models/
│   ├── AccountProfile.swift
│   ├── WeeklyUsage.swift
│   └── AppSettings.swift
├── Services/
│   ├── AccountStore.swift
│   ├── SwitchService.swift
│   ├── AddAccountService.swift
│   ├── UsageService.swift
│   └── CodexDesktopController.swift
├── Views/
│   ├── AccountMenuView.swift
│   ├── AccountRowView.swift
│   ├── SwitchConfirmationView.swift
│   ├── ManageAccountsView.swift
│   ├── AddAccountView.swift
│   └── SettingsView.swift
└── Resources/
    ├── Localizable.xcstrings
    └── Assets.xcassets
```

This is a suggested source layout, not a framework boundary. Avoid protocol-heavy abstractions until a second implementation is actually needed.

## 5. Persistent data

### 5.1 Paths

```text
~/.codex/auth.json

~/Library/Application Support/Codex Account Switcher Lite/
├── accounts.json
├── settings.json
└── accounts/
    ├── <profile-id>/auth.json
    ├── <profile-id>/auth.json
    └── ...
```

The switcher does not copy the rest of `~/.codex`. Configuration, projects, skills, MCP configuration, and local thread history remain shared.

### 5.2 Account metadata

```swift
struct AccountProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var displayName: String
    var email: String?
    var chatGPTAccountID: String?
    var createdAt: Date
    var lastSelectedAt: Date?
}
```

`auth.json` is not embedded inside `accounts.json`. Keeping it as a separate file makes the switch operation a simple file read and write.

### 5.3 Account index

```swift
struct AccountIndex: Codable {
    var version: Int = 1
    var activeAccountID: UUID?
    var accounts: [AccountProfile]
}
```

`activeAccountID` is switcher metadata. It is not proof of the account currently loaded by a running Codex process.

### 5.4 Settings

```swift
struct AppSettings: Codable {
    var language: AppLanguage = .system
}
```

No launch-at-login, retry, restart, Usage-window, credential-store, or recovery setting is modeled.

## 6. Credential snapshot handling

### 6.1 Assumption

The MVP targets the normal Codex file-backed authentication layout at:

```text
$CODEX_HOME/auth.json
```

For the default configuration, `CODEX_HOME` is `~/.codex`.

The snapshot is treated as opaque JSON for switching. The switcher does not rewrite token fields.

### 6.2 Metadata extraction

For display purposes, the switcher may decode the JWT payload stored in the snapshot and read claims such as:

- email;
- ChatGPT user ID;
- ChatGPT account ID;
- plan type.

The payload is decoded without signature verification because it is only local display metadata. The auth file itself remains the source used by Codex.

Failure to extract metadata does not invalidate the snapshot. The account can still be shown under its local display name.

### 6.3 File permissions

The application creates its Application Support directory for the current user and writes snapshots as user-readable files.

The MVP does not add a Keychain storage mode or Keychain status UI.

## 7. Direct switch sequence

### 7.1 Public API

```swift
@MainActor
final class SwitchService {
    func switchAccount(to target: AccountProfile) async throws
}
```

### 7.2 Sequence

```text
User confirms
    │
    ▼
Set isSwitching = true
    │
    ▼
Terminate Codex Desktop if running
    │
    ▼
If activeAccountID and ~/.codex/auth.json exist:
copy active auth over that profile's saved auth.json
    │
    ▼
Read target profile auth.json
    │
    ▼
Write bytes to ~/.codex/auth.json
    │
    ▼
Set activeAccountID = target.id
Set target.lastSelectedAt = now
Persist accounts.json
    │
    ▼
Launch Codex Desktop
    │
    ▼
Set isSwitching = false
Refresh weekly Usage
```

### 7.3 Reference implementation

```swift
func switchAccount(to target: AccountProfile) async throws {
    guard !isSwitching else { return }
    isSwitching = true
    defer { isSwitching = false }

    try await desktopController.stopCodexDesktop()

    if let currentID = accountStore.index.activeAccountID,
       fileManager.fileExists(atPath: paths.activeAuth.path) {
        let currentData = try Data(contentsOf: paths.activeAuth)
        try currentData.write(
            to: paths.savedAuth(for: currentID),
            options: .atomic
        )
    }

    let targetData = try Data(contentsOf: paths.savedAuth(for: target.id))
    try targetData.write(to: paths.activeAuth, options: .atomic)

    try accountStore.markActive(target.id)
    try await desktopController.launchCodexDesktop()
}
```

`.atomic` is retained as the ordinary file-write primitive so a single JSON write is not partially visible. It is not a rollback strategy. If a later step fails, the application does not restore the previous account.

### 7.4 No verification gate

After writing the target auth file, the MVP does not start a second Codex process to verify account identity before proceeding.

Codex Desktop itself is the visible result. If it opens logged out, opens the wrong account, or reports expired credentials, that state is shown to the user rather than hidden behind repair logic.

### 7.5 Process behavior

`CodexDesktopController` finds the installed application in this order:

```text
/Applications/Codex.app
~/Applications/Codex.app
/Applications/ChatGPT.app
~/Applications/ChatGPT.app
```

The final bundle identifiers and executable names must be confirmed during implementation.

Stopping behavior:

1. call `terminate()` on matching running applications;
2. wait a short fixed interval;
3. call `forceTerminate()` on any matching process still running;
4. continue or throw the returned system error.

There is no user-configurable graceful-shutdown timeout.

Launching uses `NSWorkspace.shared.openApplication` with the resolved app URL.

### 7.6 CLI semantics

Already running CLI processes may have loaded credentials into memory. The switcher does not inspect, signal, or restart them.

Therefore:

- existing CLI processes keep their current behavior;
- new CLI processes read the newly written auth file;
- the confirmation sheet explains this distinction.

## 8. Add-account flow

### 8.1 State machine

```text
idle
  └─ start
      ├─ save-current
      ├─ stop-desktop
      ├─ remove-active-auth
      ├─ launch-desktop
      ├─ waiting-for-auth
      ├─ naming-profile
      └─ saved
```

The state machine is UI state only. It is not persisted as a recovery journal.

### 8.2 Sequence

```swift
func beginAddAccount() async throws {
    try saveCurrentProfileIfKnown()
    try await desktopController.stopCodexDesktop()
    try fileManager.removeItemIfExists(at: paths.activeAuth)
    try await desktopController.launchCodexDesktop()
    await waitForNewAuthFile()
}
```

The service records the auth file's absence or modification date, then observes the parent directory using a `DispatchSourceFileSystemObject` or performs a simple foreground poll while the Add Account sheet remains open.

When a new non-empty file appears:

1. read it;
2. extract optional metadata;
3. ask for a display name;
4. write it to a new profile directory;
5. append metadata to `accounts.json`;
6. set the new profile as selected.

### 8.3 Cancellation

Canceling the Add Account sheet stops observation.

It does not restore the deleted active auth file and does not reopen a prior account automatically. The user can select a saved profile from the main menu.

## 9. Remove-account flow

```swift
func removeAccount(id: UUID) throws {
    try fileManager.removeItem(at: paths.profileDirectory(id))
    accountStore.removeMetadata(id: id)
    try accountStore.save()
}
```

If the removed account is selected, `activeAccountID` becomes `nil`.

The active `~/.codex/auth.json` is not changed. This distinction must appear in confirmation copy.

No server-side token revocation occurs.

## 10. Weekly Usage service

### 10.1 Endpoint

The MVP reads Usage directly with the credentials contained in each saved snapshot.

The current Codex implementation requests:

```text
GET https://chatgpt.com/backend-api/api/codex/usage
Authorization: Bearer <access token>
ChatGPT-Account-ID: <account id>
```

This is an implementation dependency on Codex's current backend contract. The MVP accepts that coupling instead of introducing an app-server subprocess or protocol abstraction.

### 10.2 Request model

```swift
struct UsageCredentials {
    let accessToken: String
    let accountID: String
}
```

If either field cannot be extracted, the account returns `Usage unavailable`.

### 10.3 Relevant response fields

The service only needs:

```json
{
  "rate_limit": {
    "primary_window": {
      "used_percent": 58,
      "limit_window_seconds": 18000,
      "reset_at": 1787284800
    },
    "secondary_window": {
      "used_percent": 58,
      "limit_window_seconds": 604800,
      "reset_at": 1787716800
    }
  }
}
```

Field names should be decoded with optional values so an unfamiliar response produces a visible unavailable state instead of a crash in the menu.

### 10.4 Weekly selection algorithm

```swift
func selectWeeklyWindow(_ windows: [RateLimitWindow]) -> RateLimitWindow? {
    let oneWeek = 7 * 24 * 60 * 60
    let minimum = 6 * 24 * 60 * 60
    let maximum = 8 * 24 * 60 * 60

    return windows
        .filter { minimum...maximum ~= $0.durationSeconds }
        .min { lhs, rhs in
            abs(lhs.durationSeconds - oneWeek) <
            abs(rhs.durationSeconds - oneWeek)
        }
}
```

Important:

- Do not choose the primary window merely because it exists.
- Do not choose the longest arbitrary window when no weekly candidate exists.
- Do not expose a 5-hour window in the model returned to the UI.
- Do not add a 5-hour label, bar, tooltip, detail sheet, or preference.

### 10.5 UI model

```swift
struct WeeklyUsage: Equatable {
    let remainingPercent: Int
    let resetsAt: Date
}
```

Calculation:

```swift
let remaining = min(100, max(0, 100 - usedPercent))
```

`AccountRowView` receives only `WeeklyUsage?`. It cannot render a second window because no second-window type crosses the service boundary.

### 10.6 Refresh and errors

The service fetches each account once when the menu opens.

There is:

- no automatic retry;
- no exponential backoff;
- no persisted Usage cache;
- no stale-data fallback;
- no substitution of the 5-hour window.

Error mapping:

| Condition | Row state |
| --- | --- |
| 200 with weekly window | Progress bar, percent left, reset time. |
| 200 without weekly window | `Usage unavailable`. |
| 401 or 403 | `Sign in again`. |
| Network or decode error | `Usage unavailable`; info button exposes error text. |

The main menu remains usable when Usage requests fail.

## 11. App state

```swift
@MainActor
final class AppModel: ObservableObject {
    @Published var accounts: [AccountProfile] = []
    @Published var activeAccountID: UUID?
    @Published var weeklyUsage: [UUID: Result<WeeklyUsage, UsageError>] = [:]
    @Published var isSwitching = false
    @Published var presentedError: PresentedError?
    @Published var settings = AppSettings()
}
```

`isSwitching` prevents a double click from running two file-copy sequences simultaneously. It is not a user-facing safety workflow.

## 12. Error handling philosophy

### 12.1 Rule

A failed operation returns its error to the UI.

Do not add code that silently:

- retries;
- restores a previous file;
- reads from an alternate store;
- uses stale Usage;
- changes the requested target;
- reports partial success as success.

### 12.2 Error presentation

```swift
struct PresentedError: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let operation: String
    let underlyingDescription: String
}
```

Example alert:

```text
Could not switch account

Writing active Codex credentials failed.

/Users/me/.codex/auth.json: Permission denied
```

The alert does not prescribe a fake recovery action. It offers `OK` and, where useful, `Reveal in Finder`.

### 12.3 Logging

Use `Logger` categories:

```text
app
accounts
switch
usage
process
```

Never print token values. Log file paths, profile IDs, HTTP status codes, and error descriptions.

## 13. Concurrency

- UI mutations occur on `MainActor`.
- One `SwitchService` call runs at a time.
- Usage requests use a task group and may run concurrently.
- Add Account observation exists only while its sheet is open.
- There is no background worker after the app exits.

## 14. Localization design

Use String Catalogs.

```text
Localizable.xcstrings
```

The saved setting chooses one of:

```swift
enum AppLanguage: String, Codable, CaseIterable {
    case system
    case english
    case simplifiedChinese
}
```

Apply the selected locale to the root SwiftUI scene. Account names and raw system errors remain unchanged.

## 15. Implementation milestones

### Milestone 1: static native shell

- MenuBarExtra;
- account rows matching prototype;
- selected-row highlight;
- Manage Accounts and Settings navigation;
- language selector.

### Milestone 2: local profiles

- account metadata JSON;
- auth snapshot directories;
- import the currently active auth as the first profile;
- rename and remove.

### Milestone 3: direct switch

- Desktop process control;
- save current snapshot;
- write selected auth;
- update selected profile;
- reopen Desktop;
- explicit errors.

### Milestone 4: add account

- clear active auth;
- reopen Desktop login;
- observe new auth file;
- save and name new profile.

### Milestone 5: weekly Usage

- extract request credentials;
- request Codex Usage;
- select only 6–8 day windows;
- render remaining percentage and reset time;
- ignore 5-hour windows.

### Milestone 6: packaging

- app icon;
- Developer ID signing;
- notarization;
- DMG or ZIP release;
- concise installation instructions.

## 16. Open implementation facts to verify

These are implementation checks, not product decisions:

- final Codex Desktop bundle identifier and installed path;
- exact current token field locations inside `auth.json`;
- whether Desktop writes refreshed credentials before termination completes;
- exact usage response field names in the installed Codex version;
- sandbox entitlements needed for user-home file access in the chosen distribution model.

When any assumption is wrong, the implementation should fail visibly during development and be corrected directly. It should not accumulate compatibility branches before there is a demonstrated need.

## 17. Upstream references

The design is based on the current OpenAI Codex repository structure:

- `codex-rs/config/defaults.toml` — packaged clients default to file-backed CLI auth;
- `codex-rs/login/src/auth/storage.rs` — `$CODEX_HOME/auth.json` structure and storage;
- `codex-rs/app-server/tests/suite/v2/rate_limits.rs` — Codex Usage request and rate-limit window fields;
- `codex-rs/app-server-protocol/src/protocol/v2/account.rs` — rate-limit response models.

Pin source links to a known Codex commit when implementation begins so tests describe one concrete upstream version.
