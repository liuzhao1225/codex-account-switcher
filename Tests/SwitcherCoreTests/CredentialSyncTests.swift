import Foundation
import Testing
@testable import SwitcherCore

struct CredentialSyncTests {
    @Test func refreshCopiesCredentialsToTheirActualAccount() async throws {
        let fixture = try CredentialFixture()
        defer { fixture.clean() }
        let profile = fixture.profile("personal")
        try fixture.writeLive("personal", token: "old")
        try await fixture.store.importCurrentProfile(profile)
        let saved = await fixture.store.profileHome(id: profile.id).appending(path: "auth.json")
        try fixture.writeLive("personal", token: "fresh")
        #expect(try await fixture.store.syncActiveCredential().activeAccountID == profile.id)
        let fresh = try Data(contentsOf: saved)
        #expect(try fresh == Data(contentsOf: fixture.auth))

        // Same email, different workspace must leave the personal credential untouched.
        try fixture.writeLive("workspace", token: "other")
        let registry = try await fixture.store.syncActiveCredential()
        let workspace = try #require(registry.accounts.first(where: { $0.accountID == "workspace" }))
        #expect(try Data(contentsOf: saved) == fresh)
        #expect(registry.activeAccountID == workspace.id)
        #expect(registry.accounts.count == 2)
        #expect(try await fixture.store.syncActiveCredential().accounts.count == 2)
        let workspaceAuth = await fixture.store.profileHome(id: workspace.id).appending(path: "auth.json")
        #expect(try Data(contentsOf: workspaceAuth) == Data(contentsOf: fixture.auth))
    }

    @Test func legacyIDsComeFromEachSavedProfileAndPersist() async throws {
        let fixture = try CredentialFixture()
        defer { fixture.clean() }
        let legacy = fixture.profile(nil)
        try fixture.writeLive("personal", token: "old")
        try await fixture.store.importCurrentProfile(legacy)
        try fixture.writeLive("workspace", token: "fresh")
        let reopened = AccountStore(baseURL: fixture.base, activeHomeURL: fixture.active)
        #expect(try await reopened.loadRegistry().accounts.first?.accountID == "personal")
        let updated = try await reopened.syncActiveCredential()
        #expect(updated.activeAccountID != legacy.id)
        let restarted = AccountStore(baseURL: fixture.base, activeHomeURL: fixture.active)
        #expect(try await restarted.loadRegistry().accounts.first?.accountID == "personal")
    }

    @Test @MainActor func manualRegistrationFollowsTheCurrentLocalLogin() async throws {
        let fixture = try CredentialFixture()
        defer { fixture.clean() }
        let profile = fixture.profile("personal")
        try fixture.writeLive("personal", token: "old")
        try await fixture.store.importCurrentProfile(profile)
        let saved = await fixture.store.profileHome(id: profile.id).appending(path: "auth.json")
        let original = try Data(contentsOf: saved)
        let model = AccountController(store: fixture.store, codex: CredentialClient(),
                                      switchService: CredentialSwitch(store: fixture.store))
        await model.start()
        try fixture.writeLive("workspace", token: "other")
        await model.registerCurrentAccount()
        await model.waitForWeeklyUsageRefresh()
        let registry = try await fixture.store.loadRegistry()
        let workspace = try #require(registry.accounts.first { $0.accountID == "workspace" })
        #expect(registry.accounts.count == 2)
        #expect(model.activeAccountID == workspace.id)
        #expect(try Data(contentsOf: saved) == original)
        let workspaceAuth = await fixture.store.profileHome(id: workspace.id).appending(path: "auth.json")
        #expect(try Data(contentsOf: workspaceAuth) == Data(contentsOf: fixture.auth))
        #expect(model.visibleError == nil)
    }

    @Test func workspaceIdentityDoesNotMatchAnEmailOnlyProfile() {
        let known = AccountIdentity(accountID: "personal", email: "same@example.test")
        let unknown = AccountIdentity(accountID: nil, email: "same@example.test")
        let legacy = AccountProfile(id: UUID(), displayName: "Same", email: known.email, accountID: nil, createdAt: Date())
        let personal = AccountProfile(id: UUID(), displayName: "Same", email: known.email, accountID: "personal", createdAt: Date())
        #expect(!known.matches(legacy))
        #expect(!unknown.matches(personal))
        #expect(known.matches(personal))
    }

