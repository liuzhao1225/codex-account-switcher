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
        (try? ParsedCredential.decode(credential))?.subscriptionSnapshot(
            expectedAccountID: expectedAccountID,
            expectedEmail: expectedEmail
        )
    }
}
