import Foundation
import SwitcherCore

actor NativeAPITestConfiguration: ProviderConfigurationServicing {
    private var providerID = "openai"

    func readConfiguration(codexHome: URL) -> ProviderConfigurationSnapshot {
        ProviderConfigurationSnapshot(activeProviderID: providerID,
            providers: [ProviderProfile(id: "azure", displayName: "Azure")])
    }

    func activateProvider(id: String, codexHome: URL) { providerID = id }
    func selectedProvider() -> String { providerID }
}
