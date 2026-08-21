import AppKit
import Foundation

enum DesktopControllerError: LocalizedError, Sendable {
    case applicationNotFound
    case didNotExit
    case reopenFailed

    var errorDescription: String? {
        switch self {
        case .applicationNotFound:
            "The Codex Desktop application could not be found."
        case .didNotExit:
            "Codex Desktop did not exit within five seconds."
        case .reopenFailed:
            "Codex Desktop could not be reopened. Open it manually to continue."
        }
    }
}

struct DesktopController: DesktopControlling {
    private let bundleIdentifiers = ["com.openai.codex"]
    private let applicationPaths = ["/Applications/ChatGPT.app", "/Applications/Codex.app"]

    func closeDesktop() async throws {
        let running = NSWorkspace.shared.runningApplications.filter { application in
            guard let bundleIdentifier = application.bundleIdentifier else { return false }
            return bundleIdentifiers.contains(bundleIdentifier)
        }
        guard !running.isEmpty else { return }
        running.forEach { _ = $0.terminate() }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while clock.now < deadline {
            let remains = NSWorkspace.shared.runningApplications.contains { application in
                guard let bundleIdentifier = application.bundleIdentifier else { return false }
                return bundleIdentifiers.contains(bundleIdentifier)
            }
            if !remains { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw DesktopControllerError.didNotExit
    }

    func reopenDesktop() async throws {
        guard let url = applicationURL() else {
            throw DesktopControllerError.applicationNotFound
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
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
}
