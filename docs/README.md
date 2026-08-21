# Documentation

This directory defines the MVP contract for Codex Account Switcher Lite.

- [Product decisions](./product-decisions.md) records the product boundaries and irreversible UI decisions.
- [Product requirements](./product-requirements.md) defines user-visible behavior and acceptance criteria.
- [System design](./system-design.md) describes the native macOS architecture, local data model, Codex integration, and direct switching flow.
- [Testing and release](./testing-and-release.md) defines the minimum tests required before shipping.

The key implementation rule is simple:

> Execute the account switch in order. Stop on the first error. Do not roll back, retry silently, or substitute a different data source.

`Usage` always means weekly Usage. The 5-hour window is ignored by the UI and is not configurable.
