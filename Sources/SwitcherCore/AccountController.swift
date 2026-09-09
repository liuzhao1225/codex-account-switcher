import Foundation

private enum UsageRefreshResult: Sendable {
    case success(UUID, WeeklyUsage)
    case failure(UUID, String)
}

@MainActor
open class AccountController {
    public var onChange: (@MainActor () -> Void)?
    public private(set) var providers: [ProviderProfile] = [] { didSet { onChange?() } }
    public private(set) var activeAuthentication: CodexAuthenticationState? { didSet { onChange?() } }
    public private(set) var activeProviderID = CodexConfigurationClient.openAIProviderID { didSet { onChange?() } }
    public private(set) var accounts: [AccountProfile] = [] { didSet { onChange?() } }
    public private(set) var activeAccountID: UUID? { didSet { onChange?() } }
    public private(set) var usageStates: [UUID: UsageViewState] = [:] { didSet { onChange?() } }
    public private(set) var settings: AppSettings = .default { didSet { onChange?() } }
    public private(set) var isMutating = false { didSet { onChange?() } }
    public private(set) var isAddingAccount = false { didSet { onChange?() } }
    public var visibleError: OperationError? { didSet { onChange?() } }
    public private(set) var activeIdentityConfirmed = true { didSet { onChange?() } }

    private let store: AccountStore
    private let codex: any AccountClient
    private let configuration: any ProviderConfigurationServicing
    private let providerSwitchService: any ProviderSwitchServicing
    private let switchService: any SwitchServicing
    private var hasStarted = false
    private var usageRefreshTask: Task<Void, Never>?
    private var nextUsageRefreshTask: Task<Void, Never>?
    private var addAccountTask: Task<Void, Never>?
    private var backgroundUsageRefreshInterval: Duration = .seconds(300)
    private var isBackgroundUsageRefreshEnabled = false

    public init(
        store: AccountStore,
        codex: any AccountClient,
        configuration: any ProviderConfigurationServicing,
        switchService: any SwitchServicing,
        providerSwitchService: any ProviderSwitchServicing
    ) {
        self.store = store
        self.codex = codex
        self.switchService = switchService
        self.configuration = configuration
        self.providerSwitchService = providerSwitchService
    }

    public func text(_ key: String) -> String {
        L10n.string(key, language: settings.language)
    }

    public func format(_ key: String, _ argument: String) -> String {
        String(format: text(key), argument)
    }

    public var activeRemainingPercent: Int? {
        guard let activeAccountID,
              let account = accounts.first(where: { $0.id == activeAccountID }),
              isAccountActive(account)
        else {
            return nil
        }
        return usageStates[activeAccountID]?.displayedUsage?.remainingPercent
    }

