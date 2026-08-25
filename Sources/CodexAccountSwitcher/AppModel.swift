import Foundation
import ServiceManagement
import SwiftUI

private enum UsageRefreshResult: Sendable {
    case success(UUID, WeeklyUsage)
    case failure(UUID, String)
}

enum LaunchAtLoginState: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    init(status: SMAppService.Status) {
        switch status {
        case .notRegistered:
            self = .disabled
        case .enabled:
            self = .enabled
        case .requiresApproval:
            self = .requiresApproval
        case .notFound:
            self = .unavailable
        @unknown default:
            self = .unavailable
        }
    }

    var isOn: Bool {
        self == .enabled || self == .requiresApproval
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var accounts: [AccountProfile] = []
    @Published private(set) var activeAccountID: UUID?
    @Published private(set) var usageStates: [UUID: UsageViewState] = [:]
    @Published private(set) var settings: AppSettings = .default
    @Published private(set) var isMutating = false
    @Published var visibleError: OperationError?
    @Published private(set) var activeIdentityConfirmed = true
    @Published private(set) var launchAtLoginState: LaunchAtLoginState = .disabled

    private let store: AccountStore
    private let codex: CodexClient
    private let switchService: any SwitchServicing
    private var hasStarted = false
    private var usageRefreshTask: Task<Void, Never>?
    private var nextUsageRefreshTask: Task<Void, Never>?
    private var backgroundUsageRefreshInterval: Duration = .seconds(300)
    private var isBackgroundUsageRefreshEnabled = false

    init(
        store: AccountStore,
        codex: CodexClient,
        switchService: any SwitchServicing
    ) {
        self.store = store
        self.codex = codex
        self.switchService = switchService
    }

    static func live() -> AppModel {
        let store = AccountStore()
        let codex = CodexClient()
        return AppModel(
            store: store,
            codex: codex,
            switchService: SwitchService(
                desktop: DesktopController(),
                store: store,
                codex: codex
            )
        )
    }

    func text(_ key: String) -> String {
        L10n.string(key, language: settings.language)
    }

    func format(_ key: String, _ argument: String) -> String {
        String(format: text(key), argument)
    }

    var activeRemainingPercent: Int? {
        guard let activeAccountID else { return nil }
        return usageStates[activeAccountID]?.displayedUsage?.remainingPercent
    }

    var launchesAtLogin: Bool {
        launchAtLoginState.isOn
    }

    var launchAtLoginRequiresApproval: Bool {
        launchAtLoginState == .requiresApproval
    }

    var launchAtLoginUnavailable: Bool {
        launchAtLoginState == .unavailable
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        refreshLaunchAtLoginStatus()
        do {
            settings = try await store.loadSettings()
            var registry = try await store.loadRegistry()
            if registry.accounts.isEmpty, await store.activeCredentialExists() {
                let activeHome = await store.activeCodexHome()
                let identity = try await codex.readIdentity(profileHome: activeHome)
                let profile = AccountProfile(
                    id: UUID(),
                    displayName: identity.suggestedDisplayName,
                    email: identity.email,
                    accountID: identity.accountID,
                    createdAt: Date(),
                    lastUsedAt: Date()
                )
                try await store.importCurrentProfile(profile)
                registry = try await store.loadRegistry()
            }
            apply(registry)
            do {
                apply(try await store.loadUsageCache())
            } catch {
                showError(error)
            }
            await confirmActiveIdentity()
        } catch {
            showError(error)
        }
    }

    func refreshWeeklyUsage() {
        if isBackgroundUsageRefreshEnabled {
            scheduleNextWeeklyUsageRefresh()
        }
        guard !accounts.isEmpty, usageRefreshTask == nil else { return }
        usageRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.performWeeklyUsageRefresh()
            self.usageRefreshTask = nil
        }
    }

    func waitForWeeklyUsageRefresh() async {
        await usageRefreshTask?.value
    }

    func startBackgroundUsageRefresh(every interval: Duration = .seconds(300)) async {
        backgroundUsageRefreshInterval = interval
        isBackgroundUsageRefreshEnabled = true
        await start()
        refreshWeeklyUsage()
    }

    func stopBackgroundUsageRefresh() {
        isBackgroundUsageRefreshEnabled = false
        nextUsageRefreshTask?.cancel()
        nextUsageRefreshTask = nil
    }

    private func scheduleNextWeeklyUsageRefresh() {
        nextUsageRefreshTask?.cancel()
        let interval = backgroundUsageRefreshInterval
        nextUsageRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.nextUsageRefreshTask = nil
            self.refreshWeeklyUsage()
        }
    }

    private func performWeeklyUsageRefresh() async {
        let targets = await withTaskGroup(of: (UUID, URL).self, returning: [(UUID, URL)].self) { group in
            for account in accounts {
                group.addTask { [store] in
                    (account.id, await store.profileHome(id: account.id))
                }
            }
            var values: [(UUID, URL)] = []
            for await value in group { values.append(value) }
            return values
        }

        await withTaskGroup(of: UsageRefreshResult.self) { group in
            for (id, home) in targets {
                group.addTask { [codex] in
                    do {
                        return .success(id, try await codex.readWeeklyUsage(profileHome: home))
                    } catch {
                        return .failure(id, error.localizedDescription)
                    }
                }
            }
            for await result in group {
                switch result {
                case let .success(id, usage):
                    guard accounts.contains(where: { $0.id == id }) else { continue }
                    usageStates[id] = .loaded(usage)
                    do {
                        try await store.cacheWeeklyUsage(usage, profileID: id)
                    } catch {
                        showError(error)
                    }
                case let .failure(id, message):
                    guard accounts.contains(where: { $0.id == id }) else { continue }
                    if let cached = usageStates[id]?.displayedUsage {
                        usageStates[id] = .stale(cached, message)
                    } else {
                        usageStates[id] = .unavailable(message)
                    }
                }
            }
        }
    }

    func switchAccount(to id: UUID) async {
        guard id != activeAccountID, !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            try await switchService.switchAccount(to: id)
            apply(try await store.loadRegistry())
            activeIdentityConfirmed = true
        } catch let error as OperationError {
            if error.stage == .reopenDesktop {
                do {
                    apply(try await store.loadRegistry())
                    activeIdentityConfirmed = true
                } catch {
                    showError(error)
                    return
                }
                visibleError = OperationError(
                    stage: .reopenDesktop,
                    titleKey: "switched_reopen_title",
                    messageKey: "switched_reopen_message",
                    message: text("switched_reopen_message"),
                    underlyingDescription: error.underlyingDescription
                )
            } else {
                visibleError = error
            }
        } catch {
            showError(error)
        }
    }

    func addAccount() async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            let id = UUID()
            let home = try await store.createProfileDirectory(id: id)
            let identity = try await codex.login(profileHome: home)
            let profile = AccountProfile(
                id: id,
                displayName: identity.suggestedDisplayName,
                email: identity.email,
                accountID: identity.accountID,
                createdAt: Date(),
                lastUsedAt: nil
            )
            try await store.addProfile(profile)
            apply(try await store.loadRegistry())
        } catch {
            showError(error)
        }
    }

    func removeAccount(id: UUID) async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            try await store.removeAccount(id: id)
            apply(try await store.loadRegistry())
            usageStates[id] = nil
        } catch {
            showError(error)
        }
    }

    func setLanguage(_ language: AppLanguage) async {
        settings.language = language
        do {
            try await store.saveSettings(settings)
        } catch {
            showError(error)
        }
    }

    func setShowsMenuBarPercentage(_ enabled: Bool) async {
        settings.showsMenuBarPercentage = enabled
        do {
            try await store.saveSettings(settings)
        } catch {
            showError(error)
        }
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginState = LaunchAtLoginState(status: SMAppService.mainApp.status)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            refreshLaunchAtLoginStatus()
        } catch {
            refreshLaunchAtLoginStatus()
            showError(error)
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func dismissError() {
        visibleError = nil
    }

    private func apply(_ registry: AccountRegistry) {
        accounts = registry.accounts
        activeAccountID = registry.activeAccountID
        usageStates = usageStates.filter { id, _ in registry.accounts.contains(where: { $0.id == id }) }
    }

    private func apply(_ cache: UsageCache) {
        let validAccountIDs = Set(accounts.map(\.id))
        for entry in cache.entries where validAccountIDs.contains(entry.profileID) {
            usageStates[entry.profileID] = .loaded(entry.usage)
        }
    }

    private func confirmActiveIdentity() async {
        guard let activeID = activeAccountID,
              let profile = accounts.first(where: { $0.id == activeID })
        else { return }
        do {
            let identity = try await codex.readIdentity(profileHome: await store.activeCodexHome())
            activeIdentityConfirmed = identity.matches(profile)
        } catch {
            activeIdentityConfirmed = false
        }
    }

    private func showError(_ error: any Error) {
        visibleError = OperationError(
            stage: nil,
            titleKey: "operation_failed",
            messageKey: nil,
            message: error.localizedDescription,
            underlyingDescription: String(describing: error)
        )
    }
}
