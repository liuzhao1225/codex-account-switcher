import Foundation

private enum UsageRefreshResult: Sendable {
    case success(UUID, WeeklyUsage)
    case failure(UUID, String)
}

@MainActor
open class AccountController {
    public var onChange: (@MainActor () -> Void)?
    public private(set) var accounts: [AccountProfile] = [] { didSet { onChange?() } }
    public private(set) var activeAccountID: UUID? { didSet { onChange?() } }
    public private(set) var usageStates: [UUID: UsageViewState] = [:] { didSet { onChange?() } }
    public private(set) var subscriptionStates: [UUID: LiveSubscriptionState] = [:] { didSet { onChange?() } }
    public private(set) var subscriptionSnapshots: [UUID: SubscriptionSnapshot] = [:] { didSet { onChange?() } }
    public private(set) var settings: AppSettings = .default { didSet { onChange?() } }
    public private(set) var isMutating = false { didSet { onChange?() } }
    public private(set) var isAddingAccount = false { didSet { onChange?() } }
    public var visibleError: OperationError? { didSet { onChange?() } }
    public private(set) var activeIdentityConfirmed = true { didSet { onChange?() } }

    private let store: AccountStore
    private let codex: any AccountClient
    private let subscriptionClient: any SubscriptionClient
    private let switchService: any SwitchServicing
    private var subscriptionAuthAttempts: [UUID: Date] = [:]
    private var hasStarted = false
    private var usageRefreshTask: Task<Void, Never>?
    private var nextUsageRefreshTask: Task<Void, Never>?
    private var addAccountTask: Task<Void, Never>?
    private var backgroundUsageRefreshInterval: Duration = .seconds(300)
    private var isBackgroundUsageRefreshEnabled = false

    public init(
        store: AccountStore,
        codex: any AccountClient,
        switchService: any SwitchServicing,
        subscriptionClient: any SubscriptionClient = LiveSubscriptionClient()
    ) {
        self.store = store
        self.codex = codex
        self.switchService = switchService
        self.subscriptionClient = subscriptionClient
    }

    public func text(_ key: String) -> String {
        L10n.string(key, language: settings.language)
    }

    public func format(_ key: String, _ argument: String) -> String {
        String(format: text(key), argument)
    }

    public var activeRemainingPercent: Int? {
        guard let activeAccountID else { return nil }
        guard let usage = usageStates[activeAccountID]?.displayedUsage else { return nil }
        return settings.statusBarUsageWindow == .fiveHour
            ? (usage.fiveHourRemainingPercent ?? usage.remainingPercent)
            : usage.remainingPercent
    }

