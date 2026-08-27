import Foundation

struct RateLimitWindow: Codable, Equatable, Sendable {
    let usedPercent: Double
    let windowDurationMins: Int
    let resetsAt: TimeInterval
}

enum WeeklyUsageNormalizer {
    static let fiveHourMinutes = 5 * 60
    static let minimumWeeklyMinutes = 6 * 24 * 60
    static let maximumWeeklyMinutes = 8 * 24 * 60

    static func normalize(_ windows: [RateLimitWindow]) throws -> WeeklyUsage {
        guard let weekly = windows
            .filter({ minimumWeeklyMinutes...maximumWeeklyMinutes ~= $0.windowDurationMins })
            .max(by: { $0.windowDurationMins < $1.windowDurationMins })
        else {
            throw CodexClientError.weeklyUsageUnavailable
        }

        let fiveHour = windows.first { $0.windowDurationMins == fiveHourMinutes }

        return WeeklyUsage(
            remainingPercent: remainingPercent(for: weekly),
            resetsAt: Date(timeIntervalSince1970: weekly.resetsAt),
            fiveHourRemainingPercent: fiveHour.map { remainingPercent(for: $0) },
            fiveHourResetsAt: fiveHour.map { Date(timeIntervalSince1970: $0.resetsAt) }
        )
    }

    private static func remainingPercent(for window: RateLimitWindow) -> Int {
        min(100, max(0, Int((100 - window.usedPercent).rounded())))
    }
}
