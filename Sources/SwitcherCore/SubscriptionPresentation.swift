import Foundation

/// Shared subscription display model derived in `SwitcherCore` so macOS and Windows
/// apply identical live-status, staleness, and fallback rules.
public struct SubscriptionPresentation: Encodable, Equatable, Sendable {
    public static let stalenessInterval: TimeInterval = 600

    public enum PrimaryKind: String, Encodable, Equatable, Sendable {
        case pending
        case free
        case inactive
        case active
        case activeUntil
    }

    public enum TriState: String, Encodable, Equatable, Sendable {
        case yes
        case no
        case unknown

        public init(_ value: Bool?) {
            switch value {
            case true?: self = .yes
            case false?: self = .no
            case nil: self = .unknown
            }
        }
    }

    public let primary: PrimaryKind
    public let activeUntil: Date?
    public let planType: String?
    public let isActive: Bool?
    public let fetchedAt: Date?
    public let staleAfter: Date?
    public let requiresUpdateImmediately: Bool
    public let isWaitingForRefresh: Bool
    public let refreshError: String?
    public let autoRenew: TriState
    public let paymentDelinquent: TriState
    public let historicalActiveUntil: Date?
    public let historicalLastChecked: Date?

    public init(state: LiveSubscriptionState, historical: SubscriptionSnapshot?) {
        if let live = state.displayedSubscription {
            if live.planType.lowercased() == "free" {
                primary = .free
            } else if !live.isActive {
                primary = .inactive
            } else if live.activeUntil != nil {
                primary = .activeUntil
            } else {
                primary = .active
            }
            activeUntil = live.activeUntil
            planType = live.planType
            isActive = live.isActive
            fetchedAt = live.fetchedAt
            staleAfter = live.fetchedAt.addingTimeInterval(Self.stalenessInterval)
            autoRenew = TriState(live.willRenew)
            paymentDelinquent = TriState(live.isDelinquent)
        } else {
            primary = .pending
            activeUntil = nil
            planType = nil
            isActive = nil
            fetchedAt = nil
            staleAfter = nil
            autoRenew = .unknown
            paymentDelinquent = .unknown
        }

        switch state {
        case .idle:
            requiresUpdateImmediately = false
            isWaitingForRefresh = false
            refreshError = nil
        case .cached:
            requiresUpdateImmediately = true
            isWaitingForRefresh = true
            refreshError = nil
        case .loaded:
            requiresUpdateImmediately = false
            isWaitingForRefresh = false
            refreshError = nil
        case let .stale(_, message), let .unavailable(message):
            requiresUpdateImmediately = true
            isWaitingForRefresh = false
            refreshError = message
        }

        historicalActiveUntil = historical?.activeUntil
        historicalLastChecked = historical?.lastChecked
    }

    public func needsUpdate(at now: Date) -> Bool {
        requiresUpdateImmediately || (staleAfter.map { now >= $0 } ?? false)
    }

    public func primaryText(
        at now: Date,
        language: AppLanguage,
        formatDay: (Date) -> String
    ) -> String {
        let base: String
        switch primary {
        case .pending:
            base = L10n.string("subscription_live_pending", language: language)
        case .free:
            base = L10n.string("subscription_live_free", language: language)
        case .inactive:
            base = L10n.string("subscription_live_inactive", language: language)
        case .active:
            base = L10n.string("subscription_live_active", language: language)
        case .activeUntil:
            if let activeUntil {
                base = String(format: L10n.string("subscription_live_until", language: language), formatDay(activeUntil))
            } else {
                base = L10n.string("subscription_live_active", language: language)
            }
        }
        return needsUpdate(at: now)
            ? base + " · " + L10n.string("subscription_live_needs_update", language: language)
            : base
    }

    public func detailText(
        at now: Date,
        language: AppLanguage,
        formatDay: (Date) -> String,
        formatTimestamp: (Date) -> String
    ) -> String {
        func str(_ key: String) -> String { L10n.string(key, language: language) }
        func fmt(_ key: String, _ values: CVarArg...) -> String {
            String(format: str(key), arguments: values)
        }

        var lines = [str("subscription_live_source")]
        if let fetchedAt {
            let stale = needsUpdate(at: now)
            lines.append(fmt(
                stale ? "subscription_live_last_success" : "subscription_live_updated",
                formatTimestamp(fetchedAt)
            ))
            if let planType {
                lines.append(fmt("subscription_live_plan", planType))
            }
            if let isActive {
                lines.append(str(isActive ? "subscription_live_status_active" : "subscription_live_status_inactive"))
            }
            if let activeUntil {
                lines.append(fmt("subscription_live_until", formatDay(activeUntil)))
            }
            lines.append(str(autoRenew.renewLocalizationKey))
            lines.append(str(paymentDelinquent.delinquentLocalizationKey))
            if isWaitingForRefresh {
                lines.append(str("subscription_refresh_pending"))
            } else if stale {
                lines.append(str("subscription_live_stale_hint"))
            }
        } else {
            lines.append(str("subscription_live_never_succeeded"))
            lines.append(str(autoRenew.renewLocalizationKey))
            lines.append(str(paymentDelinquent.delinquentLocalizationKey))
        }
        if let refreshError {
            lines.append(fmt("subscription_live_refresh_failed", refreshError))
        }
        if let historicalActiveUntil, let historicalLastChecked {
            lines.append(fmt(
                "subscription_live_history",
                formatDay(historicalActiveUntil),
                formatTimestamp(historicalLastChecked)
            ))
        }
        return lines.joined(separator: "\n")
    }
}

private extension SubscriptionPresentation.TriState {
    var renewLocalizationKey: String {
        switch self {
        case .yes: "subscription_live_renew_on"
        case .no: "subscription_live_renew_off"
        case .unknown: "subscription_live_renew_unknown"
        }
    }

    var delinquentLocalizationKey: String {
        switch self {
        case .yes: "subscription_live_delinquent_yes"
        case .no: "subscription_live_delinquent_no"
        case .unknown: "subscription_live_delinquent_unknown"
        }
    }
}