    public func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        isMutating = true
        defer { isMutating = false }
        do {
            settings = try await store.loadSettings()
            apply(try await store.loadRegistry())
            try await syncActiveIdentity()
            await refreshSubscriptionSnapshots()
            do {
                apply(try await store.loadUsageCache())
                for (id, value) in try await store.loadLiveSubscriptions() {
                    subscriptionStates[id] = .stale(value, text("subscription_refresh_pending"))
                }
            } catch {
                showError(error)
            }
        } catch {
            showError(error)
        }
    }

    public func refreshWeeklyUsage() {
        if isBackgroundUsageRefreshEnabled {
            scheduleNextWeeklyUsageRefresh()
        }
        guard !isMutating, usageRefreshTask == nil else { return }
        usageRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.performWeeklyUsageRefresh()
            self.usageRefreshTask = nil
        }
    }

    public func waitForWeeklyUsageRefresh() async {
        await usageRefreshTask?.value
    }

    private func refreshSubscriptionSnapshots() async {
        var snapshots: [UUID: SubscriptionSnapshot] = [:]
        for account in accounts {
            if let snapshot = await store.readSubscriptionSnapshot(
                profile: account, isActive: account.id == activeAccountID
            ) {
                snapshots[account.id] = snapshot
            }
        }
        subscriptionSnapshots = snapshots
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
        guard !Task.isCancelled else { return }
        do {
            try await syncActiveIdentity()
        } catch {
            showError(error)
            return
        }
        guard !Task.isCancelled else { return }
        await refreshSubscriptionSnapshots()
        await withTaskGroup(of: UsageRefreshResult.self) { group in
            for account in accounts {
                group.addTask { [store, codex] in
                    do {
                        let home = await store.profileHome(id: account.id)
                        try Task.checkCancellation()
                        return .success(account.id, try await codex.readWeeklyUsage(profileHome: home))
                    } catch {
                        return .failure(account.id, error.localizedDescription)
                    }
                }
            }
            for await result in group {
                guard !Task.isCancelled else { continue }
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
        await refreshLiveSubscriptions()
    }

    private func refreshLiveSubscriptions() async {
        // Each service response is account-bound. Authentication recovery runs
        // only after all quota requests have finished, avoiding concurrent writers.
        // Subscription results are cached outside auth.json.
        for account in accounts {
            guard !Task.isCancelled else { return }
            do {
                let value = try await readLiveSubscription(account)
                try Task.checkCancellation()
                guard accounts.contains(where: { $0.id == account.id && $0.accountID == account.accountID }) else { continue }
                subscriptionStates[account.id] = .loaded(value)
                try await store.cacheLiveSubscription(value, profile: account)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                // Errors are owned by this reader and contain no response body,
                // request URL or credentials. File errors use a generic message.
                let message = error is LiveSubscriptionError
                    ? error.localizedDescription : text("subscription_refresh_failed")
                if let value = subscriptionStates[account.id]?.displayedSubscription {
                    subscriptionStates[account.id] = .stale(value, message)
                } else {
                    subscriptionStates[account.id] = .unavailable(message)
                }
            }
        }
    }

    private func readLiveSubscription(_ account: AccountProfile) async throws -> LiveSubscription {
        func read() async throws -> LiveSubscription {
            let credential = try await store.subscriptionCredential(
                profile: account, isActive: account.id == activeAccountID
            )
            return try await subscriptionClient.readSubscription(
                credential: credential, expectedAccountID: account.accountID,
                expectedEmail: account.email
            )
        }
        do { return try await read() }
        catch LiveSubscriptionError.unauthenticated {
            // Only an actual authentication rejection justifies token renewal.
            // Desktop owns the active login; never rotate its saved copy here.
            guard account.id != activeAccountID,
                  subscriptionAuthAttempts[account.id].map({ Date().timeIntervalSince($0) >= 6 * 3_600 }) ?? true else {
                throw LiveSubscriptionError.unauthenticated
            }
            try Task.checkCancellation()
            // Revalidate immediately before allowing Codex to write this profile.
            guard try await store.permitsSubscriptionCredentialRenewal(profile: account) else {
                throw LiveSubscriptionError.unauthenticated
            }
            subscriptionAuthAttempts[account.id] = Date()
            do {
                let home = await store.profileHome(id: account.id)
                let identity = try await codex.refreshIdentity(profileHome: home)
                guard identity.matches(account) else { throw LiveSubscriptionError.invalidCredential }
                try Task.checkCancellation()
                let value = try await read()
                subscriptionAuthAttempts.removeValue(forKey: account.id)
                return value
            } catch is CancellationError { throw CancellationError() }
            catch {
                if Task.isCancelled { throw CancellationError() }
                // Never expose app-server diagnostics, which can contain credentials.
                throw LiveSubscriptionError.unauthenticated
            }
        }
    }

    public func switchAccount(to id: UUID) async {
        guard !isMutating else { return }
        isMutating = true
        await cancelUsageRefresh()
        defer { isMutating = false; refreshWeeklyUsage() }
        do {
            try await syncActiveIdentity()
            guard id != activeAccountID else { return }
            try await switchService.switchAccount(to: id)
            apply(try await store.loadRegistry())
            await refreshSubscriptionSnapshots()
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
                if error.stage == .saveCurrentCredential { activeIdentityConfirmed = false }
                visibleError = error
            }
        } catch {
            showError(error)
        }
    }

    public func addAccount() {
        guard !isMutating, !isAddingAccount else { return }
        visibleError = nil
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
            await refreshSubscriptionSnapshots()
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
        await cancelUsageRefresh()
        defer { isMutating = false; refreshWeeklyUsage() }
        do {
            let identity = try await codex.readIdentity(profileHome: await store.activeCodexHome())
            try await store.registerActiveIdentity(identity)
            apply(try await store.loadRegistry())
            await refreshSubscriptionSnapshots()
            activeIdentityConfirmed = true
            visibleError = nil
        } catch { showError(error) }
    }

    public func removeAccount(id: UUID) async {
        guard !isMutating else { return }
        isMutating = true
        await cancelUsageRefresh()
        defer { isMutating = false; refreshWeeklyUsage() }
        do {
            try await syncActiveIdentity()
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

    public func setStatusBarUsageWindow(_ window: StatusBarUsageWindow) async {
        settings.statusBarUsageWindow = window
        do {
            try await store.saveSettings(settings)
        } catch {
            showError(error)
        }
    }

    public func dismissError() {
        visibleError = nil
    }

    private func cancelUsageRefresh() async {
        usageRefreshTask?.cancel()
        await usageRefreshTask?.value
    }

    private func apply(_ registry: AccountRegistry) {
        accounts = registry.accounts
        activeAccountID = registry.activeAccountID
        usageStates = usageStates.filter { id, _ in registry.accounts.contains(where: { $0.id == id }) }
        subscriptionStates = subscriptionStates.filter { id, _ in registry.accounts.contains(where: { $0.id == id }) }
        subscriptionSnapshots = subscriptionSnapshots.filter { id, _ in registry.accounts.contains(where: { $0.id == id }) }
    }

    private func apply(_ cache: UsageCache) {
        let validAccountIDs = Set(accounts.map(\.id))
        for entry in cache.entries where validAccountIDs.contains(entry.profileID) {
            usageStates[entry.profileID] = .loaded(entry.usage)
        }
    }

    private func syncActiveIdentity() async throws {
        do {
            apply(try await store.syncActiveCredential())
            activeIdentityConfirmed = activeAccountID != nil || accounts.isEmpty
        } catch {
            activeAccountID = nil
            activeIdentityConfirmed = false
            throw error
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
