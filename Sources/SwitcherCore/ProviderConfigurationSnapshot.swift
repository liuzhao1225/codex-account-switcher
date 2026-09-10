public struct ProviderConfigurationSnapshot: Equatable, Sendable {
    public let activeProviderID: String
    public let providers: [ProviderProfile]

    public init(activeProviderID: String, providers: [ProviderProfile]) {
        self.activeProviderID = activeProviderID
        self.providers = providers
    }
}
