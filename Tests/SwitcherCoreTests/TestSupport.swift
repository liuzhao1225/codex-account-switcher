import Foundation
import SwitcherCore

enum TestAuthFixture {
    static func jwtToken(claims: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: claims, options: .sortedKeys)
        let payload = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(payload).signature"
    }

    static func authJSON(
        accountID: String? = nil,
        claimAccountID: String? = nil,
        email: String? = nil,
        planType: String? = nil,
        subscriptionActiveUntil: String? = nil,
        subscriptionLastChecked: String? = nil,
        accessToken: String? = nil,
        idTokenOverride: String? = nil
    ) throws -> Data {
        var authClaims: [String: Any] = [:]
        if let claimAccountID { authClaims["chatgpt_account_id"] = claimAccountID }
        if let planType { authClaims["chatgpt_plan_type"] = planType }
        if let subscriptionActiveUntil { authClaims["chatgpt_subscription_active_until"] = subscriptionActiveUntil }
        if let subscriptionLastChecked { authClaims["chatgpt_subscription_last_checked"] = subscriptionLastChecked }

        var claims: [String: Any] = [:]
        if let email { claims["email"] = email }
        if !authClaims.isEmpty { claims["https://api.openai.com/auth"] = authClaims }

        var tokens: [String: Any] = [:]
        if let accountID { tokens["account_id"] = accountID }
        if let accessToken { tokens["access_token"] = accessToken }
        if let idTokenOverride {
            tokens["id_token"] = idTokenOverride
        } else if !claims.isEmpty {
            tokens["id_token"] = try jwtToken(claims: claims)
        }
        return try JSONSerialization.data(withJSONObject: ["tokens": tokens], options: .sortedKeys)
    }
}
