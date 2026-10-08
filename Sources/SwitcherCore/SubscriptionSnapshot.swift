import Foundation

/// The subscription window in a saved Codex login. This is a dated login snapshot,
/// not a live billing query or a promise that the plan will renew.
public struct SubscriptionSnapshot: Equatable, Sendable, Encodable {
    public let activeUntil: Date
    public let lastChecked: Date

    public init(activeUntil: Date, lastChecked: Date) {
        self.activeUntil = activeUntil
        self.lastChecked = lastChecked
    }
}

public enum SubscriptionSnapshotReader {
    public static func read(
        credential: Data,
        expectedAccountID: String?,
        expectedEmail: String?
    ) -> SubscriptionSnapshot? {
        guard let auth = (try? JSONSerialization.jsonObject(with: credential)) as? [String: Any],
              let tokens = auth["tokens"] as? [String: Any],
              let idToken = tokens["id_token"] as? String,
              let payload = decodePayload(idToken),
              let account = payload["https://api.openai.com/auth"] as? [String: Any]
        else { return nil }

        let tokenAccountID = account["chatgpt_account_id"] as? String
        let tokenEmail = payload["email"] as? String
        if let expectedAccountID, !expectedAccountID.isEmpty {
            guard tokenAccountID == expectedAccountID else { return nil }
        } else if let expectedEmail, !expectedEmail.isEmpty {
            guard tokenEmail?.caseInsensitiveCompare(expectedEmail) == .orderedSame else { return nil }
        } else {
            return nil
        }
        if let expectedEmail, !expectedEmail.isEmpty, let tokenEmail,
           tokenEmail.caseInsensitiveCompare(expectedEmail) != .orderedSame {
            return nil
        }
        if (account["chatgpt_plan_type"] as? String)?.lowercased() == "free" { return nil }

        guard let untilText = account["chatgpt_subscription_active_until"] as? String,
              let checkedText = account["chatgpt_subscription_last_checked"] as? String,
              let activeUntil = parseDate(untilText),
              let lastChecked = parseDate(checkedText)
        else { return nil }
        return SubscriptionSnapshot(activeUntil: activeUntil, lastChecked: lastChecked)
    }

    private static func decodePayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var encoded = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let bytes = Data(base64Encoded: encoded) else { return nil }
        return (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = formatter.date(from: text) { return value }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
