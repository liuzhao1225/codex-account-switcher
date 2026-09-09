import Foundation

/// References saved credentials; contains no credential bytes or tokens.
public enum SavedLoginState: Sendable {
    case signedOut
    case apiKey
    case chatGPT(UUID)
}
