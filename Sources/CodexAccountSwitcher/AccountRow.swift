import SwitcherCore
import SwiftUI

struct AccountRow: View {
    private static let isoDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    let account: AccountProfile
    let usageState: UsageViewState
    let subscription: SubscriptionSnapshot?
    let subscriptionState: LiveSubscriptionState
    let isActive: Bool
    let language: AppLanguage
    let showsFiveHourUsage: Bool
    var now: Date = Date()
    @ViewState private var isHovering = false

    var body: some View {
        let title = account.preferredTitle
        let presentation = SubscriptionPresentation(state: subscriptionState, historical: subscription)
        let subscriptionDetail = presentation.detailText(
            at: now,
            language: language,
            formatDay: subscriptionDate,
            formatTimestamp: subscriptionTime
        )
        HStack(alignment: .center, spacing: 10) {
            Text(account.initials)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(verbatim: title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(title)
                    Spacer(minLength: 4)
                    if let usage = usageState.displayedUsage, !showsFiveHourUsage {
                        Text(resetText(for: usage))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    } else if let message = usageState.refreshError {
                        warningIcon(message)
                    }
                }

                if let email = account.labeledEmail {
                    Text(verbatim: email)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(email)
                }

                usageContent
                HStack(spacing: 8) {
                    Text(presentation.primaryText(at: now, language: language, formatDay: subscriptionDate))
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(presentation.needsUpdate(at: now) ? Color.orange : Color.secondary)
                        .help(subscriptionDetail)
                        .accessibilityHint(subscriptionDetail)
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
            Text("\(text("usage")) -")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        case let .unavailable(message):
            Text(text("usage_unavailable"))
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
            Text(text("usage"))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

            if let message = usageState.refreshError {
                warningIcon(message)
            }

            UsageBar(remainingPercent: usage.remainingPercent)
                .accessibilityLabel(text("usage"))
                .accessibilityValue("\(usage.remainingPercent)\(text("left"))")

            Text("\(usage.remainingPercent)\(text("left"))")
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
                    title: text("five_hour"),
                    remainingPercent: remaining,
                    resetsAt: resetsAt,
                    includesDate: false
                )
            }
            limitRow(
                title: text("weekly"),
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
                .accessibilityValue("\(remainingPercent)\(text("left"))")

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

    private func warningIcon(_ message: String) -> some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 9))
            .foregroundStyle(.orange)
            .help(message)
            .accessibilityLabel(message)
    }

    private func text(_ key: String) -> String {
        L10n.string(key, language: language)
    }

    private func resetText(for usage: WeeklyUsage) -> String {
        resetText(for: usage.resetsAt, includesDate: true)
    }

    private func resetCreditsText(for usage: WeeklyUsage) -> String {
        let count = usage.resetCreditsRemaining.map(String.init) ?? text("unknown")
        return "\(text("reset_credits")): \(count)"
    }

    private var dateLocale: Locale {
        switch language {
        case .simplifiedChinese:
            Locale(identifier: "zh_CN")
        case .english:
            Locale(identifier: "en_US")
        case .italian:
            Locale(identifier: "it_IT")
        case .system:
            switch L10n.systemLanguage(for: Locale.preferredLanguages.first ?? Locale.autoupdatingCurrent.identifier) {
            case .simplifiedChinese: Locale(identifier: "zh_CN")
            case .italian: Locale(identifier: "it_IT")
            case .english, .system: .autoupdatingCurrent
            }
        }
    }

    private func subscriptionDate(_ date: Date) -> String {
        Self.isoDayFormatter.string(from: date)
    }

    private func subscriptionTime(_ date: Date) -> String {
        date.formatted(.dateTime.year().month().day().hour().minute().locale(dateLocale))
    }

    private func resetText(for resetsAt: Date, includesDate: Bool) -> String {
        let date = includesDate
            ? resetsAt.formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(dateLocale))
            : resetsAt.formatted(.dateTime.hour().minute().locale(dateLocale))
        return "\(text("resets")) \(date)"
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
