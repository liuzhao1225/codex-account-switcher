import Foundation

public struct ProviderSwitchService: ProviderSwitchServicing {
    let desktop: any DesktopControlling
    let store: any AccountStoring
    let codex: any CodexIdentityReading
    let configuration: any ProviderConfigurationServicing

    public init(desktop: any DesktopControlling, store: any AccountStoring,
                codex: any CodexIdentityReading, configuration: any ProviderConfigurationServicing) {
        self.desktop = desktop
        self.store = store
        self.codex = codex
        self.configuration = configuration
    }

    public func switchProvider(to providerID: String) async throws {
        let codexHome = await store.activeCodexHome()
        let current: ProviderConfigurationSnapshot
        let isOpenAIAPI = providerID == CodexConfigurationClient.openAIProviderID
        do {
            current = try await configuration.readConfiguration(codexHome: codexHome)
            if isOpenAIAPI {
                let authentication = try await codex.readAuthentication(profileHome: codexHome)
                if authentication == .apiKey && current.activeProviderID == providerID { return }
                let hasSavedAPI = await store.hasOpenAIAPICredential()
                guard authentication == .apiKey || hasSavedAPI else {
                    throw NativeAPIAuthenticationError.savedLoginUnavailable
                }
            } else {
                guard current.activeProviderID != providerID else { return }
                guard current.providers.contains(where: { $0.id == providerID }) else {
                    throw ProviderConfigurationError.providerNotConfigured(providerID)
                }
            }
        } catch {
            throw OperationError.stage(.activateTargetProvider, error)
        }

        do { try await desktop.closeDesktop() }
        catch { throw OperationError.stage(.closeDesktop, error) }

        let logins = LoginCredentialManager(store: store, codex: codex)
        var originalLogin: SavedLoginState?
        var replacesCredential = false
        do {
            try await configuration.activateProvider(id: providerID, codexHome: codexHome)
            if isOpenAIAPI {
                originalLogin = try await logins.preserve(codexHome: codexHome)
                replacesCredential = true
                try await store.activateOpenAIAPICredential()
                guard try await codex.readAuthentication(profileHome: codexHome) == .apiKey else {
                    throw NativeAPIAuthenticationError.verificationFailed
                }
            }
        } catch {
            var recoveryErrors: [String] = []
            if replacesCredential, let originalLogin {
                do { try await logins.restore(originalLogin) }
                catch { recoveryErrors.append("credential: \(error.localizedDescription)") }
            }
            do { try await configuration.activateProvider(id: current.activeProviderID, codexHome: codexHome) }
            catch { recoveryErrors.append("provider: \(error.localizedDescription)") }
            do { try await desktop.reopenDesktop() }
            catch { recoveryErrors.append("reopen: \(error.localizedDescription)") }
            guard !recoveryErrors.isEmpty else { throw OperationError.stage(.activateTargetProvider, error) }
            throw OperationError(stage: .activateTargetProvider, titleKey: "switch_failed", messageKey: nil,
                message: "\(error.localizedDescription) Recovery also failed: \(recoveryErrors.joined(separator: "; "))",
                underlyingDescription: nil)
        }

        do { try await desktop.reopenDesktop() }
        catch { throw OperationError.stage(.reopenDesktop, error) }
    }
}
