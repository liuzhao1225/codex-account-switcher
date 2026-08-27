import Foundation

struct AccountProfile: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    var displayName: String
    let email: String?
    let accountID: String?
    let createdAt: Date
    var lastUsedAt: Date?

    var initials: String {
        let parts = displayName
            .split(whereSeparator: { $0.isWhitespace })
            .prefix(2)
        let value = parts.compactMap(\.first).map(String.init).joined()
        return value.isEmpty ? "?" : value.uppercased()
    }
}

struct AccountRegistry: Codable, Equatable, Sendable {
    var activeAccountID: UUID?
    var accounts: [AccountProfile]

    static let empty = AccountRegistry(activeAccountID: nil, accounts: [])
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }
}

struct AppSettings: Codable, Equatable, Sendable {
    var language: AppLanguage
    var showsMenuBarPercentage: Bool
    var showsFiveHourUsage: Bool

    static let `default` = AppSettings(
        language: .system,
        showsMenuBarPercentage: true,
        showsFiveHourUsage: false
    )

    init(
        language: AppLanguage,
        showsMenuBarPercentage: Bool = true,
        showsFiveHourUsage: Bool = false
    ) {
        self.language = language
        self.showsMenuBarPercentage = showsMenuBarPercentage
        self.showsFiveHourUsage = showsFiveHourUsage
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        showsMenuBarPercentage = try container.decodeIfPresent(
            Bool.self,
            forKey: .showsMenuBarPercentage
        ) ?? true
        showsFiveHourUsage = try container.decodeIfPresent(
            Bool.self,
            forKey: .showsFiveHourUsage
        ) ?? false
    }
}

struct WeeklyUsage: Codable, Equatable, Sendable {
    let remainingPercent: Int
    let resetsAt: Date
    let fiveHourRemainingPercent: Int?
    let fiveHourResetsAt: Date?

    init(
        remainingPercent: Int,
        resetsAt: Date,
        fiveHourRemainingPercent: Int? = nil,
        fiveHourResetsAt: Date? = nil
    ) {
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
        self.fiveHourRemainingPercent = fiveHourRemainingPercent
        self.fiveHourResetsAt = fiveHourResetsAt
    }
}

struct UsageCacheEntry: Codable, Equatable, Sendable {
    let profileID: UUID
    let usage: WeeklyUsage
    let fetchedAt: Date
}

struct UsageCache: Codable, Equatable, Sendable {
    var entries: [UsageCacheEntry]

    static let empty = UsageCache(entries: [])
}

enum UsageViewState: Equatable, Sendable {
    case idle
    case loaded(WeeklyUsage)
    case stale(WeeklyUsage, String)
    case unavailable(String)

    var displayedUsage: WeeklyUsage? {
        switch self {
        case let .loaded(usage), let .stale(usage, _):
            usage
        case .idle, .unavailable:
            nil
        }
    }

    var refreshError: String? {
        guard case let .stale(_, message) = self else { return nil }
        return message
    }
}

struct AccountIdentity: Equatable, Sendable {
    let accountID: String?
    let email: String?

    var suggestedDisplayName: String {
        guard let email, let localPart = email.split(separator: "@").first else {
            return "Codex Account"
        }
        return String(localPart)
    }

    func matches(_ profile: AccountProfile) -> Bool {
        if let expected = profile.accountID, let actual = accountID {
            return expected == actual
        }
        if let expected = profile.email, let actual = email {
            return expected.caseInsensitiveCompare(actual) == .orderedSame
        }
        return false
    }
}

enum SwitchStage: String, CaseIterable, Sendable {
    case closeDesktop
    case saveCurrentCredential
    case activateTargetCredential
    case verifyTargetIdentity
    case commitActiveAccountID
    case reopenDesktop
}

struct OperationError: LocalizedError, Equatable, Sendable {
    let stage: SwitchStage?
    let titleKey: String
    let messageKey: String?
    let message: String
    let underlyingDescription: String?

    var errorDescription: String? {
        let title = L10n.string(titleKey, language: .english)
        if let stage {
            return "\(title) (\(stage.rawValue)): \(message)"
        }
        return "\(title): \(message)"
    }

    static func stage(_ stage: SwitchStage, _ error: any Error) -> OperationError {
        OperationError(
            stage: stage,
            titleKey: "switch_failed",
            messageKey: nil,
            message: error.localizedDescription,
            underlyingDescription: String(describing: error)
        )
    }
}

enum AccountStoreError: LocalizedError, Equatable, Sendable {
    case profileNotFound
    case activeProfileMissing
    case activeCredentialMissing
    case targetCredentialMissing
    case cannotRemoveActiveAccount

    var errorDescription: String? {
        switch self {
        case .profileNotFound:
            "The account profile could not be found."
        case .activeProfileMissing:
            "No active account profile is configured."
        case .activeCredentialMissing:
            "The active Codex auth.json file is missing."
        case .targetCredentialMissing:
            "The selected account has no saved auth.json file."
        case .cannotRemoveActiveAccount:
            "The active account cannot be removed."
        }
    }
}

enum CodexClientError: LocalizedError, Equatable, Sendable {
    case executableNotFound
    case processLaunchFailed(String)
    case malformedResponse
    case remoteError(code: Int?, message: String)
    case connectionClosed
    case timeout
    case identityUnavailable
    case weeklyUsageUnavailable
    case loginFailed(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "The Codex executable could not be found."
        case let .processLaunchFailed(message):
            "Codex app-server failed to start: \(message)"
        case .malformedResponse:
            "Codex app-server returned malformed JSON."
        case let .remoteError(code, message):
            code.map { "Codex app-server error \($0): \(message)" } ?? "Codex app-server error: \(message)"
        case .connectionClosed:
            "Codex app-server closed the connection."
        case .timeout:
            "Codex app-server did not respond before the timeout."
        case .identityUnavailable:
            "Codex did not return an account identity."
        case .weeklyUsageUnavailable:
            "No weekly Codex Usage window is available."
        case let .loginFailed(message):
            "Codex login failed: \(message)"
        }
    }
}
