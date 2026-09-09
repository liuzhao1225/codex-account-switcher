# Windows shared-core preview validation

Validated locally on Windows 10 x64 on 2026-09-09, with Swift 6.3.3 and .NET SDK 10.0.401.

## Completed

- Shared `SwitcherCore` and `SwitcherHost` compile in debug and release configurations.
- 29 Swift tests pass for switch ordering, failure restoration, quota interpretation, startup registration, settings persistence, cache retention, protected active profiles, snapshot privacy, RPC identity/usage, login completion ordering, timeout and cancellation. Three additional file-backed first-activation tests and an installed-CLI test also pass (33 tests total).
- Native C# integration checks pass against the actual Swift host, including localized snapshots, settings persistence, private Windows ACLs and restart persistence.
- WPF builds with zero warnings/errors. Synthetic UI checks pass for a compact native account window with title bar and taskbar entry, focus persistence, close-to-tray and reopening, full-row switch confirmation, manage page, immediate settings, and optional five-hour usage.
- The portable EXE bundles the Swift host/runtime and .NET runtime. Its isolated `--self-test` passes with Swift/.NET SDK paths removed from the child environment.
- The final local EXE is 101,069,104 bytes. SHA-256: `bfbf217614ecb77eb4d37fea39909014a2fea5421849c62e0f97c8a1679d3e22`.
- Six release-routing and Mac-feed tests pass; Windows update-selection checks reject Mac releases, drafts and missing EXEs; site consistency checks pass for 16 HTML pages and sitemap entries.

UI screenshots in `windows/artifacts/ui` contain only fictional accounts. Windows uses Microsoft WPF Fluent controls: a top command bar, account list with a vertical selection indicator, native checkboxes, and right-aligned dialog actions. Management, confirmation and immediate settings retain the shared account flow. The former three-action footer and custom pill switches have been removed.

The transparent tray resources were compared with the installed Codex `chatgpt-tray-light.ico` and `chatgpt-tray-dark.ico`: both fill a 16 ? 16 visible bounding box at the 16px size. Native loading, transparent corners and black/white foreground checks pass at 16, 20, 24, 32, 40, 48 and 64px. `windows/artifacts/tray-icons-comparison.png` shows a magnified resource comparison, not a desktop screenshot. Computer-use did not expose the taskbar/overflow window, so the live tray alignment was not visually verified.

## Boundaries

No test switches the user's real credentials, opens real browser login, or closes the user's Codex Desktop. A real handoff should be exercised in a disposable Windows user session before a stable release. The Store Desktop adapter must be rechecked when the upstream application's process/exit behavior changes.

This host cannot execute a macOS build. The Mac SwiftUI views keep their existing interaction design, and its `AppModel` wraps the extracted shared controller. macOS compilation, its existing platform tests, Sparkle, signing and notarization still require the macOS CI runner. A passing local Windows run is not a claim that hosted CI or a Mac build ran.

The local private Swift toolchain uses a newer Windows SDK extracted under the user account alongside the existing C++ tools. Windows developer mode was not enabled. SwiftPM reports that its optional `.build/debug`/`.build/release` symlinks cannot be created; commands and packaging use `--show-bin-path` or the full target output path instead. These warnings did not prevent compilation or tests.

The preview EXE is unsigned, is not an installer, and does not automatically replace itself. The checks above describe local validation; hosted CI and release publication are separate steps.

The Windows 0.1.11 release candidate is in `windows/artifacts/release-0.1.11/`; its version metadata and isolated self-test passed before tag preparation. macOS remains 0.1.10 and is not part of this release.
