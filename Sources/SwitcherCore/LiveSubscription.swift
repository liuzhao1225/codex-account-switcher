import Foundation

/// A dated response from the subscription service, separate from ID-token claims.
public struct LiveSubscription: Codable, Equatable, Sendable {
    public let activeUntil: Date?
    public let planType: String
    public let isActive: Bool
    public let willRenew: Bool?
    public let isDelinquent: Bool?
    public let fetchedAt: Date

    public init(activeUntil: Date?, planType: String, isActive: Bool,
                willRenew: Bool?, isDelinquent: Bool?, fetchedAt: Date) {
        self.activeUntil = activeUntil
        self.planType = planType
        self.isActive = isActive
        self.willRenew = willRenew
        self.isDelinquent = isDelinquent
        self.fetchedAt = fetchedAt
    }
}

public enum LiveSubscriptionState: Equatable, Sendable {
    case idle
    case loaded(LiveSubscription)
    case stale(LiveSubscription, String)
    case unavailable(String)

    public var displayedSubscription: LiveSubscription? {
        switch self {
        case let .loaded(subscription), let .stale(subscription, _): subscription
        case .idle, .unavailable: nil
        }
    }

    public var refreshError: String? {
        switch self {
        case let .stale(_, message), let .unavailable(message): message
        case .idle, .loaded: nil
        }
    }
}

public protocol SubscriptionClient: Sendable {
    func readSubscription(credential: Data, expectedAccountID: String?,
                          expectedEmail: String?) async throws -> LiveSubscription
}
