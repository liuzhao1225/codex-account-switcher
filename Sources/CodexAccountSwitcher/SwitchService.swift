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
    let configuration: any ProviderConfigurationServicing

    func switchAccount(to targetID: UUID) async throws {
        let target: AccountProfile
        let originalActiveID: UUID
        let codexHome = await store.activeCodexHome()
        let originalProviderID: String
        do {
            target = try await store.profile(id: targetID)
        } catch {
            throw OperationError.stage(.activateTargetCredential, error)
        }

        do {
            originalProviderID = try await configuration
                .readConfiguration(codexHome: codexHome)
                .activeProviderID
        } catch {
            throw OperationError.stage(.activateTargetProvider, error)
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
            try await configuration.activateProvider(
                id: CodexConfigurationClient.openAIProviderID,
                codexHome: codexHome
            )
        } catch {
            throw await restoringOriginalState(
                originalActiveID: originalActiveID,
                originalProviderID: originalProviderID,
                codexHome: codexHome,
                failedStage: .activateTargetProvider,
                originalError: error
            )
        }

        do {
            let identity = try await codex.readIdentity(profileHome: codexHome)
            guard identity.matches(target) else {
                throw CodexClientError.identityUnavailable
            }
        } catch {
            throw await restoringOriginalState(
                originalActiveID: originalActiveID,
                originalProviderID: originalProviderID,
                codexHome: codexHome,
                failedStage: .verifyTargetIdentity,
                originalError: error
            )
        }

        do {
            try await store.commitActiveAccountID(targetID)
        } catch {
            throw await restoringOriginalState(
                originalActiveID: originalActiveID,
                originalProviderID: originalProviderID,
                codexHome: codexHome,
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

    private func restoringOriginalState(
        originalActiveID: UUID,
        originalProviderID: String,
        codexHome: URL,
        failedStage: SwitchStage,
        originalError: any Error
    ) async -> OperationError {
        var restorationErrors: [String] = []
        do {
            try await store.restoreActiveCredential(id: originalActiveID)
        } catch let restorationError {
            restorationErrors.append("credential: \(restorationError.localizedDescription)")
        }
        do {
            try await configuration.activateProvider(id: originalProviderID, codexHome: codexHome)
        } catch let restorationError {
            restorationErrors.append("provider: \(restorationError.localizedDescription)")
        }
        guard !restorationErrors.isEmpty else {
            return OperationError.stage(failedStage, originalError)
        }
        return OperationError(
            stage: failedStage,
            titleKey: "switch_failed",
            messageKey: nil,
            message: """
            \(originalError.localizedDescription) Restoring the previous state also failed: \
            \(restorationErrors.joined(separator: "; "))
            """,
            underlyingDescription: """
            \(String(describing: originalError)); restoration: \
            \(restorationErrors.joined(separator: "; "))
            """
        )
    }
}
