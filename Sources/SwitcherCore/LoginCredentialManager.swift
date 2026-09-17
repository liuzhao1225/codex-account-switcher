import Foundation

struct LoginCredentialManager {
    let store: any AccountStoring
    let codex: any CodexIdentityReading

    func preserve(codexHome: URL) async throws -> SavedLoginState {
        switch try await codex.readAuthentication(profileHome: codexHome) {
        case .signedOut:
            return .signedOut
        case .apiKey:
            try await store.saveOpenAIAPICredential()
            return .apiKey
        case let .chatGPT(identity):
            let registry = try await store.loadRegistry()
            guard let activeID = registry.activeAccountID,
                  let profile = registry.accounts.first(where: { $0.id == activeID }) else {
                throw AccountStoreError.activeProfileMissing
            }
            guard identity.matches(profile) else { throw AccountStoreError.activeCredentialMismatch }
            try await store.saveCurrentCredential()
            return .chatGPT(activeID)
        }
    }

    func restore(_ state: SavedLoginState) async throws {
        switch state {
        case .signedOut: try await store.clearActiveCredential()
        case .apiKey: try await store.activateOpenAIAPICredential()
        case let .chatGPT(id): try await store.restoreActiveCredential(id: id)
        }
    }
}
