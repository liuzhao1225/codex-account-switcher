public enum CodexAuthenticationState: Equatable, Sendable {
    case signedOut
    case apiKey
    case chatGPT(AccountIdentity)

    public var identity: AccountIdentity? {
        guard case let .chatGPT(identity) = self else { return nil }
        return identity
    }
}
