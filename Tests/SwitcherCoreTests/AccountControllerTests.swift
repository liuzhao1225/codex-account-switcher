import Foundation
import Testing
@testable import SwitcherCore

@MainActor
struct AccountControllerTests {
    @Test func firstActivationInstallsAndCommitsTheSavedAccount() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        let id = UUID()
        let profile = AccountProfile(id: id, displayName: "Demo", email: "demo@example.test", accountID: "demo-account", createdAt: Date())
        let home = try await fixture.store.createProfileDirectory(id: id)
        try Data("saved-fixture".utf8).write(to: home.appendingPathComponent("auth.json"))
        try await fixture.store.addProfile(profile)
        let service = SwitchService(desktop: FixtureDesktop(), store: fixture.store, codex: fixture.client)
        try await service.switchAccount(to: id)
        #expect(try await fixture.store.loadRegistry().activeAccountID == id)
        #expect(try String(contentsOf: fixture.active.appendingPathComponent("auth.json"), encoding: .utf8) == "saved-fixture")
    }

    @Test func failedFirstActivationRestoresTheUnsignedInState() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        let id = UUID()
        let profile = AccountProfile(id: id, displayName: "Other", email: "other@example.test", accountID: "other", createdAt: Date())
        let home = try await fixture.store.createProfileDirectory(id: id)
        try Data("saved-other-fixture".utf8).write(to: home.appendingPathComponent("auth.json"))
        try await fixture.store.addProfile(profile)
        let service = SwitchService(desktop: FixtureDesktop(), store: fixture.store, codex: fixture.client)
        do { try await service.switchAccount(to: id); Issue.record("Identity mismatch should fail.") }
        catch { #expect((error as? OperationError)?.stage == .verifyTargetIdentity) }
        #expect(try await fixture.store.loadRegistry().activeAccountID == nil)
        #expect(await !fixture.store.activeCredentialExists())
        #expect(try String(contentsOf: home.appendingPathComponent("auth.json"), encoding: .utf8) == "saved-other-fixture")
    }

    @Test func firstActivationRechecksForCredentialsCreatedDuringDesktopExit() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        let id = UUID()
        let profile = AccountProfile(id: id, displayName: "Demo", email: "demo@example.test", accountID: "demo-account", createdAt: Date())
        let home = try await fixture.store.createProfileDirectory(id: id)
        try Data("saved-fixture".utf8).write(to: home.appendingPathComponent("auth.json"))
        try await fixture.store.addProfile(profile)
        let active = fixture.active
        let desktop = CredentialCreatingDesktop(active: active)
        let service = SwitchService(desktop: desktop, store: fixture.store, codex: fixture.client)
        do { try await service.switchAccount(to: id); Issue.record("An unexpected active login should stop switching.") }
        catch { #expect((error as? OperationError)?.stage == .saveCurrentCredential) }
        #expect(try String(contentsOf: active.appendingPathComponent("auth.json"), encoding: .utf8) == "unexpected-fixture")
        #expect(try await fixture.store.loadRegistry().activeAccountID == nil)
    }

    @Test func startupImportsCurrentLoginOnce() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        try fixture.writeActiveCredential()
        await fixture.model.start()
        await fixture.model.start()
        #expect(fixture.model.accounts.count == 1)
        #expect(fixture.model.activeAccountID == fixture.model.accounts.first?.id)
        #expect(fixture.model.activeIdentityConfirmed)
    }

    @Test func emptyStartupDoesNotCreateAnAccount() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        await fixture.model.start()
        #expect(fixture.model.accounts.isEmpty)
        #expect(fixture.model.visibleError == nil)
    }

    @Test func startupUsesTheLocalCredentialAsTheIdentitySource() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        let credential = Data(#"{"tokens":{"account_id":"different-workspace"}}"#.utf8)
        try credential.write(to: fixture.active.appendingPathComponent("auth.json"))
        await fixture.model.start()
        #expect(fixture.model.accounts.count == 1)
        #expect(fixture.model.accounts.first?.accountID == "different-workspace")
        #expect(fixture.model.activeAccountID == fixture.model.accounts.first?.id)
        #expect(fixture.model.activeIdentityConfirmed)
        #expect(fixture.model.visibleError == nil)
        #expect(try Data(contentsOf: fixture.active.appendingPathComponent("auth.json")) == credential)
    }

    @Test func registerUsesLocalIdentityAndPreservesProfileWithoutAnRPC() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        try fixture.writeActiveCredential()
        await fixture.model.start()
        let id = fixture.model.activeAccountID
        await fixture.model.registerCurrentAccount()
        #expect(fixture.model.accounts.count == 1)
        #expect(fixture.model.activeAccountID == id)
        #expect(await fixture.client.identityReads == 0)
        await fixture.model.waitForWeeklyUsageRefresh()
    }

    @Test(arguments: [false, true])
    func registerReportsMissingOrMalformedCredentials(malformed: Bool) async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        await fixture.model.start()
        if malformed {
            try Data("invalid-test-credential".utf8).write(to: fixture.active.appendingPathComponent("auth.json"))
        }
        await fixture.model.registerCurrentAccount()
        await fixture.model.waitForWeeklyUsageRefresh()
        #expect(fixture.model.accounts.isEmpty)
        #expect(fixture.model.visibleError?.message == (malformed
            ? CodexClientError.identityUnavailable.localizedDescription
            : AccountStoreError.activeCredentialMissing.localizedDescription))
        #expect(await fixture.client.identityReads == 0)
    }

    @Test func refreshKeepsLastGoodUsageWhenTheServerFails() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        try fixture.writeActiveCredential()
        await fixture.model.start()
        fixture.model.refreshWeeklyUsage()
        await fixture.model.waitForWeeklyUsageRefresh()
        let id = try #require(fixture.model.activeAccountID)
        #expect(fixture.model.usageStates[id]?.displayedUsage?.remainingPercent == 72)
        await fixture.client.failUsage()
        fixture.model.refreshWeeklyUsage()
        await fixture.model.waitForWeeklyUsageRefresh()
        #expect(fixture.model.usageStates[id]?.displayedUsage?.remainingPercent == 72)
        #expect(fixture.model.usageStates[id]?.refreshError != nil)
        #expect(try await fixture.store.loadUsageCache().entries.first?.usage.remainingPercent == 72)
    }

    @Test func settingsAreSavedImmediately() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        await fixture.model.start()
        await fixture.model.setLanguage(.simplifiedChinese)
        await fixture.model.setShowsMenuBarPercentage(false)
        await fixture.model.setShowsFiveHourUsage(true)
        await fixture.model.setStatusBarUsageWindow(.weekly)
        let saved = try await fixture.store.loadSettings()
        #expect(saved.language == .simplifiedChinese)
        #expect(!saved.showsMenuBarPercentage)
        #expect(saved.showsFiveHourUsage)
        #expect(saved.statusBarUsageWindow == .weekly)
    }

    @Test func statusBarUsesSelectedUsageWindow() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        try fixture.writeActiveCredential()
        await fixture.model.start()
        fixture.model.refreshWeeklyUsage()
        await fixture.model.waitForWeeklyUsageRefresh()
        #expect(fixture.model.activeRemainingPercent == 18)
        await fixture.model.setStatusBarUsageWindow(.weekly)
        #expect(fixture.model.activeRemainingPercent == 72)
    }

    @Test func autoResetConsumesBeforeOrdinaryPollAndStopsWhenDisabled() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.model.stopBackgroundUsageRefresh(); fixture.clean() }
        try fixture.writeActiveCredential()
        await fixture.client.setResetExpiry(Date().addingTimeInterval(602))
        await fixture.model.startBackgroundUsageRefresh(every: .seconds(3600))
        await fixture.model.waitForWeeklyUsageRefresh()
        #expect(!FileManager.default.fileExists(atPath: fixture.store.resetExpiryLogURL.path))
        await fixture.model.setAutoResetEnabled(true)
        await fixture.model.waitForWeeklyUsageRefresh()
        #expect(try await fixture.store.loadSettings().autoResetEnabled)
        try await Task.sleep(for: .seconds(3))
        await fixture.model.waitForWeeklyUsageRefresh()
        let events = try await fixture.store.loadResetExpiryLog()
        #expect(events.contains { $0.checkpointMinutes == 10 && $0.decision == "attempt" })
        #expect(events.contains { $0.event == "reset_result" && $0.outcome == .reset && $0.resetAttempted })
        #expect(events.contains { $0.event == "reset_verified" && $0.usage?.remainingPercent == 100 })
        #expect(await fixture.client.consumeCalls == 1)
        #expect(fixture.model.usageStates.values.first?.displayedUsage?.resetCreditsRemaining == 0)
        await fixture.model.setAutoResetEnabled(false)
        let count = try await fixture.store.loadResetExpiryLog().count
        fixture.model.refreshWeeklyUsage()
        await fixture.model.waitForWeeklyUsageRefresh()
        #expect(try await fixture.store.loadResetExpiryLog().count == count)
        #expect(try await !fixture.store.loadSettings().autoResetEnabled)
        #expect(fixture.model.visibleError == nil)
    }

    @Test func experimentLogFailureIsVisible() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        await fixture.model.start()
        try FileManager.default.createDirectory(at: fixture.store.resetExpiryLogURL, withIntermediateDirectories: false)
        await fixture.model.setAutoResetEnabled(true)
        #expect(fixture.model.visibleError != nil)
    }

    @Test func resetFailurePreservesOriginalErrorAndNeverRetriesAfterRestart() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        try fixture.writeActiveCredential()
        await fixture.client.setResetExpiry(Date().addingTimeInterval(590))
        await fixture.client.failReset()
        await fixture.model.start()
        await fixture.model.setAutoResetEnabled(true)
        await fixture.model.waitForWeeklyUsageRefresh()
        #expect(await fixture.client.consumeCalls == 1)
        #expect(fixture.model.visibleError?.message.contains("fixture reset unavailable") == true)
        let events = try await fixture.store.loadResetExpiryLog()
        #expect(events.last?.event == "reset_result")
        #expect(events.last?.error?.contains("503") == true)
        // Reinitializing from saved history must retain the failed attempt.
        await fixture.model.setAutoResetEnabled(false)
        await fixture.model.setAutoResetEnabled(true)
        await fixture.model.waitForWeeklyUsageRefresh()
        #expect(await fixture.client.consumeCalls == 1)
    }

    @Test(arguments: [true, false])
    func allSavedAccountsConsumeWithoutChangingTheActiveLogin(hasActiveLogin: Bool) async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        if hasActiveLogin { try fixture.writeActiveCredential() }
        for index in 1...2 {
            let profile = AccountProfile(id: UUID(), displayName: "Saved \(index)", email: "saved\(index)@example.test",
                accountID: "saved-\(index)", createdAt: Date())
            let home = try await fixture.store.createProfileDirectory(id: profile.id)
            try Data("saved-fixture".utf8).write(to: home.appending(path: "auth.json"))
            try await fixture.store.addProfile(profile)
        }
        await fixture.model.start()
        let originalActiveID = fixture.model.activeAccountID
        await fixture.client.setResetExpiry(Date().addingTimeInterval(590))
        await fixture.model.setAutoResetEnabled(true)
        await fixture.model.waitForWeeklyUsageRefresh()
        #expect(await fixture.client.consumeCalls == (hasActiveLogin ? 3 : 2))
        #expect(fixture.model.activeAccountID == originalActiveID)
        #expect(fixture.model.usageStates.values.allSatisfy { $0.displayedUsage?.resetCreditsRemaining == 0 })
        let events = try await fixture.store.loadResetExpiryLog()
        #expect(Set(events.filter { $0.event == "reset_verified" }.compactMap(\.profileID)) == Set(fixture.model.accounts.map(\.id)))
        #expect(fixture.model.visibleError == nil)
    }

    @Test func successfulReplyWithoutConsumptionIsLoggedAsVerificationFailure() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        try fixture.writeActiveCredential()
        await fixture.client.setResetExpiry(Date().addingTimeInterval(590))
        await fixture.client.doNotConfirmConsumption()
        await fixture.model.start()
        await fixture.model.setAutoResetEnabled(true)
        await fixture.model.waitForWeeklyUsageRefresh()
        let events = try await fixture.store.loadResetExpiryLog()
        #expect(events.contains { $0.event == "reset_result" && $0.outcome == .reset })
        #expect(events.last?.event == "reset_verification_failed")
        #expect(events.last?.usage?.resetCreditsRemaining == 1)
        #expect(fixture.model.visibleError?.message.contains("did not confirm") == true)
        #expect(!events.contains { $0.event == "reset_verified" })
        fixture.model.refreshWeeklyUsage()
        await fixture.model.waitForWeeklyUsageRefresh()
        #expect(await fixture.client.consumeCalls == 1)
    }

    @Test func activeProfileCannotBeRemoved() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        try fixture.writeActiveCredential()
        await fixture.model.start()
        let id = try #require(fixture.model.activeAccountID)
        await fixture.model.removeAccount(id: id)
        #expect(fixture.model.accounts.count == 1)
        #expect(fixture.model.visibleError != nil)
    }

    @Test func snapshotContainsPresentationButNoCredentialContents() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        try fixture.writeActiveCredential()
        await fixture.model.start()
        let data = try JSONEncoder().encode(fixture.model.snapshot)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("fixture-secret-token"))
        #expect(json.contains("demo@example.test"))
    }
}

