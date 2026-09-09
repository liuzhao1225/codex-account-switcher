import Foundation

public protocol ProviderConfigurationServicing: Sendable {
    func readConfiguration(codexHome: URL) async throws -> ProviderConfigurationSnapshot
    func activateProvider(id: String, codexHome: URL) async throws
}
