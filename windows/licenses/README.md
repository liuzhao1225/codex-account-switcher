# Bundled runtime licenses

The packaging script embeds these notices alongside the Swift host and runtime DLLs. They are extracted with the runtime under the user's Local AppData directory.

- Swift: `swiftlang/swift`, tag `swift-6.3.3-RELEASE`, `LICENSE.txt`.
- Foundation: `swiftlang/swift-corelibs-foundation`, tag `swift-6.3.3-RELEASE`, `LICENSE`.
- Dispatch: `swiftlang/swift-corelibs-libdispatch`, tag `swift-6.3.3-RELEASE`, `LICENSE`.
- Foundation ICU: `swiftlang/swift-foundation-icu`, tag `swift-6.3.3-RELEASE`, `LICENSE.md`.
- Unicode data/code: `https://www.unicode.org/license.txt`.
- .NET runtime 10.0.12: `Microsoft.NETCore.App.Runtime.win-x64` NuGet package, `LICENSE.TXT` and `THIRD-PARTY-NOTICES.TXT`.
- WPF runtime 10.0.12: `Microsoft.WindowsDesktop.App.Runtime.win-x64` NuGet package, `LICENSE`.

The DLLs come from the signed official Swift runtime distribution. Microsoft Visual C++ runtime DLLs included in that distribution retain Microsoft's licensing terms. Update these notices when updating the packaged runtime versions.
