import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import SwitcherCore

private actor SubscriptionRequestProbe {
    private var requests: [URLRequest] = []
    func record(_ request: URLRequest) { requests.append(request) }
    var count: Int { requests.count }
    var first: URLRequest? { requests.first }
}

private enum SubscriptionFixtureError: Error { case unavailable }

private actor SubscriptionFixtureClient: SubscriptionClient {
    var fails = false
    private(set) var calls = 0
    private var pauseNext = false
    private(set) var cancelledRequests = 0
    var authFailures: [String: Int] = [:]
    var seenTokens: [String: [String]] = [:]
    let value: LiveSubscription

    init(value: LiveSubscription) { self.value = value }
    func setFails(_ value: Bool) { fails = value }
    func pauseNextRequest() { pauseNext = true }
    func rejectAuthentication(_ accountID: String, times: Int) { authFailures[accountID] = times }
    func tokens(_ accountID: String) -> [String] { seenTokens[accountID] ?? [] }

    func readSubscription(credential: Data, expectedAccountID: String?, expectedEmail: String?) async throws -> LiveSubscription {
        calls += 1
        if pauseNext {
            pauseNext = false
            do {
                try await Task.sleep(for: .seconds(5))
            } catch is CancellationError {
                cancelledRequests += 1
                throw CancellationError()
            }
        }
        let key = expectedAccountID ?? ""
        let payload = try JSONSerialization.jsonObject(with: credential) as! [String: Any]
        seenTokens[key, default: []].append((payload["tokens"] as? [String: Any])?["access_token"] as? String ?? "")
        if (authFailures[key] ?? 0) > 0 {
            authFailures[key]! -= 1
            throw LiveSubscriptionError.unauthenticated
        }
        if fails { throw SubscriptionFixtureError.unavailable }
        return value
    }
}

private actor SubscriptionFixtureCodex: AccountClient {
    private(set) var renewalCount = 0

    func refreshIdentity(profileHome: URL) async throws -> AccountIdentity {
        renewalCount += 1
        let path = profileHome.appendingPathComponent("auth.json")
        var auth = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [String: Any]
        var tokens = auth["tokens"] as! [String: Any]
        let id = tokens["account_id"] as! String
        let encoded = (tokens["id_token"] as! String).split(separator: ".")[1]
        var b64 = String(encoded).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        let claims = try JSONSerialization.jsonObject(with: Data(base64Encoded: b64)!) as! [String: Any]
        tokens["access_token"] = "fixture-renewed"
        auth["tokens"] = tokens
        try JSONSerialization.data(withJSONObject: auth).write(to: path, options: .atomic)
        return AccountIdentity(accountID: id, email: claims["email"] as? String)
    }

    func login(profileHome: URL) async throws -> AccountIdentity { throw SubscriptionFixtureError.unavailable }
    func readIdentity(profileHome: URL) async throws -> AccountIdentity { throw SubscriptionFixtureError.unavailable }
    func readWeeklyUsage(profileHome: URL) async throws -> WeeklyUsage { throw SubscriptionFixtureError.unavailable }
    func consumeResetCredit(profileHome: URL, creditID: String, idempotencyKey: String) async throws -> ResetCreditOutcome {
        throw SubscriptionFixtureError.unavailable
    }
}

private struct SubscriptionFixtureSwitch: SwitchServicing {
    func switchAccount(to targetID: UUID) async throws { throw SubscriptionFixtureError.unavailable }
}

struct LiveSubscriptionTests {
    private let fixtureID = "subscription-fixture-account"
    private let fixtureEmail = "subscription-fixture@example.com"
    private let fixtureToken = "synthetic-access-token"

    private func makeCredential(
        accountID: String? = "subscription-fixture-account",
        claimID: String = "subscription-fixture-account",
        email: String? = "subscription-fixture@example.com",
        plan: String = "plus",
        activeUntil: String? = "2026-10-10T10:00:00Z",
        lastChecked: String? = "2026-09-10T10:00:00Z",
        accessToken: String? = "synthetic-access-token",
        idTokenOverride: String? = nil
    ) throws -> Data {
        try TestAuthFixture.authJSON(
            accountID: accountID,
            claimAccountID: claimID,
            email: email,
            planType: plan,
            subscriptionActiveUntil: activeUntil,
            subscriptionLastChecked: lastChecked,
            accessToken: accessToken,
            idTokenOverride: idTokenOverride
        )
    }

