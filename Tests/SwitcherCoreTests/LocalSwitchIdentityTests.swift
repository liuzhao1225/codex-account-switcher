import Foundation
import Testing
@testable import SwitcherCore

struct LocalSwitchIdentityTests {
    @Test func switchesBetweenWorkspacesWithTheSameEmailWithoutAppServer() async throws {
        let fixture = try LocalSwitchFixture()
        defer { fixture.remove() }
        try await fixture.prepare()

        for profile in [fixture.target, fixture.original] {
            try await fixture.service.switchAccount(to: profile.id)
            #expect(try await fixture.store.loadRegistry().activeAccountID == profile.id)
            #expect(try await CredentialIdentity().readIdentity(profileHome: fixture.active).matches(profile))
            #expect(try Data(contentsOf: fixture.active.appending(path: "auth.json")) == fixture.credential(profile))
        }
        #expect(await fixture.desktop.calls == ["close", "open", "close", "open"])
    }

    @Test func firstActivationUsesTheInstalledCredential() async throws {
        let fixture = try LocalSwitchFixture()
        defer { fixture.remove() }
        try await fixture.addTarget()

        try await fixture.service.switchAccount(to: fixture.target.id)

        #expect(try await fixture.store.loadRegistry().activeAccountID == fixture.target.id)
        #expect(try await CredentialIdentity().readIdentity(profileHome: fixture.active).matches(fixture.target))
        #expect(await fixture.desktop.calls == ["close", "open"])
    }

    @Test func changedOriginalWorkspaceStopsBeforeSavingOrActivating() async throws {
        let fixture = try LocalSwitchFixture()
        defer { fixture.remove() }
        try await fixture.prepare()
        let originalHome = await fixture.store.profileHome(id: fixture.original.id)
        let savedOriginal = try Data(contentsOf: originalHome.appending(path: "auth.json"))
        let changedCredential = try fixture.credential(fixture.target)
        try changedCredential.write(to: fixture.active.appending(path: "auth.json"))

        do {
            try await fixture.service.switchAccount(to: fixture.target.id)
            Issue.record("A changed workspace must fail before saving the current credential.")
        } catch let error as OperationError {
            #expect(error.stage == .saveCurrentCredential)
        }
        #expect(try await fixture.store.loadRegistry().activeAccountID == fixture.original.id)
        #expect(try Data(contentsOf: originalHome.appending(path: "auth.json")) == savedOriginal)
        #expect(try Data(contentsOf: fixture.active.appending(path: "auth.json")) == changedCredential)
        #expect(await fixture.desktop.calls == ["close"])
    }

    @Test(arguments: ["malformed", #"{"tokens":{"account_id":"wrong-workspace"}}"#])
    func invalidTargetRestoresOriginalAndPreservesTheFailure(credential: String) async throws {
        let fixture = try LocalSwitchFixture()
        defer { fixture.remove() }
        try await fixture.prepare()
        let targetHome = await fixture.store.profileHome(id: fixture.target.id)
        try Data(credential.utf8).write(to: targetHome.appending(path: "auth.json"))

        do {
            try await fixture.service.switchAccount(to: fixture.target.id)
            Issue.record("An invalid installed credential must fail verification.")
        } catch let error as OperationError {
            #expect(error.stage == .verifyTargetIdentity)
            #expect(!error.message.isEmpty)
        }
        #expect(try await fixture.store.loadRegistry().activeAccountID == fixture.original.id)
        #expect(try Data(contentsOf: fixture.active.appending(path: "auth.json")) == fixture.credential(fixture.original))
        #expect(try Data(contentsOf: targetHome.appending(path: "auth.json")) == Data(credential.utf8))
        #expect(await fixture.desktop.calls == ["close"])
    }

    @Test func missingCredentialFailsExplicitly() async throws {
        let fixture = try LocalSwitchFixture()
        defer { fixture.remove() }
        await #expect(throws: CodexClientError.identityUnavailable) {
            try await CredentialIdentity().readIdentity(profileHome: fixture.active)
        }
    }
}

private struct LocalSwitchFixture {
    let root: URL
    let active: URL
    let store: AccountStore
    let desktop = LocalSwitchDesktop()
    let original = AccountProfile(id: UUID(), displayName: "Personal", email: "same@example.test",
                                  accountID: "personal-workspace", createdAt: Date())
    let target = AccountProfile(id: UUID(), displayName: "Work", email: "same@example.test",
                                accountID: "work-workspace", createdAt: Date())

    var service: SwitchService {
        SwitchService(desktop: desktop, store: store, codex: CredentialIdentity())
    }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "switcher-local-identity-\(UUID())")
        active = root.appending(path: "active")
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        store = AccountStore(baseURL: root.appending(path: "support"), activeHomeURL: active)
    }

    func prepare() async throws {
        try credential(original).write(to: active.appending(path: "auth.json"))
        try await store.importCurrentProfile(original)
        try await addTarget()
    }

    func addTarget() async throws {
        let home = try await store.createProfileDirectory(id: target.id)
        try credential(target).write(to: home.appending(path: "auth.json"))
        try await store.addProfile(target)
    }

    func credential(_ profile: AccountProfile) throws -> Data {
        let claims = try JSONSerialization.data(withJSONObject: ["email": profile.email!], options: .sortedKeys)
        let payload = claims.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return try JSONSerialization.data(withJSONObject: ["tokens": [
            "account_id": profile.accountID!, "id_token": "header.\(payload).signature",
        ]], options: .sortedKeys)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

private actor LocalSwitchDesktop: DesktopControlling {
    var calls: [String] = []
    func closeDesktop() { calls.append("close") }
    func reopenDesktop() { calls.append("open") }
}
