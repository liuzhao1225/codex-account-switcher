# Testing

## Unified Swift Test Suite

All Swift unit and integration tests live in `Tests/`:

- `Tests/SwitcherCoreTests/` — Shared core tests covering `AccountController`, `AccountStore` / credential sync, `SwitchService`, `CodexClientTransportTests` (process reuse, concurrency, idle expiry, timeouts, cancellation, credential replacement), `LiveSubscriptionTests` (JWT snapshots, HTTP transport validation, 401 inactive renewal & backoff, npm wrapper unwrapping), `AutoResetTests`, `WeeklyUsageNormalizerTests`, and `WindowsProfileRemovalTests` (on Windows).
- `Tests/CodexAccountSwitcherTests/` — macOS client tests covering `CodexClient`, `CodexExecutableLocator` (POSIX + `fish` login shells), `MenuBarPopover` / `ManageAccountsView` height bounds, `DesktopController`, `AppUpdater`, and `LaunchAtLoginState`.

Run the full Swift suite locally (supports both full Xcode and macOS Command Line Tools):

```bash
./scripts/run-tests.sh
```

`CodexClientTransportTests` automatically materializes a local Python JSON-RPC fixture on POSIX when `SWITCHER_TEST_RPC_EXE` is unset, and uses the compiled `CodexAccountSwitcher.Checks.exe` fixture on Windows CI.

## Release & Site Script Tests

```bash
node --test scripts/tests/*.test.mjs
```

## Windows Native & UI Checks

Executed in `.github/workflows/windows.yml` on `windows-latest`:

- `CodexAccountSwitcher.Checks` — Process-tree termination/isolation (`desktop-close`) and `CoreClient` ↔ `SwitcherHost.exe` stdio/ACL roundtrips.
- `CodexAccountSwitcher.UiChecks` — Headless WPF rendering, navigation, settings bindings, drag-and-drop wiring, and tray icon checks.
- Packaged `--self-test` — Runs the self-contained single-file EXE in a stripped `PATH` without `.NET` or Swift SDKs installed.