@MainActor
private struct ControllerFixture {
    let root: URL
    let active: URL
    let store: AccountStore
    let client: FixtureClient
    let model: AccountController
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("switcher-core-test-\(UUID())")
        active = root.appendingPathComponent("active")
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        store = AccountStore(baseURL: root.appendingPathComponent("store"), activeHomeURL: active)
        client = FixtureClient()
        model = AccountController(store: store, codex: client,
            switchService: SwitchService(desktop: FixtureDesktop(), store: store, codex: client))
    }
    func writeActiveCredential() throws {
        let claims = Data(#"{"email":"demo@example.test"}"#.utf8).base64EncodedString()
        try JSONSerialization.data(withJSONObject: ["tokens": [
            "account_id": "demo-account", "access_token": "fixture-secret-token",
            "id_token": "header.\(claims).signature",
        ]])
            .write(to: active.appendingPathComponent("auth.json"))
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
}

private actor FixtureClient: AccountClient {
    private(set) var identityReads = 0
    private var usageFails = false
    private var resetExpiry: Date?
    private var consumedHomes: Set<URL> = []
    private var resetFails = false
    private var confirmsConsumption = true
    private(set) var consumeCalls = 0
    func failReset() { resetFails = true }
    func doNotConfirmConsumption() { confirmsConsumption = false }
    func consumeResetCredit(profileHome: URL, creditID: String, idempotencyKey: String) async throws -> ResetCreditOutcome {
        consumeCalls += 1
        #expect(creditID == "fixture-credit")
        #expect(UUID(uuidString: idempotencyKey) != nil)
        if resetFails { throw CodexClientError.remoteError(code: 503, message: "fixture reset unavailable") }
        if confirmsConsumption { consumedHomes.insert(profileHome) }
        return .reset
    }
    func failUsage() { usageFails = true }
    func setResetExpiry(_ date: Date) { resetExpiry = date }
    func readIdentity(profileHome: URL) async throws -> AccountIdentity {
        identityReads += 1
        return AccountIdentity(accountID: "demo-account", email: "demo@example.test")
    }
    func readWeeklyUsage(profileHome: URL) async throws -> WeeklyUsage {
        if usageFails { throw CodexClientError.connectionClosed }
        let resetConsumed = consumedHomes.contains(profileHome)
        return WeeklyUsage(
            remainingPercent: resetConsumed ? 100 : 72,
            resetsAt: Date(timeIntervalSince1970: 2_000_000_000),
            fiveHourRemainingPercent: 18,
            resetCreditsRemaining: resetExpiry == nil ? nil : (resetConsumed ? 0 : 1),
            resetCredits: resetConsumed ? [] : resetExpiry.map { [BankedResetCredit(id: "fixture-credit", status: "available", resetType: "codexRateLimits", expiresAt: $0)] }
        )
    }
    func login(profileHome: URL) async throws -> AccountIdentity {
        throw CodexClientError.loginFailed("Fixture login is disabled.")
    }
}

private struct FixtureDesktop: DesktopControlling {
    func closeDesktop() async throws {}
    func reopenDesktop() async throws {}
}

private struct CredentialCreatingDesktop: DesktopControlling {
    let active: URL
    func closeDesktop() async throws {
        try Data("unexpected-fixture".utf8).write(to: active.appendingPathComponent("auth.json"))
    }
    func reopenDesktop() async throws {}
}
