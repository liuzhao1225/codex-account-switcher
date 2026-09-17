import Foundation
import Testing
@testable import SwitcherCore

@MainActor
struct NativeAPITests {
    @Test func credentialRoundTripsAndFailureRestoration() async throws {
        try await NativeAPIScenarios.run { condition, message in
            #expect(condition, Comment(rawValue: message))
            if !condition { throw ScenarioFailure.assertion(message) }
        }
    }

    @Test func refreshAndPreparedSwitchRecoverAnExternalLogout() async throws {
        let fixture = try await SelectionFixture()
        defer { fixture.clean() }
        await fixture.model.start()
        try FileManager.default.removeItem(at: fixture.auth)
        await fixture.model.refresh()
        #expect(fixture.model.snapshot.activeAccountID == nil)
        await fixture.model.prepareAccountSwitch(to: fixture.account.id)
        #expect(fixture.model.pendingSwitch?.accountID == fixture.account.id)
        #expect(await fixture.desktop.counts().0 == 0)
        await fixture.model.confirmSwitch()
        #expect(fixture.model.isAccountActive(fixture.account))
        #expect(await fixture.desktop.counts().0 == 1)
    }

    @Test func externalAPILoginRequiresUpdatedRetentionConfirmation() async throws {
        let fixture = try await SelectionFixture()
        defer { fixture.clean() }
        await fixture.model.start()
        try FileManager.default.removeItem(at: fixture.auth)
        await fixture.model.prepareAccountSwitch(to: fixture.account.id)
        let signedOutConfirmation = try #require(fixture.model.pendingSwitch)
        try fixture.writeAPI()
        await fixture.model.confirmSwitch()
        #expect(fixture.model.pendingSwitch != signedOutConfirmation)
        #expect(fixture.model.pendingSwitch?.message.contains(fixture.model.text("native_api_storage_notice")) == true)
        #expect(await fixture.desktop.counts().0 == 0)
        #expect(await !fixture.store.hasOpenAIAPICredential())
        await fixture.model.confirmSwitch()
        #expect(fixture.model.visibleError == nil)
        #expect(await fixture.store.hasOpenAIAPICredential())
        #expect(fixture.model.isAccountActive(fixture.account))
    }

    @Test func APIAllowsDeletingHistoricalAccountAndClearsRegistrySelection() async throws {
        let fixture = try await SelectionFixture()
        defer { fixture.clean() }
        try fixture.writeAPI()
        await fixture.model.start()
        let row = try #require(fixture.model.snapshot.accounts.first)
        #expect(!row.isActive && !row.isCredentialOwner && row.canRemove)
        let originalAPI = try Data(contentsOf: fixture.auth)
        await fixture.model.removeAccount(id: fixture.account.id)
        #expect(fixture.model.visibleError == nil)
        #expect(fixture.model.accounts.isEmpty)
        #expect(try await fixture.store.loadRegistry().activeAccountID == nil)
        #expect(try Data(contentsOf: fixture.auth) == originalAPI)
    }

    @Test func customProviderKeepsUnderlyingChatGPTCredentialProtected() async throws {
        let fixture = try await SelectionFixture()
        defer { fixture.clean() }
        await fixture.configuration.activateProvider(id: "azure", codexHome: fixture.home)
        await fixture.model.start()
        let row = try #require(fixture.model.snapshot.accounts.first)
        #expect(!row.isActive && row.isCredentialOwner && !row.canRemove)
        await fixture.model.removeAccount(id: fixture.account.id)
        #expect(fixture.model.visibleError != nil)
        #expect(fixture.model.accounts.count == 1)
    }

    @Test func providerPreparationHonorsOptInAndNeverSwitchesBeforeConfirmation() async throws {
        let fixture = try await SelectionFixture()
        defer { fixture.clean() }
        await fixture.model.start()
        await fixture.model.prepareProviderSwitch(to: "azure")
        #expect(fixture.model.pendingSwitch == nil)
        await fixture.model.setEnablesProviderSwitching(true)
        await fixture.model.prepareProviderSwitch(to: "azure")
        #expect(fixture.model.pendingSwitch?.providerID == "azure")
        #expect(await fixture.desktop.counts().0 == 0)
        fixture.model.cancelSwitch()
        #expect(fixture.model.pendingSwitch == nil)
        await fixture.model.prepareProviderSwitch(to: "azure")
        await fixture.model.confirmSwitch()
        #expect(fixture.model.activeProviderID == "azure")
        #expect(fixture.model.snapshot.providers.first(where: { $0.profile.id == "azure" })?.isActive == true)
        await fixture.model.prepareAccountSwitch(to: fixture.account.id)
        #expect(fixture.model.pendingSwitch?.message.contains(fixture.model.text("return_account_model_notice")) == true)
        await fixture.model.confirmSwitch()
        #expect(fixture.model.isAccountActive(fixture.account))
        await fixture.model.prepareProviderSwitch(to: "azure")
        await fixture.model.setEnablesProviderSwitching(false)
        #expect(fixture.model.pendingSwitch == nil)
        #expect(fixture.model.activeProviderID == "openai")
    }
}

private enum ScenarioFailure: Error { case assertion(String) }

@MainActor
private struct SelectionFixture {
    let root: URL
    let home: URL
    let store: AccountStore
    let account: AccountProfile
    let model: AccountController
    let desktop = NativeAPITestDesktop()
    let configuration = NativeAPITestConfiguration()
    var auth: URL { home.appending(path: "auth.json") }

    init() async throws {
        root = FileManager.default.temporaryDirectory.appending(path: "selection-check-\(UUID())")
        home = root.appending(path: "active")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        account = AccountProfile(id: UUID(), displayName: "Saved", email: nil, accountID: "saved", createdAt: Date())
        store = AccountStore(baseURL: root.appending(path: "store"), activeHomeURL: home)
        let client = NativeAPITestClient()
        model = AccountController(store: store, codex: client, configuration: configuration,
            switchService: SwitchService(desktop: desktop, store: store, codex: client, configuration: configuration),
            providerSwitchService: ProviderSwitchService(desktop: desktop, store: store, codex: client, configuration: configuration))
        try Data(#"{"auth_mode":"chatgpt","tokens":{"account_id":"saved"}}"#.utf8).write(to: auth)
        try await store.importCurrentProfile(account)
    }
    func writeAPI() throws {
        try Data(#"{"auth_mode":"apikey","OPENAI_API_KEY":"synthetic-only"}"#.utf8).write(to: auth)
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
}
