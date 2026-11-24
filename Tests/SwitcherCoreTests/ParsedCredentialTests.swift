import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import SwitcherCore

struct ParsedCredentialTests {
    @Test func explicitTokenAccountIDTakesPrecedenceAndIsolatesPersonalClaims() throws {
        let data = try TestAuthFixture.authJSON(
            accountID: "workspace-b",
            claimAccountID: "personal-a",
            email: "user@example.test",
            planType: "plus",
            subscriptionActiveUntil: "2026-10-17T12:00:00Z",
            subscriptionLastChecked: "2026-10-03T12:00:00Z",
            accessToken: "valid-token"
        )
        let parsed = try ParsedCredential.decode(data)

        #expect(parsed.localIdentity == AccountIdentity(accountID: "workspace-b", email: "user@example.test"))
        #expect(parsed.subscriptionSnapshot(expectedAccountID: "workspace-b", expectedEmail: "user@example.test") == nil)
        #expect(parsed.subscriptionSnapshot(expectedAccountID: "personal-a", expectedEmail: "user@example.test") != nil)
        let login = try parsed.validatedSubscriptionLogin(expectedAccountID: "workspace-b", expectedEmail: "USER@EXAMPLE.TEST")
        #expect(login.accountID == "workspace-b")
        #expect(login.accessToken == "valid-token")
    }

