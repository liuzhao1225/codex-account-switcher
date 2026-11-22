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
        if resetsAt == previous.resetsAt {
            // Small requests can round to zero. A stable reset date still means a window is active.
            confirmExpiry(resetsAt)
            return nil
        }

        zeroUseReading = current
        let movedBy = resetsAt.timeIntervalSince(previous.resetsAt)
        guard let confirmedExpiry, attemptedExpiry != confirmedExpiry,
              previous.observedAt >= confirmedExpiry, previous.isEstimate, current.isEstimate,
              abs(movedBy - elapsed) <= Self.estimateTolerance else { return nil }
        return confirmedExpiry
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
        guard let zeroUseReading else { return nil }
        // After an attempt, hurry only to confirm a candidate fixed date for the newly started window.
        let needsFastConfirmation = attemptedExpiry == confirmedExpiry
            ? !zeroUseReading.isEstimate : zeroUseReading.isEstimate
        guard needsFastConfirmation else { return nil }
        let confirmationAt = zeroUseReading.observedAt.addingTimeInterval(Self.confirmationDelay)
        return confirmationAt > now ? confirmationAt : nil
    }

    private mutating func confirmExpiry(_ expiry: Date) {
        confirmedExpiry = expiry
        zeroUseReading = nil
    }
}
