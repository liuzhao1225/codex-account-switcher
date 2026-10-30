import Foundation

public struct BankedResetCredit: Codable, Equatable, Sendable {
    public let id: String
    public let status: String
    public let resetType: String
    public let expiresAt: Date?

    public init(id: String, status: String, resetType: String, expiresAt: Date?) {
        self.id = id
        self.status = status
        self.resetType = resetType
        self.expiresAt = expiresAt
    }
}

struct ResetExpiryEvent: Codable, Sendable {
    var mode = "live"
    var resetAttempted = false
    var timestamp: Date
    let event: String
    var profileID: UUID?
    var account: String?
    var usage: WeeklyUsage?
    var error: String?
    var creditID: String?
    var expiresAt: Date?
    var checkpointMinutes: Int?
    var scheduledAt: Date?
    var delaySeconds: Double?
    var decision: String?
    var idempotencyKey: String?
    var outcome: ResetCreditOutcome?

    var creditKey: String? {
        guard let profileID, let creditID else { return nil }
        return "\(profileID)/\(creditID)"
    }

    var checkpointKey: String? {
        guard let profileID, let creditID, let expiresAt, let checkpointMinutes else { return nil }
        return "\(profileID)/\(creditID)/\(expiresAt.timeIntervalSince1970)/\(checkpointMinutes)"
    }
}

/// Schedules fresh reads and tracks real attempts across application restarts.
struct AutoReset {
    let generation = UUID()
    static let checkpoints = [10, 5, 1]
    private var latestUsage: [UUID: WeeklyUsage] = [:]
    private var completed: Set<String> = []
    private var stoppedCredits: Set<String> = []

    init(history: [ResetExpiryEvent]) {
        for event in history {
            if let id = event.profileID, let usage = event.usage, usage.resetCredits != nil {
                latestUsage[id] = usage
            }
            guard event.mode == "live" else { continue }
            if let key = event.checkpointKey { completed.insert(key) }
            recordAttempt(event)
        }
    }

    func nextCheckpoint(accountIDs: Set<UUID>) -> Date? {
        latestUsage.filter { accountIDs.contains($0.key) }.flatMap { id, usage in
            (usage.resetCredits ?? []).flatMap { credit -> [Date] in
                guard credit.status == "available", credit.resetType == "codexRateLimits",
                      let expiry = credit.expiresAt,
                      !stoppedCredits.contains("\(id)/\(credit.id)") else { return [] }
                return Self.checkpoints.compactMap { minutes in
                    let event = checkpoint(profileID: id, credit: credit, minutes: minutes, at: expiry)
                    return completed.contains(event.checkpointKey!) ? nil : event.scheduledAt
                }
            }
        }.min()
    }

    mutating func observe(
        profile: AccountProfile, usage: WeeklyUsage?, error: String? = nil, at now: Date
    ) -> [ResetExpiryEvent] {
        var events = [ResetExpiryEvent(timestamp: now, event: usage == nil ? "read_failed" : "snapshot",
            profileID: profile.id, account: profile.displayName, usage: usage, error: error)]
        let previous = latestUsage[profile.id]?.resetCredits ?? []
        let current = usage?.resetCredits ?? []
        let currentIDs = Set(current.map(\.id))
        let candidates = current + previous.filter { !currentIDs.contains($0.id) }
        for credit in candidates {
            guard credit.resetType == "codexRateLimits", let expiry = credit.expiresAt,
                  !stoppedCredits.contains("\(profile.id)/\(credit.id)") else { continue }
            for (index, minutes) in Self.checkpoints.enumerated() {
                var event = checkpoint(profileID: profile.id, credit: credit, minutes: minutes, at: now)
                guard let key = event.checkpointKey, !completed.contains(key), now >= event.scheduledAt! else { continue }
                let nextStage = index + 1 < Self.checkpoints.count
                    ? expiry.addingTimeInterval(-Double(Self.checkpoints[index + 1] * 60)) : expiry
                event.account = profile.displayName
                event.usage = usage
                event.error = error
                if now >= nextStage { event.decision = "missed" }
                else if usage == nil { event.decision = "read_failed" }
                else if usage?.resetCredits == nil { event.decision = "details_unavailable" }
                else if !currentIDs.contains(credit.id) || credit.status != "available" {
                    event.decision = "credit_unavailable"
                } else {
                    event.decision = "attempt"
                }
                events.append(event)
                completed.insert(key)
            }
        }
        // Unknown details retain only the old schedule; checkpoint decisions still require a fresh read.
        if let usage { updateUsage(usage, profileID: profile.id) }
        return events
    }

    mutating func updateUsage(_ usage: WeeklyUsage, profileID: UUID) {
        if usage.resetCredits != nil { latestUsage[profileID] = usage }
    }

    mutating func recordAttempt(_ event: ResetExpiryEvent) {
        guard let key = event.creditKey else { return }
        if event.event == "reset_attempt" {
            stoppedCredits.insert(key)
        } else if event.event == "reset_result", event.outcome == .nothingToReset {
            stoppedCredits.remove(key)
        }
    }

    private func checkpoint(profileID: UUID, credit: BankedResetCredit, minutes: Int, at now: Date) -> ResetExpiryEvent {
        let scheduled = credit.expiresAt!.addingTimeInterval(-Double(minutes * 60))
        return ResetExpiryEvent(timestamp: now, event: "checkpoint", profileID: profileID,
            creditID: credit.id, expiresAt: credit.expiresAt, checkpointMinutes: minutes,
            scheduledAt: scheduled, delaySeconds: max(0, now.timeIntervalSince(scheduled)))
    }
}
