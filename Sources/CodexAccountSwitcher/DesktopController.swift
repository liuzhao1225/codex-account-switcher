import AppKit
import Foundation

enum DesktopControllerError: LocalizedError, Sendable {
    case applicationNotFound
    case backendNotFound
    case backendCompanionNotFound
    case quitRequestFailed
    case forceQuitFailed
    case didNotExit
    case reopenFailed

    var errorDescription: String? {
        switch self {
        case .applicationNotFound:
            "The Codex Desktop application could not be found."
        case .backendNotFound:
            "The Codex app-server executable could not be found."
        case .backendCompanionNotFound:
            "The Codex code-mode host could not be found beside the app-server executable."
        case .quitRequestFailed:
            "Codex Desktop rejected the quit request."
        case .forceQuitFailed:
            "Codex Desktop rejected the force-quit request."
        case .didNotExit:
            "Codex Desktop did not exit within 15 seconds after the force-quit request."
        case .reopenFailed:
            "Codex Desktop could not be reopened. Open it manually to continue."
        }
    }
}

struct DesktopController: DesktopControlling {
    private let bundleIdentifiers = ["com.openai.codex"]
    private let applicationPaths = ["/Applications/ChatGPT.app", "/Applications/Codex.app"]
    private let codexLocator: CodexExecutableLocator

    init(codexLocator: CodexExecutableLocator = .init()) {
        self.codexLocator = codexLocator
    }

    func closeDesktop() async throws {
        let running = NSWorkspace.shared.runningApplications.filter { application in
            guard let bundleIdentifier = application.bundleIdentifier else { return false }
            return bundleIdentifiers.contains(bundleIdentifier)
        }
        guard !running.isEmpty else { return }
        for application in running where !application.isTerminated {
            let processIdentifier = application.processIdentifier
            guard application.terminate() || !isDesktopRunning(processIdentifier: processIdentifier) else {
                throw DesktopControllerError.quitRequestFailed
            }
        }

        let clock = ContinuousClock()
        let gracefulDeadline = clock.now.advanced(by: .seconds(2))
        while clock.now < gracefulDeadline {
            if !isDesktopRunning { return }
            try await Task.sleep(for: .milliseconds(100))
        }

        for application in runningDesktopApplications where !application.isTerminated {
            let processIdentifier = application.processIdentifier
            guard application.forceTerminate()
                    || !isDesktopRunning(processIdentifier: processIdentifier)
            else {
                throw DesktopControllerError.forceQuitFailed
            }
        }

        let deadline = clock.now.advanced(by: .seconds(15))
        while clock.now < deadline {
            if !isDesktopRunning { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw DesktopControllerError.didNotExit
    }

    func reopenDesktop() async throws {
        guard let url = applicationURL() else {
            throw DesktopControllerError.applicationNotFound
        }
        let codexURL: URL
        do {
            codexURL = try codexLocator.locate()
        } catch {
            throw DesktopControllerError.backendNotFound
        }
        let codeModeHostURL = codexURL
            .deletingLastPathComponent()
            .appending(path: "codex-code-mode-host")
        guard FileManager.default.isExecutableFile(atPath: codeModeHostURL.path) else {
            throw DesktopControllerError.backendCompanionNotFound
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        configuration.environment = ["CODEX_CLI_PATH": codexURL.path]
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } catch {
            throw DesktopControllerError.reopenFailed
        }
    }

    private func applicationURL() -> URL? {
        for identifier in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                return url
            }
        }
        return applicationPaths
            .map(URL.init(fileURLWithPath:))
            .first(where: { FileManager.default.fileExists(atPath: $0.path) })
    }

    private var isDesktopRunning: Bool {
        !runningDesktopApplications.isEmpty
    }

    private var runningDesktopApplications: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { application in
            guard let bundleIdentifier = application.bundleIdentifier else { return false }
            return bundleIdentifiers.contains(bundleIdentifier)
        }
    }

    private func isDesktopRunning(processIdentifier: pid_t) -> Bool {
        runningDesktopApplications.contains { $0.processIdentifier == processIdentifier }
    }
}
