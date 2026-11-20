import Foundation
import Testing
@testable import SwitcherCore

struct AutoResetTests {
    let expiry = Date(timeIntervalSince1970: 2_000_000_000)
    let profile = AccountProfile(id: UUID(), displayName: "Fixture", email: nil,
        accountID: nil, createdAt: Date(timeIntervalSince1970: 1_900_000_000))

    func usage(credits: [BankedResetCredit]? = nil) -> WeeklyUsage {
        WeeklyUsage(remainingPercent: 37, resetsAt: expiry.addingTimeInterval(-7200),
            resetCreditsRemaining: 1, resetCredits: credits ?? [
                BankedResetCredit(id: "fixture-credit", status: "available", resetType: "codexRateLimits", expiresAt: expiry)
            ])
    }

    @Test func threeCheckpointsUseCreditExpiryAndSurviveRestartsWithoutDuplicates() throws {
        var tracker = AutoReset(history: [])
        // Ordinary polls outside checkpoint windows emit zero disk log spam.
        #expect(tracker.observe(profile: profile, usage: usage(), at: expiry.addingTimeInterval(-900)).isEmpty)
        #expect(tracker.nextCheckpoint(accountIDs: [profile.id]) == expiry.addingTimeInterval(-600))
        var history: [ResetExpiryEvent] = []
        for minutes in [10, 5, 1] {
            let now = expiry.addingTimeInterval(-Double(minutes * 60))
            let events = tracker.observe(profile: profile, usage: usage(), at: now)
            let checkpoint = try #require(events.first(where: { $0.event == "checkpoint" }))
            #expect(checkpoint.checkpointMinutes == minutes)
            #expect(checkpoint.decision == "attempt")
            #expect(checkpoint.scheduledAt == now)
            #expect(checkpoint.delaySeconds == 0)
            #expect(checkpoint.mode == "live" && !checkpoint.resetAttempted)
            history += events
            tracker = AutoReset(history: history)
            #expect(tracker.observe(profile: profile, usage: usage(), at: now).isEmpty)
        }
        #expect(tracker.nextCheckpoint(accountIDs: [profile.id]) == nil)
        #expect(history.filter { $0.event == "checkpoint" }.count == 3)
    }

    @Test func wakeAfterExpiryRecordsMissedCheckpointsInsteadOfPretendingToAttempt() {
        var tracker = AutoReset(history: [])
        _ = tracker.observe(profile: profile, usage: usage(), at: expiry.addingTimeInterval(-900))
        let events = tracker.observe(profile: profile, usage: usage(credits: []), at: expiry.addingTimeInterval(30))
        let checkpoints = events.filter { $0.event == "checkpoint" }
        #expect(checkpoints.map(\.checkpointMinutes) == [10, 5, 1])
        #expect(checkpoints.allSatisfy { $0.decision == "missed" && !$0.resetAttempted })
        #expect(tracker.nextCheckpoint(accountIDs: [profile.id]) == nil)
    }

    @Test func lateStartOnlyAttemptsCurrentStageAndRecordsDelay() {
        var tracker = AutoReset(history: [])
        let events = tracker.observe(profile: profile, usage: usage(), at: expiry.addingTimeInterval(-120))
        #expect(events.filter { $0.event == "checkpoint" }.map(\.decision) == ["missed", "attempt"])
        #expect(events.last?.delaySeconds == 180)
        #expect(tracker.nextCheckpoint(accountIDs: [profile.id]) == expiry.addingTimeInterval(-60))
    }

    @Test func failedReadAndMissingDetailsNeverBecomeSuccessfulAttempts() {
        var tracker = AutoReset(history: [])
        _ = tracker.observe(profile: profile, usage: usage(), at: expiry.addingTimeInterval(-900))
        let failure = tracker.observe(profile: profile, usage: nil, error: "HTTP 503", at: expiry.addingTimeInterval(-600))
        #expect(failure.last?.decision == "read_failed")
        #expect(failure.last?.error == "HTTP 503")
        let unknown = WeeklyUsage(remainingPercent: 30, resetsAt: expiry, resetCreditsRemaining: 1)
        let noDetails = tracker.observe(profile: profile, usage: unknown, at: expiry.addingTimeInterval(-300))
        #expect(noDetails.last?.decision == "details_unavailable")
        #expect(tracker.nextCheckpoint(accountIDs: [profile.id]) == expiry.addingTimeInterval(-60))
        #expect(tracker.observe(profile: profile, usage: usage(credits: []), at: expiry.addingTimeInterval(-60)).last?.decision == "credit_unavailable")
    }

    @Test func onlyAvailableKnownExpiringCreditsAreScheduledForExistingAccounts() {
        var tracker = AutoReset(history: [])
        let credits = [
            BankedResetCredit(id: "no-expiry", status: "available", resetType: "codexRateLimits", expiresAt: nil),
            BankedResetCredit(id: "used", status: "redeemed", resetType: "codexRateLimits", expiresAt: expiry),
            BankedResetCredit(id: "other", status: "available", resetType: "unknown", expiresAt: expiry)
        ]
        _ = tracker.observe(profile: profile, usage: usage(credits: credits), at: expiry.addingTimeInterval(-900))
        #expect(tracker.nextCheckpoint(accountIDs: [profile.id]) == nil)
        _ = tracker.observe(profile: profile, usage: usage(), at: expiry.addingTimeInterval(-900))
        #expect(tracker.nextCheckpoint(accountIDs: []) == nil)
    }

