import Foundation
import Testing
@testable import SwitcherCore

struct WeeklyUsageAutoStartTests {
    private let expiry = Date(timeIntervalSince1970: 2_000_000_000)
    private let week: TimeInterval = 7 * 24 * 60 * 60
    private let confirmationDelay = WeeklyUsageAutoStartState.confirmationDelay

    @Test func attemptsOnlyAfterNaturalExpiryAndKeepsAttemptAcrossRestart() throws {
        var state = WeeklyUsageAutoStartState()
        let beforeExpiry = expiry.addingTimeInterval(-60)
        #expect(state.observe(window(used: 37, resetsAt: expiry), at: beforeExpiry) == nil)
        #expect(state.nextCheckAt(after: beforeExpiry) == expiry)

        #expect(state.observe(estimate(at: expiry), at: expiry) == nil)
        let confirmationAt = expiry.addingTimeInterval(confirmationDelay)
        #expect(state.nextCheckAt(after: expiry) == confirmationAt)
        #expect(state.nextCheckAt(after: confirmationAt) == confirmationAt.addingTimeInterval(confirmationDelay))
        #expect(state.observe(estimate(at: confirmationAt), at: confirmationAt) == expiry)
        let didAttempt = state.markAttempt(for: expiry)
        #expect(didAttempt)

        let persisted = try JSONEncoder().encode(state)
        var restarted = try JSONDecoder().decode(WeeklyUsageAutoStartState.self, from: persisted)
        let firstPoll = confirmationAt.addingTimeInterval(300)
        #expect(restarted.observe(estimate(at: firstPoll), at: firstPoll) == nil)
        #expect(restarted.nextCheckAt(after: firstPoll) == nil)
        let duplicateAttempt = restarted.markAttempt(for: expiry)
        let unrelatedAttempt = restarted.markAttempt(for: firstPoll)
        #expect(!duplicateAttempt)
        #expect(!unrelatedAttempt)
        let nextPoll = firstPoll.addingTimeInterval(300)
        #expect(restarted.observe(estimate(at: nextPoll), at: nextPoll) == nil)

        let followingExpiry = nextPoll.addingTimeInterval(week)
        #expect(restarted.observe(window(used: 0.25, resetsAt: followingExpiry), at: nextPoll) == nil)
        #expect(restarted.nextCheckAt(after: nextPoll) == followingExpiry)
        #expect(restarted.observe(estimate(at: followingExpiry), at: followingExpiry) == nil)
        let followingConfirmation = followingExpiry.addingTimeInterval(confirmationDelay)
        #expect(restarted.observe(estimate(at: followingConfirmation), at: followingConfirmation) == followingExpiry)
    }

    @Test func continuouslyFullWithoutAKnownExpiryNeverSends() {
        var state = WeeklyUsageAutoStartState()
        let first = expiry.addingTimeInterval(-300)
        for time in [first, expiry, expiry.addingTimeInterval(300)] {
            #expect(state.observe(estimate(at: time), at: time) == nil)
            #expect(state.nextCheckAt(after: time) == nil)
        }
    }

    @Test func manuallyStartedWindowIsRecognizedWhenUsageRoundsToZero() {
        var state = WeeklyUsageAutoStartState()
        let beforeExpiry = expiry.addingTimeInterval(-60)
        #expect(state.observe(window(used: 30, resetsAt: expiry), at: beforeExpiry) == nil)
        #expect(state.observe(estimate(at: expiry), at: expiry) == nil)

        let manualStart = expiry.addingTimeInterval(5)
        let fixedReset = manualStart.addingTimeInterval(week)
        let firstPoll = expiry.addingTimeInterval(confirmationDelay)
        let secondPoll = firstPoll.addingTimeInterval(confirmationDelay)
        #expect(state.observe(window(used: 0, resetsAt: fixedReset), at: firstPoll) == nil)
        #expect(state.observe(window(used: 0, resetsAt: fixedReset), at: secondPoll) == nil)
        #expect(state.nextCheckAt(after: secondPoll) == fixedReset)
    }

    @Test func repeatedEstimateKeepsTheKnownExpiredBoundary() {
        var state = WeeklyUsageAutoStartState()
        #expect(state.observe(window(used: 30, resetsAt: expiry), at: expiry.addingTimeInterval(-60)) == nil)
        #expect(state.observe(estimate(at: expiry), at: expiry) == nil)
        let repeatedAt = expiry.addingTimeInterval(confirmationDelay)
        #expect(state.observe(estimate(at: expiry), at: repeatedAt) == nil)

        let freshAt = repeatedAt.addingTimeInterval(confirmationDelay)
        #expect(state.observe(estimate(at: freshAt), at: freshAt) == nil)
        let confirmation = freshAt.addingTimeInterval(confirmationDelay)
        #expect(state.observe(estimate(at: confirmation), at: confirmation) == expiry)
    }