    @Test func emailOnlyHistoricalSnapshotMatchesCaseInsensitivelyAndSkipsFreeOrMismatch() throws {
        let paid = try ParsedCredential.decode(try TestAuthFixture.authJSON(
            claimAccountID: "personal-a",
            email: "User@Example.test",
            planType: "plus",
            subscriptionActiveUntil: "2026-10-17T12:00:00.250Z",
            subscriptionLastChecked: "2026-10-03T12:00:00Z"
        ))
        #expect(paid.subscriptionSnapshot(expectedAccountID: nil, expectedEmail: "user@example.test") != nil)
        #expect(paid.subscriptionSnapshot(expectedAccountID: nil, expectedEmail: "other@example.test") == nil)

        let free = try ParsedCredential.decode(try TestAuthFixture.authJSON(
            claimAccountID: "personal-a",
            email: "user@example.test",
            planType: "free",
            subscriptionActiveUntil: "2026-10-17T12:00:00Z",
            subscriptionLastChecked: "2026-10-03T12:00:00Z"
        ))
        #expect(free.subscriptionSnapshot(expectedAccountID: nil, expectedEmail: "user@example.test") == nil)

        let badHeader = try ParsedCredential.decode(try TestAuthFixture.authJSON(
            accountID: "workspace-b",
            email: "user@example.test",
            accessToken: "token with spaces"
        ))
        #expect(throws: LiveSubscriptionError.invalidCredential) {
            try badHeader.validatedSubscriptionLogin(expectedAccountID: "workspace-b", expectedEmail: "user@example.test")
        }
    }

    @Test func externalLoginDuringSyncSuspensionIsPreserved() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("switcher-sync-suspend-\(UUID())")
        let store = AccountStore(baseURL: root.appendingPathComponent("store"), activeHomeURL: root.appendingPathComponent("active"))
        let activeAuth = root.appendingPathComponent("active/auth.json")
        defer { try? FileManager.default.removeItem(at: root) }

        let v1 = try TestAuthFixture.authJSON(accountID: "workspace-a", email: "a@example.test", accessToken: "v1")
        let v2 = try TestAuthFixture.authJSON(accountID: "workspace-a", email: "a@example.test", accessToken: "v2")
        let external = try TestAuthFixture.authJSON(accountID: "workspace-external", email: "ext@example.test", accessToken: "ext")

        try FileManager.default.createDirectory(at: activeAuth.deletingLastPathComponent(), withIntermediateDirectories: true)
        let profileA = AccountProfile(id: UUID(), displayName: "A", email: "a@example.test", accountID: "workspace-a", createdAt: Date())
        let homeA = try await store.createProfileDirectory(id: profileA.id)
        try v1.write(to: homeA.appendingPathComponent("auth.json"))
        try await store.addProfile(profileA)
        try v2.write(to: activeAuth)

        let registry = try await store.syncActiveCredential { stoppedHome in
            #expect(stoppedHome == homeA)
            try external.write(to: activeAuth, options: .atomic)
        }

        #expect(registry.accounts.count == 2)
        let externalProfile = try #require(registry.accounts.first { $0.accountID == "workspace-external" })
        #expect(registry.activeAccountID == externalProfile.id)
        #expect(try Data(contentsOf: homeA.appendingPathComponent("auth.json")) == v1)
        #expect(try Data(contentsOf: activeAuth) == external)
    }

    @Test @MainActor func sameEmailWorkspaceBlocks401RenewalAndIdentityMismatchPreservesInvalidCredential() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("switcher-renewal-guard-\(UUID())")
        let store = AccountStore(baseURL: root.appendingPathComponent("store"), activeHomeURL: root.appendingPathComponent("active"))
        let activeAuth = root.appendingPathComponent("active/auth.json")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: activeAuth.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Inactive profile A shares an email with active workspace B -> renewal must be blocked on 401.
        let inactiveID = UUID()
        let inactiveProfile = AccountProfile(
            id: inactiveID, displayName: "A", email: "same@example.test", accountID: "workspace-a", createdAt: Date()
        )
        let inactiveHome = try await store.createProfileDirectory(id: inactiveID)
        let inactiveCred = try TestAuthFixture.authJSON(
            accountID: "workspace-a", email: "same@example.test", accessToken: "stale-a"
        )
        try inactiveCred.write(to: inactiveHome.appendingPathComponent("auth.json"))
        try await store.addProfile(inactiveProfile)

        let activeProfile = AccountProfile(
            id: UUID(), displayName: "B", email: "same@example.test", accountID: "workspace-b", createdAt: Date()
        )
        try TestAuthFixture.authJSON(accountID: "workspace-b", email: "same@example.test", accessToken: "active-b")
            .write(to: activeAuth)
        try await store.seedActiveProfile(activeProfile)

        let codex = RenewalGuardCodex(identityToReturn: AccountIdentity(accountID: "wrong-workspace", email: "other@example.test"))
        let subClient = LiveSubscriptionClient(transport: { request in
            let url = try #require(request.url)
            let status = request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "workspace-a" ? 401 : 200
            let body = try JSONSerialization.data(withJSONObject: [
                "active_until": "2026-11-10T10:00:00Z", "plan_type": "plus", "is_active": true,
            ])
            return (body, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
        let model = AccountController(
            store: store,
            codex: codex,
            switchService: SwitchService(desktop: RenewalGuardDesktop(), store: store, codex: codex),
            subscriptionClient: subClient
        )

        await model.start()
        model.refreshWeeklyUsage()
        await model.waitForWeeklyUsageRefresh()

        #expect(await codex.renewalCount == 0)
        #expect(try Data(contentsOf: inactiveHome.appendingPathComponent("auth.json")) == inactiveCred)
        #expect(model.subscriptionStates[inactiveID] == .unavailable(LiveSubscriptionError.unauthenticated.localizedDescription))

        // Switch active login to a distinct email so renewal IS permitted, then verify identity mismatch preserves .invalidCredential.
        let distinctProfile = AccountProfile(
            id: UUID(), displayName: "C", email: "distinct@example.test", accountID: "workspace-c", createdAt: Date()
        )
        let distinctHome = try await store.createProfileDirectory(id: distinctProfile.id)
        try TestAuthFixture.authJSON(accountID: "workspace-c", email: "distinct@example.test", accessToken: "active-c")
            .write(to: distinctHome.appendingPathComponent("auth.json"))
        try await store.addProfile(distinctProfile)
        await model.switchAccount(to: distinctProfile.id)
        await model.waitForWeeklyUsageRefresh()

        #expect(await codex.renewalCount == 1)
        #expect(model.subscriptionStates[inactiveID] == .unavailable(LiveSubscriptionError.invalidCredential.localizedDescription))
    }
}

private actor RenewalGuardCodex: AccountClient {
    private(set) var renewalCount = 0
    private let identityToReturn: AccountIdentity

    init(identityToReturn: AccountIdentity) {
        self.identityToReturn = identityToReturn
    }

    func login(profileHome: URL) async throws -> AccountIdentity { identityToReturn }
    func readIdentity(profileHome: URL) async throws -> AccountIdentity {
        let data = try Data(contentsOf: profileHome.appendingPathComponent("auth.json"))
        let identity = try CredentialIdentity.decode(data)
        return try #require(identity)
    }
    func refreshIdentity(profileHome: URL) async throws -> AccountIdentity {
        renewalCount += 1
        return identityToReturn
    }
    func readWeeklyUsage(profileHome: URL) async throws -> WeeklyUsage {
        WeeklyUsage(remainingPercent: 80, resetsAt: Date().addingTimeInterval(3600))
    }
    func consumeResetCredit(profileHome: URL, creditID: String, idempotencyKey: String) async throws -> ResetCreditOutcome { .reset }
}

private struct RenewalGuardDesktop: DesktopControlling {
    func closeDesktop() async throws {}
    func reopenDesktop() async throws {}
}
