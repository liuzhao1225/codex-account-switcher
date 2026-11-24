import Darwin
import Foundation
import Testing
@testable import SwitcherCore

struct CodexExecutableLocatorTests {
    @Test(arguments: [
        "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
        "Contents/Resources/codex",
    ])
    func findsBundledCLIWithMissingOrBrokenPATHCommand(relativePath: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("codex-desktop-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let application = root.appendingPathComponent("ChatGPT.app")
        let executable = application.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let pathCommand = bin.appendingPathComponent("codex")
        try FileManager.default.createSymbolicLink(at: pathCommand, withDestinationURL: root.appendingPathComponent("missing-codex"))
        let locator = CodexExecutableLocator(desktopApplicationURLs: [application])
        for path in ["/nonexistent", bin.path] {
            #expect(try locator.locate(environment: ["PATH": path]) == executable)
        }
        #expect(try locator.locate(environment: ["PATH": bin.path, "CODEX_CLI_PATH": " "]) == executable)
        for override in ["custom-codex", root.appendingPathComponent("missing-codex").path] {
            #expect(throws: CodexClientError.self) {
                try locator.locate(environment: ["PATH": bin.path, "CODEX_CLI_PATH": override])
            }
        }

        try FileManager.default.removeItem(at: pathCommand)
        try FileManager.default.copyItem(at: executable, to: pathCommand)
        #expect(try locator.locate(environment: ["PATH": bin.path]) == pathCommand)
    }

    @Test func prefersModernBundledLayoutWhenBothExist() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("codex-desktop-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let modern = root.appendingPathComponent("Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
        let legacy = root.appendingPathComponent("Contents/Resources/codex")
        try FileManager.default.createDirectory(at: modern.deletingLastPathComponent(), withIntermediateDirectories: true)
        for executable in [modern, legacy] {
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        }
        #expect(try CodexExecutableLocator(desktopApplicationURLs: [root]).locate(environment: [:]) == modern)
    }

    @Test(arguments: ["/bin/sh", "/bin/bash", "/bin/zsh"])
    func readsPOSIXLoginShellConfiguration(shell: String) async throws {
        try await checkLoginShell(shell)
    }

