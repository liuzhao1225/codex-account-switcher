import Foundation

enum ISO8601Timestamp {
    static func parse(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

/// Decodes an `auth.json` payload and its embedded `id_token` claims once so
/// identity recognition, historical snapshots, and live subscription queries
/// share one parsing pass while enforcing their distinct validation rules.
struct ParsedCredential: Sendable {
    static let maximumCredentialBytes = 1_048_576

    let hasTokens: Bool
    let selectedAccountID: String?
    let tokenAccountID: String?
    let email: String?
    let rawEmail: String?
    let rawAccessToken: String?
    let planType: String?
    let subscriptionActiveUntilText: String?
    let subscriptionLastCheckedText: String?

    var localIdentity: AccountIdentity? {
        guard hasTokens, let accountID = selectedAccountID ?? tokenAccountID else { return nil }
        return AccountIdentity(accountID: accountID, email: email)
    }

    static func decode(_ data: Data) throws -> ParsedCredential {
        let credential = try JSONDecoder().decode(CredentialPayload.self, from: data)
        guard let tokens = credential.tokens else {
            return ParsedCredential(
                hasTokens: false,
                selectedAccountID: nil,
                tokenAccountID: nil,
                email: nil,
                rawEmail: nil,
                rawAccessToken: nil,
                planType: nil,
                subscriptionActiveUntilText: nil,
                subscriptionLastCheckedText: nil
            )
        }
        let claims = try tokens.id_token.map(decodeClaims)
        let auth = claims?.auth
        return ParsedCredential(
            hasTokens: true,
            selectedAccountID: nonempty(tokens.account_id),
            tokenAccountID: nonempty(auth?.chatgpt_account_id),
            email: nonempty(claims?.email),
            rawEmail: claims?.email,
            rawAccessToken: tokens.access_token,
            planType: auth?.chatgpt_plan_type,
            subscriptionActiveUntilText: auth?.chatgpt_subscription_active_until,
            subscriptionLastCheckedText: auth?.chatgpt_subscription_last_checked
        )
    }

    func subscriptionSnapshot(expectedAccountID: String?, expectedEmail: String?) -> SubscriptionSnapshot? {
        guard hasTokens else { return nil }
        if let expectedAccountID, !expectedAccountID.isEmpty {
            guard tokenAccountID == expectedAccountID else { return nil }
        } else if let expectedEmail, !expectedEmail.isEmpty {
            guard rawEmail?.caseInsensitiveCompare(expectedEmail) == .orderedSame else { return nil }
        } else {
            return nil
        }
        if let expectedEmail, !expectedEmail.isEmpty, let rawEmail,
           rawEmail.caseInsensitiveCompare(expectedEmail) != .orderedSame {
            return nil
        }
        if planType?.lowercased() == "free" { return nil }
        guard let untilText = subscriptionActiveUntilText,
              let checkedText = subscriptionLastCheckedText,
              let activeUntil = ISO8601Timestamp.parse(untilText),
              let lastChecked = ISO8601Timestamp.parse(checkedText)
        else { return nil }
        return SubscriptionSnapshot(activeUntil: activeUntil, lastChecked: lastChecked)
    }

    func validatedSubscriptionLogin(
        expectedAccountID: String?,
        expectedEmail: String?
    ) throws -> (accountID: String, accessToken: String) {
        guard let expectedAccountID, Self.validHeaderValue(expectedAccountID),
              let accessToken = rawAccessToken, Self.validHeaderValue(accessToken),
              let identity = localIdentity, identity.accountID == expectedAccountID else {
            throw LiveSubscriptionError.invalidCredential
        }
        if let expectedEmail, !expectedEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           identity.email?.caseInsensitiveCompare(expectedEmail) != .orderedSame {
            throw LiveSubscriptionError.invalidCredential
        }
        return (expectedAccountID, accessToken)
    }

    private static func validHeaderValue(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { $0 > 32 && $0 < 127 }
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private static func decodeClaims(_ token: String) throws -> ClaimsPayload {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw CodexClientError.identityUnavailable }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload) else { throw CodexClientError.identityUnavailable }
        return try JSONDecoder().decode(ClaimsPayload.self, from: data)
    }

    private struct CredentialPayload: Decodable {
        let tokens: TokensPayload?
    }

    private struct TokensPayload: Decodable {
        let account_id: String?
        let id_token: String?
        let access_token: String?
    }

    private struct ClaimsPayload: Decodable {
        let email: String?
        let auth: AuthPayload?

        enum CodingKeys: String, CodingKey {
            case email
            case auth = "https://api.openai.com/auth"
        }
    }

    private struct AuthPayload: Decodable {
        let chatgpt_account_id: String?
        let chatgpt_plan_type: String?
        let chatgpt_subscription_active_until: String?
        let chatgpt_subscription_last_checked: String?
    }
}
