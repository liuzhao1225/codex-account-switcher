# PR #53 audit validation — 2026-11-16

Reviewed the supplied audit against PR head 78f77a2 and checked its proposed changes against the owning code. The report is review input; its proposed patch was not applied wholesale. In particular, its cancellation patch still throws a cleanup error before checking cancellation, and its diff does not implement the credential-sync or worker-eviction fixes it claims to cover.

| Finding | Assessment and final change |
| --- | --- |
| P1: failed stop cached forever | Valid conditional recovery bug. Termination attempts are coalesced while in progress; failed attempts can be retried, and a late process exit is recognized. The worker stays unusable for credential mutation until exit is confirmed. Tests simulate a failed stop followed by late exit and by a successful retry; an actual OS/antivirus-induced stall was not reproduced. |
| P2: credentials replaced during startup/read | Valid. A session retains the pre-request credential snapshot, rather than adopting arbitrary new disk bytes after a response. Replacement during initialization or quota RPC forces reconnection on the next read. The conservative behavior also reconnects if Codex itself rewrites the file. |
| P3: unordered background teardown | Valid. Shutdown cancels and drains the captured usage/subscription tasks. A retained teardown barrier orders later refreshes after cleanup. Tests cover stopping a blocked read and starting a manual refresh while cleanup is blocked. |
| P4: sync writes while a resident reader is running | Valid. The store identifies a changed matching profile, waits for its reader to stop, then rechecks the live login before writing. Unchanged credentials preserve warm sessions. Failed cleanup preserves saved bytes. A test changes the live login while the stop callback is suspended to verify revalidation. |
| P5: cancellation/error identity and late checks | Cleanup masking cancellation is valid. Cancellation now remains CancellationError even if cleanup fails; the retained session still blocks unsafe mutations. The post-response cancellation check was a conservative performance choice rather than proof of corrupt state; it was removed so a completed RPC need not discard a healthy session. Cancellation racing an outstanding RPC still stops that process. |
| P6: global teardown for profile operations | Valid isolation/performance concern. Renewal and reset consumption execute under the target profile's serialized queue with its warm session stopped. Concurrent quota reads cannot reopen that profile during the mutation; sibling sessions stay warm. Full shutdown attempts all workers concurrently and collects errors after every attempt, rather than aborting at the first failure. |
| P7: fixture whitespace and registry retention | Defensive fixture improvement and minor retention issue. Existing fixture writers used newline-free modes; trimming now also accepts CRLF. Deleted profiles explicitly retire and evict their workers. Retirement prevents an already-issued worker reference from reopening a deleted profile. This was actor-entry retention, not evidence of an indefinitely running child process. |

## Validation

- Final complete Swift suite with the offline RPC executable enabled: **99 tests in 10 suites passed**.
- Windows fixture build: zero warnings and errors.
- Windows interface checks and native/shared-core integration checks passed.
- Regressions retain the original process-reuse, account isolation, cancellation, timeout, crash recovery and idle-expiry coverage, and add the audit scenarios above.
- The earlier 500 ms quota-timeout fixture could expire before its process logged startup under concurrent test load. Its quota timeout now allows two seconds; the CRLF fixture mode verifies trimming while preserving the intended timeout/recovery assertions.
- Changed-line whitespace checks passed.

macOS build/runtime execution and authenticated before/after network-byte measurements remain unverified on this Windows machine. No GB/day saving or real-world delayed-process-termination reproduction is claimed. Stop-all failure aggregation is implemented by an all-results task group; an OS-level failure for one member of a real process batch was not injected.
