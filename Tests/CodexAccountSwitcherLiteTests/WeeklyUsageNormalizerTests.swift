import Foundation
import Testing
@testable import CodexAccountSwitcherLite

struct WeeklyUsageNormalizerTests {
    @Test func selectsLongestWeeklyWindowAndCalculatesRemaining() throws {
        let reset = Date(timeIntervalSince1970: 1_750_000_000)
        let result = try WeeklyUsageNormalizer.normalize([
            RateLimitWindow(usedPercent: 1, windowDurationMins: 300, resetsAt: 10),
            RateLimitWindow(usedPercent: 58, windowDurationMins: 7 * 24 * 60, resetsAt: reset.timeIntervalSince1970),
            RateLimitWindow(usedPercent: 20, windowDurationMins: 6 * 24 * 60, resetsAt: 20),
        ])
        #expect(result.remainingPercent == 42)
        #expect(result.resetsAt == reset)
    }

    @Test func acceptsSixThroughEightDayWindows() throws {
        for days in [6, 7, 8] {
            let result = try WeeklyUsageNormalizer.normalize([
                RateLimitWindow(usedPercent: 25, windowDurationMins: days * 24 * 60, resetsAt: 50),
            ])
            #expect(result.remainingPercent == 75, "days: \(days)")
        }
    }

    @Test func rejectsShortWindows() {
        #expect(throws: CodexClientError.weeklyUsageUnavailable) {
            try WeeklyUsageNormalizer.normalize([
                RateLimitWindow(usedPercent: 25, windowDurationMins: 5 * 60, resetsAt: 50),
                RateLimitWindow(usedPercent: 25, windowDurationMins: 24 * 60, resetsAt: 50),
            ])
        }
    }

    @Test func clampsRemainingPercent() throws {
        for (usedPercent, expected) in [(-5.0, 100), (125.0, 0)] {
            let result = try WeeklyUsageNormalizer.normalize([
                RateLimitWindow(usedPercent: usedPercent, windowDurationMins: 7 * 24 * 60, resetsAt: 50),
            ])
            #expect(result.remainingPercent == expected, "used percent: \(usedPercent)")
        }
    }
}
