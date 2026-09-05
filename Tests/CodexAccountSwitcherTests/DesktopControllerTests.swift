import Foundation
import Testing
@testable import CodexAccountSwitcher

struct DesktopControllerTests {
    @Test func allowsHistoryFlushToTakeLongerThanTwoSeconds() async throws {
        let clock = ContinuousClock()
        let exitsAt = clock.now.advanced(by: .milliseconds(2_100))
        try await DesktopQuitWaiter().wait { clock.now < exitsAt }
        #expect(clock.now >= exitsAt)
    }

    @Test func reportsTimeoutWhileDesktopStillRuns() async {
        do {
            try await DesktopQuitWaiter(timeout: .milliseconds(10)).wait { true }
            Issue.record("Expected quit timeout")
        } catch DesktopControllerError.didNotExit {
            // No force-quit or credential mutation is available to the waiter.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func returnsImmediatelyWhenDesktopHasExited() async throws {
        try await DesktopQuitWaiter(timeout: .zero).wait { false }
    }

    @Test func cancellationStopsWaiting() async {
        let task = Task { try await DesktopQuitWaiter().wait { true } }
        task.cancel()
        do {
            try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
