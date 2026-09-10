import Foundation

public protocol ProviderManaging: Sendable {
    func savedProviders() async throws -> [ManagedProvider]
    func storedKey(providerID: String) async throws -> String
    func save(_ provider: ManagedProvider, apiKey: String?) async throws
}

/// Provider configuration and model selection use Codex's configuration API.
/// SwiftUI and WPF share this implementation, including returning to ChatGPT defaults.
public struct ProviderManager: ProviderManaging, ProviderConfigurationServicing {
    public let store: AccountStore
    private let codex: any CodexConfigurationRPC
    private var configuration: CodexConfigurationClient { CodexConfigurationClient(rpc: codex) }

    public init(store: AccountStore, codex: CodexClient) { self.store = store; self.codex = codex }
    init(store: AccountStore, rpc: any CodexConfigurationRPC) { self.store = store; codex = rpc }

    public func savedProviders() async throws -> [ManagedProvider] { try await store.loadProviderLibrary().providers }

    public func readConfiguration(codexHome: URL) async throws -> ProviderConfigurationSnapshot {
        try await configuration.readConfiguration(codexHome: codexHome)
    }

    public func storedKey(providerID: String) async throws -> String {
        let home = await store.activeCodexHome()
        let config = try await codex.readConfiguration(profileHome: home)
        guard let key = config["config"]?["model_providers"]?[providerID]?["experimental_bearer_token"]?.stringValue,
              !key.isEmpty else { throw ProviderSetupError.invalidKey }
        return key
    }

    public func save(_ provider: ManagedProvider, apiKey: String?) async throws {
        guard provider.apiFormat == .responses else { throw ProviderSetupError.unsupportedFormat }
        guard provider.id.hasPrefix("switcher_"), provider.id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") })
        else { throw ProviderSetupError.invalidResponse }
        let home = await store.activeCodexHome()
        let current = try await readConfiguration(codexHome: home)
        guard current.activeProviderID != provider.id else { throw ProviderSetupError.activeProvider }
        var library = try await store.loadProviderLibrary()
        if !library.providers.contains(where: { $0.id == provider.id }), current.providers.contains(where: { $0.id == provider.id }) {
            throw ProviderConfigurationError.providerNotConfigured(provider.id)
        }
        let key: String
        if let apiKey, !apiKey.isEmpty { key = apiKey }
        else { key = try await storedKey(providerID: provider.id) }
        guard !key.isEmpty, !key.contains("\n"), !key.contains("\r") else { throw ProviderSetupError.invalidKey }
        guard !provider.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ProviderSetupError.emptyName }
        guard let selected = provider.models.first(where: { $0.id == provider.defaultModelID }), selected.isEnabled else { throw ProviderSetupError.selectDefault }
        let endpoint = try ProviderModelDiscovery.endpoint(provider.baseURL).deletingLastPathComponent().absoluteString
        try await store.protectProviderConfiguration()
        let prefix = "model_providers." + provider.id + "."
        try await codex.writeConfiguration(edits: [
            (prefix + "name", .string(provider.displayName)), (prefix + "base_url", .string(endpoint)),
            (prefix + "wire_api", .string("responses")), (prefix + "requires_openai_auth", .bool(false)),
            (prefix + "experimental_bearer_token", .string(key)), (prefix + "env_key", .null),
        ], profileHome: home)
        try await store.protectProviderConfiguration()
        let readback = try await codex.readConfiguration(profileHome: home)
        guard let result = readback["config"]?["model_providers"]?[provider.id],
              result["name"]?.stringValue == provider.displayName,
              result["base_url"]?.stringValue == endpoint,
              result["experimental_bearer_token"]?.stringValue == key,
              result["wire_api"]?.stringValue == "responses" else { throw ProviderConfigurationError.malformedConfiguration }
        var saved = provider
        saved.baseURL = endpoint
        if let index = library.providers.firstIndex(where: { $0.id == provider.id }) { library.providers[index] = saved }
        else { library.providers.append(saved) }
        try await store.saveProviderLibrary(library)
    }

    public func activateProvider(id: String, codexHome: URL) async throws {
        let current = try await readConfiguration(codexHome: codexHome)
        guard id == CodexConfigurationClient.openAIProviderID || current.providers.contains(where: { $0.id == id })
        else { throw ProviderConfigurationError.providerNotConfigured(id) }
        guard current.activeProviderID != id else { return }
        var library = try await store.loadProviderLibrary()
        // Retain the existing simple switch behavior until a managed provider is used.
        guard !library.providers.isEmpty else {
            try await configuration.activateProvider(id: id, codexHome: codexHome)
            return
        }
        let raw = try await codex.readConfiguration(profileHome: codexHome)
        guard let source = raw["config"] else { throw ProviderConfigurationError.malformedConfiguration }
        library.selections[current.activeProviderID] = Self.selection(source)
        try await store.saveProviderLibrary(library)
        var selection = library.selections[id]
        if let target = library.providers.first(where: { $0.id == id }) {
            let model = target.models.first(where: { $0.id == target.defaultModelID && $0.isEnabled })
            guard let model else { throw ProviderSetupError.selectDefault }
            selection = ProviderModelSelection(model: model.id, reasoningEffort: model.reasoningEffort, modelCatalogPath: nil)
        }
        var edits: [(String, JSONValue)] = [("model_provider", .string(id))]
        if let selection {
            edits += [("model", selection.model.map(JSONValue.string) ?? .null),
                      ("model_reasoning_effort", selection.reasoningEffort.map(JSONValue.string) ?? .null),
                      ("model_catalog_json", selection.modelCatalogPath.map(JSONValue.string) ?? .null)]
        }
        try await codex.writeConfiguration(edits: edits, profileHome: codexHome)
        let updated = try await codex.readConfiguration(profileHome: codexHome)
        guard let config = updated["config"], (config["model_provider"]?.stringValue ?? "openai") == id else {
            throw ProviderConfigurationError.providerDidNotActivate(id)
        }
        if let selection, Self.selection(config) != selection { throw ProviderConfigurationError.providerDidNotActivate(id) }
    }

    private static func selection(_ config: JSONValue) -> ProviderModelSelection {
        ProviderModelSelection(model: config["model"]?.stringValue,
            reasoningEffort: config["model_reasoning_effort"]?.stringValue,
            modelCatalogPath: config["model_catalog_json"]?.stringValue)
    }
}