    private func makeBody(_ changes: [String: Any] = [:], removing: [String] = []) throws -> Data {
        var object: [String: Any] = [
            "active_until": "2026-11-10T10:00:00Z", "plan_type": "plus", "is_active": true,
            "will_renew": true, "is_delinquent": false,
        ]
        object.merge(changes) { _, replacement in replacement }
        for key in removing { object.removeValue(forKey: key) }
        return try JSONSerialization.data(withJSONObject: object)
    }

    @Test func readsHistoricalJWTSnapshotsWithAccountIsolationAndActiveComparison() async throws {
        let iso = ISO8601DateFormatter()
        let saved = try makeCredential(accountID: "account-a", claimID: "account-a", email: "a@example.com",
                                       activeUntil: "2026-10-17T12:00:00Z", lastChecked: "2026-10-03T12:00:00Z")
        let snapshot = SubscriptionSnapshotReader.read(credential: saved, expectedAccountID: "account-a", expectedEmail: "a@example.com")
        #expect(snapshot?.activeUntil == iso.date(from: "2026-10-17T12:00:00Z"))
        #expect(snapshot?.lastChecked == iso.date(from: "2026-10-03T12:00:00Z"))
        #expect(SubscriptionSnapshotReader.read(credential: saved, expectedAccountID: "other", expectedEmail: "a@example.com") == nil)
        #expect(SubscriptionSnapshotReader.read(credential: saved, expectedAccountID: "account-a", expectedEmail: "other@example.com") == nil)
        #expect(SubscriptionSnapshotReader.read(credential: saved, expectedAccountID: nil, expectedEmail: "A@EXAMPLE.COM") == snapshot)
        #expect(try SubscriptionSnapshotReader.read(credential: makeCredential(plan: "free"), expectedAccountID: fixtureID, expectedEmail: nil) == nil)
        #expect(try SubscriptionSnapshotReader.read(credential: makeCredential(activeUntil: nil), expectedAccountID: fixtureID, expectedEmail: nil) == nil)
        #expect(SubscriptionSnapshotReader.read(credential: Data("invalid".utf8), expectedAccountID: fixtureID, expectedEmail: nil) == nil)

        let root = FileManager.default.temporaryDirectory.appending(path: "sub-snapshot-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let activeHome = root.appending(path: "active")
        let store = AccountStore(baseURL: root.appending(path: "support"), activeHomeURL: activeHome)
        let profile = AccountProfile(id: UUID(), displayName: "A", email: "a@example.com", accountID: "account-a", createdAt: Date())
        let profileHome = await store.profileHome(id: profile.id)
        try FileManager.default.createDirectory(at: profileHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: activeHome, withIntermediateDirectories: true)
        try saved.write(to: profileHome.appending(path: "auth.json"))
        let newer = try makeCredential(accountID: "account-a", claimID: "account-a", email: "a@example.com",
                                       activeUntil: "2026-10-24T12:00:00Z", lastChecked: "2026-10-04T12:00:00Z")
        try newer.write(to: activeHome.appending(path: "auth.json"))
        #expect(await store.readSubscriptionSnapshot(profile: profile, isActive: false) == snapshot)
        #expect(await store.readSubscriptionSnapshot(profile: profile, isActive: true)?.activeUntil == iso.date(from: "2026-10-24T12:00:00Z"))
    }

    @Test func liveSubscriptionClientValidatesCredentialsHeadersResponsesAndErrors() async throws {
        let iso = ISO8601DateFormatter()
        let now = iso.date(from: "2026-10-22T12:00:00Z")!
        let expectedUntil = iso.date(from: "2026-11-10T10:00:00Z")!
        let validCredential = try makeCredential()
        let validBody = try makeBody()

        func makeClient(_ responseBody: Data = validBody, status: Int = 200,
                        responseURL: URL? = nil, probe: SubscriptionRequestProbe? = nil) -> LiveSubscriptionClient {
            LiveSubscriptionClient(transport: { request in
                await probe?.record(request)
                return (responseBody, HTTPURLResponse(url: responseURL ?? request.url!, statusCode: status,
                                                      httpVersion: "HTTP/1.1", headerFields: nil)!)
            }, now: { now })
        }

        let probe = SubscriptionRequestProbe()
        let sub = try await makeClient(probe: probe).readSubscription(
            credential: validCredential, expectedAccountID: fixtureID, expectedEmail: fixtureEmail.uppercased()
        )
        #expect(sub.activeUntil == expectedUntil)
        #expect(sub.planType == "plus" && sub.isActive && sub.willRenew == true && sub.isDelinquent == false)
        #expect(sub.fetchedAt == now)

        let req = try #require(await probe.first)
        #expect(req.httpMethod == "GET" && req.timeoutInterval == 20 && req.cachePolicy == .reloadIgnoringLocalCacheData)
        let components = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)
        #expect(components?.host == "chatgpt.com" && components?.path == "/backend-api/subscriptions")
        #expect(components?.queryItems == [URLQueryItem(name: "account_id", value: fixtureID)])
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer \(fixtureToken)")
        #expect(req.value(forHTTPHeaderField: "ChatGPT-Account-ID") == fixtureID)
        #expect(req.value(forHTTPHeaderField: "OpenAI-Beta") == "codex-1")
        #expect(req.value(forHTTPHeaderField: "User-Agent") == "codex-account-switcher/\(SwitcherVersion.current)")

        let untouched = SubscriptionRequestProbe()
        let rejectedInputs = [
            try makeCredential(accountID: "other-account"),
            try makeCredential(accountID: nil, claimID: "other-account"),
            try makeCredential(email: "other@example.com"),
            try makeCredential(email: nil),
            try makeCredential(accessToken: nil),
            try makeCredential(accessToken: "injected\r\nheader"),
            try makeCredential(idTokenOverride: "invalid-token"),
            Data("corrupt".utf8),
        ]
        for bad in rejectedInputs {
            await #expect(throws: LiveSubscriptionError.invalidCredential) {
                try await makeClient(probe: untouched).readSubscription(
                    credential: bad, expectedAccountID: fixtureID, expectedEmail: fixtureEmail
                )
            }
        }
        #expect(await untouched.count == 0)

