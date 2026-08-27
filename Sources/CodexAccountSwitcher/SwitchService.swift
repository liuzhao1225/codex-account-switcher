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
        let originalActiveID: UUID
        do {
            target = try await store.profile(id: targetID)
        } catch {
            throw OperationError.stage(.activateTargetCredential, error)
        }

        do {
            let registry = try await store.loadRegistry()
            guard let activeID = registry.activeAccountID,
                  registry.accounts.contains(where: { $0.id == activeID }) else {
                throw AccountStoreError.activeProfileMissing
            }
            originalActiveID = activeID
        } catch {
            throw OperationError.stage(.saveCurrentCredential, error)
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
            throw await restoringOriginalCredential(
                originalActiveID: originalActiveID,
                failedStage: .verifyTargetIdentity,
                originalError: error
            )
        }

        do {
            try await store.commitActiveAccountID(targetID)
        } catch {
            throw await restoringOriginalCredential(
                originalActiveID: originalActiveID,
                failedStage: .commitActiveAccountID,
                originalError: error
            )
        }

        do {
            try await desktop.reopenDesktop()
        } catch {
            throw OperationError.stage(.reopenDesktop, error)
        }
    }

    private func restoringOriginalCredential(
        originalActiveID: UUID,
        failedStage: SwitchStage,
        originalError: any Error
    ) async -> OperationError {
        do {
            try await store.restoreActiveCredential(id: originalActiveID)
            return OperationError.stage(failedStage, originalError)
        } catch let restorationError {
            return OperationError(
                stage: failedStage,
                titleKey: "switch_failed",
                messageKey: nil,
                message: """
                \(originalError.localizedDescription) Restoring the previous credential also failed: \
                \(restorationError.localizedDescription)
                """,
                underlyingDescription: """
                \(String(describing: originalError)); restoration: \
                \(String(describing: restorationError))
                """
            )
        }
    }
}