    @Test func tokenWorkspaceIDTakesPrecedenceOverDefaultClaim() throws {
        let claims = Data(#"{"email":"same@example.test","https://api.openai.com/auth":{"chatgpt_account_id":"personal"}}"#.utf8)
            .base64EncodedString()
        let data = try JSONSerialization.data(withJSONObject: ["tokens": ["account_id": "workspace", "id_token": "header.\(claims).signature"]])
        #expect(try CredentialIdentity.decode(data)?.accountID == "workspace")
        #expect(try CredentialIdentity.decode(data)?.email == "same@example.test")
    }

    @Test func malformedCredentialsNeverExposeTheirContents() {
        #expect(throws: CodexClientError.identityUnavailable) {
            try CredentialIdentity.decode(Data("private-token-malformed".utf8))
        }
    }

    @Test @MainActor func usageRefreshReadsTheUpdatedSavedCopy() async throws {
        let fixture = try CredentialFixture()
        defer { fixture.clean() }
        let profile = fixture.profile("personal")
        try fixture.writeLive("personal", token: "revoked")
        try await fixture.store.importCurrentProfile(profile)
        let client = CredentialClient()
        let model = AccountController(store: fixture.store, codex: client, switchService: CredentialSwitch(store: fixture.store))
        await model.start()
        try fixture.writeLive("personal", token: "fresh")
        model.refreshWeeklyUsage()
        await model.waitForWeeklyUsageRefresh()
        #expect(model.usageStates[profile.id]?.displayedUsage?.remainingPercent == 59)
        #expect(model.usageStates[profile.id]?.refreshError == nil)
        #expect(model.activeIdentityConfirmed)
    }

    @Test @MainActor func startupAndRefreshFollowExternalLoginChanges() async throws {
        let fixture = try CredentialFixture()
        defer { fixture.clean() }
        let first = fixture.profile("personal")
        let second = fixture.profile("workspace")
        try fixture.writeLive("personal", token: "old")
        try await fixture.store.importCurrentProfile(first)
        let secondHome = try await fixture.store.createProfileDirectory(id: second.id)
        try fixture.bytes("workspace", token: "old").write(to: secondHome.appending(path: "auth.json"))
        try await fixture.store.addProfile(second)
        try fixture.writeLive("workspace", token: "fresh")
        let model = AccountController(store: fixture.store, codex: CredentialClient(),
                                      switchService: CredentialSwitch(store: fixture.store))
        await model.start()
        #expect(model.activeAccountID == second.id)
        #expect(model.activeIdentityConfirmed)
        #expect(model.accounts.count == 2)
        #expect(try Data(contentsOf: secondHome.appending(path: "auth.json")) == Data(contentsOf: fixture.auth))

        try fixture.writeLive("personal", token: "fresh")
        model.refreshWeeklyUsage()
        await model.waitForWeeklyUsageRefresh()
        #expect(model.activeAccountID == first.id)
        #expect(model.activeIdentityConfirmed)
        #expect(try await fixture.store.loadRegistry().activeAccountID == first.id)
        #expect(model.visibleError == nil)
    }

    @Test @MainActor func refreshFindsLoginAfterStartingSignedOut() async throws {
        let fixture = try CredentialFixture()
        defer { fixture.clean() }
        let model = AccountController(store: fixture.store, codex: CredentialClient(),
                                      switchService: CredentialSwitch(store: fixture.store))
        await model.start()
        try fixture.writeLive("personal", token: "fresh")
        model.refreshWeeklyUsage()
        await model.waitForWeeklyUsageRefresh()
        let id = try #require(model.activeAccountID)
        #expect(model.accounts.count == 1)
        #expect(model.activeIdentityConfirmed)

        try FileManager.default.removeItem(at: fixture.auth)
        model.refreshWeeklyUsage()
        await model.waitForWeeklyUsageRefresh()
        #expect(model.activeAccountID == nil)
        #expect(!model.activeIdentityConfirmed)
        #expect(try await fixture.store.loadRegistry().activeAccountID == nil)

        try fixture.writeLive("personal", token: "renewed")
        model.refreshWeeklyUsage()
        await model.waitForWeeklyUsageRefresh()
        #expect(model.activeAccountID == id)
        #expect(model.activeIdentityConfirmed)
        #expect(model.accounts.count == 1)
    }

