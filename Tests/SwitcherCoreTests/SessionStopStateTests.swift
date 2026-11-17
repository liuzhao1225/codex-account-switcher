import Foundation
import Testing
@testable import SwitcherCore

struct SessionStopStateTests {
    @Test func lateExitAfterStopTimeoutIsRecognized() async {
        let probe = StopProbe()
        let state = SessionStopState()
        #expect(await state.stop(isRunning: { probe.running }, terminate: { probe.attempt() }) == false)
        probe.exit()
        #expect(await state.stop(isRunning: { probe.running }, terminate: { probe.attempt() }))
        #expect(probe.attempts == 1)
    }

    @Test func failedTerminationCanBeRetried() async {
        let second = StopProbe()
        let retry = SessionStopState()
        #expect(await retry.stop(isRunning: { second.running }, terminate: { second.attempt() }) == false)
        #expect(await retry.stop(isRunning: { second.running }, terminate: { second.attempt(exits: true) }))
        #expect(second.attempts == 2)
    }

    @Test func cleanupFailureDoesNotHideCancellation() async {
        await #expect(throws: CancellationError.self) {
            try await SessionFailure.finish(CodexClientError.connectionClosed, cancelled: true) {
                throw CodexClientError.timeout
            }
        }
        await #expect(throws: CodexClientError.timeout) {
            try await SessionFailure.finish(CodexClientError.connectionClosed, cancelled: false) {
                throw CodexClientError.timeout
            }
        }
    }
}

private final class StopProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var alive = true
    private var count = 0
    var running: Bool { lock.withLock { alive } }
    var attempts: Int { lock.withLock { count } }
    func exit() { lock.withLock { alive = false } }
    func attempt(exits: Bool = false) -> Bool {
        lock.withLock { count += 1; if exits { alive = false }; return !alive }
    }
}
