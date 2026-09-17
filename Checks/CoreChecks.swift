import Darwin
import Combine
import Foundation
import SwitcherCore
import ServiceManagement

enum CheckFailure: Error {
    case failed(String)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure.failed(message) }
}

private func permissions(_ url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

private func lineCount(at url: URL) -> Int {
    guard let data = try? Data(contentsOf: url) else { return 0 }
    return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).count
}

private func waitForLineCount(at url: URL, atLeast expected: Int) async throws {
    for _ in 0..<250 {
        if lineCount(at: url) >= expected { return }
        try await Task.sleep(for: .milliseconds(20))
    }
    throw CheckFailure.failed(
        "timed out waiting for \(expected) refresh requests; observed \(lineCount(at: url))"
    )
}

private actor Recorder {
    private var values: [SwitchStage] = []
    func append(_ value: SwitchStage) { values.append(value) }
    func snapshot() -> [SwitchStage] { values }
}

private struct FakeDesktop: DesktopControlling {
    let recorder: Recorder
    func closeDesktop() async throws { await recorder.append(.closeDesktop) }
    func reopenDesktop() async throws { await recorder.append(.reopenDesktop) }
}

private actor FakeStore: AccountStoring {
    func clearActiveCredential() {}
    func hasOpenAIAPICredential() -> Bool { false }
    func saveOpenAIAPICredential() throws { throw NativeAPIAuthenticationError.savedLoginUnavailable }
    func activateOpenAIAPICredential() throws { throw NativeAPIAuthenticationError.savedLoginUnavailable }
    let recorder: Recorder
    let original: AccountProfile
    let target: AccountProfile

    init(recorder: Recorder, original: AccountProfile, target: AccountProfile) {
        self.recorder = recorder
        self.original = original
        self.target = target
    }

    func loadRegistry() -> AccountRegistry {
        AccountRegistry(activeAccountID: original.id, accounts: [original, target])
    }
    func profile(id: UUID) -> AccountProfile { target }
    func profileHome(id: UUID) -> URL { URL(fileURLWithPath: "/tmp/target") }
    func activeCodexHome() -> URL { URL(fileURLWithPath: "/tmp/active") }
    func activeCredentialExists() -> Bool { true }
    func createProfileDirectory(id: UUID) -> URL { URL(fileURLWithPath: "/tmp/target") }
    func importCurrentProfile(_ profile: AccountProfile) {}
    func addProfile(_ profile: AccountProfile) {}
    func removeAccount(id: UUID) {}
    func saveCurrentCredential() async { await recorder.append(.saveCurrentCredential) }
    func activateTargetCredential(id: UUID) async { await recorder.append(.activateTargetCredential) }
    func restoreActiveCredential(id: UUID) {}
    func commitActiveAccountID(_ id: UUID) async { await recorder.append(.commitActiveAccountID) }
}

private actor FakeCodex: CodexIdentityReading {
    let recorder: Recorder
    let original: AccountProfile
    let target: AccountProfile
    let configuration: FakeProviderConfiguration
    let failsTargetIdentity: Bool
    private var hasVerifiedOriginal = false
    init(
        recorder: Recorder,
        original: AccountProfile,
        target: AccountProfile,
        configuration: FakeProviderConfiguration,
        failsTargetIdentity: Bool = false
    ) {
        self.recorder = recorder
        self.original = original
        self.target = target
        self.configuration = configuration
        self.failsTargetIdentity = failsTargetIdentity
    }

    func readAuthentication(profileHome: URL) async throws -> CodexAuthenticationState {
        .chatGPT(try await readIdentity(profileHome: profileHome))
    }
    func readIdentity(profileHome: URL) async throws -> AccountIdentity {
        guard await configuration.activeProviderID() == CodexConfigurationClient.openAIProviderID else {
            throw CodexClientError.identityUnavailable
        }
        if !hasVerifiedOriginal {
            hasVerifiedOriginal = true
            return AccountIdentity(accountID: original.accountID, email: original.email)
        }
        await recorder.append(.verifyTargetIdentity)
        if failsTargetIdentity { throw CodexClientError.identityUnavailable }
        return AccountIdentity(accountID: target.accountID, email: target.email)
    }
}