    @Test(.enabled(if: fishPath != nil, "Install fish to run its login-shell regression check"))
    func readsFishLoginShellConfiguration() async throws {
        try await checkLoginShell(#require(Self.fishPath))
    }

    private static var fishPath: String? {
        ["/opt/homebrew/bin/fish", "/usr/local/bin/fish", "/usr/bin/fish"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func checkLoginShell(_ shell: String) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-shell-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent("bin with spaces")
        let fishConfig = root.appendingPathComponent(".config/fish")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fishConfig, withIntermediateDirectories: true)
        for name in ["codex", "custom-codex"] {
            let executable = bin.appendingPathComponent(name)
            // The child must inherit the login PATH, including paths containing spaces.
            try Data("#!/bin/sh\nprintf '%s' \"$PATH\"\n".utf8).write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        }

        let isFish = shell.hasSuffix("/fish")
        let startupName = isFish ? ".config/fish/config.fish"
            : shell.hasSuffix("/zsh") ? ".zprofile"
            : shell.hasSuffix("/bash") ? ".bash_profile" : ".profile"
        let environment = [
            "SHELL": shell, "HOME": root.path, "ZDOTDIR": root.path,
            "XDG_CONFIG_HOME": root.appendingPathComponent(".config").path,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "FIXTURE_BIN": bin.path,
        ]
        for override in [nil, "", "custom-codex", bin.appendingPathComponent("custom-codex").path,
                         "/nonexistent/codex-shell-test"] as [String?] {
            var startup = isFish
                ? "set -gx PATH \"$FIXTURE_BIN\" /usr/bin /bin /usr/sbin /sbin\n"
                : "export PATH=\"$FIXTURE_BIN:/usr/bin:/bin:/usr/sbin:/sbin\"\n"
            if let override {
                // Deliberately leave the override unexported, as a shell-local setting.
                startup += isFish ? "set -g CODEX_CLI_PATH '\(override)'\n"
                    : "CODEX_CLI_PATH='\(override)'\n"
            }
            startup += "printf 'login startup output\\n'\n"
            try Data(startup.utf8).write(to: root.appendingPathComponent(startupName))

            if override?.hasPrefix("/nonexistent/") == true {
                await #expect(throws: CodexClientError.processLaunchFailed(
                    "CODEX_CLI_PATH is not executable: \(override!)")) {
                    try await CodexExecutableLocator().launchConfigurationAsync(environment: environment)
                }
                continue
            }

            let launch = try await CodexExecutableLocator().launchConfigurationAsync(environment: environment)
            let expectedName = override == nil || override == "" ? "codex" : "custom-codex"
            #expect(launch.executable == bin.appendingPathComponent(expectedName))
            let expectedPATH = "\(bin.path):/usr/bin:/bin:/usr/sbin:/sbin"
            #expect(launch.environment["PATH"] == expectedPATH)
            let child = Process()
            let output = Pipe()
            child.executableURL = launch.executable
            child.environment = launch.environment
            child.standardOutput = output
            try child.run()
            let bytes = output.fileHandleForReading.readDataToEndOfFile()
            child.waitUntilExit()
            #expect(child.terminationStatus == 0)
            #expect(String(decoding: bytes, as: UTF8.self) == expectedPATH)
        }
    }

    @Test func asyncLoginShellTimesOutEvenWhenBackgroundChildHoldsStdoutOpen() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-shell-timeout-\(UUID())")
        let pidFile = root.appendingPathComponent("child.pid")
        let startedFile = root.appendingPathComponent("started")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            Self.terminateRecordedProcess(at: pidFile)
            try? FileManager.default.removeItem(at: root)
        }

        try Data("""
        sleep 30 &
        echo $! > '\(pidFile.path)'
        : > '\(startedFile.path)'
        sleep 30
        """.utf8).write(to: root.appendingPathComponent(".profile"))

        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: CodexClientError.timeout) {
            _ = try await CodexExecutableLocator().launchConfigurationAsync(
                environment: ["SHELL": "/bin/sh", "HOME": root.path, "PATH": "/usr/bin:/bin"],
                shellTimeout: .milliseconds(200)
            )
        }
        #expect(start.duration(to: clock.now) < .seconds(3))
        #expect(FileManager.default.fileExists(atPath: startedFile.path))
    }

    @Test func asyncLoginShellRespectsPreAndMidFlightCancellation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-shell-cancel-\(UUID())")
        let pidFile = root.appendingPathComponent("child.pid")
        let startedFile = root.appendingPathComponent("started")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            Self.terminateRecordedProcess(at: pidFile)
            try? FileManager.default.removeItem(at: root)
        }

        try Data("""
        sleep 30 &
        echo $! > '\(pidFile.path)'
        : > '\(startedFile.path)'
        sleep 30
        """.utf8).write(to: root.appendingPathComponent(".profile"))

        let env = ["SHELL": "/bin/sh", "HOME": root.path, "PATH": "/usr/bin:/bin"]

        let preCancelled = Task {
            try await CodexExecutableLocator().launchConfigurationAsync(environment: env, shellTimeout: .seconds(10))
        }
        preCancelled.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await preCancelled.value
        }
        #expect(!FileManager.default.fileExists(atPath: startedFile.path))

        let clock = ContinuousClock()
        let midFlight = Task {
            try await CodexExecutableLocator().launchConfigurationAsync(environment: env, shellTimeout: .seconds(10))
        }
        let waitDeadline = clock.now + .seconds(3)
        while !FileManager.default.fileExists(atPath: startedFile.path), clock.now < waitDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(FileManager.default.fileExists(atPath: startedFile.path))

        let cancelStart = clock.now
        midFlight.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await midFlight.value
        }
        #expect(cancelStart.duration(to: clock.now) < .seconds(3))
    }

    @Test func asyncLoginShellReadsMultiChunkNulDelimitedOutputAfterPipeEOF() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-shell-large-\(UUID())")
        let bin = root.appendingPathComponent("bin")
        let executable = bin.appendingPathComponent("codex")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

        let padding = Array(repeating: "/nonexistent/padding/directory/entry", count: 2200).joined(separator: ":")
        let expectedPATH = "\(padding):\(bin.path):/usr/bin:/bin"
        let startupBanner = String(repeating: "x", count: 70_000)
        try Data("""
        export PATH='\(expectedPATH)'
        CODEX_CLI_PATH='\(executable.path)'
        printf '%s\\n' '\(startupBanner)'
        """.utf8).write(to: root.appendingPathComponent(".profile"))

        let launch = try await CodexExecutableLocator().launchConfigurationAsync(
            environment: ["SHELL": "/bin/sh", "HOME": root.path, "PATH": "/usr/bin:/bin"],
            shellTimeout: .seconds(5)
        )
        #expect(launch.executable == executable)
        #expect(launch.environment["PATH"] == expectedPATH)
        #expect(launch.environment["CODEX_CLI_PATH"] == executable.path)
    }

    private static func terminateRecordedProcess(at pidFile: URL) {
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0
        else { return }
        _ = kill(pid, SIGKILL)
    }
}
