import Foundation
@testable import SwitcherCore

actor ControllerConfigurationFixture: ProviderConfigurationServicing {
    private var providerID = "openai"

    func readConfiguration(codexHome: URL) -> ProviderConfigurationSnapshot {
        ProviderConfigurationSnapshot(activeProviderID: providerID,
            providers: [ProviderProfile(id: "azure", displayName: "Azure")])
    }

    func activateProvider(id: String, codexHome: URL) { providerID = id }
}
