# Documentation

- [Official project identity and primary sources](project-identity.md)

This directory defines the MVP for Codex Account Switcher.

## Documents

| Document | Purpose |
| --- | --- |
| [Product positioning and messaging](positioning-and-messaging.md) | Shared audience, promise, proof, SEO terms, and claim boundaries |
| [Product decisions](product-decisions.md) | Binding product and architecture decisions |
| [Product requirements](product-requirements.md) | User-visible behavior and acceptance criteria |
| [System design](system-design.md) | Components, storage, flows, interfaces, and failure behavior |
| [Implementation plan](implementation-plan.md) | Concrete milestones and suggested source layout |
| [Testing](testing.md) | Small, failure-oriented MVP test plan |

## Product definition

Codex Account Switcher is a simple local menu-bar app for ordinary Mac users. The public workflow is: add accounts through browser sign-in once, choose from the menu bar, and let the app complete the confirmed Codex Desktop handoff. It requires no Terminal commands or config-file editing. Internally, the app manages a small set of authentication snapshots and activates the selected snapshot for Codex.

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

The sequence is deliberately linear. Every step either succeeds or returns an error. Verification and registry-commit failures after activation restore the validated original profile credential; the implementation does not add a general recovery state machine around the switch.
