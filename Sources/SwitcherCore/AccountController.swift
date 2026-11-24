import Foundation

private enum UsageRefreshResult: Sendable {
    case success(UUID, WeeklyUsage)
    case failure(UUID, String)
}

@MainActor
open class AccountController {
    public var onWillChange: (@MainActor () -> Void)?
    public var onChange: (@MainActor () -> Void)?

    private var batchDepth = 0
    private var didSendWillChangeInBatch = false
    private var hasChangedInBatch = false

    public private(set) var accounts: [AccountProfile] = [] {
        willSet { if newValue != accounts { prepareForMutation() } }
        didSet { if accounts != oldValue { finishMutation() } }
    }
    public private(set) var activeAccountID: UUID? {
        willSet { if newValue != activeAccountID { prepareForMutation() } }
        didSet { if activeAccountID != oldValue { finishMutation() } }
    }
    public private(set) var usageStates: [UUID: UsageViewState] = [:] {
        willSet { if newValue != usageStates { prepareForMutation() } }
        didSet { if usageStates != oldValue { finishMutation() } }
    }
    public private(set) var subscriptionStates: [UUID: LiveSubscriptionState] = [:] {
        willSet { if newValue != subscriptionStates { prepareForMutation() } }
        didSet { if subscriptionStates != oldValue { finishMutation() } }
    }
    public private(set) var subscriptionSnapshots: [UUID: SubscriptionSnapshot] = [:] {
        willSet { if newValue != subscriptionSnapshots { prepareForMutation() } }
        didSet { if subscriptionSnapshots != oldValue { finishMutation() } }
    }
    public private(set) var settings: AppSettings = .default {
        willSet { if newValue != settings { prepareForMutation() } }
        didSet { if settings != oldValue { finishMutation() } }
    }
    public private(set) var isMutating = false {
        willSet { if newValue != isMutating { prepareForMutation() } }
        didSet { if isMutating != oldValue { finishMutation() } }
    }
    public private(set) var isAddingAccount = false {
        willSet { if newValue != isAddingAccount { prepareForMutation() } }
        didSet { if isAddingAccount != oldValue { finishMutation() } }
    }
    public var visibleError: OperationError? {
        willSet { if newValue != visibleError { prepareForMutation() } }
        didSet { if visibleError != oldValue { finishMutation() } }
    }
    public private(set) var activeIdentityConfirmed = true {
        willSet { if newValue != activeIdentityConfirmed { prepareForMutation() } }
        didSet { if activeIdentityConfirmed != oldValue { finishMutation() } }
    }

    private let store: AccountStore
    private let codex: any AccountClient
    private let subscriptionClient: (any SubscriptionClient)?
    private let switchService: any SwitchServicing
    private var subscriptionAuthAttempts: [UUID: Date] = [:]
    private var hasStarted = false
    private var startTask: Task<Void, Never>?
    private var usageRefreshTask: Task<Void, Never>?
    private var subscriptionRefreshTask: Task<Void, Never>?
    private var usageTeardownTask: Task<Void, Never>?
    private var backgroundPollTask: Task<Void, Never>?
    private var backgroundPollGeneration = UUID()
    private var backgroundUsageRefreshInterval: Duration = .seconds(300)
    private var isBackgroundUsageRefreshEnabled = false
    private var addAccountTask: Task<Void, Never>?
    private var settingsSaveTail: Task<Void, Never>?
    private var autoReset: AutoReset?
    private var resetExpiryTask: Task<Void, Never>?
    private var hasPendingResetCheck = false

    public var resetExpiryLogURL: URL { store.resetExpiryLogURL }

    public init(
        store: AccountStore,
        codex: any AccountClient,
        switchService: any SwitchServicing,
        subscriptionClient: (any SubscriptionClient)? = nil
    ) {
        self.store = store
        self.codex = codex
        self.switchService = switchService
        self.subscriptionClient = subscriptionClient
    }

    private func prepareForMutation() {
        if batchDepth == 0 {
            onWillChange?()
        } else if !didSendWillChangeInBatch {
            didSendWillChangeInBatch = true
            onWillChange?()
        }
    }

    private func finishMutation() {
        if batchDepth == 0 {
            onChange?()
        } else {
            hasChangedInBatch = true
        }
    }

