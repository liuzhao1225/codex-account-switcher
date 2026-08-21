# ADR 0001: Use direct MVP switching without rollback

- Status: Accepted
- Date: 2026-08-21

## Context

The product is a small personal macOS utility whose main value is reducing repeated Codex logins.

An earlier design treated account switching like a transactional credential-management system. It proposed rollback copies, a persisted transaction journal, post-write identity verification, automatic recovery, storage-backend abstraction, retries, and defensive compatibility gates.

Those mechanisms would increase code size and introduce more states than the product itself requires. They would also make failures harder to understand because the application could change state again while attempting to hide the original error.

The product goal is a simple switcher that is easy to inspect and change.

## Decision

Use a direct sequence:

```text
confirm
→ stop Desktop
→ save current snapshot
→ write selected snapshot to ~/.codex/auth.json
→ update selected profile metadata
→ launch Desktop
```

Use a normal atomic file write for each individual JSON file, but do not create a multi-step transaction around the sequence.

When any step throws:

- stop the operation;
- display the original error;
- do not retry;
- do not restore prior files;
- do not continue to later steps;
- do not report success.

Usage follows the same rule:

- request once;
- display the weekly window only;
- never substitute the 5-hour window;
- display unavailable or sign-in-again state on failure;
- do not show stale data as current.

## Consequences

### Positive

- Less code and fewer states.
- The implementation matches the mental model of copying a selected auth file.
- Failures remain visible and debuggable.
- Faster path to a working MVP.
- No recovery behavior that can surprise the user.
- Weekly-only Usage remains structurally enforced.

### Negative

- A failure after the active auth write can leave metadata and active auth out of sync.
- A failed Desktop launch does not restore the prior account.
- Canceling Add Account after auth removal leaves Codex logged out.
- The user may need to retry a switch or manually inspect files.
- Direct use of the current Codex Usage endpoint may require maintenance when upstream changes.

These costs are accepted for the MVP.

## Reconsideration criteria

Revisit this decision only after a demonstrated user problem, such as:

- repeated real-world corruption caused by interrupted writes;
- many users unable to recover from partial switches;
- an upstream Codex storage change that makes direct snapshots impractical;
- a product decision to support managed enterprise deployment.

Do not add rollback or fallback merely because it is theoretically safer.
