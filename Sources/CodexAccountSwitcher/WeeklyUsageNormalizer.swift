import Foundation

struct RateLimitWindow: Codable, Equatable, Sendable {
    let usedPercent: Double
    let windowDurationMins: Int
    let resetsAt: TimeInterval
}

enum WeeklyUsageNormalizer {
    static let minimumWeeklyMinutes = 6 * 24 * 60
    static let maximumWeeklyMinutes = 8 * 24 * 60

    static func normalize(_ windows: [RateLimitWindow]) throws -> WeeklyUsage {
        guard let weekly = windows
            .filter({ minimumWeeklyMinutes...maximumWeeklyMinutes ~= $0.windowDurationMins })
            .max(by: { $0.windowDurationMins < $1.windowDurationMins })
        else {
            throw CodexClientError.weeklyUsageUnavailable
        }

        let remaining = Int((100 - weekly.usedPercent).rounded())
        return WeeklyUsage(
            remainingPercent: min(100, max(0, remaining)),
            resetsAt: Date(timeIntervalSince1970: weekly.resetsAt)
        )
    }
}
