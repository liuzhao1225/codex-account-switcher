import Foundation

public enum ProviderConfigurationError: LocalizedError, Equatable, Sendable {
    case malformedConfiguration
    case providerNotConfigured(String)
    case providerDidNotActivate(String)

    public var errorDescription: String? {
        switch self {
        case .malformedConfiguration:
            "Codex returned an invalid provider configuration."
        case let .providerNotConfigured(identifier):
            "The Codex provider '\(identifier)' is not configured."
        case let .providerDidNotActivate(identifier):
            "Codex did not activate the provider '\(identifier)'."
        }
    }
}
