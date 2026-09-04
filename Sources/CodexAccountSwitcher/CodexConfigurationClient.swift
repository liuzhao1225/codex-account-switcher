import Foundation

protocol ProviderConfigurationServicing: Sendable {
    func readConfiguration(codexHome: URL) async throws -> ProviderConfigurationSnapshot
    func activateProvider(id: String, codexHome: URL) async throws
}

struct CodexConfigurationClient: ProviderConfigurationServicing {
    static let openAIProviderID = "openai"

    let codex: CodexClient

    init(codex: CodexClient = CodexClient()) {
        self.codex = codex
    }

    func readConfiguration(codexHome: URL) async throws -> ProviderConfigurationSnapshot {
        let result = try await codex.readConfiguration(profileHome: codexHome)
        guard let config = result["config"]?.objectValue else {
            throw ProviderConfigurationError.malformedConfiguration
        }

        let activeProviderID = config["model_provider"]?.stringValue
            ?? Self.openAIProviderID
        let configuredProviders = config["model_providers"]?.objectValue ?? [:]
        let providers = configuredProviders.compactMap { identifier, value -> ProviderProfile? in
            guard identifier != Self.openAIProviderID,
                  let provider = value.objectValue
            else {
                return nil
            }
            let configuredName = provider["name"]?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = configuredName.flatMap { $0.isEmpty ? nil : $0 }
                ?? Self.displayName(for: identifier)
            return ProviderProfile(
                id: identifier,
                displayName: displayName
            )
        }
        .sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        return ProviderConfigurationSnapshot(
            activeProviderID: activeProviderID,
            providers: providers
        )
    }

    func activateProvider(id: String, codexHome: URL) async throws {
        let current = try await readConfiguration(codexHome: codexHome)
        let isBuiltInOpenAI = id == Self.openAIProviderID
        guard isBuiltInOpenAI || current.providers.contains(where: { $0.id == id }) else {
            throw ProviderConfigurationError.providerNotConfigured(id)
        }
        guard current.activeProviderID != id else { return }

        try await codex.writeModelProvider(id, profileHome: codexHome)
        let updated = try await readConfiguration(codexHome: codexHome)
        guard updated.activeProviderID == id else {
            throw ProviderConfigurationError.providerDidNotActivate(id)
        }
    }

    private static func displayName(for identifier: String) -> String {
        identifier
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
