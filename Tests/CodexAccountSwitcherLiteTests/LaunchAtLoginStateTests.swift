import ServiceManagement
import Testing
@testable import CodexAccountSwitcherLite

struct LaunchAtLoginStateTests {
    @Test func mapsEveryServiceManagementStatus() {
        #expect(LaunchAtLoginState(status: .notRegistered) == .disabled)
        #expect(LaunchAtLoginState(status: .enabled) == .enabled)
        #expect(LaunchAtLoginState(status: .requiresApproval) == .requiresApproval)
        #expect(LaunchAtLoginState(status: .notFound) == .unavailable)
    }
}
