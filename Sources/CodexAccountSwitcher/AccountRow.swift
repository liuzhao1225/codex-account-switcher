import SwitcherCore
import SwiftUI

struct AccountRow: View {
    let account: AccountProfile
    let usageState: UsageViewState
    let subscription: SubscriptionSnapshot?
    let subscriptionState: LiveSubscriptionState
    let isActive: Bool
    let language: AppLanguage
    let showsFiveHourUsage: Bool
    @State private var isHovering = false

    private var accountTitle: String {
        account.email.flatMap { $0.isEmpty ? nil : $0 } ?? account.displayName
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(account.initials)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(verbatim: accountTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(accountTitle)
                    Spacer(minLength: 4)
                    if let usage = usageState.displayedUsage, !showsFiveHourUsage {
                        Text(resetText(for: usage))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    } else if let message = usageState.refreshError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                            .help(message)
                            .accessibilityLabel(message)
                    }
                }

                usageContent
                HStack(spacing: 8) {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(subscriptionText(at: context.date))
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(subscriptionNeedsUpdate(at: context.date) ? Color.orange : Color.secondary)
                            .help(subscriptionDetail(at: context.date))
                            .accessibilityHint(subscriptionDetail(at: context.date))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let usage = usageState.displayedUsage {
                        Text(resetCreditsText(for: usage))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 50)
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(
            rowBackground,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    @ViewBuilder
    private var usageContent: some View {
        switch usageState {
        case .idle:
            Text("\(L10n.string("usage", language: language)) -")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        case let .unavailable(message):
            Text(L10n.string("usage_unavailable", language: language))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .help(message)
        case let .loaded(usage), let .stale(usage, _):
            if showsFiveHourUsage {
                expandedUsageContent(usage)
            } else {
                compactWeeklyUsageContent(usage)
            }
        }
    }

    private func compactWeeklyUsageContent(_ usage: WeeklyUsage) -> some View {
        HStack(spacing: 7) {
            Text(L10n.string("usage", language: language))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

            if let message = usageState.refreshError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                    .help(message)
                    .accessibilityLabel(message)
            }

            UsageBar(remainingPercent: usage.remainingPercent)
                .accessibilityLabel(L10n.string("usage", language: language))
                .accessibilityValue("\(usage.remainingPercent)\(L10n.string("left", language: language))")

            Text("\(usage.remainingPercent)\(L10n.string("left", language: language))")
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func expandedUsageContent(_ usage: WeeklyUsage) -> some View {
        VStack(spacing: 5) {
            if let remaining = usage.fiveHourRemainingPercent,
               let resetsAt = usage.fiveHourResetsAt {
                limitRow(
                    title: L10n.string("five_hour", language: language),
                    remainingPercent: remaining,
                    resetsAt: resetsAt,
                    includesDate: false
                )
            }
            limitRow(
                title: L10n.string("weekly", language: language),
                remainingPercent: usage.remainingPercent,
                resetsAt: usage.resetsAt,
                includesDate: true
            )
        }
    }

    private func limitRow(
        title: String,
        remainingPercent: Int,
        resetsAt: Date,
        includesDate: Bool
    ) -> some View {
        HStack(spacing: 7) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)

            UsageBar(remainingPercent: remainingPercent)
                .accessibilityLabel(title)
                .accessibilityValue("\(remainingPercent)\(L10n.string("left", language: language))")

            Text("\(remainingPercent)%")
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 31, alignment: .trailing)

            Text(resetText(for: resetsAt, includesDate: includesDate))
                .font(.system(size: 9.5).monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var rowBackground: Color {
        if isActive {
            return Color.accentColor.opacity(0.10)
        }
        return Color.primary.opacity(isHovering ? 0.055 : 0)
    }

    private func resetText(for usage: WeeklyUsage) -> String {
        resetText(for: usage.resetsAt, includesDate: true)
    }

    private func resetCreditsText(for usage: WeeklyUsage) -> String {
        let count = usage.resetCreditsRemaining.map(String.init)
            ?? L10n.string("unknown", language: language)
        return "\(L10n.string("reset_credits", language: language)): \(count)"
    }

    private var dateLocale: Locale {
        switch language {
        case .simplifiedChinese:
            Locale(identifier: "zh_CN")
        case .english:
            Locale(identifier: "en_US")
        case .system:
            Locale.preferredLanguages.first?.hasPrefix("zh") == true
                ? Locale(identifier: "zh_CN") : .autoupdatingCurrent
        }
    }

    private func subscriptionText(at now: Date) -> String {
        let text: String
        if let live = subscriptionState.displayedSubscription {
            if live.planType.lowercased() == "free" {
                text = subscriptionString("subscription_live_free")
            } else if !live.isActive {
                text = subscriptionString("subscription_live_inactive")
            } else if let activeUntil = live.activeUntil {
                text = subscriptionFormat("subscription_live_until", subscriptionDate(activeUntil))
            } else {
                text = subscriptionString("subscription_live_active")
            }
        } else {
            text = subscriptionString("subscription_live_pending")
        }
        return subscriptionNeedsUpdate(at: now)
            ? text + " · " + subscriptionString("subscription_live_needs_update")
            : text
    }

    private func subscriptionNeedsUpdate(at now: Date) -> Bool {
        switch subscriptionState {
        case .stale, .unavailable:
            return true
        case let .loaded(live):
            return now.timeIntervalSince(live.fetchedAt) >= 600
        case .idle:
            return false
        }
    }

    private func subscriptionDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func subscriptionTime(_ date: Date) -> String {
        date.formatted(.dateTime.year().month().day().hour().minute().locale(dateLocale))
    }

    private func subscriptionDetail(at now: Date) -> String {
        var lines = [subscriptionString("subscription_live_source")]
        if let live = subscriptionState.displayedSubscription {
            lines.append(subscriptionFormat("subscription_live_updated", subscriptionTime(live.fetchedAt)))
            lines.append(subscriptionFormat("subscription_live_plan", live.planType))
            lines.append(subscriptionString(live.isActive
                ? "subscription_live_status_active" : "subscription_live_status_inactive"))
            if let activeUntil = live.activeUntil {
                lines.append(subscriptionFormat("subscription_live_until", subscriptionDate(activeUntil)))
            }
            lines.append(subscriptionString(live.willRenew.map {
                $0 ? "subscription_live_renew_on" : "subscription_live_renew_off"
            } ?? "subscription_live_renew_unknown"))
            lines.append(subscriptionString(live.isDelinquent.map {
                $0 ? "subscription_live_delinquent_yes" : "subscription_live_delinquent_no"
            } ?? "subscription_live_delinquent_unknown"))
            if subscriptionNeedsUpdate(at: now) {
                lines.append(subscriptionFormat("subscription_live_last_success", subscriptionTime(live.fetchedAt)))
                lines.append(subscriptionString("subscription_live_stale_hint"))
            }
        } else {
            lines.append(subscriptionString("subscription_live_never_succeeded"))
            lines.append(subscriptionString("subscription_live_renew_unknown"))
            lines.append(subscriptionString("subscription_live_delinquent_unknown"))
        }
        if let message = subscriptionState.refreshError {
            lines.append(message == subscriptionString("subscription_refresh_pending")
                ? message : subscriptionFormat("subscription_live_refresh_failed", message))
        }
        if let subscription {
            lines.append(subscriptionFormat(
                "subscription_live_history",
                subscriptionDate(subscription.activeUntil),
                subscriptionTime(subscription.lastChecked)
            ))
        }
        return lines.joined(separator: "\n")
    }

    private func subscriptionString(_ key: String) -> String {
        L10n.string(key, language: language)
    }

    private func subscriptionFormat(_ key: String, _ values: CVarArg...) -> String {
        String(format: subscriptionString(key), arguments: values)
    }

    private func resetText(for resetsAt: Date, includesDate: Bool) -> String {
        let date = includesDate
            ? resetsAt.formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(dateLocale))
            : resetsAt.formatted(.dateTime.hour().minute().locale(dateLocale))
        return "\(L10n.string("resets", language: language)) \(date)"
    }
}

private struct UsageBar: View {
    let remainingPercent: Int

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 3)
    }

    private var fraction: CGFloat {
        CGFloat(min(max(remainingPercent, 0), 100)) / 100
    }
}