    @Test @MainActor func invalidLiveCredentialStopsRefreshAndShowsError() async throws {
        let fixture = try CredentialFixture()
        defer { fixture.clean() }
        let profile = fixture.profile("personal")
        try fixture.writeLive("personal", token: "fresh")
        try await fixture.store.importCurrentProfile(profile)
        let saved = await fixture.store.profileHome(id: profile.id).appending(path: "auth.json")
        let original = try Data(contentsOf: saved)
        let model = AccountController(store: fixture.store, codex: CredentialClient(),
                                      switchService: CredentialSwitch(store: fixture.store))
        await model.start()
        try Data("private-token-malformed".utf8).write(to: fixture.auth)
        model.refreshWeeklyUsage()
        await model.waitForWeeklyUsageRefresh()
        #expect(model.activeAccountID == nil)
        #expect(!model.activeIdentityConfirmed)
        #expect(model.visibleError?.message == CodexClientError.identityUnavailable.localizedDescription)
        #expect(model.usageStates.isEmpty)
        #expect(try Data(contentsOf: saved) == original)
    }

    @Test @MainActor func switchRechecksLiveLoginBeforeSkippingTheOldActiveAccount() async throws {
        let fixture = try CredentialFixture()
        defer { fixture.clean() }
        let first = fixture.profile("personal")
        try fixture.writeLive("personal", token: "fresh")
        try await fixture.store.importCurrentProfile(first)
        let model = AccountController(store: fixture.store, codex: CredentialClient(),
                                      switchService: CredentialSwitch(store: fixture.store))
        await model.start()
        try fixture.writeLive("workspace", token: "fresh")
        await model.switchAccount(to: first.id)
        await model.waitForWeeklyUsageRefresh()
        #expect(model.activeAccountID == first.id)
        #expect(try CredentialIdentity.read(from: fixture.active)?.accountID == "personal")
        #expect(model.accounts.count == 2)
        #expect(model.visibleError == nil)
    }

    @Test @MainActor func removalCannotDeleteAnAccountThatBecameActiveExternally() async throws {
        let fixture = try CredentialFixture()
        defer { fixture.clean() }
        let first = fixture.profile("personal")
        let second = fixture.profile("workspace")
        try fixture.writeLive("personal", token: "fresh")
        try await fixture.store.importCurrentProfile(first)
        let home = try await fixture.store.createProfileDirectory(id: second.id)
        try fixture.bytes("workspace", token: "old").write(to: home.appending(path: "auth.json"))
        try await fixture.store.addProfile(second)
        let model = AccountController(store: fixture.store, codex: CredentialClient(),
                                      switchService: CredentialSwitch(store: fixture.store))
        await model.start()
        try fixture.writeLive("workspace", token: "fresh")
        await model.removeAccount(id: second.id)
        await model.waitForWeeklyUsageRefresh()
        #expect(model.activeAccountID == second.id)
        #expect(model.accounts.count == 2)
        #expect(model.visibleError?.message == AccountStoreError.cannotRemoveActiveAccount.localizedDescription)
        #expect(try Data(contentsOf: home.appending(path: "auth.json")) == Data(contentsOf: fixture.auth))
    }

