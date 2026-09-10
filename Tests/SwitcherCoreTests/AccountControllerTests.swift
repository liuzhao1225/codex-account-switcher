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
        let service = SwitchService(desktop: FixtureDesktop(), store: fixture.store, codex: fixture.client, configuration: fixture.configuration)
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
        let service = SwitchService(desktop: FixtureDesktop(), store: fixture.store, codex: fixture.client, configuration: fixture.configuration)
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
        let service = SwitchService(desktop: desktop, store: fixture.store, codex: fixture.client, configuration: fixture.configuration)
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

    @Test func registerUsesExistingIdentityAndPreservesProfile() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.clean() }
        try fixture.writeActiveCredential()
        await fixture.model.start()
        let id = fixture.model.activeAccountID
        await fixture.model.registerCurrentAccount()
        #expect(fixture.model.accounts.count == 1)
        #expect(fixture.model.activeAccountID == id)
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
        let saved = try await fixture.store.loadSettings()
        #expect(saved.language == .simplifiedChinese)
        #expect(!saved.showsMenuBarPercentage)
        #expect(saved.showsFiveHourUsage)
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

    @Test func pendingLoginCanBeCancelledAfterRefreshAndStartedAgain() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.model.cancelAddingAccount(); fixture.clean() }
        try fixture.writeActiveCredential()
        await fixture.model.start()
        let originalIDs = fixture.model.accounts.map(\.id)
        // A failed attempt must not leave its error over a later pending login.
        fixture.model.addAccount()
        for _ in 0..<100 where fixture.model.isAddingAccount { try await Task.sleep(for: .milliseconds(10)) }
        #expect(fixture.model.visibleError != nil)
        await fixture.client.waitForLogin()
        for attempt in 1...2 {
            fixture.model.addAccount()
            #expect(fixture.model.visibleError == nil)
            fixture.model.addAccount() // Ignore duplicate clicks during the same attempt.
            for _ in 0..<100 {
                if await fixture.client.pendingHomes.count == attempt { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            let homes = await fixture.client.pendingHomes
            #expect(homes.count == attempt)
            let home = try #require(homes.last)
            #expect(FileManager.default.fileExists(atPath: home.path))
            await fixture.model.refresh() // The menu's reopen refresh must not finish or replace login.
            #expect(fixture.model.isAddingAccount)
            fixture.model.cancelAddingAccount()
            for _ in 0..<100 where fixture.model.isAddingAccount { try await Task.sleep(for: .milliseconds(10)) }
            #expect(!fixture.model.isAddingAccount)
            #expect(fixture.model.visibleError == nil)
            #expect(fixture.model.accounts.map(\.id) == originalIDs)
            #expect(!FileManager.default.fileExists(atPath: home.path))
        }
        #expect(try String(contentsOf: fixture.active.appendingPathComponent("auth.json"), encoding: .utf8) == "fixture-secret-token")
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
    let configuration = ControllerConfigurationFixture()
    let model: AccountController
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("switcher-core-test-\(UUID())")
        active = root.appendingPathComponent("active")
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        store = AccountStore(baseURL: root.appendingPathComponent("store"), activeHomeURL: active)
        client = FixtureClient()
        model = AccountController(store: store, codex: client, configuration: configuration,
            switchService: SwitchService(desktop: FixtureDesktop(), store: store, codex: client,
                                         configuration: configuration),
            providerSwitchService: ProviderSwitchService(desktop: FixtureDesktop(), store: store,
                                                         codex: client, configuration: configuration))
    }
    func writeActiveCredential() throws {
        try Data("fixture-secret-token".utf8).write(to: active.appendingPathComponent("auth.json"))
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
}

private actor FixtureClient: AccountClient {
    private var usageFails = false
    private var pendingLogin = false
    private(set) var pendingHomes: [URL] = []
    func waitForLogin() { pendingLogin = true }
    func failUsage() { usageFails = true }
    func readAuthentication(profileHome: URL) async throws -> CodexAuthenticationState {
        guard FileManager.default.fileExists(atPath: profileHome.appending(path: "auth.json").path) else { return .signedOut }
        return .chatGPT(try await readIdentity(profileHome: profileHome))
    }
    func readIdentity(profileHome: URL) async throws -> AccountIdentity {
        AccountIdentity(accountID: "demo-account", email: "demo@example.test")
    }
    func readWeeklyUsage(profileHome: URL) async throws -> WeeklyUsage {
        if usageFails { throw CodexClientError.connectionClosed }
        return WeeklyUsage(remainingPercent: 72, resetsAt: Date(timeIntervalSince1970: 2_000_000_000))
    }
    func login(profileHome: URL) async throws -> AccountIdentity {
        if pendingLogin { pendingHomes.append(profileHome); try await Task.sleep(for: .seconds(60)) }
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
