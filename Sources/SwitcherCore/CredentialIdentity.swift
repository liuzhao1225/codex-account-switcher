import Foundation
#if os(Windows)
import SwitcherPlatform
#endif

// Identity metadata labels a local login; Codex still authenticates with the service.
public struct CredentialIdentity: CodexIdentityReading {
    public init() {}

    public func readIdentity(profileHome: URL) async throws -> AccountIdentity {
        try Task.checkCancellation()
        guard let identity = try Self.read(from: profileHome) else {
            throw CodexClientError.identityUnavailable
        }
        return identity
    }

    static func read(from home: URL) throws -> AccountIdentity? {
        let url = home.appending(path: "auth.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        #if os(Windows)
        guard switcher_check_path(url.path) == 0 else { throw CodexClientError.identityUnavailable }
        #endif
        return try decode(Data(contentsOf: url))
    }

    static func decode(_ data: Data) throws -> AccountIdentity? {
        do {
            return try ParsedCredential.decode(data).localIdentity
        } catch {
            // Decoder diagnostics may contain credential contents. Expose only the failure category.
            throw CodexClientError.identityUnavailable
        }
    }
}