private actor FakeProviderConfiguration: ProviderConfigurationServicing {
    let recorder: Recorder?
    private var providerID: String

    init(providerID: String = "openai", recorder: Recorder? = nil) {
        self.providerID = providerID
        self.recorder = recorder
    }

    func readConfiguration(codexHome: URL) -> ProviderConfigurationSnapshot {
        ProviderConfigurationSnapshot(
            activeProviderID: providerID,
            providers: [ProviderProfile(id: "azure", displayName: "Azure OpenAI")]
        )
    }

    func activateProvider(id: String, codexHome: URL) async {
        await recorder?.append(.activateTargetProvider)
        providerID = id
    }

    func activeProviderID() -> String { providerID }
}

private actor FakeProviderSwitchService: ProviderSwitchServicing {
    private(set) var calls = 0
    func switchProvider(to providerID: String) async throws { calls += 1 }
}

private struct InjectedReopenFailure: LocalizedError {
    var errorDescription: String? { "Injected Desktop reopen failure" }
}

private struct ReopenFailureSwitchService: SwitchServicing {
    let store: AccountStore

    func switchAccount(to targetID: UUID) async throws {
        try await store.commitActiveAccountID(targetID)
        throw OperationError.stage(.reopenDesktop, InjectedReopenFailure())
    }
}

private func createExecutable(at url: URL, body: String) throws {
    try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
}

