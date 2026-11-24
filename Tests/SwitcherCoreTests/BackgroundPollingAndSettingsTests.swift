import Foundation
import Testing
@testable import SwitcherCore
@testable import SwitcherHost

@MainActor
struct BackgroundPollingAndSettingsTests {
    @Test func slowUsageReadAcrossPollTicksContinuesPollingWithoutOverlap() async throws {
        let fixture = try PollingFixture()
        defer { fixture.clean() }
        try fixture.writeActiveCredential()

        await fixture.client.blockNextRead()
        await fixture.model.start()
        #expect(!fixture.model.settings.autoResetEnabled)

        await fixture.model.startBackgroundUsageRefresh(every: .milliseconds(70))
        await fixture.client.waitForReadStart(count: 1)

        // Multiple poll ticks elapse while read #1 is still running; max concurrent reads stays 1.
        try await Task.sleep(for: .milliseconds(250))
        #expect(await fixture.client.readCount == 1)
        #expect(await fixture.client.maxConcurrentReads == 1)

        // Calling startBackgroundUsageRefresh again retains a single polling loop.
        await fixture.model.startBackgroundUsageRefresh(every: .milliseconds(70))
        await fixture.client.releaseBlockedReads()

        await fixture.client.waitForReadStart(count: 2)
        #expect(await fixture.client.maxConcurrentReads == 1)

        fixture.model.stopBackgroundUsageRefresh()
        await fixture.model.waitForWeeklyUsageRefresh()
        let countAfterStop = await fixture.client.readCount
        try await Task.sleep(for: .milliseconds(220))
        #expect(await fixture.client.readCount == countAfterStop)
    }

    @Test func stoppingBackgroundRefreshDuringStartPreventsZombiePolling() async throws {
        let fixture = try PollingFixture()
        defer { fixture.clean() }

        let oldProfile = AccountProfile(
            id: UUID(),
            displayName: "Old",
            email: "old@example.test",
            accountID: "old-account",
            createdAt: Date()
        )
        let oldHome = try await fixture.store.createProfileDirectory(id: oldProfile.id)
        try TestAuthFixture.authJSON(accountID: "old-account", email: "old@example.test", accessToken: "v1")
            .write(to: oldHome.appendingPathComponent("auth.json"))
        try await fixture.store.addProfile(oldProfile)
        try await fixture.store.commitActiveAccountID(oldProfile.id)

        // Updated active credential bytes trigger `syncActiveIdentity` -> `stopUsageSession`, letting us pause inside `start()`.
        try TestAuthFixture.authJSON(accountID: "old-account", email: "old@example.test", accessToken: "v2")
            .write(to: fixture.active.appendingPathComponent("auth.json"))
        await fixture.client.blockNextStopSession()

        let startTask = Task {
            await fixture.model.startBackgroundUsageRefresh(every: .milliseconds(50))
        }
        await fixture.client.waitForStopSessionStart()
        fixture.model.stopBackgroundUsageRefresh()
        await fixture.client.releaseBlockedStopSession()
        await startTask.value

        try await Task.sleep(for: .milliseconds(180))
        #expect(await fixture.client.readCount == 0)
    }

