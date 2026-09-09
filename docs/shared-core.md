# Shared core and native platform clients

This supersedes the initial Windows prototype's separate C# account implementation.

## Required design

- Reuse the existing Swift business implementation as a cross-platform `SwitcherCore` package target.
- Both clients share account models, persisted settings, localization, account lifecycle, Codex RPC, weekly/5-hour normalization, the ordered switch sequence, and bounded restoration.
- macOS keeps its SwiftUI menu-bar interface and Sparkle integration. Extracting its core is not a conversion of the Mac application to Windows.
- Windows uses a compact native tray flyout with the same pages and copy: accounts, account management, switch/remove confirmation, and settings. Use Windows fonts, icons, controls and light/dark colors; do not introduce a dashboard, marketing header, manual-refresh requirement, rename workflow, path-settings page, or separate modal account windows.
- User-provided screenshots in the Pictures directory are design references only. Do not copy their real account information into fixtures or repository assets.

## Boundaries

`SwitcherCore` owns policy and state. Platform adapters own filesystem permissions/atomic installation, executable discovery and launch, browser opening, Desktop close/open, tray integration, launch-at-login, and update installation. A Windows native client communicates with the Swift host through a private child-process stdio channel; it renders snapshots and invokes commands rather than reconstructing account policy in C#.

The Swift host exists only while the Windows UI is running. It is not a daemon or HTTP service. Credential contents never cross the UI protocol. The Windows EXE must bundle the host and its runtime dependencies so users do not install Swift separately.

## Parity acceptance

The same core tests must run on macOS and Windows. They must cover startup registration, explicit register/add/remove, automatic refresh and cache retention, identity checks, direct switch ordering, failure restoration, and cancellation. Native UI tests separately verify the reference's compact layout, full-row selection, active-row highlight without an extra label, in-place navigation/confirmation, immediate settings, and reopening on the account page.

Both clients now use `AccountController` and the shared account services. Windows no longer has its former C# account store, switch service or Codex RPC implementation. The compact native client receives shared snapshots through `SwitcherHost`.

The Windows package includes the Swift host/runtime and .NET runtime. Its isolated `--self-test` checks that no SDK installation is required. See `docs/windows-validation.md` for completed local checks and the macOS/real-account validation boundary.
