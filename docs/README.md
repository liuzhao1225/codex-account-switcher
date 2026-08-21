# Documentation

This directory defines the MVP for Codex Account Switcher Lite.

## Documents

| Document | Purpose |
| --- | --- |
| [Product decisions](product-decisions.md) | Binding product and architecture decisions |
| [Product requirements](product-requirements.md) | User-visible behavior and acceptance criteria |
| [System design](system-design.md) | Components, storage, flows, interfaces, and failure behavior |
| [Implementation plan](implementation-plan.md) | Concrete milestones and suggested source layout |
| [Testing](testing.md) | Small, failure-oriented MVP test plan |

## Product definition

Codex Account Switcher Lite is a local macOS menu-bar utility. It manages a small set of authentication snapshots and copies the selected snapshot into Codex's active authentication location.

The intended user flow is:

```text
Open menu
→ inspect weekly Usage
→ select account
→ confirm normal switch consequences
→ switch
```

The implementation flow is:

```text
Preflight
→ close Codex Desktop
→ save the current account's latest credentials
→ atomically activate the target credentials
→ verify the target identity through Codex
→ write activeAccountID
→ reopen Codex Desktop
```

The sequence is deliberately linear. Every step either succeeds or returns an error. The implementation does not add a second recovery state machine around the switch.
