import SwiftUI

struct ManageAccountsView: View {
    @ObservedObject var model: AppModel
    let onBack: () -> Void

    @State private var page: ManageAccountsPage = .accounts

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeader(
                title: headerTitle,
                backTitle: model.text("back"),
                onBack: navigateBack
            )

            Divider()

            switch page {
            case .accounts:
                accountList
            case let .remove(account):
                removePage(account)
            }
        }
    }

    private var headerTitle: String {
        switch page {
        case .accounts:
            model.text("accounts")
        case let .remove(account):
            model.format("remove_title", account.displayName)
        }
    }

    private func navigateBack() {
        switch page {
        case .accounts:
            onBack()
        case .remove:
            page = .accounts
        }
    }

    private var accountList: some View {
        VStack(spacing: 0) {
            if model.accounts.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text(model.text("no_accounts"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 2) {
                    ForEach(model.accounts) { account in
                        managedAccountRow(account)
                    }
                }
                .padding(5)
            }

            Divider()

            VStack(alignment: .leading, spacing: 3) {
                Button {
                    Task { await model.addAccount() }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "plus")
                            .frame(width: 14)
                        Text(model.text("add_account"))
                        Spacer()
                        if model.isMutating {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.isMutating)

                Text(model.text("sign_in_hint"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
            }
            .padding(5)
        }
    }

    private func removePage(_ account: AccountProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.text("remove_body"))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 7) {
                Button(model.text("cancel")) {
                    page = .accounts
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button(model.text("remove"), role: .destructive) {
                    page = .accounts
                    Task { await model.removeAccount(id: account.id) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .frame(maxWidth: .infinity)
                .disabled(model.isMutating)
            }
        }
        .padding(14)
    }

    private func managedAccountRow(_ account: AccountProfile) -> some View {
        HStack(spacing: 9) {
            Text(account.initials)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if let email = account.email {
                    Text(email)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 5)

            if account.id == model.activeAccountID {
                Text(model.text("active"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            } else {
                Button(role: .destructive) {
                    page = .remove(account)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 25, height: 25)
                }
                .buttonStyle(.plain)
                .help(model.format("remove_title", account.displayName))
                .accessibilityLabel(model.format("remove_title", account.displayName))
                .disabled(model.isMutating)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

private enum ManageAccountsPage {
    case accounts
    case remove(AccountProfile)
}

struct PopoverHeader: View {
    let title: String
    let backTitle: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 27, height: 27)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(backTitle)
            .help(backTitle)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
    }
}
