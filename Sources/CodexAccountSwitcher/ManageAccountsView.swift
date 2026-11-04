import SwitcherCore
import SwiftUI

struct ManageAccountsView: View {
    @ObservedObject var model: AppModel
    let onBack: () -> Void

    @State private var page: ManageAccountsPage = .accounts
    @State private var apiKeyName = ""
    @State private var apiKeySecret = ""
    @State private var apiKeyError = false

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
            case .apiKey:
                apiKeyForm
            case let .remove(account):
                removePage(account)
            }
        }
    }

    private var headerTitle: String {
        switch page {
        case .accounts:
            model.text("accounts")
        case .apiKey:
            model.text("add_api_key")
        case let .remove(account):
            model.format("remove_title", account.displayName)
        }
    }

    private func navigateBack() {
        switch page {
        case .accounts:
            onBack()
        case .remove, .apiKey:
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

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    if model.isAddingAccount {
                        model.cancelAddingAccount()
                    } else {
                        model.addAccount()
                    }
                } label: {
                    Label(model.text(model.isAddingAccount ? "cancel_add_account" : "add_account"),
                          systemImage: model.isAddingAccount ? "xmark" : "plus")
                }
                .buttonStyle(.bordered)
                .disabled(model.isMutating && !model.isAddingAccount)

                signInHint

                Button {
                    apiKeyName = ""
                    apiKeySecret = ""
                    apiKeyError = false
                    page = .apiKey
                } label: {
                    Label(model.text("add_api_key"), systemImage: "key")
                }
                .buttonStyle(.bordered)
                .disabled(model.isMutating || model.isAddingAccount)

                Button {
                    Task { await model.registerCurrentAccount() }
                } label: {
                    Label(model.text("register_current_account"), systemImage: "person.crop.circle.badge.checkmark")
                }
                .buttonStyle(.borderless)
                .disabled(model.isMutating || model.isAddingAccount)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }

    private var signInHint: some View {
        let hint = model.text(model.isAddingAccount ? "sign_in_pending_hint" : "sign_in_hint")
        return Text(hint)
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .help(hint)
    }

    private var apiKeyForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.text("api_key_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 5) {
                Text(model.text("api_key_name"))
                TextField(model.text("api_key_name"), text: $apiKeyName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(model.text("api_key_secret"))
                SecureField(model.text("api_key_secret"), text: $apiKeySecret)
                    .textFieldStyle(.roundedBorder)
            }

            if apiKeyError {
                Text(model.text("api_key_invalid"))
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(model.text("cancel")) { page = .accounts }
                    .buttonStyle(.bordered)
                Button(model.text("save_api_key")) { saveAPIKey() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isMutating)
            }
        }
        .padding(16)
    }

    private func saveAPIKey() {
        let name = apiKeyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = apiKeySecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !secret.isEmpty, !secret.contains(where: \.isWhitespace) else {
            apiKeyError = true
            return
        }
        apiKeyError = false
        Task {
            await model.addAPIKey(displayName: name, key: secret)
            apiKeySecret = ""
            if model.visibleError == nil { page = .accounts }
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
        let title = account.email.flatMap { $0.isEmpty ? nil : $0 } ?? account.displayName
        return HStack(spacing: 9) {
            Text(account.initials)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.10), in: Circle())

            Text(verbatim: title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(title)

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
    case apiKey
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
