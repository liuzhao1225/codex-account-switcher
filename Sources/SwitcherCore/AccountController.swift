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
    public private(set) var pendingSwitch: SwitchConfirmation? { didSet { onChange?() } }
    public private(set) var managedProviders: [ManagedProvider] = [] { didSet { onChange?() } }
    public private(set) var providerEditor: ProviderEditorState? { didSet { onChange?() } }
    private var editorAPIKey: String?
    private var providerFetchTask: Task<[ProviderModel], any Error>?
    private let modelDiscovery: any ProviderModelDiscovering

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
        providerSwitchService: any ProviderSwitchServicing,
        modelDiscovery: any ProviderModelDiscovering = ProviderModelDiscovery()
    ) {
        self.store = store
        self.codex = codex
        self.switchService = switchService
        self.configuration = configuration
        self.providerSwitchService = providerSwitchService
        self.modelDiscovery = modelDiscovery
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
        guard !isMutating else { return }
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

    public func refresh() async {
        await start()
        refreshWeeklyUsage()
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
        guard !isMutating, !isAddingAccount else { return }
        isMutating = true
        defer { isMutating = false }
        guard await refreshProviderConfiguration(), let authentication = activeAuthentication else { return }
        do {
            try await store.removeAccount(id: id, activeAuthentication: authentication)
            apply(try await store.loadRegistry())
            usageStates[id] = nil
            await confirmActiveIdentity()
            visibleError = nil
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
        guard activeAuthentication != nil else {
            activeIdentityConfirmed = false
            return
        }
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

    public func isCredentialOwner(_ account: AccountProfile) -> Bool {
        activeAuthentication?.identity?.matches(account) == true
    }

    public func canRemoveAccount(_ account: AccountProfile) -> Bool {
        !isMutating && !isAddingAccount && activeAuthentication != nil && !isCredentialOwner(account)
    }

    public func prepareAccountSwitch(to id: UUID) async {
        guard !isMutating, !isAddingAccount else { return }
        isMutating = true
        defer { isMutating = false }
        pendingSwitch = nil
        guard await refreshProviderConfiguration() else { return }
        await confirmActiveIdentity()
        guard let account = accounts.first(where: { $0.id == id }) else {
            showError(AccountStoreError.profileNotFound)
            return
        }
        guard !isAccountActive(account) else { return }
        pendingSwitch = accountConfirmation(account)
    }

    public func prepareProviderSwitch(to id: String) async {
        guard settings.enablesProviderSwitching, !isMutating, !isAddingAccount else { return }
        isMutating = true
        defer { isMutating = false }
        pendingSwitch = nil
        guard await refreshProviderConfiguration() else { return }
        guard let provider = providers.first(where: { $0.id == id }) else {
            showError(ProviderConfigurationError.providerNotConfigured(id))
            return
        }
        guard !isProviderActive(provider) else { return }
        pendingSwitch = providerConfirmation(provider)
    }

    public func cancelSwitch() {
        guard !isMutating else { return }
        pendingSwitch = nil
    }

    public func confirmSwitch() async {
        guard !isMutating, !isAddingAccount, let confirmed = pendingSwitch else { return }
        // Refresh the prepared action before accepting it: an external login can
        // change the credential-retention notice while the confirmation is open.
        if let id = confirmed.accountID {
            await prepareAccountSwitch(to: id)
            guard pendingSwitch == confirmed else { return }
            pendingSwitch = nil
            await switchAccount(to: id)
        } else if let id = confirmed.providerID {
            await prepareProviderSwitch(to: id)
            guard pendingSwitch == confirmed,
                  settings.enablesProviderSwitching,
                  let provider = providers.first(where: { $0.id == id }) else { return }
            pendingSwitch = nil
            await switchProvider(to: provider)
        }
    }

    private func accountConfirmation(_ account: AccountProfile) -> SwitchConfirmation {
        var paragraphs = [text("switch_body")]
        if activeProviderID != CodexConfigurationClient.openAIProviderID || activeAuthentication == .apiKey {
            paragraphs.append(text(managedProviders.isEmpty ? "return_account_model_notice" : "return_saved_model_notice"))
        }
        if activeAuthentication == .apiKey { paragraphs.append(text("native_api_storage_notice")) }
        return SwitchConfirmation(accountID: account.id, providerID: nil,
            title: format("switch_title", account.displayName), message: paragraphs.joined(separator: "\n\n"),
            confirmTitle: text("switch_account"))
    }

    private func providerConfirmation(_ provider: ProviderProfile) -> SwitchConfirmation {
        let managed = managedProviders.first { $0.id == provider.id }
        var paragraphs = [text(managed == nil ? "switch_provider_body" : "switch_managed_provider_body")]
        if let managed { paragraphs.append(text("provider_default_model") + ": " + managed.defaultModelID) }
        if provider.id == CodexConfigurationClient.openAIProviderID {
            paragraphs.append(text("native_api_storage_notice"))
        }
        return SwitchConfirmation(accountID: nil, providerID: provider.id,
            title: format("switch_provider_title", provider.displayName), message: paragraphs.joined(separator: "\n\n"),
            confirmTitle: text("switch_provider"))
    }

    public func providerSubtitle(_ provider: ProviderProfile) -> String {
        managedProviders.first(where: { $0.id == provider.id })?.defaultModelID
            ?? text(provider.id == CodexConfigurationClient.openAIProviderID ? "native_api_login" : "configured_provider")
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
        guard !isMutating, !isAddingAccount else { return }
        var updated = settings
        updated.enablesProviderSwitching = enabled
        do {
            try await store.saveSettings(updated)
            settings = updated
            if !enabled, pendingSwitch?.providerID != nil { pendingSwitch = nil }
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
            if let manager = configuration as? any ProviderManaging { managedProviders = try await manager.savedProviders() }
            return true
        } catch {
            activeAuthentication = nil
            activeIdentityConfirmed = false
            showError(error)
            return false
        }
    }

}

extension AccountController {
    public func openProviderEditor(id: String? = nil) async {
        guard !isMutating, !isAddingAccount else { return }
        guard let manager = configuration as? any ProviderManaging else {
            showError(ProviderSetupError.unsupportedFormat)
            return
        }
        do {
            managedProviders = try await manager.savedProviders()
            let existing = id.flatMap { requested in managedProviders.first { $0.id == requested } }
            if id != nil, existing == nil { throw ProviderSetupError.invalidResponse }
            providerFetchTask?.cancel()
            editorAPIKey = nil
            providerEditor = ProviderEditorState(provider: existing)
        } catch { showError(error) }
    }

    public func closeProviderEditor() {
        guard !isMutating else { return }
        providerFetchTask?.cancel()
        providerFetchTask = nil
        editorAPIKey = nil
        providerEditor = nil
    }

    private func applyConnectionInput(_ input: ProviderConnectionInput) throws {
        guard var editor = providerEditor else { return }
        let base = try ProviderModelDiscovery.endpoint(input.baseURL).deletingLastPathComponent().absoluteString
        let key = input.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newKey = key.flatMap { $0.isEmpty ? nil : $0 }
        if editor.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) != base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            || editor.apiFormat != input.apiFormat || (newKey != editorAPIKey) {
            editor.models = []
            editor.defaultModelID = nil
        }
        editor.displayName = input.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        editor.baseURL = base
        editor.apiFormat = input.apiFormat
        editorAPIKey = newKey
        editor.error = nil
        editor.didSave = false
        editor.updateVisibleModels()
        providerEditor = editor
    }

    public func fetchProviderModels(_ input: ProviderConnectionInput) async {
        guard let original = providerEditor, !original.isBusy, !isMutating else { return }
        do {
            try applyConnectionInput(input)
            guard let editor = providerEditor else { return }
            providerEditor?.isBusy = true
            defer { if providerEditor?.id == original.id { providerEditor?.isBusy = false } }
            let key: String
            if let editorAPIKey { key = editorAPIKey }
            else if editor.hasStoredKey, let manager = configuration as? any ProviderManaging { key = try await manager.storedKey(providerID: editor.id) }
            else { throw ProviderSetupError.invalidKey }
            let discovery = modelDiscovery
            let task = Task { try await discovery.fetchModels(baseURL: editor.baseURL, apiKey: key, format: editor.apiFormat) }
            providerFetchTask = task
            let fetched = try await task.value
            guard providerEditor?.id == original.id else { return }
            // Preserve selection, effort and custom order for IDs that still exist.
            let byID = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var merged = editor.models.compactMap { previous -> ProviderModel? in
                guard var fresh = byID[previous.id] else { return nil }
                fresh.isEnabled = previous.isEnabled
                fresh.reasoningEffort = previous.reasoningEffort
                return fresh
            }
            let retained = Set(merged.map(\.id))
            merged += fetched.filter { !retained.contains($0.id) }
            providerEditor?.models = merged
            if !merged.contains(where: { $0.id == editor.defaultModelID && $0.isEnabled }) { providerEditor?.defaultModelID = nil }
            providerEditor?.updateVisibleModels()
        } catch is CancellationError {
            if providerEditor?.id == original.id { providerEditor?.error = text("provider_fetch_cancelled") }
        } catch { if providerEditor?.id == original.id { providerEditor?.error = providerError(error) } }
    }

    public func searchProviderModels(_ query: String) {
        providerEditor?.query = query
        providerEditor?.updateVisibleModels()
    }

    public func sortProviderModels(_ order: ProviderModelSort) {
        providerEditor?.sort = order
        providerEditor?.updateVisibleModels()
    }

    public func enableProviderModel(id: String, enabled: Bool) {
        guard var editor = providerEditor, !editor.isBusy,
              let index = editor.models.firstIndex(where: { $0.id == id }) else { return }
        editor.models[index].isEnabled = enabled
        if !enabled, editor.defaultModelID == id { editor.defaultModelID = nil }
        editor.error = nil
        providerEditor = editor
    }

    public func chooseProviderDefaultModel(id: String) {
        guard var editor = providerEditor, !editor.isBusy,
              let index = editor.models.firstIndex(where: { $0.id == id }) else { return }
        editor.models[index].isEnabled = true
        editor.defaultModelID = id
        editor.error = nil
        providerEditor = editor
    }

    public func setProviderReasoning(_ effort: String) {
        guard var editor = providerEditor, !editor.isBusy,
              let index = editor.models.firstIndex(where: { $0.id == editor.defaultModelID }) else { return }
        let value = effort.trimmingCharacters(in: .whitespacesAndNewlines)
        editor.models[index].reasoningEffort = value.isEmpty ? nil : value
        providerEditor = editor
    }

    public func moveProviderModel(id: String, offset: Int) {
        guard var editor = providerEditor, !editor.isBusy, !isMutating, [-1, 1].contains(offset),
              let visibleIndex = editor.visibleModelIDs.firstIndex(of: id),
              editor.visibleModelIDs.indices.contains(visibleIndex + offset) else { return }
        let neighbor = editor.visibleModelIDs[visibleIndex + offset]
        // Start custom ordering from the displayed sort, then move between visible matches.
        var unfiltered = editor
        unfiltered.query = ""
        unfiltered.updateVisibleModels()
        let byID = Dictionary(uniqueKeysWithValues: editor.models.map { ($0.id, $0) })
        editor.models = unfiltered.visibleModelIDs.compactMap { byID[$0] }
        guard let index = editor.models.firstIndex(where: { $0.id == id }),
              let destination = editor.models.firstIndex(where: { $0.id == neighbor }) else { return }
        editor.models.swapAt(index, destination)
        editor.sort = .custom
        editor.updateVisibleModels()
        providerEditor = editor
    }

    public func addProviderModel(id raw: String, connection: ProviderConnectionInput? = nil) {
        if let connection {
            do { try applyConnectionInput(connection) }
            catch { providerEditor?.error = providerError(error); return }
        }
        guard var editor = providerEditor, !editor.isBusy else { return }
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !editor.models.contains(where: { $0.id == id }) else { return }
        editor.models.append(ProviderModel(id: id, isEnabled: true))
        editor.query = ""
        editor.updateVisibleModels()
        providerEditor = editor
    }

    public func saveProvider(_ input: ProviderConnectionInput) async {
        guard let editor = providerEditor, !editor.isBusy, !isMutating, !isAddingAccount,
              let manager = configuration as? any ProviderManaging else { return }
        isMutating = true
        defer { isMutating = false; providerEditor?.isBusy = false }
        do {
            try applyConnectionInput(input)
            guard let state = providerEditor, let defaultID = state.defaultModelID,
                  state.models.contains(where: { $0.id == defaultID && $0.isEnabled }) else { throw ProviderSetupError.selectDefault }
            providerEditor?.isBusy = true
            try await manager.save(ManagedProvider(id: state.id, displayName: state.displayName, baseURL: state.baseURL,
                apiFormat: state.apiFormat, models: state.models, defaultModelID: defaultID, sort: state.sort), apiKey: editorAPIKey)
            var updated = settings
            updated.enablesProviderSwitching = true
            try await store.saveSettings(updated)
            settings = updated
            guard await refreshProviderConfiguration() else {
                providerEditor?.error = visibleError.map { $0.messageKey.map(text) ?? $0.message }
                return
            }
            providerEditor?.didSave = true
            editorAPIKey = nil
        } catch { providerEditor?.error = providerError(error) }
    }

    private func providerError(_ error: any Error) -> String {
        // HTTP response bodies and submitted keys are never included in UI errors.
        let message = (error as? ProviderSetupError)?.errorDescription ?? error.localizedDescription
        let safe = editorAPIKey.map { message.replacingOccurrences(of: $0, with: "••••") } ?? message
        return text(safe)
    }
}