    public func start() async {
        if hasStarted {
            await refreshProviderConfiguration()
            await confirmActiveIdentity()
            return
        }
        hasStarted = true
        do {
            settings = try await store.loadSettings()
            await refreshProviderConfiguration()
            var registry = try await store.loadRegistry()
            if activeProviderID == CodexConfigurationClient.openAIProviderID,
               activeAuthentication?.identity != nil,
               registry.accounts.isEmpty, await store.activeCredentialExists() {
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

    public func refreshWeeklyUsage() {
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

    public func waitForWeeklyUsageRefresh() async {
        await usageRefreshTask?.value
    }

    public func startBackgroundUsageRefresh(every interval: Duration = .seconds(300)) async {
        backgroundUsageRefreshInterval = interval
        isBackgroundUsageRefreshEnabled = true
        await start()
        refreshWeeklyUsage()
    }

    public func stopBackgroundUsageRefresh() {
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

    public func switchAccount(to id: UUID) async {
        guard !isMutating, !isAddingAccount else { return }
        isMutating = true
        defer { isMutating = false }
        guard await refreshProviderConfiguration() else { return }
        await confirmActiveIdentity()
        guard !isAccountSelectionActive(id) else { return }
        do {
            try await switchService.switchAccount(to: id)
            apply(try await store.loadRegistry())
            if await refreshProviderConfiguration() {
                await confirmActiveIdentity()
                visibleError = nil
            }
        } catch let error as OperationError {
            await refreshProviderConfiguration()
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
                if error.stage == .saveCurrentCredential { activeIdentityConfirmed = false }
                visibleError = error
            }
        } catch {
            await refreshProviderConfiguration()
            showError(error)
        }
    }

    public func addAccount() {
        guard !isMutating, !isAddingAccount else { return }
        isAddingAccount = true
        addAccountTask = Task { [weak self] in
            guard let self else { return }
            await self.performAddAccount()
            self.isAddingAccount = false
            self.addAccountTask = nil
        }
    }

    public func cancelAddingAccount() {
        addAccountTask?.cancel()
    }

    private func performAddAccount() async {
        let id = UUID()
        do {
            let home = try await store.createProfileDirectory(id: id)
            try Task.checkCancellation()
            let identity = try await codex.login(profileHome: home)
            try Task.checkCancellation()
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
            let loginError = error
            do {
                try await store.discardUnregisteredProfile(id: id)
            } catch {
                showError(NSError(domain: "CodexAccountSwitcher.Login", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "\(loginError.localizedDescription) Removing the incomplete profile also failed: \(error.localizedDescription)",
                ]))
                return
            }
            if !(loginError is CancellationError) { showError(loginError) }
        }
    }

    public func registerCurrentAccount() async {
        guard !isMutating, !isAddingAccount else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            let identity = try await codex.readIdentity(profileHome: await store.activeCodexHome())
            try await store.registerActiveIdentity(identity)
            apply(try await store.loadRegistry())
            if await refreshProviderConfiguration() {
                await confirmActiveIdentity()
                visibleError = nil
            }
        } catch { showError(error) }
    }

    public func removeAccount(id: UUID) async {
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

    public func setLanguage(_ language: AppLanguage) async {
        settings.language = language
        do {
            try await store.saveSettings(settings)
        } catch {
            showError(error)
        }
    }

    public func setShowsMenuBarPercentage(_ enabled: Bool) async {
        settings.showsMenuBarPercentage = enabled
        do {
            try await store.saveSettings(settings)
        } catch {
            showError(error)
        }
    }

    public func setShowsFiveHourUsage(_ enabled: Bool) async {
        settings.showsFiveHourUsage = enabled
        do {
            try await store.saveSettings(settings)
        } catch {
            showError(error)
        }
    }

    public func dismissError() {
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
        if activeProviderID != CodexConfigurationClient.openAIProviderID || activeAuthentication == .apiKey {
            activeIdentityConfirmed = true
            return
        }
        guard let identity = activeAuthentication?.identity,
              let activeID = activeAccountID,
              let profile = accounts.first(where: { $0.id == activeID }) else {
            activeIdentityConfirmed = accounts.isEmpty && activeAuthentication == .signedOut
            return
        }
        activeIdentityConfirmed = identity.matches(profile)
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

    public func isAccountActive(_ account: AccountProfile) -> Bool {
        activeProviderID == CodexConfigurationClient.openAIProviderID
            && account.id == activeAccountID
            && activeAuthentication?.identity?.matches(account) == true
    }

    public func isProviderActive(_ provider: ProviderProfile) -> Bool {
        provider.id == activeProviderID
            && (provider.id != CodexConfigurationClient.openAIProviderID || activeAuthentication == .apiKey)
    }

    public func switchProvider(to provider: ProviderProfile) async {
        guard settings.enablesProviderSwitching, !isMutating, !isAddingAccount else { return }
        isMutating = true
        defer { isMutating = false }
        guard await refreshProviderConfiguration() else { return }
        guard !isProviderActive(provider) else { return }
        do {
            try await providerSwitchService.switchProvider(to: provider.id)
            if await refreshProviderConfiguration() {
                await confirmActiveIdentity()
                visibleError = nil
            }
        } catch let error as OperationError {
            await refreshProviderConfiguration()
            if error.stage == .reopenDesktop {
                visibleError = OperationError(
                    stage: .reopenDesktop,
                    titleKey: "switched_reopen_title",
                    messageKey: "provider_switched_reopen_message",
                    message: text("provider_switched_reopen_message"),
                    underlyingDescription: error.underlyingDescription
                )
            } else {
                visibleError = error
            }
        } catch {
            showError(error)
        }
    }

    public func setEnablesProviderSwitching(_ enabled: Bool) async {
        var updated = settings
        updated.enablesProviderSwitching = enabled
        do {
            try await store.saveSettings(updated)
            settings = updated
        } catch {
            showError(error)
        }
    }

    private func isAccountSelectionActive(_ id: UUID) -> Bool {
        accounts.first(where: { $0.id == id }).map(isAccountActive) ?? false
    }

    @discardableResult
    private func refreshProviderConfiguration() async -> Bool {
        do {
            let snapshot = try await configuration.readConfiguration(
                codexHome: await store.activeCodexHome()
            )
            let authentication = try await codex.readAuthentication(profileHome: await store.activeCodexHome())
            let hasSavedAPI = await store.hasOpenAIAPICredential()
            var choices = snapshot.providers
            if authentication == .apiKey || hasSavedAPI {
                choices.insert(ProviderProfile(id: CodexConfigurationClient.openAIProviderID,
                                               displayName: "OpenAI API"), at: 0)
            }
            providers = choices
            activeProviderID = snapshot.activeProviderID
            activeAuthentication = authentication
            return true
        } catch {
            activeAuthentication = nil
            showError(error)
            return false
        }
    }

}
