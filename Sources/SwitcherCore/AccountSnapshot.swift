import Foundation

/// Presentation data only. Credentials and authentication tokens never leave the core.
public struct AccountSnapshot: Encodable, Sendable {
    public struct Row: Encodable, Sendable {
        public let profile: AccountProfile
        public let title: String
        public let initials: String
        public let usage: WeeklyUsage?
        public let usageError: String?
        public let usageStatus: String
        public let subscription: SubscriptionSnapshot?
        public let subscriptionStatus: String
        public let liveSubscription: LiveSubscription?
        public let subscriptionError: String?
        public let subscriptionView: SubscriptionPresentation
    }
    public let accounts: [Row]
    public let activeAccountID: UUID?
    public let activeRemainingPercent: Int?
    public let settings: AppSettings
    public let isMutating: Bool
    public let isAddingAccount: Bool
    public let activeIdentityConfirmed: Bool
    public let error: String?
    public let strings: [String: String]?
}

extension AccountController {
    @available(*, deprecated, message: "Use snapshot(includeStrings:) instead")
    public var snapshot: AccountSnapshot {
        snapshot(includeStrings: true)
    }

    public func snapshot(includeStrings: Bool) -> AccountSnapshot {
        AccountSnapshot(
            accounts: accounts.map { account in
                let subState = subscriptionStates[account.id] ?? .idle
                let historical = subscriptionSnapshots[account.id]
                return AccountSnapshot.Row(
                    profile: account,
                    title: account.preferredTitle,
                    initials: account.initials,
                    usage: usageStates[account.id]?.displayedUsage,
                    usageError: usageStates[account.id]?.presentationError,
                    usageStatus: usageStates[account.id]?.presentationStatus ?? "idle",
                    subscription: historical,
                    subscriptionStatus: subState.presentationStatus,
                    liveSubscription: subState.displayedSubscription,
                    subscriptionError: subState.refreshError,
                    subscriptionView: SubscriptionPresentation(state: subState, historical: historical)
                )
            },
            activeAccountID: activeAccountID,
            activeRemainingPercent: activeRemainingPercent,
            settings: settings,
            isMutating: isMutating,
            isAddingAccount: isAddingAccount,
            activeIdentityConfirmed: activeIdentityConfirmed,
            error: visibleError.map { $0.messageKey.map(text) ?? $0.message },
            strings: includeStrings ? L10n.allStrings(language: settings.language) : nil
        )
    }
}

private extension UsageViewState {
    var presentationStatus: String {
        switch self { case .idle: "idle"; case .loaded: "loaded"; case .stale: "stale"; case .unavailable: "unavailable" }
    }
    var presentationError: String? {
        switch self { case let .stale(_, error), let .unavailable(error): error; default: nil }
    }
}

private extension LiveSubscriptionState {
    var presentationStatus: String {
        switch self {
        case .idle: "idle"
        case .cached: "cached"
        case .loaded: "loaded"
        case .stale: "stale"
        case .unavailable: "unavailable"
        }
    }
}
