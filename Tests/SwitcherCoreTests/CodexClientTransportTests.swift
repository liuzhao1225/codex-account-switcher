import Foundation
import Testing
@testable import SwitcherCore

private let fixtureExecutable = ProcessInfo.processInfo.environment["SWITCHER_TEST_RPC_EXE"]

@Suite(.enabled(if: fixtureExecutable != nil))
struct CodexClientTransportTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SWITCHER_TEST_INSTALLED_CLI"] != nil))
    func installedCliUsesOnlyAnIsolatedEmptyHome() async throws {
        let home = try fixtureHome("installed-cli")
        defer { try? FileManager.default.removeItem(at: home) }
        try Data("cli_auth_credentials_store = \"file\"\n".utf8).write(to: home.appendingPathComponent("config.toml"))
        let client = CodexClient(locator: .init(explicitURL: URL(fileURLWithPath:
            ProcessInfo.processInfo.environment["SWITCHER_TEST_INSTALLED_CLI"]!)))
        do { _ = try await client.readIdentity(profileHome: home); Issue.record("An isolated home must not have a login.") }
        catch { #expect(error as? CodexClientError == .identityUnavailable) }
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("auth.json").path))
    }

    @Test func parsesIdentityAndBothUsageWindows() async throws {
        let home = try fixtureHome("normal")
        defer { try? FileManager.default.removeItem(at: home) }
        let client = makeClient()
        let identity = try await client.readIdentity(profileHome: home)
        #expect(identity.accountID == "fixture")
        let usage = try await client.readWeeklyUsage(profileHome: home)
        #expect(usage.remainingPercent == 42)
        #expect(usage.fiveHourRemainingPercent == 67)
    }

    @Test func loginAcceptsCompletionBeforeStartResponse() async throws {
        let home = try fixtureHome("login")
        defer { try? FileManager.default.removeItem(at: home) }
        let client = makeClient()
        let identity = try await client.login(profileHome: home)
        #expect(identity.email == "fixture@example.test")
    }

    @Test func aSilentServerTimesOut() async throws {
        let home = try fixtureHome("timeout")
        defer { try? FileManager.default.removeItem(at: home) }
        let client = makeClient(timeout: .milliseconds(500))
        do {
            _ = try await client.readIdentity(profileHome: home)
            Issue.record("Expected a timeout")
        } catch { #expect(error as? CodexClientError == .timeout) }
    }

    @Test func pendingLoginCanBeCancelled() async throws {
        let home = try fixtureHome("cancel")
        defer { try? FileManager.default.removeItem(at: home) }
        let signal = BrowserSignal()
        let client = CodexClient(locator: .init(explicitURL: URL(fileURLWithPath: fixtureExecutable!)),
            openBrowser: { _ in await signal.opened() })
        let task = Task { try await client.login(profileHome: home) }
        for _ in 0..<100 {
            if await signal.isOpen { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(await signal.isOpen)
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch { #expect(error is CancellationError) }
    }

    private func makeClient(timeout: Duration = .seconds(5)) -> CodexClient {
        CodexClient(locator: .init(explicitURL: URL(fileURLWithPath: fixtureExecutable!)), requestTimeout: timeout,
            openBrowser: { url in #expect(url.host == "example.test") })
    }
    private func fixtureHome(_ scenario: String) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("switcher-rpc-test-\(UUID())")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Data(scenario.utf8).write(to: home.appendingPathComponent("fixture-mode"))
        return home
    }
}

private actor BrowserSignal {
    var isOpen = false
    func opened() { isOpen = true }
}
