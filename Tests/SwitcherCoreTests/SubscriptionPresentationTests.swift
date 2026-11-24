import Foundation
import Testing
@testable import SwitcherCore

struct SubscriptionPresentationTests {
    private let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let activeUntil = Date(timeIntervalSince1970: 1_800_000_000)
    private let historicalUntil = Date(timeIntervalSince1970: 1_750_000_000)
    private let historicalChecked = Date(timeIntervalSince1970: 1_699_000_000)

    private func day(_ date: Date) -> String { "DAY(\(Int(date.timeIntervalSince1970)))" }
    private func timestamp(_ date: Date) -> String { "TS(\(Int(date.timeIntervalSince1970)))" }

    @Test func idlePendingWithoutHistoricalSnapshot() {
        let presentation = SubscriptionPresentation(state: .idle, historical: nil)
        #expect(presentation.primary == .pending)
        #expect(presentation.staleAfter == nil)
        #expect(!presentation.needsUpdate(at: fetchedAt))
        #expect(
            presentation.primaryText(at: fetchedAt, language: .english, formatDay: day)
                == L10n.string("subscription_live_pending", language: .english)
        )

        let detail = presentation.detailText(at: fetchedAt, language: .english, formatDay: day, formatTimestamp: timestamp)
        #expect(detail.contains(L10n.string("subscription_live_never_succeeded", language: .english)))
        #expect(detail.contains(L10n.string("subscription_live_renew_unknown", language: .english)))
        #expect(detail.contains(L10n.string("subscription_live_delinquent_unknown", language: .english)))
        #expect(!detail.contains("TS("))
        #expect(!detail.contains("DAY("))
    }

    @Test func firstSyncFailureWithHistoricalSnapshotShowsNeedsUpdateErrorAndHistory() {
        let historical = SubscriptionSnapshot(activeUntil: historicalUntil, lastChecked: historicalChecked)
        let presentation = SubscriptionPresentation(state: .unavailable("Network timeout"), historical: historical)
        #expect(presentation.primary == .pending)
        #expect(presentation.requiresUpdateImmediately)
        #expect(presentation.needsUpdate(at: fetchedAt))

        let expectedPrimary = L10n.string("subscription_live_pending", language: .english)
            + " · "
            + L10n.string("subscription_live_needs_update", language: .english)
        #expect(presentation.primaryText(at: fetchedAt, language: .english, formatDay: day) == expectedPrimary)

        let detail = presentation.detailText(at: fetchedAt, language: .english, formatDay: day, formatTimestamp: timestamp)
        #expect(detail.contains(String(format: L10n.string("subscription_live_refresh_failed", language: .english), "Network timeout")))
        #expect(detail.contains(String(
            format: L10n.string("subscription_live_history", language: .english),
            day(historicalUntil),
            timestamp(historicalChecked)
        )))
    }

    @Test func activePaidSubscriptionTransitionsAtStaleAfterAndFormatsFetchedAtOnce() {
        let live = LiveSubscription(
            activeUntil: activeUntil,
            planType: "plus",
            isActive: true,
            willRenew: true,
            isDelinquent: false,
            fetchedAt: fetchedAt
        )
        let presentation = SubscriptionPresentation(state: .loaded(live), historical: nil)
        #expect(presentation.primary == .activeUntil)
        #expect(presentation.staleAfter == fetchedAt.addingTimeInterval(600))

        let beforeDeadline = fetchedAt.addingTimeInterval(599)
        #expect(!presentation.needsUpdate(at: beforeDeadline))
        let freshPrimary = presentation.primaryText(at: beforeDeadline, language: .english, formatDay: day)
        #expect(freshPrimary == String(format: L10n.string("subscription_live_until", language: .english), day(activeUntil)))

        let freshDetail = presentation.detailText(at: beforeDeadline, language: .english, formatDay: day, formatTimestamp: timestamp)
        #expect(freshDetail.contains(String(format: L10n.string("subscription_live_updated", language: .english), timestamp(fetchedAt))))
        #expect(freshDetail.contains(L10n.string("subscription_live_renew_on", language: .english)))
        #expect(freshDetail.contains(L10n.string("subscription_live_delinquent_no", language: .english)))
        #expect(!freshDetail.contains(L10n.string("subscription_live_stale_hint", language: .english)))
        #expect(freshDetail.components(separatedBy: timestamp(fetchedAt)).count - 1 == 1)

        let atDeadline = fetchedAt.addingTimeInterval(600)
        #expect(presentation.needsUpdate(at: atDeadline))
        let stalePrimary = presentation.primaryText(at: atDeadline, language: .english, formatDay: day)
        #expect(stalePrimary == freshPrimary + " · " + L10n.string("subscription_live_needs_update", language: .english))

        let staleDetail = presentation.detailText(at: atDeadline, language: .english, formatDay: day, formatTimestamp: timestamp)
        #expect(staleDetail.contains(String(format: L10n.string("subscription_live_last_success", language: .english), timestamp(fetchedAt))))
        #expect(staleDetail.contains(L10n.string("subscription_live_stale_hint", language: .english)))
        #expect(staleDetail.components(separatedBy: timestamp(fetchedAt)).count - 1 == 1)
    }

    @Test func freeInactiveAndActiveWithoutExpiryVariants() {
        let free = SubscriptionPresentation(
            state: .loaded(LiveSubscription(activeUntil: nil, planType: "Free", isActive: true, willRenew: false, isDelinquent: nil, fetchedAt: fetchedAt)),
            historical: nil
        )
        #expect(free.primary == .free)
        #expect(free.primaryText(at: fetchedAt, language: .english, formatDay: day) == L10n.string("subscription_live_free", language: .english))

        let inactive = SubscriptionPresentation(
            state: .loaded(LiveSubscription(activeUntil: activeUntil, planType: "plus", isActive: false, willRenew: false, isDelinquent: true, fetchedAt: fetchedAt)),
            historical: nil
        )
        #expect(inactive.primary == .inactive)
        #expect(inactive.primaryText(at: fetchedAt, language: .english, formatDay: day) == L10n.string("subscription_live_inactive", language: .english))

        let activeNoDate = SubscriptionPresentation(
            state: .loaded(LiveSubscription(activeUntil: nil, planType: "team", isActive: true, willRenew: nil, isDelinquent: false, fetchedAt: fetchedAt)),
            historical: nil
        )
        #expect(activeNoDate.primary == .active)
        #expect(activeNoDate.primaryText(at: fetchedAt, language: .english, formatDay: day) == L10n.string("subscription_live_active", language: .english))
    }

    @Test @MainActor func cachedStartupStateRemainsExplicitAcrossLanguageSwitch() async throws {
        let cached = LiveSubscription(
            activeUntil: activeUntil,
            planType: "plus",
            isActive: true,
            willRenew: true,
            isDelinquent: false,
            fetchedAt: fetchedAt
        )
        let directPresentation = SubscriptionPresentation(state: .cached(cached), historical: nil)
        #expect(directPresentation.requiresUpdateImmediately)
        #expect(directPresentation.isWaitingForRefresh)
        #expect(directPresentation.refreshError == nil)
        let directDetail = directPresentation.detailText(at: fetchedAt, language: .english, formatDay: day, formatTimestamp: timestamp)
        #expect(directDetail.contains(L10n.string("subscription_refresh_pending", language: .english)))
        #expect(!directDetail.contains(L10n.string("subscription_live_stale_hint", language: .english)))

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("switcher-cached-sub-\(UUID())")
        let store = AccountStore(baseURL: root.appendingPathComponent("store"), activeHomeURL: root.appendingPathComponent("active"))
        defer { try? FileManager.default.removeItem(at: root) }

        let profile = AccountProfile(
            id: UUID(),
            displayName: "Cached",
            email: "cached@example.test",
            accountID: "cached-account",
            createdAt: Date()
        )
        let home = try await store.createProfileDirectory(id: profile.id)
        try TestAuthFixture.authJSON(accountID: "cached-account", email: "cached@example.test")
            .write(to: home.appendingPathComponent("auth.json"))
        try await store.addProfile(profile)
        try await store.cacheLiveSubscription(cached, profile: profile)

        let codex = CachedSubCodex()
        let model = AccountController(
            store: store,
            codex: codex,
            switchService: SwitchService(desktop: CachedSubDesktop(), store: store, codex: codex),
            subscriptionClient: NoopSubscriptionClient()
        )
        await model.start()
        #expect(model.subscriptionStates[profile.id] == .cached(cached))

        await model.setLanguage(.simplifiedChinese)
        #expect(model.subscriptionStates[profile.id] == .cached(cached))
        let row = try #require(model.snapshot(includeStrings: false).accounts.first)
        #expect(row.subscriptionStatus == "cached")
        #expect(row.subscriptionView.isWaitingForRefresh)
        #expect(row.subscriptionView.requiresUpdateImmediately)
        let zhPrimary = row.subscriptionView.primaryText(at: fetchedAt, language: .simplifiedChinese, formatDay: day)
        #expect(zhPrimary.contains(L10n.string("subscription_live_needs_update", language: .simplifiedChinese)))
        let zhDetail = row.subscriptionView.detailText(
            at: fetchedAt,
            language: .simplifiedChinese,
            formatDay: day,
            formatTimestamp: timestamp
        )
        #expect(zhDetail.contains(L10n.string("subscription_refresh_pending", language: .simplifiedChinese)))
    }
}

private actor CachedSubCodex: AccountClient {
    func login(profileHome: URL) async throws -> AccountIdentity { throw CancellationError() }
    func readIdentity(profileHome: URL) async throws -> AccountIdentity { throw CancellationError() }
    func readWeeklyUsage(profileHome: URL) async throws -> WeeklyUsage { throw CancellationError() }
    func consumeResetCredit(profileHome: URL, creditID: String, idempotencyKey: String) async throws -> ResetCreditOutcome { .reset }
}

private struct CachedSubDesktop: DesktopControlling {
    func closeDesktop() async throws {}
    func reopenDesktop() async throws {}
}

private struct NoopSubscriptionClient: SubscriptionClient {
    func readSubscription(credential: Data, expectedAccountID: String?, expectedEmail: String?) async throws -> LiveSubscription {
        throw LiveSubscriptionError.serverUnavailable
    }
}
