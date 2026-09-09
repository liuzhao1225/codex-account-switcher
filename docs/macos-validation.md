# macOS 0.1.11 shared-core validation

Validated on Apple Silicon with macOS 26.6.2 and Apple Swift 6.3.3 on September 9, 2026.

## Repair

The Windows shared-core extraction at `6b9e737` made `AppModel` inherit from `AccountController`. Its explicit `ObservableObjectPublisher` is main-actor isolated, while the unqualified `ObservableObject` conformance requires nonisolated access. Both local compilation and macOS CI failed at `AppModel.swift:33`. Explicit `@MainActor ObservableObject` conformance restores the intended UI isolation without weakening concurrency checks.

## Local evidence

- Swift Testing executed using the CLT framework search path documented in [Testing](testing.md): the runner reports 71 tests in 9 suites passed. The five environment-gated transport tests were skipped because the Windows RPC fixture and installed-CLI opt-in were unset; macOS subprocess transport tests executed.
- CoreChecks passed, including new assertions for Combine notifications after shared-core startup, settings changes, and usage refresh.
- All six release-routing and macOS-feed tests passed; site consistency checks passed for 16 pages.
- The release App bundle built successfully, passed strict ad-hoc signature verification, and started from the release build directory. Its version is 0.1.11, `LSUIElement` is true, and Sparkle uses the dedicated macOS feed.
- A temporary native window loaded the production `MenuBarPopover`, `AppModel`, account-management and settings views with an isolated account store and fake RPC client. Accessibility interaction verified account rendering, the settings page/version, immediate five-hour toggle changes, and account-management navigation.

The temporary window is a test harness under ignored `.build/macos-validation/`; it is excluded from the package. Its first run failed because the fixture omitted the fake credential file required by `addProfile`; the fixture was corrected before UI validation. The production app retains `MenuBarExtra` and its menu-bar popover. Automation could not directly inspect that menu-bar-only application, so the UI interaction evidence is scoped to the isolated production-view harness. Real Codex Desktop account switching was not performed during this validation.

Developer ID signing, Apple notarization, DMG validation, and Sparkle signing are performed by the tag-triggered release workflow after these local checks.
