import Foundation

protocol DesktopControlling: Sendable {
    func closeDesktop() async throws
    func reopenDesktop() async throws
}

protocol CodexIdentityReading: Sendable {
    func readIdentity(profileHome: URL) async throws -> AccountIdentity
}

protocol SwitchServicing: Sendable {
    func switchAccount(to targetID: UUID) async throws
}

struct SwitchService: SwitchServicing {
    let desktop: any DesktopControlling
    let store: any AccountStoring
    let codex: any CodexIdentityReading

    func switchAccount(to targetID: UUID) async throws {
        let target: AccountProfile
        do {
            target = try await store.profile(id: targetID)
        } catch {
            throw OperationError.stage(.activateTargetCredential, error)
        }

        do {
            try await desktop.closeDesktop()
        } catch {
            throw OperationError.stage(.closeDesktop, error)
        }

        do {
            try await store.saveCurrentCredential()
        } catch {
            throw OperationError.stage(.saveCurrentCredential, error)
        }

        do {
            try await store.activateTargetCredential(id: targetID)
        } catch {
            throw OperationError.stage(.activateTargetCredential, error)
        }

        do {
            let identity = try await codex.readIdentity(profileHome: await store.activeCodexHome())
            guard identity.matches(target) else {
                throw CodexClientError.identityUnavailable
            }
        } catch {
            throw OperationError.stage(.verifyTargetIdentity, error)
        }

        do {
            try await store.commitActiveAccountID(targetID)
        } catch {
            throw OperationError.stage(.commitActiveAccountID, error)
        }

        do {
            try await desktop.reopenDesktop()
        } catch {
            throw OperationError.stage(.reopenDesktop, error)
        }
    }
}
