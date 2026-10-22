import Foundation
import Darwin
import SwitcherCore

private enum SubscriptionFixtureError: Error { case unavailable }

private actor SubscriptionFixtureClient: SubscriptionClient {
    var fails = false
    var count = 0
    var authFailures: [String: Int] = [:]
    var seenTokens: [String: [String]] = [:]
    let value: LiveSubscription
    init(value: LiveSubscription) { self.value = value }
    func setFails(_ value: Bool) { fails = value }
    func calls() -> Int { count }
    func rejectAuthentication(_ accountID: String, times: Int) { authFailures[accountID] = times }
    func tokens(_ accountID: String) -> [String] { seenTokens[accountID] ?? [] }
    func readSubscription(credential: Data, expectedAccountID: String?, expectedEmail: String?) async throws -> LiveSubscription {
        count += 1
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
    var renewals = 0
    func renewalCount() -> Int { renewals }
    func refreshIdentity(profileHome: URL) async throws -> AccountIdentity {
        renewals += 1
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
}

private struct SubscriptionFixtureSwitch: SwitchServicing {
    func switchAccount(to targetID: UUID) async throws { throw SubscriptionFixtureError.unavailable }
}

private func subscriptionFixtureCredential(_ accountID: String, email: String) throws -> Data {
    let payload: [String: Any] = ["email": email, "https://api.openai.com/auth": [
        "chatgpt_account_id": accountID, "chatgpt_plan_type": "pro",
        "chatgpt_subscription_active_until": "2026-10-10T07:05:51Z",
        "chatgpt_subscription_last_checked": "2026-09-10T07:05:51Z"
    ]]
    let encoded = try JSONSerialization.data(withJSONObject: payload).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return try JSONSerialization.data(withJSONObject: ["tokens": [
        "account_id": accountID, "access_token": "fixture-old", "id_token": "fixture.\(encoded).signature"
    ]])
}

@MainActor
func runSubscriptionControllerChecks() async throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("switcher-live-controller-\(UUID().uuidString)")
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let home = root.appendingPathComponent("active")
    let support = root.appendingPathComponent("support")
    try fm.createDirectory(at: home, withIntermediateDirectories: true)
    let active = AccountProfile(id: UUID(), displayName: "Active fixture", email: "active@example.test", accountID: "active-fixture", createdAt: Date())
    let other = AccountProfile(id: UUID(), displayName: "Other fixture", email: "other@example.test", accountID: "other-fixture", createdAt: Date())
    let original = try subscriptionFixtureCredential(active.accountID!, email: active.email!)
    try original.write(to: home.appendingPathComponent("auth.json"))
    let store = AccountStore(baseURL: support, activeHomeURL: home)
    try await store.importCurrentProfile(active)
    let otherHome = try await store.createProfileDirectory(id: other.id)
    try subscriptionFixtureCredential(other.accountID!, email: other.email!).write(to: otherHome.appendingPathComponent("auth.json"))
    try await store.addProfile(other)
    let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    let latest = LiveSubscription(activeUntil: ISO8601DateFormatter().date(from: "2026-11-10T07:05:51Z")!, planType: "pro", isActive: true, willRenew: true, isDelinquent: false, fetchedAt: now)
    let client = SubscriptionFixtureClient(value: latest)
    let codex = SubscriptionFixtureCodex()
    let controller = AccountController(store: store, codex: codex, switchService: SubscriptionFixtureSwitch(), subscriptionClient: client)
    await controller.start()
    try require(controller.subscriptionStates.isEmpty, "login snapshots do not masquerade as live subscription dates")
    controller.refreshWeeklyUsage()
    await controller.waitForWeeklyUsageRefresh()
    try require(controller.subscriptionStates[active.id]?.displayedSubscription == latest, "active profile displays renewed API date in the same refresh")
    try require(controller.subscriptionStates[other.id]?.displayedSubscription == latest, "inactive profile displays renewed API date")
    try require(controller.subscriptionStates[active.id]?.refreshError == nil, "quota failure does not prevent subscription success")
    try require(controller.usageStates[active.id]?.displayedUsage == nil, "test exercises independent subscription success with quota failure")
    try require(controller.subscriptionSnapshots[active.id]?.activeUntil != latest.activeUntil, "test fixture reproduces stale login claim")
    let liveCredentialAfterRefresh = try Data(contentsOf: home.appendingPathComponent("auth.json"))
    try require(liveCredentialAfterRefresh == original, "subscription reads do not rotate or rewrite live credentials")
    let persisted = try await store.loadLiveSubscriptions()
    try require(persisted.count == 2 && persisted[active.id] == latest, "successful service dates persist across launches")
    let attributes = try fm.attributesOfItem(atPath: support.appendingPathComponent("subscription-cache.json").path)
    try require((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "derived subscription cache is private")
    let newStore = AccountStore(baseURL: support, activeHomeURL: home)
    let reloaded = AccountController(store: newStore, codex: codex, switchService: SubscriptionFixtureSwitch(), subscriptionClient: client)
    await reloaded.start()
    try require(reloaded.subscriptionStates[active.id]?.displayedSubscription == latest, "restart retains the last service result")
    try require(reloaded.subscriptionStates[active.id]?.refreshError != nil, "restart marks cache pending refresh")
    await client.setFails(true)
    reloaded.refreshWeeklyUsage()
    await reloaded.waitForWeeklyUsageRefresh()
    try require(reloaded.subscriptionStates[active.id]?.displayedSubscription == latest, "failed service refresh retains last live date instead of JWT fallback")
    try require(reloaded.subscriptionStates[active.id]?.refreshError != nil, "failed service refresh is visible")
    try require(reloaded.subscriptionStates[active.id]?.displayedSubscription?.fetchedAt == now, "failure cannot advance the successful check time")
    await client.setFails(false)
    await client.rejectAuthentication(active.accountID!, times: 1)
    await client.rejectAuthentication(other.accountID!, times: 1)
    reloaded.refreshWeeklyUsage()
    await reloaded.waitForWeeklyUsageRefresh()
    let renewalCount = await codex.renewalCount()
    let tokens = await client.tokens(other.accountID!)
    try require(renewalCount == 1, "only the inactive account with a real 401 is renewed")
    try require(tokens.suffix(2) == ["fixture-old", "fixture-renewed"], "retry rereads newly persisted credentials")
    try require(reloaded.subscriptionStates[other.id]?.refreshError == nil, "one auth renewal recovers live subscription")
    try require(reloaded.subscriptionStates[active.id]?.refreshError != nil, "active Desktop credentials are never forcibly rotated")
    let preservedActive = try Data(contentsOf: home.appendingPathComponent("auth.json"))
    try require(preservedActive == original, "401 recovery leaves Desktop login untouched")
    await client.rejectAuthentication(other.accountID!, times: 5)
    reloaded.refreshWeeklyUsage()
    await reloaded.waitForWeeklyUsageRefresh()
    let afterFailedRetry = await codex.renewalCount()
    reloaded.refreshWeeklyUsage()
    await reloaded.waitForWeeklyUsageRefresh()
    let afterBackoff = await codex.renewalCount()
    try require(afterFailedRetry == 2 && afterBackoff == 2, "a failed retry backs off credential renewal")
    let previousCalls = await client.calls()
    let savedHome = await newStore.profileHome(id: other.id)
    try subscriptionFixtureCredential("unrelated-fixture", email: other.email!).write(to: savedHome.appendingPathComponent("auth.json"))
    reloaded.refreshWeeklyUsage()
    await reloaded.waitForWeeklyUsageRefresh()
    let newCalls = await client.calls()
    try require(newCalls == previousCalls + 1, "mismatched saved identity is rejected before network access")
    try await newStore.removeAccount(id: other.id)
    let afterRemoval = try await newStore.loadLiveSubscriptions()
    try require(afterRemoval[other.id] == nil, "removed accounts leave no subscription cache entry")
    // Bind persisted data to both local profile and remote account identity.
    let cacheURL = support.appendingPathComponent("subscription-cache.json")
    var cache = try JSONSerialization.jsonObject(with: Data(contentsOf: cacheURL)) as! [[String: Any]]
    cache[0]["accountID"] = "unrelated-fixture"
    try JSONSerialization.data(withJSONObject: cache).write(to: cacheURL)
    let invalidCache = try await newStore.loadLiveSubscriptions()
    try require(invalidCache.isEmpty, "cached subscriptions cannot cross account identities")
    let disposable = AccountProfile(id: UUID(), displayName: "Disposable fixture", email: "disposable@example.test", accountID: "disposable-fixture", createdAt: Date())
    let disposableHome = try await newStore.createProfileDirectory(id: disposable.id)
    try subscriptionFixtureCredential(disposable.accountID!, email: disposable.email!).write(to: disposableHome.appendingPathComponent("auth.json"))
    try await newStore.addProfile(disposable)
    try Data("invalid-cache".utf8).write(to: cacheURL)
    try await newStore.removeAccount(id: disposable.id)
    let repairedCache = try await newStore.loadLiveSubscriptions()
    try require(repairedCache.isEmpty, "a corrupt derived cache does not prevent removing an account")
    // Exercise the real app-server adapter against a local fake process. It
    // ignores TERM so the test also covers the bounded exit wait before reread.
    let executable = root.appendingPathComponent("fake-codex")
    let fixtureProgram = #"""
    #!/usr/bin/python3
    import json, os, pathlib, signal, sys
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    home = pathlib.Path(os.environ["CODEX_HOME"])
    for line in sys.stdin:
        message = json.loads(line)
        if message["method"] == "initialize":
            print(json.dumps({"id": message["id"], "result": {}}), flush=True)
        elif message["method"] == "account/read":
            (home / "renewal-request.json").write_text(json.dumps({"args": sys.argv[1:], "refresh": message["params"].get("refreshToken"), "pid": os.getpid()}))
            print(json.dumps({"id": message["id"], "result": {"account": {"accountId": "other-fixture", "email": "other@example.test", "type": "chatgpt"}}}), flush=True)
            while True:
                signal.pause()
    """#
    // Use a native exec shim: the interpreter replaces it with the same PID,
    // unlike the unsupported custom launchers that spawn an unmanaged child.
    let shimSource = root.appendingPathComponent("fake-codex.c")
    try Data(#"""
    #include <limits.h>
    #include <stdio.h>
    #include <stdlib.h>
    #include <unistd.h>
    int main(int argc, char **argv) {
        char script[PATH_MAX];
        if (snprintf(script, sizeof(script), "%s.py", argv[0]) >= sizeof(script)) return 1;
        char **args = calloc(argc + 2, sizeof(char *));
        if (!args) return 1;
        args[0] = "/usr/bin/python3";
        args[1] = script;
        for (int i = 1; i < argc; i++) args[i + 1] = argv[i];
        execv(args[0], args);
        return 1;
    }
    """#.utf8).write(to: shimSource)
    try Data(fixtureProgram.utf8).write(to: executable.appendingPathExtension("py"))
    let compiler = Process()
    compiler.executableURL = URL(fileURLWithPath: "/usr/bin/cc")
    compiler.arguments = [shimSource.path, "-o", executable.path]
    try compiler.run()
    compiler.waitUntilExit()
    try require(compiler.terminationStatus == 0, "native credential-writer fixture compiles")
    let rpcHome = root.appendingPathComponent("rpc-profile")
    try fm.createDirectory(at: rpcHome, withIntermediateDirectories: true)
    let actualClient = CodexClient(locator: CodexExecutableLocator(explicitURL: executable), requestTimeout: .seconds(2))
    let renewedIdentity = try await actualClient.refreshIdentity(profileHome: rpcHome)
    try require(renewedIdentity.accountID == "other-fixture", "forced managed refresh returns the requested profile identity")
    let receipt = try JSONSerialization.jsonObject(with: Data(contentsOf: rpcHome.appendingPathComponent("renewal-request.json"))) as! [String: Any]
    try require(receipt["refresh"] as? Bool == true, "authentication recovery requests official forced renewal")
    try require((receipt["args"] as? [String])?.contains("cli_auth_credentials_store=\"file\"") == true, "renewed tokens are persisted to the isolated profile file")
    let childPID = (receipt["pid"] as! NSNumber).int32Value
    try require(Darwin.kill(childPID, 0) != 0, "renewal returns only after its credential writer has exited")

    // npm's launcher spawns a native child. Renewal must own that child directly,
    // including installations reached through a command symlink and spaced paths.
    #if arch(arm64)
    let npmPlatform = "codex-darwin-arm64"
    let npmTarget = "aarch64-apple-darwin"
    #else
    let npmPlatform = "codex-darwin-x64"
    let npmTarget = "x86_64-apple-darwin"
    #endif
    for (layout, binaryFolder) in [("optional", "bin"), ("legacy", "codex")] {
        let npmRoot = root.appendingPathComponent("npm \(layout) fixture")
        let modules = npmRoot.appendingPathComponent("node_modules")
        let package = modules.appendingPathComponent("@openai/codex")
        let launcher = package.appendingPathComponent("bin/codex.js")
        let binaryPackage = layout == "legacy" ? package : modules.appendingPathComponent("@openai/\(npmPlatform)")
        let native = binaryPackage.appendingPathComponent("vendor/\(npmTarget)/\(binaryFolder)/codex")
        try fm.createDirectory(at: launcher.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: native.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"name":"@openai/codex","version":"0.0.0","bin":{"codex":"bin/codex.js"}}"#.utf8)
            .write(to: package.appendingPathComponent("package.json"))
        if layout != "legacy" {
            try Data(#"{"name":"@openai/codex","version":"0.0.0"}"#.utf8)
                .write(to: binaryPackage.appendingPathComponent("package.json"))
        }
        try Data("#!/bin/sh\ntouch \"$CODEX_HOME/wrapper-was-run\"\nexit 75\n".utf8).write(to: launcher)
        try fm.copyItem(at: executable, to: native)
        try Data(fixtureProgram.utf8).write(to: native.appendingPathExtension("py"))
        for file in [launcher, native] {
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        }
        let command = npmRoot.appendingPathComponent("bin/codex")
        try fm.createDirectory(at: command.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: command, withDestinationURL: launcher)
        let npmHome = npmRoot.appendingPathComponent("profile")
        try fm.createDirectory(at: npmHome, withIntermediateDirectories: true)
        let npmClient = CodexClient(locator: CodexExecutableLocator(explicitURL: command), requestTimeout: .seconds(2))
        let npmIdentity = try await npmClient.refreshIdentity(profileHome: npmHome)
        try require(npmIdentity.accountID == "other-fixture", "\(layout) npm renewal launches the native adapter")
        let npmReceipt = try JSONSerialization.jsonObject(with: Data(contentsOf: npmHome.appendingPathComponent("renewal-request.json"))) as! [String: Any]
        let writerPID = (npmReceipt["pid"] as! NSNumber).int32Value
        try require(Darwin.kill(writerPID, 0) != 0, "\(layout) npm credential writer exits before renewal returns")
        try require(!fm.fileExists(atPath: npmHome.appendingPathComponent("wrapper-was-run").path), "npm launcher is bypassed for credential renewal")
        try fm.removeItem(at: native)
        do {
            _ = try await npmClient.refreshIdentity(profileHome: npmHome)
            throw CheckFailure.failed("npm renewal must reject a missing native binary")
        } catch is CodexClientError {
            // An incomplete installation must not fall back to an unmanaged child.
        }
        try require(!fm.fileExists(atPath: npmHome.appendingPathComponent("wrapper-was-run").path), "missing native binary fails before launching npm")
    }
    let unknownLauncher = root.appendingPathComponent("unknown-launcher")
    try Data("#!/bin/sh\ntouch \"$CODEX_HOME/wrapper-was-run\"\nexit 75\n".utf8).write(to: unknownLauncher)
    try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: unknownLauncher.path)
    let unknownClient = CodexClient(locator: CodexExecutableLocator(explicitURL: unknownLauncher))
    do {
        _ = try await unknownClient.refreshIdentity(profileHome: rpcHome)
        throw CheckFailure.failed("credential renewal must reject unknown launch scripts")
    } catch is CodexClientError {}
    try require(!fm.fileExists(atPath: rpcHome.appendingPathComponent("wrapper-was-run").path), "unknown credential writer is never launched")
    print("Live subscription controller/cache checks passed")
}
