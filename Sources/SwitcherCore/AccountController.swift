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
    public private(set) var subscriptionSnapshots: [UUID: SubscriptionSnapshot] = [:] { didSet { onChange?() } }
    public private(set) var settings: AppSettings = .default { didSet { onChange?() } }
    public private(set) var isMutating = false { didSet { onChange?() } }
    public private(set) var isAddingAccount = false { didSet { onChange?() } }
    public var visibleError: OperationError? { didSet { onChange?() } }
    public private(set) var activeIdentityConfirmed = true { didSet { onChange?() } }

    private let store: AccountStore
    private let codex: any AccountClient
    private let switchService: any SwitchServicing
    private var hasStarted = false
    private var usageRefreshTask: Task<Void, Never>?
    private var nextUsageRefreshTask: Task<Void, Never>?
    private var addAccountTask: Task<Void, Never>?
    private var backgroundUsageRefreshInterval: Duration = .seconds(300)
    private var isBackgroundUsageRefreshEnabled = false
    private var autoReset: AutoReset?
    private var resetExpiryTask: Task<Void, Never>?

    public var resetExpiryLogURL: URL { store.resetExpiryLogURL }

    public init(
        store: AccountStore,
        codex: any AccountClient,
        switchService: any SwitchServicing
    ) {
        self.store = store
        self.codex = codex
        self.switchService = switchService
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
            } catch {
                showError(error)
            }
            if settings.autoResetEnabled {
                try await beginAutoReset(event: "resumed")
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
            self.scheduleResetExpiryCheck()
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
        resetExpiryTask?.cancel()
        resetExpiryTask = nil
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
            for account in accounts {
                await observeResetExpiry(profile: account, usage: nil, error: error.localizedDescription)
            }
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
                    guard let account = accounts.first(where: { $0.id == id }) else { continue }
                    usageStates[id] = .loaded(usage)
                    do {
                        try await store.cacheWeeklyUsage(usage, profileID: id)
                    } catch {
                        showError(error)
                    }
                    await observeResetExpiry(profile: account, usage: usage)
                case let .failure(id, message):
                    guard let account = accounts.first(where: { $0.id == id }) else { continue }
                    await observeResetExpiry(profile: account, usage: nil, error: message)
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
            guard await store.activeCredentialExists() else { throw AccountStoreError.activeCredentialMissing }
            try await syncActiveIdentity()
            await refreshSubscriptionSnapshots()
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

    public func setAutoResetEnabled(_ enabled: Bool) async {
        do {
            var updated = settings
            updated.autoResetEnabled = enabled
            try await store.saveSettings(updated)
            settings = updated
            resetExpiryTask?.cancel()
            resetExpiryTask = nil
            autoReset = nil
            if enabled {
                try await beginAutoReset(event: "enabled")
                refreshWeeklyUsage()
            } else {
                try await store.appendResetExpiryLog([ResetExpiryEvent(timestamp: Date(), event: "disabled")])
            }
        } catch {
            stopAutoReset(error)
        }
    }

    private func beginAutoReset(event: String) async throws {
        let history = try await store.loadResetExpiryLog()
        guard settings.autoResetEnabled else { return }
        try await store.appendResetExpiryLog([ResetExpiryEvent(timestamp: Date(), event: event)])
        guard settings.autoResetEnabled else { return }
        autoReset = AutoReset(history: history)
    }

    private func observeResetExpiry(profile: AccountProfile, usage: WeeklyUsage?, error: String? = nil) async {
        guard settings.autoResetEnabled, var experiment = autoReset else { return }
        let events = experiment.observe(profile: profile, usage: usage, error: error, at: Date())
        autoReset = experiment
        do {
            try await store.appendResetExpiryLog(events)
            var latestUsage = usage
            for checkpoint in events where checkpoint.decision == "attempt" {
                guard settings.autoResetEnabled, autoReset?.generation == experiment.generation,
                      !Task.isCancelled else { return }
                guard let creditID = checkpoint.creditID, let expiry = checkpoint.expiresAt,
                      expiry > Date(),
                      latestUsage?.resetCredits?.contains(where: { $0.id == creditID && $0.status == "available" }) == true
                else { continue }
                let key = UUID().uuidString
                let attempt = ResetExpiryEvent(resetAttempted: true, timestamp: Date(), event: "reset_attempt",
                    profileID: profile.id, account: profile.displayName, usage: latestUsage,
                    creditID: creditID, expiresAt: expiry, checkpointMinutes: checkpoint.checkpointMinutes,
                    scheduledAt: checkpoint.scheduledAt, idempotencyKey: key)
                // Persist the attempt before the network mutation. An interrupted attempt is never replayed.
                try await store.appendResetExpiryLog([attempt])
                autoReset?.recordAttempt(attempt)
                var result = ResetExpiryEvent(resetAttempted: true, timestamp: Date(), event: "reset_result",
                    profileID: profile.id, account: profile.displayName, creditID: creditID,
                    expiresAt: expiry, checkpointMinutes: checkpoint.checkpointMinutes, idempotencyKey: key)
                let home = await store.profileHome(id: profile.id)
                do {
                    try Task.checkCancellation()
                    guard settings.autoResetEnabled, autoReset?.generation == experiment.generation else { return }
                    result.outcome = try await codex.consumeResetCredit(profileHome: home, creditID: creditID, idempotencyKey: key)
                } catch {
                    result.timestamp = Date()
                    result.error = error.localizedDescription
                    do { try await store.appendResetExpiryLog([result]) }
                    catch { throw AutoResetError(message: "\(result.error!) Log write failed: \(error.localizedDescription)") }
                    showError(AutoResetError(message: "\(profile.displayName) · \(creditID): \(error.localizedDescription)"))
                    return
                }
                result.timestamp = Date()
                try await store.appendResetExpiryLog([result])
                autoReset?.recordAttempt(result)
                guard result.outcome != .nothingToReset else { continue }
                var readback: WeeklyUsage?
                do {
                    let refreshed = try await codex.readWeeklyUsage(profileHome: home)
                    readback = refreshed
                    if result.outcome == .reset {
                        guard let credits = refreshed.resetCredits,
                              !credits.contains(where: { $0.id == creditID && $0.status == "available" }) else {
                            throw AutoResetError(message: "\(profile.displayName) · \(creditID): reset returned success, but the usage read did not confirm credit consumption.")
                        }
                    }
                } catch {
                    let message = error.localizedDescription
                    do {
                        try await store.appendResetExpiryLog([ResetExpiryEvent(timestamp: Date(), event: "reset_verification_failed",
                            profileID: profile.id, account: profile.displayName, usage: readback, error: message,
                            creditID: creditID, expiresAt: expiry, idempotencyKey: key, outcome: result.outcome)])
                    } catch { throw AutoResetError(message: "\(message) Log write failed: \(error.localizedDescription)") }
                    throw error
                }
                guard let refreshed = readback else { throw CodexClientError.malformedResponse }
                latestUsage = refreshed
                autoReset?.updateUsage(refreshed, profileID: profile.id)
                try await store.appendResetExpiryLog([ResetExpiryEvent(timestamp: Date(), event: "reset_verified",
                    profileID: profile.id, account: profile.displayName, usage: refreshed,
                    creditID: creditID, expiresAt: expiry, idempotencyKey: key, outcome: result.outcome)])
                usageStates[profile.id] = .loaded(refreshed)
                try await store.cacheWeeklyUsage(refreshed, profileID: profile.id)
            }
        } catch {
            stopAutoReset(error)
        }
    }

    private func scheduleResetExpiryCheck() {
        resetExpiryTask?.cancel()
        resetExpiryTask = nil
        guard isBackgroundUsageRefreshEnabled, settings.autoResetEnabled,
              let date = autoReset?.nextCheckpoint(accountIDs: Set(accounts.map(\.id))) else { return }
        let delay = max(0, date.timeIntervalSinceNow)
        resetExpiryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) }
            catch { return }
            guard !Task.isCancelled, let self else { return }
            self.resetExpiryTask = nil
            self.refreshWeeklyUsage()
        }
    }

    private func stopAutoReset(_ error: any Error) {
        resetExpiryTask?.cancel()
        resetExpiryTask = nil
        autoReset = nil
        showError(error)
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

private struct AutoResetError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