    @Test @MainActor func switchingDrainsOldRefreshBeforeChangingCredentials() async throws {
        let fixture = try CredentialFixture()
        defer { fixture.clean() }
        let first = fixture.profile("personal")
        let second = fixture.profile("workspace")
        try fixture.writeLive("personal", token: "fresh")
        try await fixture.store.importCurrentProfile(first)
        let secondHome = try await fixture.store.createProfileDirectory(id: second.id)
        try fixture.bytes("workspace", token: "fresh").write(to: secondHome.appending(path: "auth.json"))
        try await fixture.store.addProfile(second)
        let client = CredentialClient(pausesPersonal: true)
        let model = AccountController(store: fixture.store, codex: client, switchService: CredentialSwitch(store: fixture.store))
        await model.start()
        model.refreshWeeklyUsage()
        await client.waitForRead()
        let switching = Task { await model.switchAccount(to: second.id) }
        while !model.isMutating { await Task.yield() }
        #expect(try await fixture.store.loadRegistry().activeAccountID == first.id)
        await client.releaseRead()
        await switching.value
        await model.waitForWeeklyUsageRefresh()
        #expect(model.activeAccountID == second.id)
        #expect(model.activeIdentityConfirmed)
        #expect(try CredentialIdentity.read(from: fixture.active)?.accountID == "workspace")
        #expect(try await fixture.store.loadUsageCache().entries.allSatisfy { $0.usage.remainingPercent == 59 })
        #expect(model.usageStates[first.id]?.displayedUsage?.remainingPercent == 59)
        #expect(model.usageStates[second.id]?.displayedUsage?.remainingPercent == 59)
    }
}

private struct CredentialFixture {
    let root: URL
    let base: URL
    let active: URL
    let store: AccountStore
    var auth: URL { active.appending(path: "auth.json") }
    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "credential-sync-\(UUID())")
        base = root.appending(path: "store")
        active = root.appending(path: "active")
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        store = AccountStore(baseURL: base, activeHomeURL: active)
    }
    func profile(_ accountID: String?) -> AccountProfile {
        AccountProfile(id: UUID(), displayName: "Same", email: "same@example.test", accountID: accountID, createdAt: Date())
    }
    func bytes(_ id: String, token: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["tokens": ["account_id": id, "access_token": token]])
    }
    func writeLive(_ id: String, token: String) throws { try bytes(id, token: token).write(to: auth) }
    func clean() { try? FileManager.default.removeItem(at: root) }
}

private struct CredentialSwitch: SwitchServicing {
    let store: AccountStore
    func switchAccount(to id: UUID) async throws {
        try await store.activateTargetCredential(id: id)
        try await store.commitActiveAccountID(id)
    }
}

private actor CredentialClient: AccountClient {
    var pausesPersonal: Bool
    var readStarted = false
    var observer: CheckedContinuation<Void, Never>?
    var blocked: CheckedContinuation<Void, Never>?
    init(pausesPersonal: Bool = false) { self.pausesPersonal = pausesPersonal }
    func readIdentity(profileHome: URL) async throws -> AccountIdentity {
        guard let identity = try CredentialIdentity.read(from: profileHome) else { throw CodexClientError.identityUnavailable }
        return identity
    }
    func login(profileHome: URL) async throws -> AccountIdentity { try await readIdentity(profileHome: profileHome) }
    func consumeResetCredit(profileHome: URL, creditID: String, idempotencyKey: String) async throws -> ResetCreditOutcome {
        throw CodexClientError.remoteError(code: nil, message: "Unexpected reset consumption in this fixture.")
    }
    func readWeeklyUsage(profileHome: URL) async throws -> WeeklyUsage {
        let bytes = try String(contentsOf: profileHome.appending(path: "auth.json"), encoding: .utf8)
        if bytes.contains("revoked") { throw CodexClientError.identityUnavailable }
        if pausesPersonal, bytes.contains("personal") {
            pausesPersonal = false
            readStarted = true
            observer?.resume(); observer = nil
            // Deliberately return an old result even after cancellation.
            await withCheckedContinuation { blocked = $0 }
            return WeeklyUsage(remainingPercent: 17, resetsAt: Date(timeIntervalSince1970: 2_000_000_000))
        }
        return WeeklyUsage(remainingPercent: 59, resetsAt: Date(timeIntervalSince1970: 2_000_000_000))
    }
    func waitForRead() async {
        if !readStarted { await withCheckedContinuation { observer = $0 } }
    }
    func releaseRead() { blocked?.resume(); blocked = nil }
}
