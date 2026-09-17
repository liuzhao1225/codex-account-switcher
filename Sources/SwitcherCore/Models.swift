import Foundation

// Shared account and usage types for both native platform clients.

public struct AccountProfile: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var displayName: String
    public let email: String?
    public let accountID: String?
    public let createdAt: Date
    public var lastUsedAt: Date?

    public init(id: UUID, displayName: String, email: String?, accountID: String?, createdAt: Date, lastUsedAt: Date? = nil) {
        self.id = id; self.displayName = displayName; self.email = email
        self.accountID = accountID; self.createdAt = createdAt; self.lastUsedAt = lastUsedAt
    }

    public var initials: String {
        let parts = displayName
            .split(whereSeparator: { $0.isWhitespace })
            .prefix(2)
        let value = parts.compactMap(\.first).map(String.init).joined()
        return value.isEmpty ? "?" : value.uppercased()
    }
}

public struct AccountRegistry: Codable, Equatable, Sendable {
    public var activeAccountID: UUID?
    public var accounts: [AccountProfile]

    public init(activeAccountID: UUID?, accounts: [AccountProfile]) {
        self.activeAccountID = activeAccountID; self.accounts = accounts
    }

    public static let empty = AccountRegistry(activeAccountID: nil, accounts: [])
}

public enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case simplifiedChinese

    public var id: String { rawValue }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var language: AppLanguage
    public var showsMenuBarPercentage: Bool
    public var showsFiveHourUsage: Bool
    public var enablesProviderSwitching: Bool

    public static let `default` = AppSettings(
        language: .system,
        showsMenuBarPercentage: true,
        showsFiveHourUsage: false
    )

    public init(
        language: AppLanguage,
        showsMenuBarPercentage: Bool = true,
        showsFiveHourUsage: Bool = false,
        enablesProviderSwitching: Bool = false
    ) {
        self.language = language
        self.showsMenuBarPercentage = showsMenuBarPercentage
        self.showsFiveHourUsage = showsFiveHourUsage
        self.enablesProviderSwitching = enablesProviderSwitching
    }

    public init(from decoder: any Decoder) throws {
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
        enablesProviderSwitching = try container.decodeIfPresent(
            Bool.self,
            forKey: .enablesProviderSwitching
        ) ?? false
    }
}

public struct WeeklyUsage: Codable, Equatable, Sendable {
    public let remainingPercent: Int
    public let resetsAt: Date
    public let fiveHourRemainingPercent: Int?
    public let fiveHourResetsAt: Date?

    public init(
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

public struct UsageCacheEntry: Codable, Equatable, Sendable {
    public let profileID: UUID
    public let usage: WeeklyUsage
    public let fetchedAt: Date

    public init(profileID: UUID, usage: WeeklyUsage, fetchedAt: Date) {
        self.profileID = profileID; self.usage = usage; self.fetchedAt = fetchedAt
    }
}

public struct UsageCache: Codable, Equatable, Sendable {
    public var entries: [UsageCacheEntry]

    public init(entries: [UsageCacheEntry]) { self.entries = entries }

    public static let empty = UsageCache(entries: [])
}

public enum UsageViewState: Equatable, Sendable {
    case idle
    case loaded(WeeklyUsage)
    case stale(WeeklyUsage, String)
    case unavailable(String)

    public var displayedUsage: WeeklyUsage? {
        switch self {
        case let .loaded(usage), let .stale(usage, _):
            usage
        case .idle, .unavailable:
            nil
        }
    }

    public var refreshError: String? {
        guard case let .stale(_, message) = self else { return nil }
        return message
    }
}

public struct AccountIdentity: Equatable, Sendable {
    public let accountID: String?
    public let email: String?

    public init(accountID: String?, email: String?) { self.accountID = accountID; self.email = email }

    public var suggestedDisplayName: String {
        guard let email, let localPart = email.split(separator: "@").first else {
            return "Codex Account"
        }
        return String(localPart)
    }

    public func matches(_ profile: AccountProfile) -> Bool {
        if let expected = profile.accountID, let actual = accountID {
            return expected == actual
        }
        if let expected = profile.email, let actual = email {
            return expected.caseInsensitiveCompare(actual) == .orderedSame
        }
        return false
    }
}

public enum SwitchStage: String, CaseIterable, Sendable {
    case closeDesktop
    case activateTargetProvider
    case saveCurrentCredential
    case activateTargetCredential
    case verifyTargetIdentity
    case commitActiveAccountID
    case reopenDesktop
}

public struct OperationError: LocalizedError, Equatable, Sendable {
    public let stage: SwitchStage?
    public let titleKey: String
    public let messageKey: String?
    public let message: String
    public let underlyingDescription: String?

    public init(stage: SwitchStage?, titleKey: String, messageKey: String?, message: String, underlyingDescription: String?) {
        self.stage = stage; self.titleKey = titleKey; self.messageKey = messageKey
        self.message = message; self.underlyingDescription = underlyingDescription
    }

    public var errorDescription: String? {
        let title = L10n.string(titleKey, language: .english)
        if let stage {
            return "\(title) (\(stage.rawValue)): \(message)"
        }
        return "\(title): \(message)"
    }

    public static func stage(_ stage: SwitchStage, _ error: any Error) -> OperationError {
        OperationError(
            stage: stage,
            titleKey: "switch_failed",
            messageKey: nil,
            message: error.localizedDescription,
            underlyingDescription: String(describing: error)
        )
    }
}

public enum AccountStoreError: LocalizedError, Equatable, Sendable {
    case profileNotFound
    case activeProfileMissing
    case activeCredentialMissing
    case activeCredentialMismatch
    case targetCredentialMissing
    case duplicateAccount
    case cannotRemoveActiveAccount

    public var errorDescription: String? {
        switch self {
        case .profileNotFound:
            "The account profile could not be found."
        case .activeProfileMissing:
            "No active account profile is configured."
        case .activeCredentialMissing:
            "The active Codex auth.json file is missing."
        case .activeCredentialMismatch:
            "Codex is signed in to a different account than Switcher expects. No saved credential was overwritten. Use Register Current Account to associate the current login before switching."
        case .targetCredentialMissing:
            "The selected account has no saved auth.json file."
        case .duplicateAccount:
            "This account is already saved. Select the existing account instead."
        case .cannotRemoveActiveAccount:
            "The active account cannot be removed."
        }
    }
}

public enum CodexClientError: LocalizedError, Equatable, Sendable {
    case executableNotFound
    case processLaunchFailed(String)
    case malformedResponse
    case remoteError(code: Int?, message: String)
    case connectionClosed
    case connectionClosedWithDetails(String)
    case timeout
    case identityUnavailable
    case weeklyUsageUnavailable
    case loginFailed(String)

    public var errorDescription: String? {
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
        case let .connectionClosedWithDetails(details):
            "Codex app-server closed the connection: \(details)"
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
