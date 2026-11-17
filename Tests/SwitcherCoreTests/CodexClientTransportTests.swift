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
        #expect(usage.resetCreditsRemaining == 2)
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

    @Test func repeatedAndConcurrentQuotaReadsReuseOneProcessPerProfile() async throws {
        let home = try fixtureHome("normal")
        let other = try fixtureHome("normal")
        defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: other) }
        let client = makeClient()
        _ = try await client.readWeeklyUsage(profileHome: home)
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<6 {
                group.addTask { try await client.readWeeklyUsage(profileHome: home).remainingPercent }
            }
            for try await remaining in group { #expect(remaining == 42) }
        }
        _ = try await client.readWeeklyUsage(profileHome: other)
        #expect(try launchCount(home) == 1)
        #expect(try launchCount(other) == 1)
        let requests = try String(contentsOf: home.appendingPathComponent("requests"), encoding: .utf8)
        #expect(requests.components(separatedBy: "initialize\n").count - 1 == 1)
        #expect(requests.components(separatedBy: "account/rateLimits/read").count - 1 == 7)
        try await client.stopUsageSessions()
    }

    @Test func credentialReplacementAndExplicitStopReopenQuotaSession() async throws {
        let home = try fixtureHome("normal")
        defer { try? FileManager.default.removeItem(at: home) }
        let client = makeClient()
        try Data("first".utf8).write(to: home.appendingPathComponent("auth.json"))
        _ = try await client.readWeeklyUsage(profileHome: home)
        try Data("replacement".utf8).write(to: home.appendingPathComponent("auth.json"))
        _ = try await client.readWeeklyUsage(profileHome: home)
        #expect(try launchCount(home) == 2)
        try await client.stopUsageSessions()
        _ = try await client.readWeeklyUsage(profileHome: home)
        #expect(try launchCount(home) == 3)
        try await client.stopUsageSessions()
    }

    @Test func failedQuotaProcessIsDiscardedAndNextReadRecovers() async throws {
        let home = try fixtureHome("exit-once")
        defer { try? FileManager.default.removeItem(at: home) }
        let client = makeClient()
        await #expect(throws: (any Error).self) { try await client.readWeeklyUsage(profileHome: home) }
        #expect(try await client.readWeeklyUsage(profileHome: home).remainingPercent == 42)
        #expect(try launchCount(home) == 2)
        try await client.stopUsageSessions()
    }

    @Test func cancelledQuotaReadStopsTheProcessAndRecovers() async throws {
        let home = try fixtureHome("quota-timeout")
        defer { try? FileManager.default.removeItem(at: home) }
        let client = makeClient()
        let read = Task { try await client.readWeeklyUsage(profileHome: home) }
        for _ in 0..<100 {
            let log = (try? String(contentsOf: home.appendingPathComponent("requests"), encoding: .utf8)) ?? ""
            if log.contains("account/rateLimits/read") { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        read.cancel()
        await #expect(throws: CancellationError.self) { try await read.value }
        try Data("normal".utf8).write(to: home.appendingPathComponent("fixture-mode"))
        #expect(try await client.readWeeklyUsage(profileHome: home).remainingPercent == 42)
        #expect(try launchCount(home) == 2)
        try await client.stopUsageSessions()
    }

    @Test(arguments: ["hold-initialize", "hold-quota"])
    func credentialReplacementDuringAnRPCIsDetected(_ mode: String) async throws {
        let home = try fixtureHome(mode)
        defer { try? FileManager.default.removeItem(at: home) }
        let client = makeClient()
        try Data("old".utf8).write(to: home.appendingPathComponent("auth.json"))
        let read = Task { try await client.readWeeklyUsage(profileHome: home) }
        try await waitForRequest(mode == "hold-initialize" ? "initialize" : "account/rateLimits/read", home: home)
        try Data("replacement".utf8).write(to: home.appendingPathComponent("auth.json"))
        try Data().write(to: home.appendingPathComponent("release"))
        _ = try await read.value
        try Data("normal".utf8).write(to: home.appendingPathComponent("fixture-mode"))
        _ = try await client.readWeeklyUsage(profileHome: home)
        #expect(try launchCount(home) == 2)
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("overlap").path))
        try await client.stopUsageSessions()
    }

    @Test func profileOperationsPreserveSiblingSessionsAndEvictRemovedProfiles() async throws {
        let home = try fixtureHome("normal")
        let sibling = try fixtureHome("normal")
        defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: sibling) }
        let client = makeClient()
        _ = try await client.readWeeklyUsage(profileHome: home)
        _ = try await client.readWeeklyUsage(profileHome: sibling)
        _ = try await client.refreshIdentity(profileHome: home)
        #expect(try await client.consumeResetCredit(profileHome: home, creditID: "test", idempotencyKey: "test") == .reset)
        _ = try await client.readWeeklyUsage(profileHome: sibling)
        #expect(try launchCount(sibling) == 1)
        #expect(await client.usageSessionCount == 2)
        try await client.forgetUsageSession(profileHome: home)
        #expect(await client.usageSessionCount == 1)
        _ = try await client.readWeeklyUsage(profileHome: home)
        #expect(await client.usageSessionCount == 2)
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("overlap").path))
        try await client.stopUsageSessions()
    }

    @Test func quotaReadWaitsForCredentialRenewalOnTheSameProfile() async throws {
        let home = try fixtureHome("normal")
        defer { try? FileManager.default.removeItem(at: home) }
        let client = makeClient()
        _ = try await client.readWeeklyUsage(profileHome: home)
        try Data("hold-identity".utf8).write(to: home.appendingPathComponent("fixture-mode"))
        let renewal = Task { try await client.refreshIdentity(profileHome: home) }
        try await waitForRequest("account/read", home: home)
        let read = Task { try await client.readWeeklyUsage(profileHome: home) }
        try Data("normal".utf8).write(to: home.appendingPathComponent("fixture-mode"))
        try Data().write(to: home.appendingPathComponent("release"))
        _ = try await renewal.value
        _ = try await read.value
        #expect(try launchCount(home) == 3)
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("overlap").path))
        try await client.stopUsageSessions()
    }

    private func waitForRequest(_ method: String, home: URL) async throws {
        for _ in 0..<250 {
            let requests = (try? String(contentsOf: home.appendingPathComponent("requests"), encoding: .utf8)) ?? ""
            if requests.split(separator: "\n").contains(Substring(method)) { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw CodexClientError.timeout
    }

    @Test func timedOutQuotaSessionIsDiscarded() async throws {
        let home = try fixtureHome("quota-timeout\r\n")
        defer { try? FileManager.default.removeItem(at: home) }
        let client = makeClient(timeout: .seconds(2))
        do { _ = try await client.readWeeklyUsage(profileHome: home); Issue.record("Expected timeout") }
        catch { #expect(error as? CodexClientError == .timeout) }
        try Data("normal".utf8).write(to: home.appendingPathComponent("fixture-mode"))
        #expect(try await client.readWeeklyUsage(profileHome: home).remainingPercent == 42)
        #expect(try launchCount(home) == 2)
        try await client.stopUsageSessions()
    }

    @Test func unusedQuotaSessionsExpire() async throws {
        let home = try fixtureHome("normal")
        defer { try? FileManager.default.removeItem(at: home) }
        let client = CodexClient(locator: .init(explicitURL: URL(fileURLWithPath: fixtureExecutable!)),
                                 usageSessionIdleTimeout: .milliseconds(50))
        _ = try await client.readWeeklyUsage(profileHome: home)
        try await Task.sleep(for: .seconds(1))
        _ = try await client.readWeeklyUsage(profileHome: home)
        #expect(try launchCount(home) == 2)
        try await client.stopUsageSessions()
    }

    private func launchCount(_ home: URL) throws -> Int {
        try String(contentsOf: home.appendingPathComponent("launches"), encoding: .utf8).split(separator: "\n").count
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