    private func withBatchedUpdates<T>(_ body: () throws -> T) rethrows -> T {
        batchDepth += 1
        defer {
            batchDepth -= 1
            if batchDepth == 0 {
                let changed = hasChangedInBatch
                didSendWillChangeInBatch = false
                hasChangedInBatch = false
                if changed { onChange?() }
            }
        }
        return try body()
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
        if let startTask {
            await startTask.value
            return
        }
        guard !hasStarted else { return }
        hasStarted = true
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performStart()
        }
        startTask = task
        await task.value
        startTask = nil
    }

    private func performStart() async {
        isMutating = true
        defer { isMutating = false }
        do {
            let loadedSettings = try await store.loadSettings()
            let loadedRegistry = try await store.loadRegistry()
            withBatchedUpdates {
                settings = loadedSettings
                apply(loadedRegistry)
            }
            try await syncActiveIdentity()
            await refreshSubscriptionSnapshots()
            do {
                let cache = try await store.loadUsageCache()
                let cachedSubs = subscriptionClient != nil ? try await store.loadLiveSubscriptions() : [:]
                withBatchedUpdates {
                    apply(cache)
                    for (id, value) in cachedSubs {
                        subscriptionStates[id] = .cached(value)
                    }
                }
            } catch {
                reportError(error)
            }
            if settings.autoResetEnabled {
                try await beginAutoReset(event: "resumed")
            }
        } catch {
            reportError(error)
        }
    }

    public func refreshWeeklyUsage() {
        guard !isMutating, usageRefreshTask == nil else { return }
        hasPendingResetCheck = false
        let teardown = usageTeardownTask
        usageRefreshTask = Task { [weak self] in
            guard let self else { return }
            await teardown?.value
            guard !Task.isCancelled else { self.usageRefreshTask = nil; return }
            await self.cancelLiveSubscriptionRefresh()
            await self.performWeeklyUsageRefresh()
            self.usageRefreshTask = nil
            self.completeRefreshCycle()
        }
    }

    public func waitForWeeklyUsageRefresh() async {
        await usageRefreshTask?.value
        await subscriptionRefreshTask?.value
        await usageTeardownTask?.value
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
        let generation = UUID()
        backgroundPollGeneration = generation
        backgroundUsageRefreshInterval = interval
        isBackgroundUsageRefreshEnabled = true
        backgroundPollTask?.cancel()
        backgroundPollTask = nil
        await start()
        guard !Task.isCancelled, isBackgroundUsageRefreshEnabled, backgroundPollGeneration == generation else { return }
        refreshWeeklyUsage()
        backgroundPollTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
                guard !Task.isCancelled, let self,
                      self.isBackgroundUsageRefreshEnabled,
                      self.backgroundPollGeneration == generation else { return }
                self.refreshWeeklyUsage()
            }
        }
    }

    public func stopBackgroundUsageRefresh() {
        isBackgroundUsageRefreshEnabled = false
        backgroundPollGeneration = UUID()
        hasPendingResetCheck = false
        backgroundPollTask?.cancel()
        backgroundPollTask = nil
        resetExpiryTask?.cancel()
        resetExpiryTask = nil
        subscriptionRefreshTask?.cancel()
        let usage = usageRefreshTask
        let subscription = subscriptionRefreshTask
        let previous = usageTeardownTask
        usage?.cancel()
        usageTeardownTask = Task { [weak self, codex] in
            await previous?.value
            await subscription?.value
            await usage?.value
            do { try await codex.stopUsageSessions() }
            catch { self?.reportError(error) }
        }
    }

    private func performWeeklyUsageRefresh() async {
        guard !Task.isCancelled else { return }
        do {
            try await syncActiveIdentity()
        } catch {
            reportError(error)
            for account in accounts {
                await observeResetExpiry(profile: account, usage: nil, error: error.localizedDescription)
            }
            return
        }
        guard !Task.isCancelled else { return }
        await refreshSubscriptionSnapshots()
        var cacheEntries: [UsageCacheEntry] = []
        var observations: [(AccountProfile, WeeklyUsage?, String?)] = []
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
                    cacheEntries.append(UsageCacheEntry(profileID: id, usage: usage, fetchedAt: Date()))
                    observations.append((account, usage, nil))
                case let .failure(id, message):
                    guard let account = accounts.first(where: { $0.id == id }) else { continue }
                    observations.append((account, nil, message))
                    if let cached = usageStates[id]?.displayedUsage {
                        usageStates[id] = .stale(cached, message)
                    } else {
                        usageStates[id] = .unavailable(message)
                    }
                }
            }
        }
        if !Task.isCancelled, !cacheEntries.isEmpty {
            do { try await store.cacheWeeklyUsage(cacheEntries) }
            catch { reportError(error) }
        }
        for (account, usage, message) in observations where !Task.isCancelled {
            await observeResetExpiry(profile: account, usage: usage, error: message)
        }
        guard !Task.isCancelled, let subscriptionClient else { return }
        subscriptionRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshLiveSubscriptions(using: subscriptionClient)
            self.subscriptionRefreshTask = nil
        }
    }

    private func refreshLiveSubscriptions(using client: any SubscriptionClient) async {
        for account in accounts {
            guard !Task.isCancelled else { return }
            do {
                let value = try await readLiveSubscription(account, using: client)
                try Task.checkCancellation()
                guard accounts.contains(where: { $0.id == account.id && $0.accountID == account.accountID }) else { continue }
                subscriptionStates[account.id] = .loaded(value)
                try await store.cacheLiveSubscription(value, profile: account)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
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

    private func readLiveSubscription(_ account: AccountProfile, using client: any SubscriptionClient) async throws -> LiveSubscription {
        func read() async throws -> LiveSubscription {
            let isActive = account.id == activeAccountID
            if let liveClient = client as? LiveSubscriptionClient {
                let parsed = try await store.parsedSubscriptionCredential(profile: account, isActive: isActive)
                return try await liveClient.readSubscription(
                    parsed: parsed,
                    expectedAccountID: account.accountID,
                    expectedEmail: account.email
                )
            }
            let credential = try await store.subscriptionCredential(profile: account, isActive: isActive)
            return try await client.readSubscription(
                credential: credential, expectedAccountID: account.accountID,
                expectedEmail: account.email
            )
        }
        do { return try await read() }
        catch LiveSubscriptionError.unauthenticated {
            guard account.id != activeAccountID,
                  subscriptionAuthAttempts[account.id].map({ Date().timeIntervalSince($0) >= 6 * 3_600 }) ?? true else {
                throw LiveSubscriptionError.unauthenticated
            }
            try Task.checkCancellation()
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
            catch LiveSubscriptionError.invalidCredential { throw LiveSubscriptionError.invalidCredential }
            catch {
                if Task.isCancelled { throw CancellationError() }
                throw LiveSubscriptionError.unauthenticated
            }
        }
    }

    public func switchAccount(to id: UUID) async {
        guard !isMutating, !isAddingAccount else { return }
        isMutating = true
        defer { isMutating = false; refreshWeeklyUsage() }
        do {
            try await cancelUsageRefresh()
            try await syncActiveIdentity()
            guard id != activeAccountID else { return }
            try await switchService.switchAccount(to: id)
            let registry = try await store.loadRegistry()
            withBatchedUpdates {
                apply(registry)
                activeIdentityConfirmed = true
            }
            await refreshSubscriptionSnapshots()
        } catch let error as OperationError {
            if error.stage == .reopenDesktop {
                do {
                    let registry = try await store.loadRegistry()
                    withBatchedUpdates {
                        apply(registry)
                        activeIdentityConfirmed = true
                    }
                } catch {
                    reportError(error)
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
                withBatchedUpdates {
                    if error.stage == .saveCurrentCredential { activeIdentityConfirmed = false }
                    visibleError = error
                }
            }
        } catch {
            reportError(error)
        }
    }

    public func addAccount() {
        guard !isMutating, !isAddingAccount else { return }
        withBatchedUpdates {
            visibleError = nil
            isAddingAccount = true
        }
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
            let registry = try await store.loadRegistry()
            withBatchedUpdates { apply(registry) }
            await refreshSubscriptionSnapshots()
        } catch {
            let loginError = error
            do {
                try await store.discardUnregisteredProfile(id: id)
            } catch {
                reportError(NSError(domain: "CodexAccountSwitcher.Login", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "\(loginError.localizedDescription) Removing the incomplete profile also failed: \(error.localizedDescription)",
                ]))
                return
            }
            if !(loginError is CancellationError) { reportError(loginError) }
        }
    }

    public func registerCurrentAccount() async {
        guard !isMutating, !isAddingAccount else { return }
        isMutating = true
        defer { isMutating = false; refreshWeeklyUsage() }
        do {
            try await cancelUsageRefresh()
            guard await store.activeCredentialExists() else { throw AccountStoreError.activeCredentialMissing }
            try await syncActiveIdentity()
            await refreshSubscriptionSnapshots()
            visibleError = nil
        } catch { reportError(error) }
    }

    public func removeAccount(id: UUID) async {
        guard !isMutating, !isAddingAccount else { return }
        isMutating = true
        defer { isMutating = false; refreshWeeklyUsage() }
        do {
            try await cancelUsageRefresh()
            try await syncActiveIdentity()
            let home = await store.profileHome(id: id)
            try await store.removeAccount(id: id)
            try await codex.forgetUsageSession(profileHome: home)
            let registry = try await store.loadRegistry()
            withBatchedUpdates {
                apply(registry)
            }
        } catch {
            reportError(error)
        }
    }

    public func moveAccount(id: UUID, to targetID: UUID) async {
        guard !isMutating, !isAddingAccount else { return }
        isMutating = true
        defer { isMutating = false; completePendingResetCheckIfNeeded() }
        do {
            let registry = try await store.moveAccount(id: id, to: targetID)
            withBatchedUpdates {
                apply(registry)
                visibleError = nil
            }
        } catch {
            reportError(error)
        }
    }

    public func setLanguage(_ language: AppLanguage) async {
        await enqueueSettingsUpdate { $0.language = language }
    }

    public func setShowsMenuBarPercentage(_ enabled: Bool) async {
        await enqueueSettingsUpdate { $0.showsMenuBarPercentage = enabled }
    }

    public func setShowsFiveHourUsage(_ enabled: Bool) async {
        await enqueueSettingsUpdate { $0.showsFiveHourUsage = enabled }
    }

    public func setStatusBarUsageWindow(_ window: StatusBarUsageWindow) async {
        await enqueueSettingsUpdate { $0.statusBarUsageWindow = window }
    }

    public func setAutoResetEnabled(_ enabled: Bool) async {
        await enqueueSettingsUpdate({ $0.autoResetEnabled = enabled }) { [weak self] updated in
            guard let self else { return }
            self.resetExpiryTask?.cancel()
            self.resetExpiryTask = nil
            self.hasPendingResetCheck = false
            self.autoReset = nil
            if updated.autoResetEnabled {
                try await self.beginAutoReset(event: "enabled")
                self.refreshWeeklyUsage()
            } else {
                try await self.store.appendResetExpiryLog([ResetExpiryEvent(timestamp: Date(), event: "disabled")])
            }
        }
    }

    private func enqueueSettingsUpdate(
        _ mutate: @escaping @Sendable (inout AppSettings) -> Void,
        afterSave: (@MainActor (AppSettings) async throws -> Void)? = nil
    ) async {
        let previous = settingsSaveTail
        let task = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                let updated = try await self.store.updateSettings(mutate)
                self.settings = updated
                try await afterSave?(updated)
            } catch {
                self.reportError(error)
            }
        }
        settingsSaveTail = task
        await task.value
    }

    private func beginAutoReset(event: String) async throws {
        let history = try await store.loadResetExpiryLog()
        guard settings.autoResetEnabled else { return }
        try await store.appendResetExpiryLog([ResetExpiryEvent(timestamp: Date(), event: event)])
        guard settings.autoResetEnabled else { return }
        autoReset = AutoReset(history: history)
    }

    private func observeResetExpiry(profile: AccountProfile, usage: WeeklyUsage?, error: String? = nil) async {
        guard settings.autoResetEnabled else { return }
        if autoReset == nil {
            autoReset = AutoReset(history: (try? await store.loadResetExpiryLog()) ?? [])
        }
        guard var tracker = autoReset else { return }
        let events = tracker.observe(profile: profile, usage: usage, error: error, at: Date())
        autoReset = tracker
        do {
            try await store.appendResetExpiryLog(events)
            var latestUsage = usage
            for checkpoint in events where checkpoint.decision == "attempt" {
                guard settings.autoResetEnabled, autoReset?.generation == tracker.generation,
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
                // Persist intent before network mutation so interrupted attempts are never replayed.
                try await store.appendResetExpiryLog([attempt])
                autoReset?.recordAttempt(attempt)
                var result = ResetExpiryEvent(resetAttempted: true, timestamp: Date(), event: "reset_result",
                    profileID: profile.id, account: profile.displayName, creditID: creditID,
                    expiresAt: expiry, checkpointMinutes: checkpoint.checkpointMinutes, idempotencyKey: key)
                let home = await store.profileHome(id: profile.id)
                do {
                    try Task.checkCancellation()
                    guard settings.autoResetEnabled, autoReset?.generation == tracker.generation else { return }
                    result.outcome = try await codex.consumeResetCredit(profileHome: home, creditID: creditID, idempotencyKey: key)
                } catch {
                    result.timestamp = Date()
                    result.error = error.localizedDescription
                    try? await store.appendResetExpiryLog([result])
                    reportError(AutoResetError(message: "\(profile.displayName) · \(creditID): \(error.localizedDescription)"))
                    continue
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
                    latestUsage = refreshed
                    autoReset?.updateUsage(refreshed, profileID: profile.id)
                    try await store.appendResetExpiryLog([ResetExpiryEvent(timestamp: Date(), event: "reset_verified",
                        profileID: profile.id, account: profile.displayName, usage: refreshed,
                        creditID: creditID, expiresAt: expiry, idempotencyKey: key, outcome: result.outcome)])
                    usageStates[profile.id] = .loaded(refreshed)
                    try await store.cacheWeeklyUsage(refreshed, profileID: profile.id)
                } catch {
                    let message = error.localizedDescription
                    try? await store.appendResetExpiryLog([ResetExpiryEvent(timestamp: Date(), event: "reset_verification_failed",
                        profileID: profile.id, account: profile.displayName, usage: readback, error: message,
                        creditID: creditID, expiresAt: expiry, idempotencyKey: key, outcome: result.outcome)])
                    reportError(error)
                }
            }
        } catch {
            reportError(error)
        }
    }

    private func completeRefreshCycle() {
        let pendingReset = hasPendingResetCheck
        hasPendingResetCheck = false
        guard isBackgroundUsageRefreshEnabled, settings.autoResetEnabled else { return }
        if pendingReset,
           let next = autoReset?.nextCheckpoint(accountIDs: Set(accounts.map(\.id))),
           next <= Date() {
            refreshWeeklyUsage()
            return
        }
        scheduleResetExpiryCheck()
    }

    private func completePendingResetCheckIfNeeded() {
        guard hasPendingResetCheck else { return }
        completeRefreshCycle()
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
            guard self.isBackgroundUsageRefreshEnabled, self.settings.autoResetEnabled else { return }
            if self.isMutating || self.usageRefreshTask != nil {
                self.hasPendingResetCheck = true
            } else {
                self.refreshWeeklyUsage()
            }
        }
    }

    public func dismissError() {
        visibleError = nil
    }

    private func cancelUsageRefresh() async throws {
        usageRefreshTask?.cancel()
        await cancelLiveSubscriptionRefresh()
        await usageRefreshTask?.value
        try await codex.stopUsageSessions()
    }

    private func cancelLiveSubscriptionRefresh() async {
        subscriptionRefreshTask?.cancel()
        await subscriptionRefreshTask?.value
    }

    private func apply(_ registry: AccountRegistry) {
        let validIDs = Set(registry.accounts.map(\.id))
        accounts = registry.accounts
        activeAccountID = registry.activeAccountID
        usageStates = usageStates.filter { validIDs.contains($0.key) }
        subscriptionStates = subscriptionStates.filter { validIDs.contains($0.key) }
        subscriptionSnapshots = subscriptionSnapshots.filter { validIDs.contains($0.key) }
    }

    private func apply(_ cache: UsageCache) {
        let validAccountIDs = Set(accounts.map(\.id))
        var updated = usageStates
        for entry in cache.entries where validAccountIDs.contains(entry.profileID) {
            updated[entry.profileID] = .loaded(entry.usage)
        }
        usageStates = updated
    }

    private func syncActiveIdentity() async throws {
        do {
            let registry = try await store.syncActiveCredential(beforeUpdatingProfile: { [codex] home in
                try await codex.stopUsageSession(profileHome: home)
            })
            withBatchedUpdates {
                apply(registry)
                activeIdentityConfirmed = activeAccountID != nil || accounts.isEmpty
            }
        } catch {
            withBatchedUpdates {
                activeAccountID = nil
                activeIdentityConfirmed = false
            }
            throw error
        }
    }

    public func reportError(_ error: any Error) {
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
