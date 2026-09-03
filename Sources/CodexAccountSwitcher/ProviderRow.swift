import SwiftUI

struct ProviderRow: View {
    let provider: ProviderProfile
    let isActive: Bool
    let language: AppLanguage
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "server.rack")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(provider.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(L10n.string("configured_provider", language: language))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if isActive {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 50)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(
            isActive
                ? Color.accentColor.opacity(0.10)
                : Color.primary.opacity(isHovering ? 0.055 : 0),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
