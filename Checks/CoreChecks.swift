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
    func activeCodexHome() -> URL { URL(fileURLWithPath: "/tmp/active") }
    func activeCredentialExists() -> Bool { true }
    func saveCurrentCredential() async { await recorder.append(.saveCurrentCredential) }
    func activateTargetCredential(id: UUID) async { await recorder.append(.activateTargetCredential) }
    func restoreActiveCredential(id: UUID) {}
    func commitActiveAccountID(_ id: UUID) async { await recorder.append(.commitActiveAccountID) }
}

private actor FakeCodex: CodexIdentityReading {
    let recorder: Recorder
    let original: AccountProfile
    let target: AccountProfile
    private var hasVerifiedOriginal = false
    init(recorder: Recorder, original: AccountProfile, target: AccountProfile) {
        self.recorder = recorder
        self.original = original
        self.target = target
    }

    func readIdentity(profileHome: URL) async throws -> AccountIdentity {
        if !hasVerifiedOriginal {
            hasVerifiedOriginal = true
            return AccountIdentity(accountID: original.accountID, email: original.email)
        }
        await recorder.append(.verifyTargetIdentity)
        return AccountIdentity(accountID: target.accountID, email: target.email)
    }
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

private func testCredential(
    accountID: String = "account-a",
    email: String = "a@example.com",
    plan: String = "plus",
    activeUntil: String? = "2026-10-17T12:00:00Z",
    lastChecked: String? = "2026-10-03T12:00:00Z"
) throws -> Data {
    var account: [String: Any] = ["chatgpt_account_id": accountID, "chatgpt_plan_type": plan]
    account["chatgpt_subscription_active_until"] = activeUntil
    account["chatgpt_subscription_last_checked"] = lastChecked
    let payload: [String: Any] = ["email": email, "https://api.openai.com/auth": account]
    let encoded = try JSONSerialization.data(withJSONObject: payload).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return try JSONSerialization.data(withJSONObject: ["tokens": ["id_token": "header.\(encoded).signature"]])
}

private func testTiboForecastReader() throws {
    let now = Date(timeIntervalSince1970: 1_791_149_623)
    let iso = ISO8601DateFormatter()
    func event(_ daysAgo: Int, group: String = "reset", state: String = "announced") -> [String: Any] {
        let postedAt = now.addingTimeInterval(-Double(daysAgo * 86_400))
        let milliseconds = UInt64(postedAt.timeIntervalSince1970 * 1_000)
        let id = String((milliseconds - 1_288_834_974_657) << 22)
        return [
            "id": id, "group": group, "announcement_state": state,
            "url": "https://x.com/thsottiaux/status/\(id)",
            "summary": "Fictional reset fixture", "announced_at": iso.string(from: postedAt),
        ]
    }
    var events = (1...6).map { event($0) }
    events.append(event(7, group: "credits"))
    events.append(event(8, state: "none"))
    let conditionalPlanID = "2106845241357824205"
    events.append([
        "id": conditionalPlanID, "group": "reset", "announcement_state": "none",
        "url": "https://x.com/thsottiaux/status/\(conditionalPlanID)",
        "summary": "Over the next 28 days, each day we'll either ship an improvement or ship a full reset.",
    ])
    let forecastPayload: [String: Any] = [
        "updated_at": iso.string(from: now),
        "last_reset_at": iso.string(from: now.addingTimeInterval(-86_400)),
        "probabilities": ["rounded_24h": 16, "rounded_48h": 29],
        "confidence": "low",
        "time_window": ["start_hour": 7, "end_hour": 10, "timezone": "Asia/Shanghai"],
    ]
    let forecastData = try JSONSerialization.data(withJSONObject: forecastPayload)
    func timelineData(_ events: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["updated_at": iso.string(from: now), "events": events])
    }
    let result = try TiboResetForecastReader.read(
        forecast: forecastData, timeline: timelineData(events), now: now
    )
    try require(result.next24HourPercent == 16 && result.next48HourPercent == 29,
                "public Tibo probability fields")
    try require(result.events.count == 6, "credits and unconfirmed posts do not enter history")
    try require(result.forwardSignal?.url.absoluteString ==
                "https://x.com/thsottiaux/status/\(conditionalPlanID)",
                "the conditional plan is shown separately from confirmed resets")
    try require(result.events[0].postedAt == now.addingTimeInterval(-86_400),
                "post time comes from the original X status ID")
    try require(result.recentMedianDays == 1 && result.historicalNextWindow != nil,
                "historical window uses the latest five confirmed post gaps")
    events[5]["url"] = "https://x.com/another-author/status/\(events[5]["id"]!)"
    let filtered = try TiboResetForecastReader.read(
        forecast: forecastData, timeline: timelineData(events), now: now
    )
    try require(filtered.events.count == 5, "other authors cannot enter Tibo history")
    try require(filtered.recentMedianDays == nil && filtered.historicalNextWindow == nil,
                "historical window requires five confirmed intervals")
    events[8]["url"] = "https://x.com/not-tibo/status/\(conditionalPlanID)"
    let invalidSignal = try TiboResetForecastReader.read(
        forecast: forecastData, timeline: timelineData(events), now: now
    )
    try require(invalidSignal.forwardSignal == nil,
                "a non-original URL cannot support the conditional plan")
    do {
        _ = try TiboResetForecastReader.read(
            forecast: forecastData, timeline: timelineData(events), now: now.addingTimeInterval(10_800)
        )
        throw CheckFailure.failed("stale Tibo forecast was shown")
    } catch TiboResetForecastReader.DataError.staleResponse {
        // Expected: a delayed public feed cannot be presented as current.
    }
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
        try testTiboForecastReader()

        let credential = try testCredential()
        let subscription = SubscriptionSnapshotReader.read(
            credential: credential, expectedAccountID: "account-a", expectedEmail: "a@example.com"
        )
        let iso = ISO8601DateFormatter()
        try require(subscription?.activeUntil == iso.date(from: "2026-10-17T12:00:00Z"), "saved subscription date")
        try require(subscription?.lastChecked == iso.date(from: "2026-10-03T12:00:00Z"), "saved subscription check time")
        try require(SubscriptionSnapshotReader.read(
            credential: credential, expectedAccountID: "other-account", expectedEmail: "a@example.com"
        ) == nil, "subscription cannot cross account IDs")
        try require(SubscriptionSnapshotReader.read(
            credential: credential, expectedAccountID: "account-a", expectedEmail: "other@example.com"
        ) == nil, "subscription cannot cross emails")
        try require(SubscriptionSnapshotReader.read(
            credential: credential, expectedAccountID: nil, expectedEmail: "A@EXAMPLE.COM"
        ) == subscription, "email-only saved profiles identify their own subscription")
        let freeCredential = try testCredential(plan: "free")
        try require(SubscriptionSnapshotReader.read(
            credential: freeCredential, expectedAccountID: "account-a", expectedEmail: nil
        ) == nil, "free login has no membership date")
        let missingDateCredential = try testCredential(activeUntil: nil)
        try require(SubscriptionSnapshotReader.read(
            credential: missingDateCredential, expectedAccountID: "account-a", expectedEmail: nil
        ) == nil, "missing subscription date stays unknown")
        try require(SubscriptionSnapshotReader.read(
            credential: Data("invalid".utf8), expectedAccountID: "account-a", expectedEmail: nil
        ) == nil, "invalid credential stays unknown")

        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(path: "switcher-check-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: root) }
        let activeHome = root.appending(path: "active")
        let support = root.appending(path: "support")
        try fileManager.createDirectory(at: activeHome, withIntermediateDirectories: true)
        try Data(#"{"tokens":{"account_id":"first"}}"#.utf8).write(to: activeHome.appending(path: "auth.json"))

        let subscriptionHome = root.appending(path: "subscription-active")
        let subscriptionStore = AccountStore(
            baseURL: root.appending(path: "subscription-support"), activeHomeURL: subscriptionHome
        )
        let subscriptionProfile = AccountProfile(
            id: UUID(), displayName: "A", email: "a@example.com",
            accountID: nil, createdAt: Date(), lastUsedAt: nil
        )
        let savedHome = await subscriptionStore.profileHome(id: subscriptionProfile.id)
        try fileManager.createDirectory(at: savedHome, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: subscriptionHome, withIntermediateDirectories: true)
        try credential.write(to: savedHome.appending(path: "auth.json"))
        let newerCredential = try testCredential(
            activeUntil: "2026-10-24T12:00:00Z", lastChecked: "2026-10-04T12:00:00Z"
        )
        try newerCredential.write(to: subscriptionHome.appending(path: "auth.json"))
        let inactiveDate = await subscriptionStore.readSubscriptionSnapshot(profile: subscriptionProfile, isActive: false)
        let activeDate = await subscriptionStore.readSubscriptionSnapshot(profile: subscriptionProfile, isActive: true)
        try require(inactiveDate == subscription, "inactive profile uses its saved login")
        try require(activeDate?.activeUntil == iso.date(from: "2026-10-24T12:00:00Z"),
                    "active profile uses the newer current login")

        let migrationHome = root.appending(path: "migration-active")
        let migrationSupport = root.appending(path: "migration-support")
        try fileManager.createDirectory(at: migrationHome, withIntermediateDirectories: true)
        try credential.write(to: migrationHome.appending(path: "auth.json"))
        let migrationProfile = AccountProfile(
            id: UUID(), displayName: "A", email: "a@example.com",
            accountID: nil, createdAt: Date(), lastUsedAt: nil
        )
        let migrationStore = AccountStore(baseURL: migrationSupport, activeHomeURL: migrationHome)
        try await migrationStore.importCurrentProfile(migrationProfile)
        let reloadedMigrationStore = AccountStore(baseURL: migrationSupport, activeHomeURL: migrationHome)
        let migrated = try await reloadedMigrationStore.loadRegistry()
        try require(migrated.accounts.first?.accountID == "account-a", "legacy profile gains its saved account ID")
        try newerCredential.write(to: migrationHome.appending(path: "auth.json"))
        let didSync = try await reloadedMigrationStore.syncActiveCredentialIfMatching(id: migrationProfile.id)
        try require(didSync,
                    "matching active credential refreshes the saved profile")
        let migratedHome = await reloadedMigrationStore.profileHome(id: migrationProfile.id)
        let savedAfterSync = try Data(contentsOf: migratedHome.appending(path: "auth.json"))
        try require(savedAfterSync == newerCredential,
                    "saved profile receives the refreshed credential")
        let wrongAccountCredential = try testCredential(accountID: "other-account")
        try wrongAccountCredential.write(to: migrationHome.appending(path: "auth.json"))
        let rejectedSync = try await reloadedMigrationStore.syncActiveCredentialIfMatching(id: migrationProfile.id)
        try require(!rejectedSync,
                    "other account cannot replace the saved credential")
        let savedAfterRejectedSync = try Data(contentsOf: migratedHome.appending(path: "auth.json"))
        try require(savedAfterRejectedSync == newerCredential,
                    "rejected credential leaves the saved profile intact")

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
        let secondBytes = Data(#"{"tokens":{"account_id":"second"}}"#.utf8)
        try secondBytes.write(to: secondHome.appending(path: "auth.json"))
        try await store.addProfile(second)
        let third = AccountProfile(
            id: UUID(), displayName: "Third", email: "third@example.com",
            accountID: "third", createdAt: Date(), lastUsedAt: nil
        )
        let thirdHome = try await store.createProfileDirectory(id: third.id)
        try Data(#"{"tokens":{"account_id":"third"}}"#.utf8).write(to: thirdHome.appending(path: "auth.json"))
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
        try require(
            legacySettings.showsMenuBarPercentage,
            "legacy settings enable menu bar percentage"
        )
        try require(
            !legacySettings.showsFiveHourUsage,
            "legacy settings hide five-hour usage"
        )
        try require(
            legacySettings.statusBarUsageWindow == .fiveHour,
            "legacy settings default to the five-hour status bar window"
        )
        let hiddenPercentageSettings = AppSettings(
            language: .simplifiedChinese,
            showsMenuBarPercentage: false,
            showsFiveHourUsage: true
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
        let switcher = SwitchService(
            desktop: FakeDesktop(recorder: recorder),
            store: FakeStore(recorder: recorder, original: first, target: second),
            codex: FakeCodex(recorder: recorder, original: first, target: second)
        )
        try await switcher.switchAccount(to: second.id)
        let recordedStages = await recorder.snapshot()
        try require(recordedStages == SwitchStage.allCases, "switch stage order")

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

        let appModel = AppModel(
            store: store,
            codex: client,
            switchService: ReopenFailureSwitchService(store: store)
        )
        var modelChangeCount = 0
        let modelObservation = appModel.objectWillChange.sink { modelChangeCount += 1 }
        await appModel.start()
        try require(modelChangeCount > 0, "shared-core startup notifies the macOS interface")
        try require(
            appModel.usageStates[first.id] == .loaded(cachedWeekly),
            "cached usage is visible at startup"
        )
        try require(
            appModel.activeRemainingPercent == 73,
            "five-hour status bar falls back to weekly-only cached usage"
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
        try require(
            appModel.usageStates[first.id]?.displayedUsage?.remainingPercent == 42,
            "refresh replaces displayed cached usage"
        )
        try require(
            appModel.usageStates[first.id]?.displayedUsage?.fiveHourRemainingPercent == 20,
            "hidden five-hour usage is still normalized"
        )
        try require(
            appModel.activeRemainingPercent == 20,
            "default status bar shows 100 minus the fixture's five-hour usedPercent of 80"
        )
        await appModel.setShowsFiveHourUsage(true)
        try require(
            appModel.activeRemainingPercent == 20,
            "account-row five-hour visibility does not change the selected status bar window"
        )
        let changesBeforeWindow = modelChangeCount
        await appModel.setStatusBarUsageWindow(.weekly)
        try require(modelChangeCount > changesBeforeWindow, "status bar window notifies the macOS interface")
        try require(
            appModel.activeRemainingPercent == 42,
            "weekly status bar shows 100 minus the fixture's weekly usedPercent of 58"
        )
        await appModel.setStatusBarUsageWindow(.fiveHour)
        try require(
            appModel.activeRemainingPercent == 20,
            "switching back to five-hour status bar restores its remaining percentage"
        )
        modelObservation.cancel()
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
            switchService: ReopenFailureSwitchService(store: store)
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
            switchService: ReopenFailureSwitchService(store: store)
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
            switchService: ReopenFailureSwitchService(store: store)
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

        print("Core checks passed")
    }
}
