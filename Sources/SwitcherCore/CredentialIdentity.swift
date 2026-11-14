import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
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
            let credential = try JSONDecoder().decode(Credential.self, from: data)
            if credential.auth_mode == "apikey" {
                guard let key = credential.OPENAI_API_KEY, !key.isEmpty else {
                    throw CodexClientError.identityUnavailable
                }
                return try identity(forAPIKey: key)
            }
            guard let tokens = credential.tokens else { return nil }
            let claims = try tokens.id_token.map(decodeClaims)
            guard let accountID = nonempty(tokens.account_id) ?? nonempty(claims?.auth?.chatgpt_account_id) else {
                return nil
            }
            return AccountIdentity(accountID: accountID, email: nonempty(claims?.email))
        } catch {
            // Decoder diagnostics may contain credential contents. Expose only the failure category.
            throw CodexClientError.identityUnavailable
        }
    }

    static func identity(forAPIKey key: String) throws -> AccountIdentity {
        let bytes = Data(key.utf8)
        let digest: [UInt8]
        #if os(Windows)
        var result = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeBytes { input in
            result.withUnsafeMutableBufferPointer { output in
                switcher_sha256(input.baseAddress, bytes.count, output.baseAddress)
            }
        }
        guard status == 0 else { throw CodexClientError.identityUnavailable }
        digest = result
        #elseif canImport(CryptoKit)
        digest = Array(SHA256.hash(data: bytes))
        #else
        throw CodexClientError.identityUnavailable
        #endif
        let fingerprint = digest.map { String(format: "%02x", $0) }.joined()
        return AccountIdentity(accountID: "api-key:\(fingerprint)", email: nil)
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private static func decodeClaims(_ token: String) throws -> Claims {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw CodexClientError.identityUnavailable }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload) else { throw CodexClientError.identityUnavailable }
        return try JSONDecoder().decode(Claims.self, from: data)
    }

    private struct Credential: Decodable {
        let auth_mode: String?
        let OPENAI_API_KEY: String?
        let tokens: Tokens?
    }
    private struct Tokens: Decodable {
        let account_id: String?
        let id_token: String?
    }
    private struct Claims: Decodable {
        let email: String?
        let auth: Auth?
        enum CodingKeys: String, CodingKey {
            case email
            case auth = "https://api.openai.com/auth"
        }
    }
    private struct Auth: Decodable { let chatgpt_account_id: String? }
}
