import Testing

@testable import CodexAccountSwitcher

@Suite("Desktop launch environment")
struct DesktopLaunchEnvironmentTests {
    @Test("parses environment variables")
    func parsesEnvironmentVariables() {
        let environment = DesktopLaunchEnvironment.parse(
            """
            all_proxy=http://127.0.0.1:7890
            HTTPS_PROXY=http://127.0.0.1:7890
            TOKEN=a=b=c
            """
        )

        #expect(
            environment["all_proxy"]
                == "http://127.0.0.1:7890"
        )
        #expect(
            environment["HTTPS_PROXY"]
                == "http://127.0.0.1:7890"
        )
        #expect(environment["TOKEN"] == "a=b=c")
    }

    @Test("ignores comments, blank lines, and malformed entries")
    func ignoresInvalidEntries() {
        let environment = DesktopLaunchEnvironment.parse(
            """
            # proxy configuration

            INVALID
            =missing-key
            http_proxy=http://localhost:7890
            """
        )

        #expect(environment.count == 1)
        #expect(
            environment["http_proxy"]
                == "http://localhost:7890"
        )
    }
}