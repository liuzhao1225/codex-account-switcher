#if os(Windows)
import Foundation
import Testing
@testable import SwitcherCore

struct WindowsCodexExecutableLocatorTests {
    @Test func prefersDesktopRuntimeAndRespectsExplicitOverrides() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-windows-locator-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let desktopCLI = root.appendingPathComponent("store/app/resources/codex.exe")
        let materializedCLI = root.appendingPathComponent("OpenAI/Codex/bin/current/codex.exe")
        let pathCLI = root.appendingPathComponent("bin/codex.exe")
        for executable in [desktopCLI, materializedCLI, pathCLI] {
            try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data().write(to: executable)
        }

        var environment = ["Path": pathCLI.deletingLastPathComponent().path, "LOCALAPPDATA": root.path]
        let locator = CodexExecutableLocator(prefersBundledDesktop: true, locateDesktopCLI: { desktopCLI })
        #expect(try await locator.launchConfigurationAsync(environment: environment).executable == desktopCLI)

        environment["CODEX_CLI_PATH"] = "codex"
        #expect(try await locator.launchConfigurationAsync(environment: environment).executable == pathCLI)
        environment["CODEX_CLI_PATH"] = pathCLI.path
        #expect(try await locator.launchConfigurationAsync(environment: environment).executable == pathCLI)
        environment["CODEX_CLI_PATH"] = "missing-cli"
        await #expect(throws: CodexClientError.executableNotFound) {
            try await locator.launchConfigurationAsync(environment: environment)
        }

        environment["CODEX_CLI_PATH"] = nil
        try FileManager.default.removeItem(at: desktopCLI)
        #expect(try await locator.launchConfigurationAsync(environment: environment).executable == materializedCLI)
        try FileManager.default.removeItem(at: materializedCLI)
        #expect(try await locator.launchConfigurationAsync(environment: environment).executable == pathCLI)
    }
}
#endif