@main
struct CoreChecks {
    @MainActor static func main() async throws {
        try require(
            LaunchAtLoginState(status: .notRegistered) == .disabled,
            "not-registered launch-at-login state"
        )
        try require(
            LaunchAtLoginState(status: .enabled) == .enabled,
            "enabled launch-at-login state"
        )
        try require(
            LaunchAtLoginState(status: .requiresApproval) == .requiresApproval,
            "approval-required launch-at-login state"
        )
        try require(
            LaunchAtLoginState(status: .notFound) == .unavailable,
            "unavailable launch-at-login state"
        )

        let weekly = try WeeklyUsageNormalizer.normalize([
            RateLimitWindow(usedPercent: 90, windowDurationMins: 300, resetsAt: 1),
            RateLimitWindow(usedPercent: 58, windowDurationMins: 10_080, resetsAt: 1_750_000_000),
        ])
        try require(weekly.remainingPercent == 42, "weekly remaining percent")
        try require(weekly.fiveHourRemainingPercent == 10, "five-hour remaining percent")
        let nonExactFiveHour = try WeeklyUsageNormalizer.normalize([
            RateLimitWindow(usedPercent: 10, windowDurationMins: 240, resetsAt: 1),
            RateLimitWindow(usedPercent: 20, windowDurationMins: 360, resetsAt: 1),
            RateLimitWindow(usedPercent: 58, windowDurationMins: 10_080, resetsAt: 1_750_000_000),
        ])
        try require(
            nonExactFiveHour.fiveHourRemainingPercent == nil,
            "four-hour and six-hour windows are not five-hour usage"
        )
        try require(
            L10n.string("show_five_hour_usage", language: .english) == "Show 5-hour Usage",
            "English five-hour setting label"
        )
        try require(
            L10n.string("show_five_hour_usage", language: .simplifiedChinese) == "显示 5 小时用量",
            "Simplified Chinese five-hour setting label"
        )

        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(path: "switcher-check-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: root) }
        let activeHome = root.appending(path: "active")
        let support = root.appending(path: "support")
        try fileManager.createDirectory(at: activeHome, withIntermediateDirectories: true)
        try Data("first".utf8).write(to: activeHome.appending(path: "auth.json"))

        let store = AccountStore(baseURL: support, activeHomeURL: activeHome)
        let first = AccountProfile(
            id: UUID(), displayName: "First", email: "first@example.com",
            accountID: "first", createdAt: Date(), lastUsedAt: nil
        )
        try await store.importCurrentProfile(first)
        let firstCredential = await store.profileHome(id: first.id).appending(path: "auth.json")
        let firstPermissions = try permissions(firstCredential)
        try require(firstPermissions == 0o600, "imported credential permissions")

        let second = AccountProfile(
            id: UUID(), displayName: "Second", email: "second@example.com",
            accountID: "second", createdAt: Date(), lastUsedAt: nil
        )
        let secondHome = try await store.createProfileDirectory(id: second.id)
        let secondBytes = Data("second".utf8)
        try secondBytes.write(to: secondHome.appending(path: "auth.json"))
        try await store.addProfile(second)
        let third = AccountProfile(
            id: UUID(), displayName: "Third", email: "third@example.com",
            accountID: "third", createdAt: Date(), lastUsedAt: nil
        )
        let thirdHome = try await store.createProfileDirectory(id: third.id)
        try Data("third".utf8).write(to: thirdHome.appending(path: "auth.json"))
        try await store.addProfile(third)
        try await store.activateTargetCredential(id: second.id)
        let activeCredential = activeHome.appending(path: "auth.json")
        let activeBytes = try Data(contentsOf: activeCredential)
        let activePermissions = try permissions(activeCredential)
        try require(activeBytes == secondBytes, "credential activation")
        try require(activePermissions == 0o600, "active credential permissions")

        let cachedWeekly = WeeklyUsage(
            remainingPercent: 73,
            resetsAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
        let cachedAt = Date(timeIntervalSince1970: 1_749_000_000)
        try await store.cacheWeeklyUsage(cachedWeekly, profileID: first.id, fetchedAt: cachedAt)
        let persistedCache = try await store.loadUsageCache()
        try require(
            persistedCache.entries == [
                UsageCacheEntry(profileID: first.id, usage: cachedWeekly, fetchedAt: cachedAt),
            ],
            "weekly usage cache persistence"
        )
        let usageCachePermissions = try permissions(support.appending(path: "usage-cache.json"))
        try require(usageCachePermissions == 0o600, "weekly usage cache permissions")

        let legacyCacheData = Data("""
        {"entries":[{"profileID":"\(first.id.uuidString)","usage":{"remainingPercent":73,"resetsAt":"2025-06-15T15:06:40Z"},"fetchedAt":"2025-06-04T01:20:00Z"}]}
        """.utf8)
        try legacyCacheData.write(to: support.appending(path: "usage-cache.json"))
        let legacyCacheStore = AccountStore(baseURL: support, activeHomeURL: activeHome)
        let legacyCache = try await legacyCacheStore.loadUsageCache()
        try require(
            legacyCache.entries.first?.usage.fiveHourRemainingPercent == nil,
            "weekly-only usage cache compatibility"
        )

        let settingsURL = support.appending(path: "settings.json")
        try Data(#"{"language":"english"}"#.utf8).write(to: settingsURL)
        let legacySettings = try await store.loadSettings()
        try require(legacySettings.language == .english, "legacy settings language")
        try require(!AppSettings.default.enablesProviderSwitching, "providers are opt-in")
        try require(!legacySettings.enablesProviderSwitching, "upgrades do not enable providers")
        try require(
            legacySettings.showsMenuBarPercentage,
            "legacy settings enable menu bar percentage"
        )
        try require(
            !legacySettings.showsFiveHourUsage,
            "legacy settings hide five-hour usage"
        )
        let hiddenPercentageSettings = AppSettings(
            language: .simplifiedChinese,
            showsMenuBarPercentage: false,
            showsFiveHourUsage: true,
            enablesProviderSwitching: true
        )
        try await store.saveSettings(hiddenPercentageSettings)
        let reloadedSettingsStore = AccountStore(baseURL: support, activeHomeURL: activeHome)
        let reloadedSettings = try await reloadedSettingsStore.loadSettings()
        try require(
            reloadedSettings == hiddenPercentageSettings,
            "menu bar percentage setting persistence"
        )
        let settingsPermissions = try permissions(settingsURL)
        try require(settingsPermissions == 0o600, "settings permissions")

        try fileManager.removeItem(at: activeCredential)
        try fileManager.createDirectory(at: activeCredential, withIntermediateDirectories: false)
        do {
            try await store.activateTargetCredential(id: second.id)
            throw CheckFailure.failed("credential rename failure")
        } catch is POSIXError {
            let names = try fileManager.contentsOfDirectory(atPath: activeHome.path)
            try require(
                !names.contains(where: { $0.hasPrefix("auth.json.switcher-") }),
                "failed credential write cleanup"
            )
        }
        try fileManager.removeItem(at: activeCredential)
        try secondBytes.write(to: activeCredential)

        let recorder = Recorder()
        let providerConfiguration = FakeProviderConfiguration(providerID: "azure", recorder: recorder)
        let switcher = SwitchService(
            desktop: FakeDesktop(recorder: recorder),
            store: FakeStore(recorder: recorder, original: first, target: second),
            codex: FakeCodex(
                recorder: recorder,
                original: first,
                target: second,
                configuration: providerConfiguration
            ),
            configuration: providerConfiguration
        )
        try await switcher.switchAccount(to: second.id)
        let recordedStages = await recorder.snapshot()
        try require(recordedStages == SwitchStage.allCases, "switch stage order")

        let failureRecorder = Recorder()
        let failureConfiguration = FakeProviderConfiguration(
            providerID: "azure",
            recorder: failureRecorder
        )
        let failureStore = FakeStore(recorder: failureRecorder, original: first, target: second)
        let failureSwitcher = SwitchService(
            desktop: FakeDesktop(recorder: failureRecorder),
            store: failureStore,
            codex: FakeCodex(
                recorder: failureRecorder,
                original: first,
                target: second,
                configuration: failureConfiguration,
                failsTargetIdentity: true
            ),
            configuration: failureConfiguration
        )
        do {
            try await failureSwitcher.switchAccount(to: second.id)
            throw CheckFailure.failed("target identity failure must stop the switch")
        } catch let error as OperationError {
            try require(error.stage == .verifyTargetIdentity, "target identity failure stage")
        }
        let failureStages = await failureRecorder.snapshot()
        try require(failureStages.last == .reopenDesktop, "post-close switch failure reopens Desktop")
        let restoredProviderID = await failureConfiguration.activeProviderID()
        try require(restoredProviderID == "azure", "post-close switch failure restores provider")

        let providerSwitcher = ProviderSwitchService(
            desktop: FakeDesktop(recorder: recorder),
            store: FakeStore(recorder: recorder, original: first, target: second),
            codex: switcher.codex, configuration: providerConfiguration
        )
        try await providerSwitcher.switchProvider(to: "azure")
        let providerSwitchStages = Array((await recorder.snapshot()).suffix(3))
        try require(
            providerSwitchStages == [.closeDesktop, .activateTargetProvider, .reopenDesktop],
            "provider switch stage order"
        )

        let fakeCodex = root.appending(path: "fake-codex")
        try createExecutable(at: fakeCodex, body: """
        state=0
        while IFS= read -r line; do
          case "$line" in
            *initialized*) state=2 ;;
            *initialize*) state=1; printf '%s\\n' '{"id":0,"result":{}}' ;;
            *rateLimits*)
              test "$state" -eq 2 || exit 12
              i=0
              while [ "$i" -lt 10000 ]; do
                printf '%s\\n' 'diagnostic output' >&2
                i=$((i + 1))
              done
              printf '%s\\n' '{"id":1,"result":{"rateLimits":{"primary":{"usedPercent":80,"windowDurationMins":300,"resetsAt":100},"secondary":{"usedPercent":58,"windowDurationMins":10080,"resetsAt":1750000000}}}}'
              ;;
            *account*read*)
              test "$state" -eq 2 || exit 13
              printf '%s\\n' '{"id":1,"result":{"account":{"type":"chatgpt","email":"user@example.com","accountId":"acct-123"},"requiresOpenaiAuth":true}}'
              ;;
          esac
        done
        """)
        let client = CodexClient(
            locator: CodexExecutableLocator(explicitURL: fakeCodex),
            requestTimeout: .seconds(3)
        )
        let rpcWeekly = try await client.readWeeklyUsage(profileHome: root)
        try require(rpcWeekly.remainingPercent == 42, "JSONL rate-limit handshake")
        try require(rpcWeekly.fiveHourRemainingPercent == 20, "JSONL five-hour rate limit")
        let identity = try await client.readIdentity(profileHome: root)
        try require(identity.accountID == "acct-123", "JSONL account handshake")

        let providerMarker = root.appending(path: "provider-selected")
        let providerCodex = root.appending(path: "provider-codex")
        try createExecutable(at: providerCodex, body: """
        while IFS= read -r line; do
          case "$line" in
            *initialized*) ;;
            *initialize*) printf '%s\\n' '{"id":0,"result":{}}' ;;
            *config*read*)
              if test -f '\(providerMarker.path)'; then
                printf '%s\\n' '{"id":1,"result":{"config":{"model_provider":"openai","model_providers":{"azure":{"name":"Azure OpenAI"}}},"origins":{}}}'
              else
                printf '%s\\n' '{"id":1,"result":{"config":{"model_provider":"azure","model_providers":{"azure":{"name":"Azure OpenAI"},"local_proxy":{}}},"origins":{}}}'
              fi
              ;;
            *config*value*write*)
              : > '\(providerMarker.path)'
              printf '%s\\n' '{"id":1,"result":{"filePath":"/tmp/config.toml","status":"ok","version":"1"}}'
              ;;
          esac
        done
        """)
        let providerClient = CodexConfigurationClient(
            codex: CodexClient(
                locator: CodexExecutableLocator(explicitURL: providerCodex),
                requestTimeout: .seconds(3)
            )
        )
        let providerSnapshot = try await providerClient.readConfiguration(codexHome: root)
        try require(providerSnapshot.activeProviderID == "azure", "active provider discovery")
        try require(
            providerSnapshot.providers.map(\.displayName) == ["Azure OpenAI", "Local Proxy"],
            "configured provider discovery and display names"
        )
        try await providerClient.activateProvider(id: "openai", codexHome: root)
        let updatedProviderSnapshot = try await providerClient.readConfiguration(codexHome: root)
        try require(updatedProviderSnapshot.activeProviderID == "openai", "provider activation")

        let returnHome = root.appending(path: "return-active")
        try fileManager.createDirectory(at: returnHome, withIntermediateDirectories: true)
        try Data("return-fixture".utf8).write(to: returnHome.appending(path: "auth.json"))
        let returnStore = AccountStore(baseURL: root.appending(path: "return-store"), activeHomeURL: returnHome)
        let returnProfile = AccountProfile(id: UUID(), displayName: "Return fixture",
            email: "user@example.com", accountID: "acct-123", createdAt: Date())
        try await returnStore.importCurrentProfile(returnProfile)
        let returnConfiguration = FakeProviderConfiguration(providerID: "azure")
        let returnRecorder = Recorder()
        let returnModel = AppModel(
            store: returnStore, codex: client, configuration: returnConfiguration,
            switchService: SwitchService(
                desktop: FakeDesktop(recorder: returnRecorder), store: returnStore,
                codex: client, configuration: returnConfiguration),
            providerSwitchService: ProviderSwitchService(
                desktop: FakeDesktop(recorder: returnRecorder), store: returnStore,
                codex: client, configuration: returnConfiguration)
        )
        await returnModel.start()
        try require(returnModel.activeIdentityConfirmed, "custom provider does not trigger a false account mismatch")
        try require(returnModel.activeRemainingPercent == nil, "provider does not show ChatGPT quota as active")
        try require(returnModel.snapshot.activeAccountID == nil, "Windows snapshot does not mark a ChatGPT account active under a provider")
        try require(!returnModel.isAccountActive(returnProfile), "saved account is not active under a provider")
        await returnModel.switchAccount(to: returnProfile.id)
        try require(returnModel.isAccountActive(returnProfile), "return to the same saved account is not skipped")
        try require(returnModel.visibleError == nil, "return to saved account succeeds")
        let returnStages = await returnRecorder.snapshot()
        try require(returnStages == [.closeDesktop, .reopenDesktop], "same-account return restarts Desktop")
        await returnModel.setEnablesProviderSwitching(true)
        await returnModel.switchProvider(to: ProviderProfile(id: "azure", displayName: "Azure"))
        try require(returnModel.activeProviderID == "azure", "account-to-provider selection updates the shared controller")
        await returnModel.setEnablesProviderSwitching(false)
        let hiddenProviderID = await returnConfiguration.activeProviderID()
        try require(hiddenProviderID == "azure", "disabling provider UI does not change the active provider")

        let gatedProviderService = FakeProviderSwitchService()
        let appModel = AppModel(
            store: store,
            codex: client,
            configuration: FakeProviderConfiguration(),
            switchService: ReopenFailureSwitchService(store: store),
            providerSwitchService: gatedProviderService
        )
        var modelChangeCount = 0
        let modelObservation = appModel.objectWillChange.sink { modelChangeCount += 1 }
        await appModel.start()
        try require(modelChangeCount > 0, "shared-core startup notifies the macOS interface")
        try require(
            appModel.usageStates[first.id] == .loaded(cachedWeekly),
            "cached usage is visible at startup"
        )
        let changesBeforeSettings = modelChangeCount
        await appModel.setShowsFiveHourUsage(false)
        try require(modelChangeCount > changesBeforeSettings, "shared-core settings notify the macOS interface")
        try require(
            !appModel.settings.showsFiveHourUsage,
            "five-hour setting updates immediately"
        )
        appModel.refreshWeeklyUsage()
        try require(
            appModel.usageStates[first.id] == .loaded(cachedWeekly),
            "refresh keeps cached usage visible"
        )
        await appModel.waitForWeeklyUsageRefresh()
        try require(modelChangeCount > changesBeforeSettings + 1, "shared-core usage refresh notifies the macOS interface")
        modelObservation.cancel()
        try require(
            appModel.usageStates[first.id]?.displayedUsage?.remainingPercent == 42,
            "refresh replaces displayed cached usage"
        )
        try require(
            appModel.usageStates[first.id]?.displayedUsage?.fiveHourRemainingPercent == 20,
            "hidden five-hour usage is still normalized"
        )
        try require(
            appModel.activeRemainingPercent == nil,
            "an unconfirmed account does not present its old quota as active"
        )
        let refreshedCache = try await store.loadUsageCache()
        try require(
            refreshedCache.entries.first(where: { $0.profileID == first.id })?.usage.remainingPercent == 42,
            "refresh replaces persisted cached usage"
        )
        try require(
            refreshedCache.entries.first(where: { $0.profileID == first.id })?.usage.fiveHourRemainingPercent == 20,
            "hidden five-hour usage is still cached"
        )

        let requestCountURL = root.appending(path: "rate-limit-request-count")
        let countingCodex = root.appending(path: "counting-codex")
        try createExecutable(at: countingCodex, body: """
        state=0
        while IFS= read -r line; do
          case "$line" in
            *initialized*) state=2 ;;
            *initialize*) state=1; printf '%s\\n' '{"id":0,"result":{}}' ;;
            *rateLimits*)
              test "$state" -eq 2 || exit 15
              printf '%s\\n' 'request' >> '\(requestCountURL.path)'
              sleep 1
              printf '%s\\n' '{"id":1,"result":{"rateLimits":{"primary":{"usedPercent":57,"windowDurationMins":10080,"resetsAt":1750000000}}}}'
              ;;
            *account*read*) printf '%s\\n' '{"id":1,"result":{"account":{"type":"chatgpt","email":"user@example.com","accountId":"acct-123"},"requiresOpenaiAuth":true}}' ;;
          esac
        done
        """)
        let countingClient = CodexClient(
            locator: CodexExecutableLocator(explicitURL: countingCodex),
            requestTimeout: .seconds(3)
        )
        let countingModel = AppModel(
            store: store,
            codex: countingClient,
            configuration: FakeProviderConfiguration(),
            switchService: ReopenFailureSwitchService(store: store),
            providerSwitchService: FakeProviderSwitchService()
        )
        await countingModel.start()
        try require(countingModel.accounts.count == 3, "counting model loaded all profiles")

        countingModel.refreshWeeklyUsage()
        try await waitForLineCount(at: requestCountURL, atLeast: 3)
        countingModel.refreshWeeklyUsage()
        await countingModel.waitForWeeklyUsageRefresh()
        try require(lineCount(at: requestCountURL) == 3, "in-flight refresh stays single-flight")

        countingModel.refreshWeeklyUsage()
        await countingModel.waitForWeeklyUsageRefresh()
        try require(lineCount(at: requestCountURL) == 6, "next popover refresh starts a new request round")

        countingModel.refreshWeeklyUsage()
        try await waitForLineCount(at: requestCountURL, atLeast: 9)
        await countingModel.removeAccount(id: third.id)
        await countingModel.waitForWeeklyUsageRefresh()
        try require(countingModel.usageStates[third.id] == nil, "deleted profile stays absent from usage state")
        let cacheAfterDeletion = try await store.loadUsageCache()
        try require(
            !cacheAfterDeletion.entries.contains(where: { $0.profileID == third.id }),
            "deleted profile is not revived in usage cache"
        )

        let scheduledRequestCountURL = root.appending(path: "scheduled-rate-limit-request-count")
        let scheduledCodex = root.appending(path: "scheduled-codex")
        try createExecutable(at: scheduledCodex, body: """
        state=0
        while IFS= read -r line; do
          case "$line" in
            *initialized*) state=2 ;;
            *initialize*) state=1; printf '%s\\n' '{"id":0,"result":{}}' ;;
            *rateLimits*)
              test "$state" -eq 2 || exit 16
              printf '%s\\n' 'request' >> '\(scheduledRequestCountURL.path)'
              printf '%s\\n' '{"id":1,"result":{"rateLimits":{"primary":{"usedPercent":56,"windowDurationMins":10080,"resetsAt":1750000000}}}}'
              ;;
            *account*read*) printf '%s\\n' '{"id":1,"result":{"account":{"type":"chatgpt","email":"user@example.com","accountId":"acct-123"},"requiresOpenaiAuth":true}}' ;;
          esac
        done
        """)
        let scheduledClient = CodexClient(
            locator: CodexExecutableLocator(explicitURL: scheduledCodex),
            requestTimeout: .seconds(3)
        )
        let scheduledModel = AppModel(
            store: store,
            codex: scheduledClient,
            configuration: FakeProviderConfiguration(),
            switchService: ReopenFailureSwitchService(store: store),
            providerSwitchService: FakeProviderSwitchService()
        )
        await scheduledModel.startBackgroundUsageRefresh(every: .seconds(3))
        try await waitForLineCount(at: scheduledRequestCountURL, atLeast: 2)
        await scheduledModel.waitForWeeklyUsageRefresh()

        try await Task.sleep(for: .seconds(1))
        scheduledModel.refreshWeeklyUsage()
        try await waitForLineCount(at: scheduledRequestCountURL, atLeast: 4)
        await scheduledModel.waitForWeeklyUsageRefresh()

        try await Task.sleep(for: .milliseconds(2_500))
        try require(
            lineCount(at: scheduledRequestCountURL) == 4,
            "manual refresh postpones the previously scheduled refresh"
        )

        try await waitForLineCount(at: scheduledRequestCountURL, atLeast: 6)
        await scheduledModel.waitForWeeklyUsageRefresh()
        scheduledModel.stopBackgroundUsageRefresh()
        let countAfterBackgroundCancellation = lineCount(at: scheduledRequestCountURL)
        scheduledModel.refreshWeeklyUsage()
        try await waitForLineCount(
            at: scheduledRequestCountURL,
            atLeast: countAfterBackgroundCancellation + 2
        )
        await scheduledModel.waitForWeeklyUsageRefresh()
        let countAfterStoppedManualRefresh = lineCount(at: scheduledRequestCountURL)
        try await Task.sleep(for: .milliseconds(3_200))
        try require(
            lineCount(at: scheduledRequestCountURL) == countAfterStoppedManualRefresh,
            "manual refresh does not restart a stopped background schedule"
        )

        let usageCacheURL = support.appending(path: "usage-cache.json")
        guard Darwin.chflags(usageCacheURL.path, UInt32(UF_IMMUTABLE)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let cacheWriteError: (any Error)?
        do {
            try await store.cacheWeeklyUsage(
                WeeklyUsage(remainingPercent: 99, resetsAt: cachedWeekly.resetsAt),
                profileID: first.id
            )
            cacheWriteError = nil
        } catch {
            cacheWriteError = error
        }
        guard Darwin.chflags(usageCacheURL.path, 0) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try require(cacheWriteError is POSIXError, "immutable cache file rejects atomic replacement")
        let cacheAfterFailedWrite = try await AccountStore(
            baseURL: support,
            activeHomeURL: activeHome
        ).loadUsageCache()
        try require(
            cacheAfterFailedWrite.entries.first(where: { $0.profileID == first.id })?.usage.remainingPercent == 44,
            "failed cache replacement preserves the previous complete file"
        )
        let cacheTemporaryFiles = try fileManager.contentsOfDirectory(atPath: support.path)
            .filter { $0.hasPrefix("usage-cache.json.switcher-") }
        try require(cacheTemporaryFiles.isEmpty, "failed cache replacement removes temporary file")

        try require(!appModel.activeIdentityConfirmed, "precondition identity mismatch")
        await appModel.switchAccount(to: second.id)
        try require(appModel.activeAccountID == second.id, "reopen failure active account reload")
        try require(appModel.activeIdentityConfirmed, "reopen failure identity state")
        try require(appModel.visibleError?.stage == .reopenDesktop, "reopen failure message stage")

        let failingCodex = root.appending(path: "failing-codex")
        try createExecutable(at: failingCodex, body: """
        state=0
        while IFS= read -r line; do
          case "$line" in
            *initialized*) state=2 ;;
            *initialize*) state=1; printf '%s\\n' '{"id":0,"result":{}}' ;;
            *account*read*) printf '%s\\n' '{"id":1,"result":{"account":{"type":"chatgpt","email":"user@example.com","accountId":"acct-123"},"requiresOpenaiAuth":true}}' ;;
            *rateLimits*) exit 14 ;;
          esac
        done
        """)
        let failingClient = CodexClient(
            locator: CodexExecutableLocator(explicitURL: failingCodex),
            requestTimeout: .seconds(2)
        )
        let failureModel = AppModel(
            store: store,
            codex: failingClient,
            configuration: FakeProviderConfiguration(),
            switchService: ReopenFailureSwitchService(store: store),
            providerSwitchService: FakeProviderSwitchService()
        )
        await failureModel.start()
        failureModel.refreshWeeklyUsage()
        await failureModel.waitForWeeklyUsageRefresh()
        try require(
            failureModel.usageStates[first.id]?.displayedUsage?.remainingPercent == 44,
            "failed refresh retains cached usage"
        )
        try require(
            failureModel.usageStates[first.id]?.refreshError != nil,
            "failed refresh exposes stale-cache warning"
        )

        let stalledCodex = root.appending(path: "stalled-codex")
        try createExecutable(at: stalledCodex, body: """
        while IFS= read -r line; do
          case "$line" in
            *initialized*) ;;
            *initialize*) printf '%s\\n' '{"id":0,"result":{}}' ;;
            *account*read*) sleep 5 ;;
          esac
        done
        """)
        let stalledClient = CodexClient(
            locator: CodexExecutableLocator(explicitURL: stalledCodex),
            requestTimeout: .milliseconds(50)
        )
        do {
            _ = try await stalledClient.readIdentity(profileHome: root)
            throw CheckFailure.failed("app-server timeout")
        } catch CodexClientError.timeout {
            // Expected: the first deadline stops the request without retrying.
        }

        let provider = ProviderProfile(id: "azure", displayName: "Azure OpenAI")
        await appModel.setEnablesProviderSwitching(false)
        await appModel.switchProvider(to: provider)
        let disabledCalls = await gatedProviderService.calls
        try require(disabledCalls == 0, "disabled providers cannot trigger a switch")
        await appModel.setEnablesProviderSwitching(true)
        await appModel.switchProvider(to: provider)
        let enabledCalls = await gatedProviderService.calls
        try require(enabledCalls == 1, "enabled provider selection reaches the switching service")
        await appModel.setEnablesProviderSwitching(false)
        let savedAdvancedSettings = try await store.loadSettings()
        try require(!savedAdvancedSettings.enablesProviderSwitching, "provider opt-out persists")

        try await NativeAPIScenarios.run { condition, message in try require(condition, message) }
        print("Core checks passed")
    }
}
