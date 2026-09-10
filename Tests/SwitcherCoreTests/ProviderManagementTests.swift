import Foundation
import Testing
@testable import SwitcherCore

struct ProviderManagementTests {
    @Test func fuzzySearchMatchesSeparatedAbbreviationsAndNames() {
        #expect(ModelSearch.score("g5m", id: "gpt-5-mini", name: "Compact") != nil)
        #expect(ModelSearch.score("G P T 5", id: "gpt-5", name: "") == 0)
        #expect(ModelSearch.score("小模型", id: "vendor-32b", name: "中文小模型") != nil)
        #expect(ModelSearch.score("unrelated", id: "gpt-5", name: "OpenAI") == nil)
        #expect(ModelSearch.score("", id: "anything", name: "") == 0)
    }

    @Test func discoveryNormalizesBasePathsAndRejectsCredentialRedirectDestinations() throws {
        #expect(try ProviderModelDiscovery.endpoint("https://example.test").absoluteString == "https://example.test/v1/models")
        #expect(try ProviderModelDiscovery.endpoint("https://example.test/api/v1/").path == "/api/v1/models")
        #expect(throws: ProviderSetupError.self) { try ProviderModelDiscovery.endpoint("https://key@example.test/v1") }
        #expect(throws: ProviderSetupError.self) { try ProviderModelDiscovery.endpoint("http://example.test/v1") }
        #expect(try ProviderModelDiscovery.endpoint("http://127.0.0.1:1234/v1").path == "/v1/models")
        let page = try ProviderModelDiscovery.parse(Data(#"{"data":[{"id":"vendor/model","display_name":"Vendor","supported_reasoning_efforts":["low","high"]}],"has_more":true,"last_id":"vendor/model"}"#.utf8))
        #expect(page.models.first?.reasoningOptions == ["low", "high"])
        #expect(page.nextCursor == "vendor/model")
        #expect(throws: ProviderSetupError.self) { try ProviderModelDiscovery.parse(Data(#"{"data":[],"has_more":true}"#.utf8)) }
    }

    @Test @MainActor func editorKeepsOrderAndSelectionAcrossSearchAndFetchWithoutLeakingKeys() async throws {
        let fixture = try ProviderFixture()
        defer { fixture.clean() }
        let model = fixture.controller()
        await model.start()
        await model.openProviderEditor()
        await model.fetchProviderModels(fixture.input)
        let first = try #require(model.providerEditor?.models.first?.id)
        model.enableProviderModel(id: first, enabled: true)
        model.chooseProviderDefaultModel(id: "gpt-5-mini")
        model.setProviderReasoning("high")
        model.moveProviderModel(id: "gpt-5-mini", offset: -1)
        let savedOrder = model.providerEditor?.models.map(\.id)
        model.searchProviderModels("g5m")
        #expect(model.providerEditor?.visibleModelIDs == ["gpt-5-mini"])
        model.sortProviderModels(.nameDescending)
        #expect(model.providerEditor?.models.map(\.id) == savedOrder)
        model.searchProviderModels("")
        model.sortProviderModels(.custom)
        await model.fetchProviderModels(fixture.input)
        #expect(model.providerEditor?.models.map(\.id) == savedOrder)
        #expect(model.providerEditor?.models.first?.reasoningEffort == "high")
        #expect(model.providerEditor?.defaultModelID == "gpt-5-mini")
        let snapshot = try JSONEncoder().encode(model.snapshot)
        #expect(!String(decoding: snapshot, as: UTF8.self).contains("synthetic-secret"))
        model.sortProviderModels(.nameDescending)
        await model.saveProvider(fixture.input)
        #expect(model.providerEditor?.didSave == true)
        #expect(model.settings.enablesProviderSwitching)
        #expect(try await fixture.store.loadProviderLibrary().providers.first?.models.map(\.id) == savedOrder)
        #expect(try await fixture.store.loadProviderLibrary().providers.first?.sort == .nameDescending)
        #expect(await fixture.rpc.configuredKey() == "synthetic-secret")
    }

    @Test @MainActor func pastedConnectionWhitespaceIsTrimmedForDiscoveryValidationAndSaving() async throws {
        let fixture = try ProviderFixture(); defer { fixture.clean() }
        let validator = ProviderValidationFixture()
        let model = fixture.controller(validator: validator)
        await model.start(); await model.openProviderEditor()
        var input = fixture.input
        input.baseURL = " \t\n" + input.baseURL + " \r\n"
        input.apiKey = " \t synthetic-secret \r\n"
        await model.fetchProviderModels(input)
        #expect(model.providerEditor?.error == nil)
        #expect(model.providerEditor?.baseURL == fixture.input.baseURL + "/")
        model.chooseProviderDefaultModel(id: "gpt-5-mini")
        await model.validateProviderConnection(input)
        #expect(await validator.baseURL == fixture.input.baseURL + "/")
        #expect(await validator.apiKey == "synthetic-secret")
        await model.saveProvider(input)
        #expect(model.providerEditor?.didSave == true)
        #expect(await fixture.rpc.configuredKey() == "synthetic-secret")
    }

    @Test @MainActor func manualModelsWorkWithoutAFetchAndChangedConnectionClearsOldSelection() async throws {
        let fixture = try ProviderFixture()
        defer { fixture.clean() }
        let model = fixture.controller()
        await model.start(); await model.openProviderEditor()
        model.addProviderModel(id: "custom-model", connection: fixture.input)
        model.chooseProviderDefaultModel(id: "custom-model")
        await model.saveProvider(fixture.input)
        #expect(model.providerEditor?.didSave == true)
        await model.openProviderEditor()
        await model.fetchProviderModels(fixture.input)
        model.chooseProviderDefaultModel(id: "gpt-5-mini")
        var changed = fixture.input
        changed.baseURL = "https://another.example.test/v1"
        await model.saveProvider(changed)
        #expect(model.providerEditor?.didSave == false)
        #expect(model.providerEditor?.models.isEmpty == true)
        #expect(model.providerEditor?.error != nil)
    }

    @Test @MainActor func movingUsesDisplayedOrderAndChangingKeyInvalidatesSelection() async throws {
        let fixture = try ProviderFixture()
        defer { fixture.clean() }
        let model = fixture.controller()
        await model.start(); await model.openProviderEditor()
        await model.fetchProviderModels(fixture.input)
        model.addProviderModel(id: "aaa")
        model.sortProviderModels(.nameAscending)
        let before = try #require(model.providerEditor?.visibleModelIDs)
        model.moveProviderModel(id: before[1], offset: -1)
        #expect(model.providerEditor?.models.first?.id == before[1])
        #expect(model.providerEditor?.sort == .custom)
        model.chooseProviderDefaultModel(id: "gpt-5-mini")
        var changed = fixture.input
        changed.apiKey = "another-synthetic-key"
        await model.saveProvider(changed)
        #expect(model.providerEditor?.didSave == false)
        #expect(model.providerEditor?.models.isEmpty == true)
    }

    @Test func savedProviderAppliesDefaultsAndRestoresNativeModelAndCatalog() async throws {
        let fixture = try ProviderFixture()
        defer { fixture.clean() }
        let provider = fixture.provider()
        try await fixture.manager.save(provider, apiKey: "synthetic-secret")
        #expect(await fixture.rpc.selectedProvider() == "openai")
        try await fixture.manager.activateProvider(id: provider.id, codexHome: fixture.home)
        #expect(await fixture.rpc.selectedModel() == "gpt-5-mini")
        #expect(await fixture.rpc.selectedEffort() == "high")
        #expect(await fixture.rpc.catalog() == nil)
        try await fixture.manager.activateProvider(id: "openai", codexHome: fixture.home)
        #expect(await fixture.rpc.selectedModel() == "native-original")
        #expect(await fixture.rpc.selectedEffort() == "medium")
        #expect(await fixture.rpc.catalog() == "/synthetic/native-models.json")
        let libraryBytes = try Data(contentsOf: fixture.root.appending(path: "store/providers.json"))
        #expect(!String(decoding: libraryBytes, as: UTF8.self).contains("synthetic-secret"))
    }

    @Test func rejectsNonResponsesInputAndEditingTheActiveProvider() async throws {
        let fixture = try ProviderFixture()
        defer { fixture.clean() }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(ProviderAPIFormat.self, from: Data("\"anthropic\"".utf8)) }
        let provider = fixture.provider()
        try await fixture.manager.save(provider, apiKey: "synthetic-secret")
        try await fixture.manager.activateProvider(id: provider.id, codexHome: fixture.home)
        await #expect(throws: ProviderSetupError.self) { try await fixture.manager.save(provider, apiKey: "replacement-secret") }
        #expect(await fixture.rpc.configuredKey() == "synthetic-secret")
    }

    @Test @MainActor func verificationIsSeparateFromDiscoveryAndInvalidatedByModelSettings() async throws {
        let fixture = try ProviderFixture(); defer { fixture.clean() }
        let validator = ProviderValidationFixture()
        let controller = fixture.controller(validator: validator)
        await controller.start(); await controller.openProviderEditor()
        await controller.fetchProviderModels(fixture.input)
        #expect(await validator.calls == 0)
        #expect(controller.providerEditor?.connectionVerified == false)
        controller.chooseProviderDefaultModel(id: "gpt-5-mini"); controller.setProviderReasoning("high")
        await controller.validateProviderConnection(fixture.input)
        #expect(controller.providerEditor?.connectionVerified == true)
        #expect(await validator.model == "gpt-5-mini")
        #expect(await validator.effort == "high")
        #expect(await fixture.rpc.writeCount == 0)
        controller.setProviderReasoning("low")
        #expect(controller.providerEditor?.connectionVerified == false)
        await controller.validateProviderConnection(fixture.input)
        controller.chooseProviderDefaultModel(id: "vendor-large")
        #expect(controller.providerEditor?.connectionVerified == false)
        await validator.fail()
        await controller.validateProviderConnection(fixture.input)
        #expect(controller.providerEditor?.connectionVerified == false)
        #expect(controller.providerEditor?.error == "HTTP 401")
    }

    @Test func validationRejectsModelsListsChatCompletionsAndIncompleteResponses() throws {
        for body in [#"{"data":[{"id":"gpt-5"}]}"#, #"{"choices":[{"message":{"content":"OK"}}]}"#,
                     #"{"object":"response","status":"incomplete","output":[]}"#,
                     #"{"object":"response","status":"completed","output":[]}"#] {
            #expect(throws: ProviderSetupError.self) { try ProviderModelDiscovery.checkValidationResponse(Data(body.utf8)) }
        }
        try ProviderModelDiscovery.checkValidationResponse(Data(#"{"object":"response","status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"OK"}]}]}"#.utf8))
    }

    @Test func failedConfigurationWriteDoesNotReportASavedProvider() async throws {
        let fixture = try ProviderFixture()
        defer { fixture.clean() }
        await fixture.rpc.rejectWrites()
        await #expect(throws: ProviderSetupError.self) { try await fixture.manager.save(fixture.provider(), apiKey: "synthetic-secret") }
        #expect(try await fixture.manager.savedProviders().isEmpty)
    }
}

private struct ProviderFixture {
    let root: URL
    let home: URL
    let store: AccountStore
    let rpc = ProviderRPCFixture()
    var manager: ProviderManager { ProviderManager(store: store, rpc: rpc) }
    var input: ProviderConnectionInput { ProviderConnectionInput(displayName: "Synthetic Service", baseURL: "https://example.test/v1", apiFormat: .responses, apiKey: "synthetic-secret") }
    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "provider-manager-\(UUID())")
        home = root.appending(path: "active")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        store = AccountStore(baseURL: root.appending(path: "store"), activeHomeURL: home)
    }
    func provider() -> ManagedProvider {
        ManagedProvider(id: "switcher_fixture", displayName: "Synthetic Service", baseURL: input.baseURL, apiFormat: .responses,
            models: [ProviderModel(id: "gpt-5-mini", isEnabled: true, reasoningEffort: "high")], defaultModelID: "gpt-5-mini")
    }
    @MainActor func controller(validator: any ProviderConnectionValidating = ProviderValidationFixture()) -> AccountController {
        let client = NativeAPITestClient()
        let desktop = NativeAPITestDesktop()
        return AccountController(store: store, codex: client, configuration: manager,
            switchService: SwitchService(desktop: desktop, store: store, codex: client, configuration: manager),
            providerSwitchService: ProviderSwitchService(desktop: desktop, store: store, codex: client, configuration: manager),
            modelDiscovery: ProviderDiscoveryFixture(), connectionValidator: validator)
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
}

private struct ProviderDiscoveryFixture: ProviderModelDiscovering {
    func fetchModels(baseURL: String, apiKey: String) async throws -> [ProviderModel] {
        [ProviderModel(id: "vendor-large"), ProviderModel(id: "gpt-5-mini", reasoningOptions: ["low", "high"]), ProviderModel(id: "vendor-small")]
    }
}

private actor ProviderRPCFixture: CodexConfigurationRPC {
    var value: [String: JSONValue] = ["model_provider": .string("openai"), "model": .string("native-original"),
        "model_reasoning_effort": .string("medium"), "model_catalog_json": .string("/synthetic/native-models.json"), "model_providers": .object([:])]
    var writeCount = 0
    private var rejectsWrites = false
    func rejectWrites() { rejectsWrites = true }
    func readConfiguration(profileHome: URL) -> JSONValue { .object(["config": .object(value)]) }
    func writeModelProvider(_ providerID: String, profileHome: URL) throws {
        try writeConfiguration(edits: [("model_provider", .string(providerID))], profileHome: profileHome)
    }
    func writeConfiguration(edits: [(String, JSONValue)], profileHome: URL) throws {
        if rejectsWrites { throw ProviderSetupError.invalidResponse }
        writeCount += 1
        for (path, newValue) in edits {
            let parts = path.split(separator: ".").map(String.init)
            if parts.count == 3 {
                var providers = value["model_providers"]?.objectValue ?? [:]
                var provider = providers[parts[1]]?.objectValue ?? [:]
                provider[parts[2]] = newValue
                providers[parts[1]] = .object(provider)
                value["model_providers"] = .object(providers)
            } else { value[path] = newValue }
        }
    }
    func selectedProvider() -> String? { value["model_provider"]?.stringValue }
    func selectedModel() -> String? { value["model"]?.stringValue }
    func selectedEffort() -> String? { value["model_reasoning_effort"]?.stringValue }
    func catalog() -> String? { value["model_catalog_json"]?.stringValue }
    func configuredKey() -> String? { value["model_providers"]?.objectValue?.values.first?["experimental_bearer_token"]?.stringValue }
}

private actor ProviderValidationFixture: ProviderConnectionValidating {
    var calls = 0
    var baseURL: String?
    var apiKey: String?
    var model: String?
    var effort: String?
    var shouldFail = false
    func fail() { shouldFail = true }
    func validateConnection(baseURL: String, apiKey: String, model: String, effort: String?) throws {
        calls += 1; self.model = model; self.effort = effort
        self.baseURL = baseURL; self.apiKey = apiKey
        if shouldFail { throw ProviderSetupError.http(401) }
    }
}
