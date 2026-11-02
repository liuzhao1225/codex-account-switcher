# Automatic reset before expiry

Settings includes **Use resets before expiry**, off by default. Enabling it applies to every saved account, including accounts that are not currently active in Codex. Each request uses that profile’s saved credentials without switching the active account. Expired credentials surface a read error.

The former log-only setting does not enable real consumption on upgrade. Enable the new `autoResetEnabled` setting explicitly. Historical `dry_run` records remain unchanged and never suppress a real checkpoint.

## Timing and consumption

The app reads usage at 10, 5 and 1 minute before each available `codexRateLimits` credit’s `expiresAt`, independently of the ordinary five-minute poll. It calls `account/rateLimitResetCredit/consume` with that exact `creditId` and a UUID `idempotencyKey` at the first eligible checkpoint. The protocol is generated from the installed Codex CLI with `codex app-server generate-ts`; no LLM request is involved.

- `reset`: the service reports consumption. The app reads usage again, checks that the credit is no longer available, updates the displayed/cache usage and logs the readback. It never attempts that credit again.
- `nothingToReset`: the service reports no reset was needed. The next scheduled checkpoint may try again; this result stays in the log.
- `noCredit` or `alreadyRedeemed`: stop attempts for that credit and read back the current state.
- RPC, timeout or transport failure: preserve the original error in the log and UI; stop automatic attempts for that credit, including after restart.

An attempt is persisted before sending the mutation. An interrupted attempt stays stopped because its server outcome is unknown. Each stage is attempted at most once. Late start or wake within the expiry window uses the current stage; after expiry, missed checkpoints are logged without consumption. A successful outcome is recorded separately from successful readback. A failed log write or readback stops automation for the current process and surfaces the error.

The app must be running and the computer awake at a checkpoint. On macOS wake it refreshes immediately. No wake timer or independent daemon is installed.

## Retained evidence

The existing log file is retained without rotation or automatic deletion:

- macOS: `~/Library/Application Support/Codex Account Switcher/reset-expiry-experiment.jsonl`
- Windows: `%LOCALAPPDATA%\Codex Account Switcher\reset-expiry-experiment.jsonl`

New records use `mode: "live"`. Old experiment records keep `mode: "dry_run"`. The private file contains account names/profile IDs, credit IDs/expiry, usage snapshots, planned and actual checkpoint times, delays, idempotency keys, service outcomes and original errors; credentials are never logged. Timestamps use UTC ISO 8601 (`Z`). Add eight hours for Beijing time.

| Event | Meaning |
| --- | --- |
| `enabled`, `resumed`, `disabled` | Automation lifecycle |
| `snapshot`, `read_failed` | Usage read or its original error |
| `checkpoint` | `attempt`, `missed`, `read_failed`, `details_unavailable` or `credit_unavailable` |
| `reset_attempt` | Persisted intent immediately before the real call; a missing result means its outcome is unknown |
| `reset_result` | Actual service outcome or original call error, with `resetAttempted: true` |
| `reset_verified` | Post-call usage/credit readback; `outcome` identifies what the service reported |
| `reset_verification_failed` | Original readback error or unconfirmed consumption, including the available readback data |

Disabling stops new attempts and scheduled observation. An already-sent request can finish and its outcome remains logged. A damaged log stops automation and surfaces the parsing error.

## Validation boundary

Development, unit tests and UI checks use isolated fake clients or JSON-RPC subprocess fixtures only. They never consume a real user credit. Tests cover all outcomes, exact credit/attempt parameters, original errors, deadline scheduling, missed windows, old dry-run history, restart deduplication, active/inactive saved accounts, post-consumption usage, disabled state and log errors. Production consumption begins only after the released application is installed and the user enables it. Live acceptance before the next deadline is limited to settings, reads and the planned schedule; a real `reset_result` plus readback is the later consumption evidence.
