import Foundation

// The same ordered handoff and bounded restoration run on both platforms.

public protocol DesktopControlling: Sendable {
    func closeDesktop() async throws
    func reopenDesktop() async throws
}

public protocol CodexIdentityReading: Sendable {
    func readIdentity(profileHome: URL) async throws -> AccountIdentity
    func readAuthentication(profileHome: URL) async throws -> CodexAuthenticationState
}

public protocol SwitchServicing: Sendable {
    func switchAccount(to targetID: UUID) async throws
}

public struct SwitchService: SwitchServicing {
    public let desktop: any DesktopControlling
    public let store: any AccountStoring
    public let codex: any CodexIdentityReading
    public let configuration: any ProviderConfigurationServicing

    public init(desktop: any DesktopControlling, store: any AccountStoring,
                codex: any CodexIdentityReading, configuration: any ProviderConfigurationServicing) {
        self.desktop = desktop; self.store = store; self.codex = codex
        self.configuration = configuration
    }

    public func switchAccount(to targetID: UUID) async throws {
        let target: AccountProfile
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
            if let activeID = registry.activeAccountID {
                guard registry.accounts.contains(where: { $0.id == activeID }) else {
                    throw AccountStoreError.activeProfileMissing
                }
            }
        } catch {
            throw OperationError.stage(.saveCurrentCredential, error)
        }

        do {
            try await desktop.closeDesktop()
        } catch {
            throw OperationError.stage(.closeDesktop, error)
        }

        var failedStage = SwitchStage.activateTargetProvider
        var restoresCredential = false
        var originalLogin: SavedLoginState?
        let logins = LoginCredentialManager(store: store, codex: codex)
        do {
            try await configuration.activateProvider(
                id: CodexConfigurationClient.openAIProviderID,
                codexHome: codexHome
            )

            failedStage = .saveCurrentCredential
            originalLogin = try await logins.preserve(codexHome: codexHome)

            failedStage = .activateTargetCredential
            restoresCredential = true
            try await store.activateTargetCredential(id: targetID)

            failedStage = .verifyTargetIdentity
            let identity = try await codex.readIdentity(profileHome: codexHome)
            guard identity.matches(target) else {
                throw CodexClientError.identityUnavailable
            }

            failedStage = .commitActiveAccountID
            try await store.commitActiveAccountID(targetID)
        } catch {
            let restoredError = await restoringOriginalState(
                originalLogin: restoresCredential ? originalLogin : nil,
                originalProviderID: originalProviderID,
                codexHome: codexHome,
                failedStage: failedStage,
                originalError: error
            )
            throw await reopeningDesktop(after: restoredError)
        }

        do {
            try await desktop.reopenDesktop()
        } catch {
            throw OperationError.stage(.reopenDesktop, error)
        }
    }

    private func restoringOriginalState(
        originalLogin: SavedLoginState?,
        originalProviderID: String,
        codexHome: URL,
        failedStage: SwitchStage,
        originalError: any Error
    ) async -> OperationError {
        var restorationErrors: [String] = []
        if let originalLogin {
            do {
                try await LoginCredentialManager(store: store, codex: codex).restore(originalLogin)
            } catch let restorationError {
                restorationErrors.append("credential: \(restorationError.localizedDescription)")
            }
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

    private func reopeningDesktop(after error: OperationError) async -> OperationError {
        do {
            try await desktop.reopenDesktop()
            return error
        } catch let reopenError {
            return OperationError(
                stage: error.stage,
                titleKey: error.titleKey,
                messageKey: nil,
                message: """
                \(error.message) Reopening Codex Desktop also failed: \
                \(reopenError.localizedDescription)
                """,
                underlyingDescription: """
                \(error.underlyingDescription ?? error.message); reopen: \
                \(String(describing: reopenError))
                """
            )
        }
    }
}
