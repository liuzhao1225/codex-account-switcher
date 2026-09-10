public protocol ProviderSwitchServicing: Sendable {
    func switchProvider(to providerID: String) async throws
}
