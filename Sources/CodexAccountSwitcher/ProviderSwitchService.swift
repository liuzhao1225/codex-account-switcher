import Foundation

protocol ProviderSwitchServicing: Sendable {
    func switchProvider(to providerID: String) async throws
}

struct ProviderSwitchService: ProviderSwitchServicing {
    let desktop: any DesktopControlling
    let store: any AccountStoring
    let configuration: any ProviderConfigurationServicing

    func switchProvider(to providerID: String) async throws {
        let codexHome = await store.activeCodexHome()
        let current: ProviderConfigurationSnapshot
        do {
            current = try await configuration.readConfiguration(codexHome: codexHome)
        } catch {
            throw OperationError.stage(.activateTargetProvider, error)
        }
        guard current.activeProviderID != providerID else { return }
        guard current.providers.contains(where: { $0.id == providerID }) else {
            throw OperationError.stage(
                .activateTargetProvider,
                ProviderConfigurationError.providerNotConfigured(providerID)
            )
        }

        do {
            try await desktop.closeDesktop()
        } catch {
            throw OperationError.stage(.closeDesktop, error)
        }

        do {
            try await configuration.activateProvider(id: providerID, codexHome: codexHome)
        } catch {
            throw await restoringOriginalProvider(
                current.activeProviderID,
                codexHome: codexHome,
                originalError: error
            )
        }

        do {
            try await desktop.reopenDesktop()
        } catch {
            throw OperationError.stage(.reopenDesktop, error)
        }
    }

    private func restoringOriginalProvider(
        _ providerID: String,
        codexHome: URL,
        originalError: any Error
    ) async -> OperationError {
        do {
            try await configuration.activateProvider(id: providerID, codexHome: codexHome)
            return OperationError.stage(.activateTargetProvider, originalError)
        } catch let restorationError {
            return OperationError(
                stage: .activateTargetProvider,
                titleKey: "switch_failed",
                messageKey: nil,
                message: """
                \(originalError.localizedDescription) Restoring the previous provider also failed: \
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
