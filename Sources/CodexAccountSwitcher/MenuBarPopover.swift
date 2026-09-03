import AppKit
import SwiftUI

struct MenuBarPopover: View {
    @ObservedObject var model: AppModel
    @State private var page: PopoverPage = .accounts

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.visibleError {
                InlineErrorBanner(
                    title: model.text(error.titleKey),
                    message: error.messageKey.map(model.text) ?? error.message,
                    dismissTitle: model.text("ok"),
                    onDismiss: model.dismissError
                )
                Divider()
            }

            Group {
                switch page {
                case .accounts:
                    accountPage
                case .manageAccounts:
                    ManageAccountsView(model: model) {
                        page = .accounts
                    }
                case .settings:
                    SettingsView(model: model) {
                        page = .accounts
                    }
                case let .confirmAccountSwitch(account):
                    SwitchConfirmationPage(
                        title: model.format("switch_title", account.displayName),
                        message: model.text("switch_body"),
                        cancelTitle: model.text("cancel"),
                        confirmTitle: model.text("switch_account"),
                        onCancel: {
                            page = .accounts
                        },
                        onConfirm: {
                            page = .accounts
                            Task { await model.switchAccount(to: account.id) }
                        }
                    )
                case let .confirmProviderSwitch(provider):
                    SwitchConfirmationPage(
                        title: model.format("switch_provider_title", provider.displayName),
                        message: model.text("switch_provider_body"),
                        cancelTitle: model.text("cancel"),
                        confirmTitle: model.text("switch_provider"),
                        onCancel: {
                            page = .accounts
                        },
                        onConfirm: {
                            page = .accounts
                            Task { await model.switchProvider(to: provider) }
                        }
                    )
                }
            }
        }
        .frame(width: 326)
        .onAppear {
            page = .accounts
        }
        .task {
            await model.start()
            model.refreshWeeklyUsage()
        }
    }

    private var accountPage: some View {
        VStack(spacing: 0) {
            if !model.activeIdentityConfirmed {
                Text(model.text("active_unconfirmed"))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.orange.opacity(0.08))
            }

            if model.accounts.isEmpty && model.providers.isEmpty {
                Text(model.text("no_accounts"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else {
                VStack(spacing: 2) {
                    if !model.accounts.isEmpty {
                        sectionHeader(model.text("accounts"))
                        ForEach(model.accounts) { account in
                            Button {
                                if model.isAccountActive(account) {
                                    NSApp.keyWindow?.close()
                                } else {
                                    page = .confirmAccountSwitch(account)
                                }
                            } label: {
                                AccountRow(
                                    account: account,
                                    usageState: model.usageStates[account.id] ?? .idle,
                                    isActive: model.isAccountActive(account),
                                    language: model.settings.language,
                                    showsFiveHourUsage: model.settings.showsFiveHourUsage
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(model.isMutating)
                        }
                    }

                    if !model.providers.isEmpty {
                        sectionHeader(model.text("providers"))
                        ForEach(model.providers) { provider in
                            Button {
                                if model.isProviderActive(provider) {
                                    NSApp.keyWindow?.close()
                                } else {
                                    page = .confirmProviderSwitch(provider)
                                }
                            } label: {
                                ProviderRow(
                                    provider: provider,
                                    isActive: model.isProviderActive(provider),
                                    language: model.settings.language
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(model.isMutating)
                        }
                    }
                }
                .padding(5)
            }

            Divider()
            HStack(spacing: 2) {
                FooterAction(
                    title: model.text("manage"),
                    systemImage: "person.2"
                ) {
                    page = .manageAccounts
                }
                .disabled(model.isMutating)

                FooterAction(
                    title: model.text("settings"),
                    systemImage: "gearshape"
                ) {
                    page = .settings
                }
                .disabled(model.isMutating)

                FooterAction(
                    title: model.text("quit"),
                    systemImage: "power",
                    shortcut: KeyboardShortcut("q", modifiers: .command)
                ) {
                    NSApp.terminate(nil)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 5)
            .padding(.bottom, 1)
    }
}

private enum PopoverPage {
    case accounts
    case manageAccounts
    case settings
    case confirmAccountSwitch(AccountProfile)
    case confirmProviderSwitch(ProviderProfile)
}

private struct SwitchConfirmationPage: View {
    let title: String
    let message: String
    let cancelTitle: String
    let confirmTitle: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeader(
                title: title,
                backTitle: cancelTitle,
                onBack: onCancel
            )

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 7) {
                    Button(cancelTitle, action: onCancel)
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)

                    Button(confirmTitle, action: onConfirm)
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(14)
        }
    }
}

private struct InlineErrorBanner: View {
    let title: String
    let message: String
    let dismissTitle: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(dismissTitle)
            .help(dismissTitle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }
}

private struct FooterAction: View {
    let title: String
    let systemImage: String
    var shortcut: KeyboardShortcut?
    let action: () -> Void

    @State private var isHovering = false

    init(
        title: String,
        systemImage: String,
        shortcut: KeyboardShortcut? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.80)
                .padding(.horizontal, 5)
                .frame(maxWidth: .infinity, minHeight: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut)
        .frame(maxWidth: .infinity)
        .background(
            Color.primary.opacity(isHovering ? 0.06 : 0),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .onHover { isHovering = $0 }
    }
}
