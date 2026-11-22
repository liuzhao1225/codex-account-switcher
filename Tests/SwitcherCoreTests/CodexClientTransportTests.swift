import Foundation
import Testing
@testable import SwitcherCore

private let fixtureExecutable: String? = {
    if let explicit = ProcessInfo.processInfo.environment["SWITCHER_TEST_RPC_EXE"], !explicit.isEmpty {
        return explicit
    }
    #if !os(Windows)
    let compilerURL = URL(fileURLWithPath: "/usr/bin/cc")
    guard FileManager.default.isExecutableFile(atPath: compilerURL.path) else { return nil }
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("switcher-posix-rpc-fixture-\(ProcessInfo.processInfo.processIdentifier)")
    let sourceURL = directory.appendingPathComponent("rpc-fixture.c")
    let binaryURL = directory.appendingPathComponent("rpc-fixture")
    let source = #"""
    #include <signal.h>
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <unistd.h>

    static void join_path(char *out, size_t cap, const char *dir, const char *name) {
        snprintf(out, cap, "%s/%s", dir, name);
    }

    static void write_file(const char *path, const char *text, const char *mode) {
        FILE *f = fopen(path, mode);
        if (f) {
            fputs(text, f);
            fclose(f);
        }
    }

    static int parse_id(const char *line, long *out_id) {
        const char *p = strstr(line, "\"id\"");
        if (!p) return 0;
        p += 4;
        while (*p == ' ' || *p == '\t') p++;
        if (*p != ':') return 0;
        p++;
        while (*p == ' ' || *p == '\t') p++;
        char *end = NULL;
        long val = strtol(p, &end, 10);
        if (end == p) return 0;
        *out_id = val;
        return 1;
    }

    static void parse_method(const char *line, char *out, size_t cap) {
        out[0] = '\0';
        const char *p = strstr(line, "\"method\"");
        if (!p) return;
        p += 8;
        while (*p == ' ' || *p == '\t') p++;
        if (*p != ':') return;
        p++;
        while (*p == ' ' || *p == '\t') p++;
        if (*p != '"') return;
        p++;
        size_t i = 0;
        while (*p && *p != '"' && i + 1 < cap) {
            if (*p == '\\' && p[1]) p++;
            out[i++] = *p++;
        }
        out[i] = '\0';
    }

    int main(void) {
        const char *home = getenv("CODEX_HOME");
        if (!home || !*home) return 1;

        char launches_path[1024], overlap_path[1024], mode_path[1024];
        char requests_path[1024], release_path[1024], exited_path[1024];
        join_path(launches_path, sizeof(launches_path), home, "launches");
        join_path(overlap_path, sizeof(overlap_path), home, "overlap");
        join_path(mode_path, sizeof(mode_path), home, "fixture-mode");
        join_path(requests_path, sizeof(requests_path), home, "requests");
        join_path(release_path, sizeof(release_path), home, "release");
        join_path(exited_path, sizeof(exited_path), home, "exited");

        FILE *lf = fopen(launches_path, "r");
        if (lf) {
            char buf[64];
            while (fgets(buf, sizeof(buf), lf)) {
                long pid = strtol(buf, NULL, 10);
                if (pid > 0 && pid != (long)getpid() && kill((pid_t)pid, 0) == 0) {
                    write_file(overlap_path, "yes", "w");
                }
            }
            fclose(lf);
        }
        lf = fopen(launches_path, "a");
        if (lf) {
            fprintf(lf, "%ld\n", (long)getpid());
            fclose(lf);
        }

        char scenario[128] = {0};
        FILE *mf = fopen(mode_path, "r");
        if (!mf) return 1;
        if (fgets(scenario, sizeof(scenario), mf)) {
            size_t len = strlen(scenario);
            while (len > 0 && (scenario[len - 1] == '\n' || scenario[len - 1] == '\r' || scenario[len - 1] == ' ')) {
                scenario[--len] = '\0';
            }
        }
        fclose(mf);

        char *line = NULL;
        size_t cap = 0;
        int thread_started = 0;
        while (getline(&line, &cap, stdin) > 0) {
            long req_id = 0;
            if (!parse_id(line, &req_id)) continue;
            char method[128];
            parse_method(line, method, sizeof(method));

            FILE *rf = fopen(requests_path, "a");
            if (rf) {
                fprintf(rf, "%s\n", method);
                fclose(rf);
            }

            if ((strcmp(scenario, "hold-initialize") == 0 && strcmp(method, "initialize") == 0) ||
                (strcmp(scenario, "hold-quota") == 0 && strcmp(method, "account/rateLimits/read") == 0) ||
                (strcmp(scenario, "hold-identity") == 0 && strcmp(method, "account/read") == 0)) {
                while (access(release_path, F_OK) != 0) {
                    usleep(10000);
                }
            }
            if (strcmp(scenario, "timeout") == 0 ||
                (strcmp(scenario, "quota-timeout") == 0 && strcmp(method, "account/rateLimits/read") == 0)) {
                continue;
            }
            if (strcmp(scenario, "exit-once") == 0 &&
                strcmp(method, "account/rateLimits/read") == 0 &&
                access(exited_path, F_OK) != 0) {
                write_file(exited_path, "yes", "w");
                free(line);
                return 0;
            }

            const char *result = "{}";
            if (strcmp(method, "account/read") == 0) {
                result = strcmp(scenario, "turn-api-key") == 0
                    ? "{\"account\":{\"type\":\"apiKey\"}}"
                    : "{\"account\":{\"type\":\"chatgpt\",\"accountId\":\"fixture\",\"email\":\"fixture@example.test\"}}";
            } else if (strcmp(method, "account/rateLimits/read") == 0) {
                if (strncmp(scenario, "turn-", 5) == 0 && (strcmp(scenario, "turn-nonfull") != 0 || !thread_started)) {
                    result = "{\"rateLimits\":{\"ordinaryUsageAllowed\":true,\"primary\":{\"usedPercent\":0,\"windowDurationMins\":10080,\"resetsAt\":2000000000}}}";
                } else {
                    result = "{\"rateLimitResetCredits\":{\"availableCount\":2},\"rateLimits\":{\"ordinaryUsageAllowed\":true,\"primary\":{\"usedPercent\":33,\"windowDurationMins\":300,\"resetsAt\":2000000000},\"secondary\":{\"usedPercent\":58,\"windowDurationMins\":10080,\"resetsAt\":2000000000}}}";
                }
            } else if (strcmp(method, "account/rateLimitResetCredit/consume") == 0) {
                result = "{\"outcome\":\"reset\"}";
            } else if (strcmp(method, "account/login/start") == 0) {
                result = "{\"authUrl\":\"https://example.test/sign-in\"}";
            } else if (strcmp(method, "thread/start") == 0) {
                if (strstr(line, "\"ephemeral\":true") && strstr(line, "\"sandbox\":\"read-only\"")) {
                    thread_started = 1;
                    result = "{\"thread\":{\"id\":\"quota-thread\"}}";
                }
            } else if (strcmp(method, "turn/start") == 0) {
                if (strstr(line, "\"threadId\":\"quota-thread\"") && strstr(line, "\"text\":\"只回复 OK\"") &&
                    strstr(line, "\"serviceTier\":\"default\"")) {
                    result = "{\"turn\":{\"id\":\"quota-turn\",\"status\":\"inProgress\"}}";
                    fputs("{\"method\":\"turn/completed\",\"params\":{\"threadId\":\"other-thread\",\"turn\":{\"id\":\"quota-turn\",\"status\":\"failed\"}}}\n", stdout);
                    fputs("{\"method\":\"turn/completed\",\"params\":{\"threadId\":\"quota-thread\",\"turn\":{\"id\":\"other-turn\",\"status\":\"failed\"}}}\n", stdout);
                    if (strcmp(scenario, "turn-timeout") != 0) {
                        const char *status = strcmp(scenario, "turn-failed") == 0 ? "failed" : "completed";
                        printf("{\"method\":\"turn/completed\",\"params\":{\"threadId\":\"quota-thread\",\"turn\":{\"id\":\"quota-turn\",\"status\":\"%s\"}}}\n", status);
                    }
                }
            }

            if (strcmp(method, "account/login/start") == 0 && strcmp(scenario, "login") == 0) {
                fputs("{\"method\":\"account/login/completed\",\"params\":{\"success\":true}}\n", stdout);
            }
            printf("{\"id\":%ld,\"result\":%s}\n", req_id, result);
            fflush(stdout);
        }
        free(line);
        return 0;
    }
    """#
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(source.utf8).write(to: sourceURL, options: .atomic)
        let compiler = Process()
        compiler.executableURL = compilerURL
        compiler.arguments = [sourceURL.path, "-O2", "-Wall", "-Werror", "-o", binaryURL.path]
        compiler.standardOutput = FileHandle.nullDevice
        compiler.standardError = FileHandle.nullDevice
        try compiler.run()
        compiler.waitUntilExit()
        guard compiler.terminationStatus == 0 else { return nil }
        return binaryURL.path
    } catch {
        return nil
    }
    #else
    return nil
    #endif
}()

@Suite(.enabled(if: fixtureExecutable != nil))
struct CodexClientTransportTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SWITCHER_TEST_INSTALLED_CLI"] != nil))
    func installedCliUsesOnlyAnIsolatedEmptyHome() async throws {
        let home = try fixtureHome("installed-cli")
        defer { try? FileManager.default.removeItem(at: home) }
        let client = CodexClient(locator: .init(explicitURL: URL(fileURLWithPath:
            ProcessInfo.processInfo.environment["SWITCHER_TEST_INSTALLED_CLI"]!)))
        do { _ = try await client.readIdentity(profileHome: home); Issue.record("An isolated home must not have a login.") }
        catch { #expect(error as? CodexClientError == .identityUnavailable) }
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("auth.json").path))
    }

    @Test func parsesIdentityAndBothUsageWindows() async throws {
        let home = try fixtureHome("normal")
        defer { try? FileManager.default.removeItem(at: home) }
        let client = makeClient()
        let identity = try await client.readIdentity(profileHome: home)
        #expect(identity.accountID == "fixture")
        let usage = try await client.readWeeklyUsage(profileHome: home)
        #expect(usage.remainingPercent == 42)
        #expect(usage.fiveHourRemainingPercent == 67)
        #expect(usage.resetCreditsRemaining == 2)
        #if os(macOS)
        #expect(usage.ordinaryUsageAllowed == true)
        #endif
        try await client.stopUsageSessions()
    }

    @Test func loginAcceptsCompletionBeforeStartResponse() async throws {
        let home = try fixtureHome("login")
        defer { try? FileManager.default.removeItem(at: home) }
        let client = makeClient()
        let identity = try await client.login(profileHome: home)
        #expect(identity.email == "fixture@example.test")
    }

    @Test func aSilentServerTimesOut() async throws {
        let home = try fixtureHome("timeout")
        defer { try? FileManager.default.removeItem(at: home) }
        let client = makeClient(timeout: .milliseconds(300))
        do {
            _ = try await client.readIdentity(profileHome: home)
            Issue.record("Expected a timeout")
        } catch { #expect(error as? CodexClientError == .timeout) }
    }

    @Test func pendingLoginCanBeCancelled() async throws {
        let home = try fixtureHome("cancel")
        defer { try? FileManager.default.removeItem(at: home) }
        let signal = BrowserSignal()
        let client = CodexClient(locator: .init(explicitURL: URL(fileURLWithPath: fixtureExecutable!)),
            openBrowser: { _ in await signal.opened() })
        let task = Task { try await client.login(profileHome: home) }
        for _ in 0..<100 {
            if await signal.isOpen { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(await signal.isOpen)
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch { #expect(error is CancellationError) }
    }

    @Test func repeatedAndConcurrentQuotaReadsReuseOneProcessPerProfile() async throws {
        let home = try fixtureHome("normal")
        let other = try fixtureHome("normal")
        defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: other) }
        let client = makeClient()
        _ = try await client.readWeeklyUsage(profileHome: home)
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<6 {
                group.addTask { try await client.readWeeklyUsage(profileHome: home).remainingPercent }
            }
            for try await remaining in group { #expect(remaining == 42) }
        }
        _ = try await client.readWeeklyUsage(profileHome: other)
        #expect(try launchCount(home) == 1)
        #expect(try launchCount(other) == 1)
        let requests = try String(contentsOf: home.appendingPathComponent("requests"), encoding: .utf8)
        #expect(requests.components(separatedBy: "initialize\n").count - 1 == 1)
        #expect(requests.components(separatedBy: "account/rateLimits/read").count - 1 == 7)
        try await client.stopUsageSessions()
    }

    @Test func credentialReplacementAndExplicitStopReopenQuotaSession() async throws {
        let home = try fixtureHome("normal")
        defer { try? FileManager.default.removeItem(at: home) }
        let client = makeClient()
        try Data("first".utf8).write(to: home.appendingPathComponent("auth.json"))
        _ = try await client.readWeeklyUsage(profileHome: home)
        try Data("replacement".utf8).write(to: home.appendingPathComponent("auth.json"))
        _ = try await client.readWeeklyUsage(profileHome: home)
        #expect(try launchCount(home) == 2)
        try await client.stopUsageSessions()
        _ = try await client.readWeeklyUsage(profileHome: home)
        #expect(try launchCount(home) == 3)
        try await client.stopUsageSessions()
    }

    @Test func failedQuotaProcessIsDiscardedAndNextReadRecovers() async throws {
        let home = try fixtureHome("exit-once")
        defer { try? FileManager.default.removeItem(at: home) }
        let client = makeClient()
        await #expect(throws: (any Error).self) { try await client.readWeeklyUsage(profileHome: home) }
        #expect(try await client.readWeeklyUsage(profileHome: home).remainingPercent == 42)
        #expect(try launchCount(home) == 2)
        try await client.stopUsageSessions()
    }

    @Test func cancelledQuotaReadStopsTheProcessAndRecovers() async throws {
        let home = try fixtureHome("quota-timeout")
        defer { try? FileManager.default.removeItem(at: home) }
        let client = makeClient()
        let read = Task { try await client.readWeeklyUsage(profileHome: home) }
        for _ in 0..<100 {
            let log = (try? String(contentsOf: home.appendingPathComponent("requests"), encoding: .utf8)) ?? ""
            if log.contains("account/rateLimits/read") { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        read.cancel()
        await #expect(throws: CancellationError.self) { try await read.value }
        try Data("normal".utf8).write(to: home.appendingPathComponent("fixture-mode"))
        #expect(try await client.readWeeklyUsage(profileHome: home).remainingPercent == 42)
        #expect(try launchCount(home) == 2)
        try await client.stopUsageSessions()
    }

    @Test(arguments: ["hold-initialize", "hold-quota"])
    func credentialReplacementDuringAnRPCIsDetected(_ mode: String) async throws {
        let home = try fixtureHome(mode)
        defer { try? FileManager.default.removeItem(at: home) }
        let client = makeClient()
        try Data("old".utf8).write(to: home.appendingPathComponent("auth.json"))
        let read = Task { try await client.readWeeklyUsage(profileHome: home) }
        try await waitForRequest(mode == "hold-initialize" ? "initialize" : "account/rateLimits/read", home: home)
        try Data("replacement".utf8).write(to: home.appendingPathComponent("auth.json"))
        try Data().write(to: home.appendingPathComponent("release"))
        _ = try await read.value
        try Data("normal".utf8).write(to: home.appendingPathComponent("fixture-mode"))
        _ = try await client.readWeeklyUsage(profileHome: home)
        #expect(try launchCount(home) == 2)
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("overlap").path))
        try await client.stopUsageSessions()
    }

    @Test func profileOperationsPreserveSiblingSessionsAndEvictRemovedProfiles() async throws {
        let home = try fixtureHome("normal")
        let sibling = try fixtureHome("normal")
        defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: sibling) }
        let client = makeClient()
        _ = try await client.readWeeklyUsage(profileHome: home)
        _ = try await client.readWeeklyUsage(profileHome: sibling)
        #expect(try await client.consumeResetCredit(profileHome: home, creditID: "test", idempotencyKey: "test") == .reset)
        _ = try await client.readWeeklyUsage(profileHome: sibling)
        #expect(try launchCount(sibling) == 1)
        #expect(await client.usageSessionCount == 2)
        try await client.forgetUsageSession(profileHome: home)
        #expect(await client.usageSessionCount == 1)
        _ = try await client.readWeeklyUsage(profileHome: home)
        #expect(await client.usageSessionCount == 2)
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("overlap").path))
        try await client.stopUsageSessions()
    }

    @Test func usageStartSendsOneEphemeralTurnInTheTargetProfile() async throws {
        let home = try fixtureHome("turn-completed")
        let sibling = try fixtureHome("normal")
        defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: sibling) }
        let client = makeClient()
        _ = try await client.readWeeklyUsage(profileHome: home)
        _ = try await client.readWeeklyUsage(profileHome: sibling)

        let started = try await client.startWeeklyUsageWindow(profileHome: home) { usage, _ in
            usage.weeklyWindow?.usedPercent == 0
        }
        #expect(started)

        let methods = try String(contentsOf: home.appendingPathComponent("requests"), encoding: .utf8)
            .split(separator: "\n")
        #expect(methods.suffix(4) == ["account/read", "thread/start", "account/rateLimits/read", "turn/start"])
        #expect(methods.filter { $0 == "turn/start" }.count == 1)
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent("overlap").path))
        _ = try await client.readWeeklyUsage(profileHome: sibling)
        #expect(try launchCount(sibling) == 1)
        try await client.stopUsageSessions()
    }

    @Test func usageStartRechecksTheSameSessionBeforeSending() async throws {
        let home = try fixtureHome("turn-nonfull")
        defer { try? FileManager.default.removeItem(at: home) }
        let client = makeClient()
        let previous = try await client.readWeeklyUsage(profileHome: home)
        #expect(previous.weeklyWindow?.usedPercent == 0)

        let started = try await client.startWeeklyUsageWindow(profileHome: home) { fresh, _ in
            #expect(fresh.weeklyWindow?.usedPercent == 58)
            return fresh.weeklyWindow?.usedPercent == 0
        }
        #expect(!started)

        let methods = try String(contentsOf: home.appendingPathComponent("requests"), encoding: .utf8)
            .split(separator: "\n")
        #expect(methods.suffix(3) == ["account/read", "thread/start", "account/rateLimits/read"])
        #expect(!methods.contains("turn/start"))
    }

    @Test(arguments: [
        ("turn-failed", CodexClientError.remoteError(code: nil, message: "The weekly usage request ended with status failed.")),
        ("turn-timeout", CodexClientError.timeout),
    ])
    func usageStartPropagatesFailureWithoutRepeatingTheTurn(_ fixture: (String, CodexClientError)) async throws {
        let (mode, expectedError) = fixture
        let home = try fixtureHome(mode)
        defer { try? FileManager.default.removeItem(at: home) }
        let client = makeClient(timeout: .seconds(2))

        await #expect(throws: expectedError) {
            _ = try await client.startWeeklyUsageWindow(profileHome: home) { _, _ in true }
        }

        let methods = try String(contentsOf: home.appendingPathComponent("requests"), encoding: .utf8)
            .split(separator: "\n")
        #expect(methods.filter { $0 == "turn/start" }.count == 1)
    }

    @Test func usageStartRequiresChatGPTAuthentication() async throws {
        let home = try fixtureHome("turn-api-key")
        defer { try? FileManager.default.removeItem(at: home) }
        let client = makeClient()

        await #expect(throws: CodexClientError.identityUnavailable) {
            _ = try await client.startWeeklyUsageWindow(profileHome: home) { _, _ in
                Issue.record("Authorization must not run for a non-ChatGPT account")
                return false
            }
        }

        let methods = try String(contentsOf: home.appendingPathComponent("requests"), encoding: .utf8)
            .split(separator: "\n")
        #expect(!methods.contains("thread/start"))
    }

    private func waitForRequest(_ method: String, home: URL) async throws {
        for _ in 0..<250 {
            let requests = (try? String(contentsOf: home.appendingPathComponent("requests"), encoding: .utf8)) ?? ""
            if requests.split(separator: "\n").contains(Substring(method)) { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw CodexClientError.timeout
    }

    @Test func timedOutQuotaSessionIsDiscarded() async throws {
        let home = try fixtureHome("quota-timeout\r\n")
        defer { try? FileManager.default.removeItem(at: home) }
        let client = makeClient(timeout: .milliseconds(500))
        do { _ = try await client.readWeeklyUsage(profileHome: home); Issue.record("Expected timeout") }
        catch { #expect(error as? CodexClientError == .timeout) }
        try Data("normal".utf8).write(to: home.appendingPathComponent("fixture-mode"))
        #expect(try await client.readWeeklyUsage(profileHome: home).remainingPercent == 42)
        #expect(try launchCount(home) == 2)
        try await client.stopUsageSessions()
    }

    @Test func unusedQuotaSessionsExpire() async throws {
        let home = try fixtureHome("normal")
        defer { try? FileManager.default.removeItem(at: home) }
        let client = CodexClient(locator: .init(explicitURL: URL(fileURLWithPath: fixtureExecutable!)),
                                 usageSessionIdleTimeout: .milliseconds(50))
        _ = try await client.readWeeklyUsage(profileHome: home)
        try await Task.sleep(for: .milliseconds(300))
        _ = try await client.readWeeklyUsage(profileHome: home)
        #expect(try launchCount(home) == 2)
        try await client.stopUsageSessions()
    }

    private func launchCount(_ home: URL) throws -> Int {
        try String(contentsOf: home.appendingPathComponent("launches"), encoding: .utf8).split(separator: "\n").count
    }

    private func makeClient(timeout: Duration = .seconds(5)) -> CodexClient {
        CodexClient(locator: .init(explicitURL: URL(fileURLWithPath: fixtureExecutable!)), requestTimeout: timeout,
            openBrowser: { url in #expect(url.host == "example.test") })
    }
    private func fixtureHome(_ scenario: String) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("switcher-rpc-test-\(UUID())")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Data(scenario.utf8).write(to: home.appendingPathComponent("fixture-mode"))
        return home
    }
}

private actor BrowserSignal {
    var isOpen = false
    func opened() { isOpen = true }
}
