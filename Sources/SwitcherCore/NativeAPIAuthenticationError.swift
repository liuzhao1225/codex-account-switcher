import Foundation

public enum NativeAPIAuthenticationError: LocalizedError, Sendable {
    case savedLoginUnavailable
    case verificationFailed

    public var errorDescription: String? {
        switch self {
        case .savedLoginUnavailable:
            "No saved OpenAI API login is available. Sign in with an API key in Codex first. The switcher currently supports file-based Codex credential storage."
        case .verificationFailed:
            "Codex did not activate OpenAI API authentication."
        }
    }
}