    @Test func checkpointsAreIsolatedBetweenAccountsWithTheSameCreditID() {
        var tracker = AutoReset(history: [])
        let other = AccountProfile(id: UUID(), displayName: "Other", email: nil, accountID: nil, createdAt: expiry)
        for account in [profile, other] {
            let events = tracker.observe(profile: account, usage: usage(), at: expiry.addingTimeInterval(-600))
            #expect(events.last?.decision == "attempt")
            #expect(events.last?.profileID == account.id)
        }
    }

    @Test func logPersistsMigratesLegacyFileSkipsDamagedTrailingLinesAndCompacts() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "reset-log-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        var tracker = AutoReset(history: [])
        let events = tracker.observe(profile: profile, usage: usage(), at: expiry.addingTimeInterval(-600))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var legacyBytes = try encoder.encode(events[0])
        legacyBytes.append(contentsOf: "\ntruncated-json-line\n".utf8)
        try legacyBytes.write(to: root.appending(path: "reset-expiry-experiment.jsonl"))

        let store = AccountStore(baseURL: root)
        let migratedHistory = try await store.loadResetExpiryLog()
        #expect(migratedHistory.count == 1)
        #expect(FileManager.default.fileExists(atPath: store.resetExpiryLogURL.path))
        #expect(AutoReset(history: migratedHistory).nextCheckpoint(accountIDs: [profile.id]) == expiry.addingTimeInterval(-300))

        try await store.appendResetExpiryLog([ResetExpiryEvent(timestamp: Date(), event: "enabled")])
        #if !os(Windows)
        let attributes = try FileManager.default.attributesOfItem(atPath: store.resetExpiryLogURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #endif

        let many = (0..<600).map { index in
            ResetExpiryEvent(timestamp: Date(timeIntervalSince1970: Double(index)), event: "enabled")
        }
        let compacted = AutoReset.compactedHistory(many, now: Date(timeIntervalSince1970: 1_000_000))
        #expect(compacted.count == AutoReset.retainedLogEntries)
    }

    @Test func olderSettingsKeepAutoResetOff() throws {
        #expect(!AppSettings.default.autoResetEnabled)
        #expect(try !JSONDecoder().decode(AppSettings.self, from: Data(#"{"language":"system"}"#.utf8)).autoResetEnabled)
        #expect(try !JSONDecoder().decode(AppSettings.self, from: Data(#"{"resetExpiryExperimentEnabled":true}"#.utf8)).autoResetEnabled)
    }

    @Test func oldDryRunCheckpointsDoNotSuppressRealAttempts() {
        var old = AutoReset(history: [])
        var history = old.observe(profile: profile, usage: usage(), at: expiry.addingTimeInterval(-600))
        for i in history.indices { history[i].mode = "dry_run" }
        var live = AutoReset(history: history)
        #expect(live.observe(profile: profile, usage: usage(), at: expiry.addingTimeInterval(-590)).last?.decision == "attempt")
    }

    @Test func startedAttemptsRemainStoppedAcrossRestartUnlessNothingNeededResetting() {
        var tracker = AutoReset(history: [])
        var history = tracker.observe(profile: profile, usage: usage(), at: expiry.addingTimeInterval(-600))
        let attempt = ResetExpiryEvent(resetAttempted: true, timestamp: expiry.addingTimeInterval(-600),
            event: "reset_attempt", profileID: profile.id, creditID: "fixture-credit", idempotencyKey: UUID().uuidString)
        history.append(attempt)
        tracker = AutoReset(history: history)
        #expect(tracker.nextCheckpoint(accountIDs: [profile.id]) == nil)
        #expect(tracker.observe(profile: profile, usage: usage(), at: expiry.addingTimeInterval(-300)).isEmpty)
        history.append(ResetExpiryEvent(timestamp: expiry.addingTimeInterval(-599), event: "reset_result",
            profileID: profile.id, error: "HTTP 503", creditID: "fixture-credit"))
        #expect(AutoReset(history: history).nextCheckpoint(accountIDs: [profile.id]) == nil)
        history[history.count - 1].error = nil
        history[history.count - 1].outcome = .reset
        #expect(AutoReset(history: history).nextCheckpoint(accountIDs: [profile.id]) == nil)
        history[history.count - 1].outcome = .nothingToReset
        tracker = AutoReset(history: history)
        #expect(tracker.nextCheckpoint(accountIDs: [profile.id]) == expiry.addingTimeInterval(-300))
        #expect(tracker.observe(profile: profile, usage: usage(), at: expiry.addingTimeInterval(-300)).last?.decision == "attempt")
    }
}
