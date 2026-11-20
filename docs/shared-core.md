# Shared Core and Native Platform Clients

## Boundaries

- `SwitcherCore` owns account models, `SwitcherVersion.current`, persisted settings, localization (`L10n`), registry/credential sync (`AccountStore`), Codex JSON-RPC (`CodexClient`), live subscription queries (`LiveSubscriptionClient`), pre-expiry reset consumption (`AutoReset`), and the ordered switch sequence (`SwitchService`).
- macOS (`Sources/CodexAccountSwitcher`) observes `AccountController` via `AppModel` (`onWillChange` for SwiftUI `ObservableObject` updates and `onSettledChange` for Sparkle install deferral).
- Windows (`windows/CodexAccountSwitcher`) runs `SwitcherHost.exe` as a private child process over stdio JSON lines:
  - `AccountController` batches internal state mutations (`withBatchedUpdates`) so `SwitcherHost` emits one settled `AccountSnapshot` per logical state transition.
  - `SwitcherHost` encodes typed `Encodable` envelopes in a single `JSONEncoder` pass, transmitting the localization dictionary only on initialization and language changes (`CoreClient` retains the last dictionary across lightweight updates).
  - `HostRuntime` verifies a `.extracted` sentinel per SHA-256 runtime digest to avoid re-hashing DLLs on every startup and cleans up superseded runtime directories automatically.
  - Credentials and tokens never cross the UI snapshot protocol.
