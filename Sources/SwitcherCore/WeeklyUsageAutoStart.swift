import Foundation

/// Tracks one account's current weekly window and records an attempt before any request is sent.
struct WeeklyUsageAutoStartState: Codable, Equatable, Sendable {
    static let weeklyMinutes = 7 * 24 * 60
    static let confirmationDelay: TimeInterval = 15
    private static let estimateTolerance: TimeInterval = 5
    private static let weeklySeconds = TimeInterval(weeklyMinutes * 60)

    private struct ZeroUseReading: Codable, Equatable, Sendable {
        let observedAt: Date
        let resetsAt: Date

        var isEstimate: Bool {
            abs(resetsAt.timeIntervalSince(observedAt) - WeeklyUsageAutoStartState.weeklySeconds)
                <= WeeklyUsageAutoStartState.estimateTolerance
        }

        func movesWithTime(since previous: ZeroUseReading) -> Bool {
            let elapsed = observedAt.timeIntervalSince(previous.observedAt)
            let movedBy = resetsAt.timeIntervalSince(previous.resetsAt)
            return previous.isEstimate && isEstimate && elapsed >= 0 && movedBy >= 0
                && abs(movedBy - elapsed) <= WeeklyUsageAutoStartState.estimateTolerance
        }
    }

    private var confirmedExpiry: Date?
    private var attemptedExpiry: Date?
    private var zeroUseReading: ZeroUseReading?

    mutating func resetObservations() {
        confirmedExpiry = nil
        zeroUseReading = nil
    }

    /// Returns the previous window's confirmed expiry when a new, unstarted window is observed.
    mutating func observe(_ window: RateLimitWindow, at now: Date) -> Date? {
        guard window.windowDurationMins == Self.weeklyMinutes,
              (0...100).contains(window.usedPercent), window.resetsAt.isFinite else { return nil }
        let resetsAt = Date(timeIntervalSince1970: window.resetsAt)
        guard resetsAt > now,
              resetsAt.timeIntervalSince(now) <= Self.weeklySeconds + Self.estimateTolerance else { return nil }

        if window.usedPercent > 0 {
            confirmExpiry(resetsAt)
            return nil
        }
        if resetsAt == confirmedExpiry {
            zeroUseReading = nil
            return nil
        }
        if let confirmedExpiry, now < confirmedExpiry {
            // A change before the confirmed boundary is not its natural expiry.
            resetObservations()
        }

        let current = ZeroUseReading(observedAt: now, resetsAt: resetsAt)
        guard let previous = zeroUseReading else {
            zeroUseReading = current
            return nil
        }
        let elapsed = now.timeIntervalSince(previous.observedAt)
        guard elapsed >= Self.confirmationDelay else { return nil }
        zeroUseReading = current
        if resetsAt == previous.resetsAt {
            // An estimate can briefly be cached. Require two fixed-date reads before discarding the old expiry.
            // Small requests can round to zero even when a new window is already active.
            if !previous.isEstimate { confirmExpiry(resetsAt) }
            return nil
        }

        guard let confirmedExpiry, attemptedExpiry != confirmedExpiry,
              previous.observedAt >= confirmedExpiry, current.movesWithTime(since: previous) else { return nil }
        return confirmedExpiry
    }

    func canDispatch(_ window: RateLimitWindow, after expiredAt: Date, at observedAt: Date) -> Bool {
        guard window.windowDurationMins == Self.weeklyMinutes, window.usedPercent == 0,
              window.resetsAt.isFinite, confirmedExpiry == expiredAt, attemptedExpiry != expiredAt,
              let previous = zeroUseReading, previous.observedAt >= expiredAt else { return false }
        let resetsAt = Date(timeIntervalSince1970: window.resetsAt)
        let current = ZeroUseReading(observedAt: observedAt, resetsAt: resetsAt)
        return current.movesWithTime(since: previous)
    }

    @discardableResult
    mutating func markAttempt(for expiredAt: Date) -> Bool {
        guard confirmedExpiry == expiredAt, attemptedExpiry != expiredAt else { return false }
        attemptedExpiry = expiredAt
        zeroUseReading = nil
        return true
    }

    func nextCheckAt(after now: Date) -> Date? {
        guard let confirmedExpiry else { return nil }
        if now < confirmedExpiry { return confirmedExpiry }
        let attempted = attemptedExpiry == confirmedExpiry
        // After an attempt, hurry only to confirm a candidate fixed date for the newly started window.
        if let zeroUseReading {
            let needsConfirmation = attempted ? !zeroUseReading.isEstimate : zeroUseReading.isEstimate
            let confirmationAt = zeroUseReading.observedAt.addingTimeInterval(Self.confirmationDelay)
            if needsConfirmation, confirmationAt > now { return confirmationAt }
        }
        // The service may still report the expired window when the timer first wakes.
        if !attempted, now.timeIntervalSince(confirmedExpiry) < 60 {
            return now.addingTimeInterval(Self.confirmationDelay)
        }
        return nil
    }

    private mutating func confirmExpiry(_ expiry: Date) {
        confirmedExpiry = expiry
        zeroUseReading = nil
    }
}