    @Test func autoResetCheckpointCollidingWithBusyRefreshCatchesUpAndConsumesOnce() async throws {
        let fixture = try PollingFixture()
        defer {
            fixture.model.stopBackgroundUsageRefresh()
            fixture.clean()
        }
        try fixture.writeActiveCredential()

        // First checkpoint occurs 10 minutes before expiry, so +600.4s puts it ~400ms in the future.
        await fixture.model.start()
        await fixture.client.setResetExpiry(Date().addingTimeInterval(600.4))
        await fixture.model.setAutoResetEnabled(true)
        await fixture.model.waitForWeeklyUsageRefresh()
        await fixture.model.startBackgroundUsageRefresh(every: .seconds(60))
        await fixture.model.waitForWeeklyUsageRefresh()
        let readsBeforeBusyWindow = await fixture.client.readCount
        #expect(await fixture.client.consumeCalls == 0)

        // Start a gated manual refresh before the checkpoint arrives so the checkpoint hits an in-flight read.
        await fixture.client.blockNextRead()
        fixture.model.refreshWeeklyUsage()
        await fixture.client.waitForReadStart(count: readsBeforeBusyWindow + 1)

        // Wait past the checkpoint deadline while the refresh is still blocked.
        try await Task.sleep(for: .milliseconds(550))
        #expect(await fixture.client.consumeCalls == 0)

        await fixture.client.releaseBlockedReads()
        await fixture.client.waitForConsumeCalls(atLeast: 1)
        await fixture.model.waitForWeeklyUsageRefresh()

        #expect(await fixture.client.consumeCalls == 1)
        #expect(fixture.model.visibleError == nil)
    }

