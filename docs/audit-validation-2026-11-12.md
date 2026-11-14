# Audit report validation (2026-11-12)

This checks `codex_account_switcher_audit_report.md` against the local `codex/api-key-profiles-native-ui` checkout at `36bf980`, with pre-existing uncommitted edits preserved. The report describes `main` at `1f2deac`; its line numbers and several claims are from an older revision.

| Finding | Current assessment | Action |
| --- | --- | --- |
| BUG-01, BUG-02 | Already fixed. The Windows atomic writer uses a GUID temporary name, loops over partial writes, checks flush and close results, and commits the private-ACL file with `MoveFileExW`. | No further change. |
| BUG-03 | Confirmed. Process exit and access errors could escape during parent/child inspection. | Handle exit races and fail safely when a live process cannot be inspected. |
| BUG-04 | Confirmed for the `MainModule` fallback. | Use `QueryFullProcessImageNameW` with limited query access, including for AUMID lookup. |
| BUG-05 | Confirmed for stdout; stderr already clears its handler. | Clear the stdout readability handler on EOF. |
| BUG-06 | Confirmed. Disposal could race a write and an exited host could leave a request pending. | Serialize input close with writes, reject writes during disposal, cancel pending waits on reader exit, and add a host-exit check. |
| BUG-07 | Confirmed for switch and remove. Other account mutations already check `isAddingAccount`. | Guard switch and remove during OAuth add. |
| OPT-01 | Repeated PowerShell discovery is real, but the proposed cache breaks the existing Store-update behavior covered by `DesktopCloseChecks`: a package path can change between close and reopen. | Retain fresh discovery for both operations. |
| OPT-02 | Confirmed. Snapshots were encoded, parsed, and encoded again, often repeatedly in one actor turn. | Encode a typed message once and coalesce notifications scheduled in the same actor turn. |
| OPT-03 | Repeated runtime verification is real, but a `.verified` marker would skip the current file-content integrity check and permit a modified cached host to execute. | Retain verification; do not introduce a trust marker. |
| OPT-04 | Usage-cache write amplification was confirmed and fixed with one batched write per refresh. The reset log is already JSON Lines and append-only, contrary to the report; its full history is used for reset idempotency across restarts. | Retain the log format and history. |
| OPT-05 | The package is explicitly named and published as `@liuzhao1225/codex-account-switcher`; its upstream release route matches that package identity. | Do not redirect the published installer to fork releases. |

## Verification

- .NET Windows app and checks projects: built with 0 warnings and 0 errors using the workspace private .NET SDK.
- Host-exit check: passed; a stopped host fails a pending command promptly.
- Swift frontend parse of the changed sources: passed.
- `git diff --check`: passed.
- `swift test`: did not run; the Windows Swift tool exited with status `-1073741795` before diagnostics.
- Full desktop-close check: blocked by `Get-AppxPackage` returning `Access is denied` in this environment.
- Fixture-only desktop-close check: blocked by Windows rejecting the temporary `ChatGPT.exe` launch with Win32 error 1223.

The Swift changes therefore still need a full Swift build and test run in a working toolchain. The desktop-close behavior needs an unrestricted Windows test environment.

## Follow-up validation (2026-11-13)

The revised attached report uses IDs B1-B7 and O1-O4 and includes proposed patches. Its claims still refer to the older revision, and several patches reference functions and model fields absent from this checkout. B1-B7, O2, and usage-cache batching are already addressed at `2e567cd`; the reset log is already append-only. The report's latency savings are estimates, not measurements reproduced here.

O3 received a further improvement: runtime verification now hashes streams rather than allocating whole byte arrays for each installed DLL and copying the ZIP payload for hashing. Healthy cached entries are verified without building decompressed byte arrays; missing or modified entries are restored. Content verification remains mandatory. O1's proposed cache still conflicts with package changes between close and reopen, so fresh discovery remains in place. Arbitrarily truncating reset history could remove idempotency records, so the proposed fixed-count pruning was not applied.

Validation on the working tree based on `2e567cd`, including its pre-existing local edits, succeeded outside the restricted sandbox:

- Swift build and test run: 78 tests reported passed; the Windows-disabled `CodexClientTransportTests` suite was skipped.
- Isolated Windows desktop fixture checks: passed, including version rediscovery, graceful close, rejection of unsafe closes, and cancellation.
- Freshly built Swift host with Windows integration checks: passed for IPC, shared snapshots/localization, settings persistence, private ACLs, and restart persistence.
- Runtime cache regression check: passed for warm reuse without rewriting, modified-host repair, and missing-library recovery.

These results supersede the earlier sandbox-blocked attempts. macOS-specific behavior and Windows-disabled transport tests remain unverified here. No account-switch latency benchmark was performed.