    @Test func dispatchRequiresTheLiveWeeklyWindowToStillBeFullAndUnstarted() {
        var state = WeeklyUsageAutoStartState()
        let beforeExpiry = expiry.addingTimeInterval(-60)
        #expect(state.observe(window(used: 30, resetsAt: expiry), at: beforeExpiry) == nil)
        #expect(!state.canDispatch(estimate(at: beforeExpiry), after: expiry, at: beforeExpiry))
        #expect(state.observe(estimate(at: expiry), at: expiry) == nil)
        let confirmation = expiry.addingTimeInterval(confirmationDelay)
        #expect(state.observe(estimate(at: confirmation), at: confirmation) == expiry)

        let quickRead = confirmation.addingTimeInterval(1)
        let finalRead = confirmation.addingTimeInterval(10)
        let fixedReset = confirmation.addingTimeInterval(week)
        #expect(state.canDispatch(estimate(at: confirmation), after: expiry, at: quickRead))
        #expect(state.canDispatch(estimate(at: finalRead), after: expiry, at: finalRead))
        #expect(!state.canDispatch(window(used: 0, resetsAt: fixedReset), after: expiry, at: finalRead))
        #expect(!state.canDispatch(window(used: 0, resetsAt: fixedReset.addingTimeInterval(-1)),
            after: expiry, at: quickRead))
        #expect(!state.canDispatch(window(used: 0.01, resetsAt: finalRead.addingTimeInterval(week)),
            after: expiry, at: finalRead))
        #expect(!state.canDispatch(window(used: 0, resetsAt: finalRead.addingTimeInterval(week), duration: 300),
            after: expiry, at: finalRead))
        #expect(!state.canDispatch(estimate(at: finalRead), after: beforeExpiry, at: finalRead))

        let didAttempt = state.markAttempt(for: expiry)
        #expect(didAttempt)
        #expect(!state.canDispatch(estimate(at: finalRead), after: expiry, at: finalRead))
    }

    @Test func detectsAnActiveZeroUseWindowFromAStableResetDate() {
        var state = WeeklyUsageAutoStartState()
        let first = expiry.addingTimeInterval(-300)
        let second = first.addingTimeInterval(confirmationDelay)
        let reading = window(used: 0, resetsAt: expiry)
        #expect(state.observe(reading, at: first) == nil)
        #expect(state.nextCheckAt(after: first) == nil)
        #expect(state.observe(reading, at: second) == nil)
        #expect(state.nextCheckAt(after: second) == expiry)
    }

    @Test func quicklyConfirmsTheFixedDateAfterAZeroUseStart() {
        var state = WeeklyUsageAutoStartState()
        let beforeExpiry = expiry.addingTimeInterval(-60)
        #expect(state.observe(window(used: 30, resetsAt: expiry), at: beforeExpiry) == nil)
        #expect(state.observe(estimate(at: expiry), at: expiry) == nil)
        let startedAt = expiry.addingTimeInterval(confirmationDelay)
        #expect(state.observe(estimate(at: startedAt), at: startedAt) == expiry)
        let didAttempt = state.markAttempt(for: expiry)
        #expect(didAttempt)

        let readbackAt = startedAt.addingTimeInterval(6)
        let fixedReset = startedAt.addingTimeInterval(week)
        let readback = window(used: 0, resetsAt: fixedReset)
        #expect(state.observe(readback, at: readbackAt) == nil)
        let confirmation = readbackAt.addingTimeInterval(confirmationDelay)
        #expect(state.nextCheckAt(after: readbackAt) == confirmation)
        #expect(state.observe(readback, at: confirmation) == nil)
        #expect(state.nextCheckAt(after: confirmation) == fixedReset)
    }

    @Test func resetObservedBeforeDueClearsTheOldBoundary() {
        var state = WeeklyUsageAutoStartState()
        let beforeExpiry = expiry.addingTimeInterval(-300)
        #expect(state.observe(window(used: 37, resetsAt: expiry), at: beforeExpiry) == nil)
        let earlyReset = expiry.addingTimeInterval(-60)
        #expect(state.observe(estimate(at: earlyReset), at: earlyReset) == nil)
        #expect(state.nextCheckAt(after: earlyReset) == nil)
        #expect(state.observe(estimate(at: expiry), at: expiry) == nil)
    }

    @Test func ignoresLookalikeDurationsAndWaitsForFreshReadAfterExpiry() {
        var state = WeeklyUsageAutoStartState()
        let beforeExpiry = expiry.addingTimeInterval(-300)
        #expect(state.observe(window(used: 37, resetsAt: expiry, duration: 6 * 24 * 60), at: beforeExpiry) == nil)
        #expect(state.nextCheckAt(after: beforeExpiry) == nil)
        #expect(state.observe(window(used: 37, resetsAt: expiry), at: beforeExpiry) == nil)
        #expect(state.observe(window(used: 0, resetsAt: expiry), at: expiry) == nil)
        #expect(state.nextCheckAt(after: expiry) == expiry.addingTimeInterval(confirmationDelay))
        #expect(state.nextCheckAt(after: expiry.addingTimeInterval(60)) == nil)

        let wake = expiry.addingTimeInterval(3600)
        #expect(state.observe(estimate(at: wake), at: wake) == nil)
        let confirmation = wake.addingTimeInterval(confirmationDelay)
        #expect(state.nextCheckAt(after: wake) == confirmation)
        #expect(state.observe(estimate(at: confirmation), at: confirmation) == expiry)
    }

    private func estimate(at date: Date) -> RateLimitWindow {
        window(used: 0, resetsAt: date.addingTimeInterval(week))
    }

    private func window(used: Double, resetsAt: Date, duration: Int = 7 * 24 * 60) -> RateLimitWindow {
        RateLimitWindow(usedPercent: used, windowDurationMins: duration, resetsAt: resetsAt.timeIntervalSince1970)
    }
}