    @Test func concurrentSettingsUpdatesSerializeAndSurfaceWriteFailures() async throws {
        let fixture = try PollingFixture()
        defer { fixture.clean() }
        await fixture.model.start()

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await fixture.model.setLanguage(.italian) }
            group.addTask { await fixture.model.setShowsMenuBarPercentage(false) }
            group.addTask { await fixture.model.setShowsFiveHourUsage(true) }
            group.addTask { await fixture.model.setStatusBarUsageWindow(.weekly) }
            group.addTask { await fixture.model.setAutoResetEnabled(true) }
        }

        let reloaded = AccountStore(baseURL: fixture.storeURL, activeHomeURL: fixture.active)
        let persisted = try await reloaded.loadSettings()
        #expect(persisted.language == .italian)
        #expect(persisted.showsMenuBarPercentage == false)
        #expect(persisted.showsFiveHourUsage == true)
        #expect(persisted.statusBarUsageWindow == .weekly)
        #expect(persisted.autoResetEnabled == true)
        #expect(fixture.model.visibleError == nil)

        // Replace `settings.json` with a directory so writing fails and surfaces an error.
        let settingsURL = fixture.storeURL.appendingPathComponent("settings.json")
        try FileManager.default.removeItem(at: settingsURL)
        try FileManager.default.createDirectory(at: settingsURL, withIntermediateDirectories: false)
        await fixture.model.setLanguage(.english)
        #expect(fixture.model.visibleError != nil)
        #expect(fixture.model.snapshot(includeStrings: false).error != nil)
    }

    @Test func hostInitializeSendsSingleSnapshotInSavedLanguageAndDeduplicatesStrings() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("switcher-host-test-\(UUID())")
        let dataURL = root.appendingPathComponent("data")
        let activeURL = root.appendingPathComponent("active")
        try FileManager.default.createDirectory(at: activeURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try await AccountStore(baseURL: dataURL, activeHomeURL: activeURL)
            .updateSettings { $0.language = .simplifiedChinese }

        let collector = HostLineCollector()
        let host = Host(
            environment: [
                "CODEX_SWITCHER_DATA_HOME": dataURL.path,
                "CODEX_HOME": activeURL.path,
            ],
            writeOutput: { collector.append($0) }
        )
        defer { host.shutdown() }

        host.accept(#"{"id":1,"command":"initialize"}"#)
        await host.waitForIdle()
        let initEnvelopes = try collector.drain()
        let initSnapshots = initEnvelopes.filter { $0.kind == "snapshot" }
        #expect(initSnapshots.count == 1)
        #expect(initSnapshots[0].state?.settings.language == "simplifiedChinese")
        #expect(initSnapshots[0].state?.strings?["manage"] == "管理账号")
        #expect(initEnvelopes.contains { $0.kind == "completed" && $0.id == 1 && $0.error == nil })

        host.accept(#"{"id":2,"command":"percentage","value":false}"#)
        await host.waitForIdle()
        let percentageEnvelopes = try collector.drain()
        let percentageSnapshots = percentageEnvelopes.filter { $0.kind == "snapshot" }
        #expect(percentageSnapshots.count == 1)
        #expect(percentageSnapshots[0].state?.settings.showsMenuBarPercentage == false)
        #expect(percentageSnapshots[0].state?.strings == nil)

        host.accept(#"{"id":3,"command":"language","language":"italian"}"#)
        await host.waitForIdle()
        let languageEnvelopes = try collector.drain()
        let languageSnapshots = languageEnvelopes.filter { $0.kind == "snapshot" }
        #expect(languageSnapshots.count == 1)
        #expect(languageSnapshots[0].state?.settings.language == "italian")
        #expect(languageSnapshots[0].state?.strings?["manage"] == "Gestisci account")
        let snapshotIndex = try #require(languageEnvelopes.firstIndex { $0.kind == "snapshot" })
        let completedIndex = try #require(languageEnvelopes.firstIndex { $0.kind == "completed" && $0.id == 3 })
        #expect(snapshotIndex < completedIndex)
    }

    @Test func hostCoalescesBurstStateChangesIntoSingleSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("switcher-host-coalesce-\(UUID())")
        let dataURL = root.appendingPathComponent("data")
        let activeURL = root.appendingPathComponent("active")
        try FileManager.default.createDirectory(at: activeURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let collector = HostLineCollector()
        let host = Host(
            environment: [
                "CODEX_SWITCHER_DATA_HOME": dataURL.path,
                "CODEX_HOME": activeURL.path,
            ],
            writeOutput: { collector.append($0) }
        )
        defer { host.shutdown() }

        host.accept(#"{"id":1,"command":"initialize"}"#)
        await host.waitForIdle()
        _ = try collector.drain()

        let controller = try #require(host.controller)
        for _ in 0..<5 {
            controller.onChange?()
        }
        await host.waitForIdle()

        let burstSnapshots = try collector.drain().filter { $0.kind == "snapshot" }
        #expect(burstSnapshots.count == 1)
    }
}

@MainActor
private struct PollingFixture {
    let root: URL
    let storeURL: URL
    let active: URL
    let store: AccountStore
    let client: GatedPollingClient
    let model: AccountController

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("switcher-poll-test-\(UUID())")
        storeURL = root.appendingPathComponent("store")
        active = root.appendingPathComponent("active")
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        store = AccountStore(baseURL: storeURL, activeHomeURL: active)
        client = GatedPollingClient()
        model = AccountController(
            store: store,
            codex: client,
            switchService: SwitchService(desktop: PollingDesktop(), store: store, codex: client)
        )
    }

    func writeActiveCredential() throws {
        try TestAuthFixture.authJSON(
            accountID: "poll-account",
            email: "poll@example.test",
            accessToken: "poll-token"
        ).write(to: active.appendingPathComponent("auth.json"))
    }

    func clean() { try? FileManager.default.removeItem(at: root) }
}

private actor GatedPollingClient: AccountClient {
    private(set) var readCount = 0
    private(set) var consumeCalls = 0
    private var activeReads = 0
    private(set) var maxConcurrentReads = 0
    private var shouldBlockRead = false
    private var blockedReadContinuations: [CheckedContinuation<Void, Never>] = []
    private var readWaiters: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var consumeWaiters: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var shouldBlockStop = false
    private var stopStarted = false
    private var stopStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var stopReleaseContinuations: [CheckedContinuation<Void, Never>] = []
    private var resetExpiry: Date?
    private var consumed = false

    func blockNextRead() { shouldBlockRead = true }
    func blockNextStopSession() { shouldBlockStop = true }
    func setResetExpiry(_ date: Date) { resetExpiry = date }

    func releaseBlockedReads() {
        shouldBlockRead = false
        let continuations = blockedReadContinuations
        blockedReadContinuations.removeAll()
        for continuation in continuations { continuation.resume() }
    }

    func releaseBlockedStopSession() {
        shouldBlockStop = false
        let continuations = stopReleaseContinuations
        stopReleaseContinuations.removeAll()
        for continuation in continuations { continuation.resume() }
    }

    func waitForReadStart(count: Int) async {
        if readCount >= count { return }
        await withCheckedContinuation { continuation in
            readWaiters.append((count, continuation))
        }
    }

    func waitForConsumeCalls(atLeast count: Int) async {
        if consumeCalls >= count { return }
        await withCheckedContinuation { continuation in
            consumeWaiters.append((count, continuation))
        }
    }

    func waitForStopSessionStart() async {
        if stopStarted { return }
        await withCheckedContinuation { continuation in
            stopStartWaiters.append(continuation)
        }
    }

    func stopUsageSession(profileHome: URL) async throws {
        stopStarted = true
        let waiters = stopStartWaiters
        stopStartWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        if shouldBlockStop {
            await withCheckedContinuation { continuation in
                stopReleaseContinuations.append(continuation)
            }
        }
    }

    func readIdentity(profileHome: URL) async throws -> AccountIdentity {
        AccountIdentity(accountID: "poll-account", email: "poll@example.test")
    }

    func readWeeklyUsage(profileHome: URL) async throws -> WeeklyUsage {
        readCount += 1
        activeReads += 1
        maxConcurrentReads = max(maxConcurrentReads, activeReads)
        defer { activeReads -= 1 }

        let matchingWaiters = readWaiters.filter { readCount >= $0.target }
        readWaiters.removeAll { readCount >= $0.target }
        for waiter in matchingWaiters { waiter.continuation.resume() }

        if shouldBlockRead {
            await withCheckedContinuation { continuation in
                blockedReadContinuations.append(continuation)
            }
        }

        return WeeklyUsage(
            remainingPercent: consumed ? 100 : 64,
            resetsAt: Date(timeIntervalSince1970: 2_000_000_000),
            fiveHourRemainingPercent: 40,
            resetCreditsRemaining: resetExpiry == nil ? nil : (consumed ? 0 : 1),
            resetCredits: consumed ? [] : resetExpiry.map {
                [BankedResetCredit(id: "fixture-credit", status: "available", resetType: "codexRateLimits", expiresAt: $0)]
            }
        )
    }

    func consumeResetCredit(profileHome: URL, creditID: String, idempotencyKey: String) async throws -> ResetCreditOutcome {
        consumeCalls += 1
        consumed = true
        let matchingWaiters = consumeWaiters.filter { consumeCalls >= $0.target }
        consumeWaiters.removeAll { consumeCalls >= $0.target }
        for waiter in matchingWaiters { waiter.continuation.resume() }
        return .reset
    }

    func login(profileHome: URL) async throws -> AccountIdentity {
        throw CodexClientError.loginFailed("Fixture login is disabled.")
    }
}

private struct PollingDesktop: DesktopControlling {
    func closeDesktop() async throws {}
    func reopenDesktop() async throws {}
}

private final class HostLineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) {
        lock.lock()
        buffer.append(data)
        lock.unlock()
    }

    func drain() throws -> [DecodedHostEnvelope] {
        lock.lock()
        let captured = buffer
        buffer.removeAll()
        lock.unlock()
        let lines = String(decoding: captured, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
        return try lines.map { try JSONDecoder().decode(DecodedHostEnvelope.self, from: Data($0.utf8)) }
    }
}

private struct DecodedHostEnvelope: Decodable {
    let kind: String
    let id: Int?
    let error: String?
    let state: DecodedHostSnapshot?
}

private struct DecodedHostSnapshot: Decodable {
    let settings: DecodedHostSettings
    let strings: [String: String]?
}

private struct DecodedHostSettings: Decodable {
    let language: String
    let showsMenuBarPercentage: Bool
}