        let invalidBodies: [Data] = [
            Data("not-json".utf8), Data("[]".utf8),
            try makeBody(["is_active": 1]), try makeBody(["plan_type": "  "]),
            try makeBody(["active_until": "bad-date"]), try makeBody(removing: ["active_until"]),
        ]
        for badBody in invalidBodies {
            await #expect(throws: LiveSubscriptionError.invalidResponse) {
                try await makeClient(badBody).readSubscription(
                    credential: validCredential, expectedAccountID: fixtureID, expectedEmail: fixtureEmail
                )
            }
        }

        let free = try await makeClient(makeBody(["plan_type": "free", "active_until": NSNull()])).readSubscription(
            credential: validCredential, expectedAccountID: fixtureID, expectedEmail: fixtureEmail
        )
        #expect(free.isActive && free.planType == "free" && free.activeUntil == nil)

        for (status, expectedError) in [
            (401, LiveSubscriptionError.unauthenticated),
            (403, .forbidden),
            (429, .rateLimited),
            (500, .serverUnavailable),
            (503, .serverUnavailable),
            (302, .redirected),
            (404, .requestFailed),
        ] {
            await #expect(throws: expectedError) {
                try await makeClient(Data("err".utf8), status: status).readSubscription(
                    credential: validCredential, expectedAccountID: fixtureID, expectedEmail: fixtureEmail
                )
            }
        }

        await #expect(throws: LiveSubscriptionError.redirected) {
            try await makeClient(responseURL: URL(string: "https://example.invalid/redirected")).readSubscription(
                credential: validCredential, expectedAccountID: fixtureID, expectedEmail: fixtureEmail
            )
        }
        await #expect(throws: LiveSubscriptionError.responseTooLarge) {
            try await makeClient(Data(repeating: 32, count: 1_048_577)).readSubscription(
                credential: validCredential, expectedAccountID: fixtureID, expectedEmail: fixtureEmail
            )
        }
        await #expect(throws: LiveSubscriptionError.timedOut) {
            try await LiveSubscriptionClient(transport: { _ in throw URLError(.timedOut) }).readSubscription(
                credential: validCredential, expectedAccountID: fixtureID, expectedEmail: fixtureEmail
            )
        }
    }

    @MainActor
    @Test func controllerRefreshesCachesPreemptsAndRenewsInactive401CredentialsSafely() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("switcher-live-sub-ctrl-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let home = root.appendingPathComponent("active")
        let support = root.appendingPathComponent("support")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)

        let active = AccountProfile(id: UUID(), displayName: "Active", email: "active@example.test", accountID: "active-fixture", createdAt: Date())
        let other = AccountProfile(id: UUID(), displayName: "Other", email: "other@example.test", accountID: "other-fixture", createdAt: Date())
        let activeCred = try makeCredential(accountID: active.accountID, claimID: active.accountID!, email: active.email, accessToken: "fixture-old")
        let otherCred = try makeCredential(accountID: other.accountID, claimID: other.accountID!, email: other.email, accessToken: "fixture-old")
        try activeCred.write(to: home.appendingPathComponent("auth.json"))

        let store = AccountStore(baseURL: support, activeHomeURL: home)
        try await store.seedActiveProfile(active)
        let otherHome = try await store.createProfileDirectory(id: other.id)
        try otherCred.write(to: otherHome.appendingPathComponent("auth.json"))
        try await store.addProfile(other)

        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let latest = LiveSubscription(
            activeUntil: ISO8601DateFormatter().date(from: "2026-11-10T07:05:51Z")!,
            planType: "pro", isActive: true, willRenew: true, isDelinquent: false, fetchedAt: now
        )
        let client = SubscriptionFixtureClient(value: latest)
        let codex = SubscriptionFixtureCodex()
        let controller = AccountController(store: store, codex: codex, switchService: SubscriptionFixtureSwitch(), subscriptionClient: client)

        await controller.start()
        #expect(controller.subscriptionStates.isEmpty)
        controller.refreshWeeklyUsage()
        await controller.waitForWeeklyUsageRefresh()
        #expect(controller.subscriptionStates[active.id]?.displayedSubscription == latest)
        #expect(controller.subscriptionStates[other.id]?.displayedSubscription == latest)
        #expect(try Data(contentsOf: home.appendingPathComponent("auth.json")) == activeCred)

        #if !os(Windows)
        let attrs = try fm.attributesOfItem(atPath: support.appendingPathComponent("subscription-cache.json").path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #endif

        // New quota refresh preempts an in-flight slow subscription query.
        let beforeSlow = await client.calls
        await client.pauseNextRequest()
        controller.refreshWeeklyUsage()
        for _ in 0..<100 {
            if await client.calls > beforeSlow { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        controller.refreshWeeklyUsage()
        await controller.waitForWeeklyUsageRefresh()
        #expect(await client.cancelledRequests == 1)

        // Reload retains cached subscription waiting for refresh, survives failures, and renews ONLY inactive 401 accounts.
        let newStore = AccountStore(baseURL: support, activeHomeURL: home)
        let reloaded = AccountController(store: newStore, codex: codex, switchService: SubscriptionFixtureSwitch(), subscriptionClient: client)
        await reloaded.start()
        #expect(reloaded.subscriptionStates[active.id] == .cached(latest))
        #expect(reloaded.subscriptionStates[active.id]?.displayedSubscription == latest)
        #expect(reloaded.subscriptionStates[active.id]?.refreshError == nil)
        let cachedPresentation = SubscriptionPresentation(state: reloaded.subscriptionStates[active.id] ?? .idle, historical: nil)
        #expect(cachedPresentation.isWaitingForRefresh)
        #expect(cachedPresentation.needsUpdate(at: now))

        await client.setFails(true)
        reloaded.refreshWeeklyUsage()
        await reloaded.waitForWeeklyUsageRefresh()
        #expect(reloaded.subscriptionStates[active.id]?.displayedSubscription == latest)
        #expect(reloaded.subscriptionStates[active.id]?.refreshError != nil)

        await client.setFails(false)
        await client.rejectAuthentication(active.accountID!, times: 1)
        await client.rejectAuthentication(other.accountID!, times: 1)
        reloaded.refreshWeeklyUsage()
        await reloaded.waitForWeeklyUsageRefresh()
        #expect(await codex.renewalCount == 1)
        #expect(await client.tokens(other.accountID!).suffix(2) == ["fixture-old", "fixture-renewed"])
        #expect(reloaded.subscriptionStates[other.id]?.refreshError == nil)
        #expect(reloaded.subscriptionStates[active.id]?.refreshError != nil)
        #expect(try Data(contentsOf: home.appendingPathComponent("auth.json")) == activeCred)

        // Backoff prevents repeated renewal storms after failed auth recovery.
        await client.rejectAuthentication(other.accountID!, times: 5)
        reloaded.refreshWeeklyUsage()
        await reloaded.waitForWeeklyUsageRefresh()
        reloaded.refreshWeeklyUsage()
        await reloaded.waitForWeeklyUsageRefresh()
        #expect(await codex.renewalCount == 2)

        try await newStore.removeAccount(id: other.id)
        #expect(try await newStore.loadLiveSubscriptions()[other.id] == nil)
    }

    #if !os(Windows)
    @Test func locatorUnwrapsOfficialNPMPackagesAndRejectsNonNativeLaunchersForRenewal() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("switcher-npm-locator-\(UUID())")
        defer { try? fm.removeItem(at: root) }

        #if arch(arm64)
        let npmPlatform = "codex-darwin-arm64"
        let npmTarget = "aarch64-apple-darwin"
        #else
        let npmPlatform = "codex-darwin-x64"
        let npmTarget = "x86_64-apple-darwin"
        #endif

        for (layout, binaryFolder) in [("optional", "bin"), ("legacy", "codex")] {
            let npmRoot = root.appendingPathComponent("npm-\(layout)")
            let modules = npmRoot.appendingPathComponent("node_modules")
            let pkg = modules.appendingPathComponent("@openai/codex")
            let launcher = pkg.appendingPathComponent("bin/codex.js")
            let binaryPkg = layout == "legacy" ? pkg : modules.appendingPathComponent("@openai/\(npmPlatform)")
            let native = binaryPkg.appendingPathComponent("vendor/\(npmTarget)/\(binaryFolder)/codex")
            try fm.createDirectory(at: launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createDirectory(at: native.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(#"{"name":"@openai/codex","version":"0.0.0","bin":{"codex":"bin/codex.js"}}"#.utf8)
                .write(to: pkg.appendingPathComponent("package.json"))
            if layout != "legacy" {
                try Data(#"{"name":"@openai/\(npmPlatform)","version":"0.0.0"}"#.utf8)
                    .write(to: binaryPkg.appendingPathComponent("package.json"))
            }
            try Data("#!/usr/bin/env node\n".utf8).write(to: launcher)
            // Synthetic 64-bit Mach-O magic header (`0xcf 0xfa 0xed 0xfe`) — no C compiler needed.
            try Data([0xcf, 0xfa, 0xed, 0xfe, 0x00, 0x00, 0x00, 0x00]).write(to: native)
            for file in [launcher, native] {
                try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
            }
            let symlink = npmRoot.appendingPathComponent("bin/codex")
            try fm.createDirectory(at: symlink.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: symlink, withDestinationURL: launcher)

            let locator = CodexExecutableLocator(explicitURL: symlink)
            let resolved = try await locator.launchConfigurationAsync(requireDirectExecutable: true)
            #expect(resolved.executable == native.resolvingSymlinksInPath())

            try fm.removeItem(at: native)
            await #expect(throws: CodexClientError.self) {
                try await locator.launchConfigurationAsync(requireDirectExecutable: true)
            }
        }

        let scriptLauncher = root.appendingPathComponent("custom-script")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: scriptLauncher)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptLauncher.path)
        await #expect(throws: CodexClientError.self) {
            try await CodexExecutableLocator(explicitURL: scriptLauncher).launchConfigurationAsync(requireDirectExecutable: true)
        }
    }
    #endif
}
