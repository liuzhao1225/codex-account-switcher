import Foundation
import Testing
@testable import CodexAccountSwitcher

struct CodexClientTests {
    @Test func keepsCodexQuotaSeparateFromOtherMeteredBuckets() async throws {
        let fixture = try ScriptFixture(body: #"""
        while IFS= read -r line; do
          case "$line" in
            *initialized*) ;;
            *initialize*) printf '%s\n' '{"id":0,"result":{}}' ;;
            *rateLimits*) printf '%s\n' '{"id":1,"result":{"rateLimits":{"secondary":{"usedPercent":50,"windowDurationMins":10080,"resetsAt":100}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":10,"windowDurationMins":300,"resetsAt":100},"secondary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":100}},"other-product":{"primary":{"usedPercent":99,"windowDurationMins":300,"resetsAt":100},"secondary":{"usedPercent":95,"windowDurationMins":11520,"resetsAt":100}}}}}' ;;
          esac
        done
        """#)
        defer { fixture.remove() }
        let client = CodexClient(locator: .init(explicitURL: fixture.executable), requestTimeout: .seconds(2))
        let usage = try await client.readWeeklyUsage(profileHome: fixture.root)
        #expect(usage.remainingPercent == 80)
        #expect(usage.fiveHourRemainingPercent == 90)
    }

    @Test func preservesFinalResponseWithoutNewline() async throws {
        let fixture = try ScriptFixture(body: #"""
        while IFS= read -r line; do
          case "$line" in
            *initialized*) ;;
            *initialize*) printf '%s\n' '{"id":0,"result":{}}' ;;
            *account*read*) printf '%s' '{"id":1,"result":{"account":{"accountId":"last-response"}}}'; exit 0 ;;
          esac
        done
        """#)
        defer { fixture.remove() }
        let client = CodexClient(locator: .init(explicitURL: fixture.executable), requestTimeout: .seconds(2))
        #expect(try await client.readIdentity(profileHome: fixture.root).accountID == "last-response")
    }

    @Test func waitsForStderrThatArrivesAfterStdoutEOF() async throws {
        let fixture = try ScriptFixture(body: #"""
        read -r line
        exec 1>&-
        sleep 0.05
        printf '%s\n' 'Delayed stderr: unsupported protocol' >&2
        exit 42
        """#)
        defer { fixture.remove() }
        let client = CodexClient(locator: .init(explicitURL: fixture.executable), requestTimeout: .seconds(2))
        do {
            _ = try await client.readIdentity(profileHome: fixture.root)
            Issue.record("Expected runtime failure")
        } catch {
            #expect(error.localizedDescription.contains("Delayed stderr: unsupported protocol"))
        }
    }

    @Test func stderrCompletionStillHonorsRequestTimeout() async throws {
        let fixture = try ScriptFixture(body: #"""
        read -r line
        exec 1>&-
        sleep 2
        """#)
        defer { fixture.remove() }
        let client = CodexClient(locator: .init(explicitURL: fixture.executable), requestTimeout: .milliseconds(50))
        await #expect(throws: CodexClientError.timeout) { try await client.readIdentity(profileHome: fixture.root) }
    }

    @Test func includesSubprocessFailureReason() async throws {
        let fixture = try ScriptFixture(body: #"""
        read -r line
        printf '%s\n' 'Test runtime: unsupported protocol' >&2
        exit 42
        """#)
        defer { fixture.remove() }
        let client = CodexClient(locator: .init(explicitURL: fixture.executable), requestTimeout: .seconds(2))
        do {
            _ = try await client.readIdentity(profileHome: fixture.root)
            Issue.record("Expected runtime failure")
        } catch {
            #expect(error.localizedDescription.contains("unsupported protocol"))
        }
    }

    @Test func ignoresErrorsForOtherRequestIDs() async throws {
        let fixture = try ScriptFixture(body: #"""
        while IFS= read -r line; do
          case "$line" in
            *initialized*) ;;
            *initialize*) printf '%s\n' '{"id":0,"result":{}}' ;;
            *account*read*)
              printf '%s\n' '{"id":99,"error":{"code":-1,"message":"other request"}}'
              printf '%s\n' '{"id":1,"result":{"account":{"accountId":"expected"}}}' ;;
          esac
        done
        """#)
        defer { fixture.remove() }
        let client = CodexClient(locator: .init(explicitURL: fixture.executable), requestTimeout: .seconds(2))
        #expect(try await client.readIdentity(profileHome: fixture.root).accountID == "expected")
    }

    @Test func numericWindowRejectsOverflowAndFractionInsteadOfCrashingOrTruncating() throws {
        for number in ["1e100", "300.5"] {
            let value = try JSONDecoder().decode(JSONValue.self, from: Data(number.utf8))
            #expect(value.intValue == nil)
        }
    }

    @Test func usesDesktopRuntimeOverrideBeforeBundledCLI() throws {
        let fixture = try ScriptFixture(body: "exit 0")
        defer { fixture.remove() }
        let located = try CodexExecutableLocator().locate(environment: [
            "CODEX_CLI_PATH": fixture.executable.path,
        ])
        #expect(located == fixture.executable)
    }

    @Test func resolvesSystemCommandFromPATHWithoutSwitcherSpecificOverride() throws {
        let fixture = try ScriptFixture(body: "exit 0")
        defer { fixture.remove() }
        #expect(try CodexExecutableLocator().locate(environment: [
            "CODEX_CLI_PATH": fixture.executable.lastPathComponent,
            "PATH": fixture.executable.deletingLastPathComponent().path,
            "CODEX_SWITCHER_CODEX_PATH": "/bin/sh",
        ]) == fixture.executable)
        #expect(throws: CodexClientError.self) {
            try CodexExecutableLocator().locate(environment: ["PATH": "/nonexistent"])
        }
    }

    @Test func invalidDesktopOverrideDoesNotSilentlyUseAnotherRuntime() throws {
        #expect(throws: CodexClientError.self) {
            try CodexExecutableLocator().locate(environment: [
                "CODEX_CLI_PATH": "/nonexistent/codex-switcher-test",
            ])
        }
    }

    @Test func performsHandshakeBeforeReadingFiveHourAndWeeklyUsage() async throws {
        let fixture = try ScriptFixture(body: """
        state=0
        while IFS= read -r line; do
          case "$line" in
            *initialized*)
              test "$state" -eq 1 || exit 11
              state=2
              ;;
            *initialize*)
              state=1
              printf '%s\n' '{"id":0,"result":{}}'
              ;;
            *rateLimits*)
              test "$state" -eq 2 || exit 12
              printf '%s\n' '{"id":1,"result":{"rateLimits":{"primary":{"usedPercent":80,"windowDurationMins":300,"resetsAt":100},"secondary":{"usedPercent":58,"windowDurationMins":10080,"resetsAt":1750000000}}}}'
              ;;
          esac
        done
        """)
        defer { fixture.remove() }
        let client = CodexClient(
            locator: CodexExecutableLocator(explicitURL: fixture.executable),
            requestTimeout: .seconds(2)
        )

        let usage = try await client.readWeeklyUsage(profileHome: fixture.root)
        #expect(usage.remainingPercent == 42)
        #expect(usage.resetsAt == Date(timeIntervalSince1970: 1_750_000_000))
        #expect(usage.fiveHourRemainingPercent == 20)
        #expect(usage.fiveHourResetsAt == Date(timeIntervalSince1970: 100))
    }

    @Test func decodesAccountIdentity() async throws {
        let fixture = try ScriptFixture(body: """
        while IFS= read -r line; do
          case "$line" in
            *initialized*) ;;
            *initialize*) printf '%s\n' '{"id":0,"result":{}}' ;;
            *account*read*) printf '%s\n' '{"id":1,"result":{"account":{"type":"chatgpt","email":"user@example.com","accountId":"acct-123"},"requiresOpenaiAuth":true}}' ;;
          esac
        done
        """)
        defer { fixture.remove() }
        let client = CodexClient(
            locator: CodexExecutableLocator(explicitURL: fixture.executable),
            requestTimeout: .seconds(2)
        )

        let identity = try await client.readIdentity(profileHome: fixture.root)
        #expect(identity == AccountIdentity(accountID: "acct-123", email: "user@example.com"))
    }

    @Test func surfacesMalformedJSON() async {
        let fixture = try! ScriptFixture(body: """
        while IFS= read -r line; do
          printf '%s\n' 'malformed'
        done
        """)
        defer { fixture.remove() }
        let client = CodexClient(
            locator: CodexExecutableLocator(explicitURL: fixture.executable),
            requestTimeout: .seconds(2)
        )

        do {
            _ = try await client.readIdentity(profileHome: fixture.root)
            Issue.record("Malformed JSON should fail")
        } catch let error as CodexClientError {
            #expect(error == .malformedResponse)
        } catch {
            Issue.record("Expected CodexClientError, got \(error)")
        }
    }

    @Test func timesOutWithoutRetrying() async throws {
        let fixture = try ScriptFixture(body: """
        while IFS= read -r line; do
          case "$line" in
            *initialized*) ;;
            *initialize*) printf '%s\n' '{"id":0,"result":{}}' ;;
            *account*read*) sleep 5 ;;
          esac
        done
        """)
        defer { fixture.remove() }
        let client = CodexClient(
            locator: CodexExecutableLocator(explicitURL: fixture.executable),
            requestTimeout: .milliseconds(50)
        )

        do {
            _ = try await client.readIdentity(profileHome: fixture.root)
            Issue.record("The request should time out")
        } catch let error as CodexClientError {
            #expect(error == .timeout)
        } catch {
            Issue.record("Expected CodexClientError, got \(error)")
        }
    }
}

private struct ScriptFixture {
    let root: URL
    let executable: URL

    init(body: String) throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "codex-client-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        executable = root.appending(path: "fake-codex")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
