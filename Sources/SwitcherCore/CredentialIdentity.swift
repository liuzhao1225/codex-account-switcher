import Foundation
#if os(Windows)
import SwitcherPlatform
#endif

// Identity metadata labels a local login; Codex still authenticates with the service.
enum CredentialIdentity {
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

    private struct Credential: Decodable { let tokens: Tokens? }
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
