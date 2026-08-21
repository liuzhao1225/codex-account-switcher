# Documentation

Codex Account Switcher Lite has one job: let a user see weekly account usage and switch the account used by new Codex Desktop and CLI processes.

The project intentionally prefers a short, inspectable implementation over a defensive account-management platform.

## Documents

| Document | Purpose |
| --- | --- |
| [Product decisions](product-decisions.md) | Final interaction and scope decisions. |
| [Product requirements](product-requirements.md) | User flows, UI rules, acceptance criteria, and non-goals. |
| [System design](system-design.md) | Native macOS architecture, storage, switching, login, weekly Usage, and errors. |
| [Testing and release](testing-and-release.md) | Small test suite and direct release process. |
| [ADR 0001](adr/0001-direct-mvp-switching.md) | Why the MVP deliberately has no rollback or fallback machinery. |

## Non-negotiable constraints

1. **Weekly Usage only.** Never show the 5-hour window, even when the backend returns it.
2. **One direct switch path.** Save current auth, activate selected auth, record the selected profile, reopen Desktop.
3. **No hidden recovery.** No retries, stale-value fallback, automatic rollback, transaction journal, or silent repair.
4. **Errors remain visible.** The operation stops and the original error is shown.
5. **Settings stays small.** It contains language selection and nothing related to switching semantics or credential storage.

## MVP implementation target

- macOS 14+
- Swift 6
- SwiftUI `MenuBarExtra`
- AppKit only where process control or alerts require it
- Foundation `FileManager` and `URLSession`
- No Electron, local HTTP server, daemon, database, reverse proxy, or third-party dependency
