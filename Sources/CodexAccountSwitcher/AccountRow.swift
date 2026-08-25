import SwiftUI

struct AccountRow: View {
    let account: AccountProfile
    let usageState: UsageViewState
    let isActive: Bool
    let language: AppLanguage
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(account.initials)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(account.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    if let usage = usageState.displayedUsage {
                        Text(resetText(for: usage))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                usageContent
            }
        }
        .frame(minHeight: 50)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
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
    }

    private var rowBackground: Color {
        if isActive {
            return Color.accentColor.opacity(0.10)
        }
        return Color.primary.opacity(isHovering ? 0.055 : 0)
    }

    private func resetText(for usage: WeeklyUsage) -> String {
        let date = usage.resetsAt.formatted(
            .dateTime
                .month(.abbreviated)
                .day()
                .hour()
                .minute()
        )
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
