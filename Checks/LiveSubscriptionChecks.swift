import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwitcherCore

private struct LiveSubscriptionCheckFailure: Error {
    let message: String
}

private func liveRequire(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw LiveSubscriptionCheckFailure(message: message) }
}

private actor LiveSubscriptionRequestProbe {
    private var requests: [URLRequest] = []
    func record(_ request: URLRequest) { requests.append(request) }
    func count() -> Int { requests.count }
    func first() -> URLRequest? { requests.first }
}

func runLiveSubscriptionChecks() async throws {
    let fixtureID = "subscription-fixture-account"
    let fixtureEmail = "subscription-fixture@example.com"
    let fixtureToken = "synthetic-access-token"
    let iso = ISO8601DateFormatter()
    let now = iso.date(from: "2026-10-22T12:00:00Z")!
    let expectedUntil = iso.date(from: "2026-11-10T10:00:00Z")!

    func credential(accountID: String? = "subscription-fixture-account",
                    claimID: String = "subscription-fixture-account",
                    email: String? = "subscription-fixture@example.com",
                    accessToken: String? = "synthetic-access-token",
                    idTokenOverride: String? = nil) throws -> Data {
        var claims: [String: Any] = [
            "https://api.openai.com/auth": [
                "chatgpt_account_id": claimID,
                "chatgpt_plan_type": "plus",
                "chatgpt_subscription_active_until": "2026-10-10T10:00:00Z",
                "chatgpt_subscription_last_checked": "2026-09-10T10:00:00Z",
            ],
        ]
        claims["email"] = email
        let payload = try JSONSerialization.data(withJSONObject: claims).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var tokens: [String: Any] = ["id_token": idTokenOverride ?? "header.\(payload).signature"]
        tokens["account_id"] = accountID
        tokens["access_token"] = accessToken
        return try JSONSerialization.data(withJSONObject: ["tokens": tokens])
    }
    func body(_ changes: [String: Any] = [:], removing: [String] = []) throws -> Data {
        var object: [String: Any] = [
            "active_until": "2026-11-10T10:00:00Z", "plan_type": "plus", "is_active": true,
            "will_renew": true, "is_delinquent": false,
        ]
        object.merge(changes) { _, replacement in replacement }
        for key in removing { object.removeValue(forKey: key) }
        return try JSONSerialization.data(withJSONObject: object)
    }
    let validCredential = try credential()
    let validBody = try body()
    func client(_ responseBody: Data = validBody, status: Int = 200,
                responseURL: URL? = nil, probe: LiveSubscriptionRequestProbe? = nil) -> LiveSubscriptionClient {
        LiveSubscriptionClient(transport: { request in
            await probe?.record(request)
            return (responseBody, HTTPURLResponse(url: responseURL ?? request.url!, statusCode: status,
                                                  httpVersion: "HTTP/1.1", headerFields: nil)!)
        }, now: { now })
    }
    func read(_ client: LiveSubscriptionClient, data: Data = validCredential,
              accountID: String? = "subscription-fixture-account",
              email: String? = "subscription-fixture@example.com") async throws -> LiveSubscription {
        try await client.readSubscription(credential: data, expectedAccountID: accountID, expectedEmail: email)
    }
    func requireError(_ expected: LiveSubscriptionError, client: LiveSubscriptionClient,
                      data: Data = validCredential, accountID: String? = "subscription-fixture-account",
                      email: String? = "subscription-fixture@example.com", _ message: String) async throws {
        do {
            _ = try await read(client, data: data, accountID: accountID, email: email)
            throw LiveSubscriptionCheckFailure(message: message)
        } catch let error as LiveSubscriptionError {
            try liveRequire(error == expected, message)
        }
    }

    let probe = LiveSubscriptionRequestProbe()
    let subscription = try await read(client(probe: probe), email: fixtureEmail.uppercased())
    try liveRequire(subscription.activeUntil == expectedUntil,
                    "API subscription date replaces the older JWT date")
    try liveRequire(subscription.planType == "plus" && subscription.isActive &&
                    subscription.willRenew == true && subscription.isDelinquent == false &&
                    subscription.fetchedAt == now,
                    "live subscription retains service status and local fetch time")
    let request = await probe.first()
    try liveRequire(request?.httpMethod == "GET" && request?.timeoutInterval == 20 &&
                    request?.cachePolicy == .reloadIgnoringLocalCacheData,
                    "live subscription uses a bounded uncached GET")
    let query = request?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
    try liveRequire(query?.host == "chatgpt.com" && query?.path == "/backend-api/subscriptions" &&
                    query?.queryItems == [URLQueryItem(name: "account_id", value: fixtureID)],
                    "subscription request is bound to the expected account")
    try liveRequire(request?.value(forHTTPHeaderField: "Authorization") == "Bearer \(fixtureToken)" &&
                    request?.value(forHTTPHeaderField: "ChatGPT-Account-ID") == fixtureID &&
                    request?.value(forHTTPHeaderField: "Accept") == "application/json" &&
                    request?.value(forHTTPHeaderField: "OpenAI-Beta") == "codex-1" &&
                    request?.value(forHTTPHeaderField: "Originator") == "codex-account-switcher" &&
                    request?.value(forHTTPHeaderField: "User-Agent") == "codex-account-switcher/0.1.21",
                    "subscription request uses its own product identity and matching access token")
    let roundTrip = try JSONDecoder().decode(LiveSubscription.self, from: JSONEncoder().encode(subscription))
    try liveRequire(roundTrip == subscription, "live subscription cache encoding preserves service fields")
    try liveRequire(LiveSubscriptionState.idle.displayedSubscription == nil &&
                    LiveSubscriptionState.loaded(subscription).displayedSubscription == subscription &&
                    LiveSubscriptionState.stale(subscription, "fixture stale").displayedSubscription == subscription &&
                    LiveSubscriptionState.stale(subscription, "fixture stale").refreshError == "fixture stale" &&
                    LiveSubscriptionState.unavailable("fixture unavailable").refreshError == "fixture unavailable",
                    "subscription state preserves its last good response and controlled failure")

    let untouchedProbe = LiveSubscriptionRequestProbe()
    let identityClient = client(probe: untouchedProbe)
    let invalidCredentials = [
        try credential(accountID: "other-account"),
        try credential(accountID: nil, claimID: "other-account"),
        try credential(email: "other@example.com"),
        try credential(email: nil),
        try credential(accessToken: nil),
        try credential(accessToken: "injected\r\nheader"),
        try credential(idTokenOverride: "invalid-token"),
        Data("private invalid credential fixture".utf8),
    ]
    for data in invalidCredentials {
        try await requireError(.invalidCredential, client: identityClient, data: data,
                               "mismatched or incomplete credentials are rejected before transport")
    }
    try await requireError(.invalidCredential, client: identityClient, accountID: nil,
                           "subscription query requires an expected account ID")
    let untouchedCount = await untouchedProbe.count()
    try liveRequire(untouchedCount == 0, "identity failures perform no transport calls")
    let noTopLevelID = try await read(client(), data: credential(accountID: nil))
    try liveRequire(noTopLevelID == subscription, "matching ID-token identity supports credentials without duplicate account_id")
    let workspaceProbe = LiveSubscriptionRequestProbe()
    let workspace = try await read(client(probe: workspaceProbe), data: credential(claimID: "default-personal-account"))
    let workspaceRequest = await workspaceProbe.first()
    try liveRequire(workspace == subscription &&
                    workspaceRequest?.value(forHTTPHeaderField: "ChatGPT-Account-ID") == fixtureID,
                    "selected workspace account_id takes precedence over the JWT default account")
    try await requireError(.invalidCredential, client: identityClient,
                           data: credential(accountID: "different-workspace", claimID: fixtureID),
                           "the default JWT account cannot override a different selected workspace")
    let afterWorkspaceMismatchCount = await untouchedProbe.count()
    try liveRequire(afterWorkspaceMismatchCount == 0,
                    "workspace identity mismatch is rejected before transport")
    let emptyTopLevelID = try await read(client(), data: credential(accountID: ""))
    try liveRequire(emptyTopLevelID == subscription, "empty selected account ID falls back to the JWT identity")
    let noExpectedEmail = try await read(client(), email: nil)
    let noEmailMetadata = try await read(client(), data: credential(email: nil), email: nil)
    try liveRequire(noExpectedEmail == subscription && noEmailMetadata == subscription,
                    "an explicit matching account ID supports profiles without saved email metadata")

    let invalidBodies = [
        Data("private server body fixture".utf8), Data("[]".utf8),
        try body(["is_active": 1]), try body(["is_active": "true"]),
        try body(removing: ["is_active"]), try body(["plan_type": "   "]),
        try body(["active_until": "invalid date"]), try body(["active_until": 42]),
        try body(removing: ["active_until"]), try body(["active_until": NSNull()]),
        try body(["will_renew": "false"]), try body(["is_delinquent": 1]),
    ]
    for data in invalidBodies {
        try await requireError(.invalidResponse, client: client(data),
                               "malformed live subscription fields cannot become a verified date")
    }
    let free = try await read(client(body(["plan_type": "free", "active_until": NSNull()])))
    try liveRequire(free.isActive && free.planType == "free" && free.activeUntil == nil,
                    "free subscription does not fabricate an expiry date")
    let inactive = try await read(client(body(["is_active": false], removing: ["active_until", "will_renew", "is_delinquent"])))
    try liveRequire(!inactive.isActive && inactive.activeUntil == nil && inactive.willRenew == nil && inactive.isDelinquent == nil,
                    "inactive subscription preserves unknown expiry and optional status")
    let fractional = try await read(client(body(["active_until": "2026-11-10T10:00:00.000Z"])))
    try liveRequire(fractional.activeUntil == expectedUntil, "fractional ISO dates are accepted")

    for (status, error) in [(401, LiveSubscriptionError.unauthenticated), (403, .forbidden),
                            (429, .rateLimited), (500, .serverUnavailable), (503, .serverUnavailable),
                            (302, .redirected), (404, .requestFailed)] {
        try await requireError(error, client: client(Data("private HTTP body fixture".utf8), status: status),
                               "HTTP failures return only controlled categories")
    }
    try await requireError(.redirected,
                           client: client(responseURL: URL(string: "https://example.invalid/redirected")),
                           "a transport cannot silently follow a subscription redirect")
    try await requireError(.responseTooLarge, client: client(Data(repeating: 32, count: 1_048_577)),
                           "subscription response body is limited to one MiB")
    let transportFailure = LiveSubscriptionClient(transport: { _ in
        throw NSError(domain: "private credential fixture", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "private server body fixture"])
    })
    try await requireError(.requestFailed, client: transportFailure,
                           "transport diagnostics cannot leak through the subscription error")
    let timeoutClient = LiveSubscriptionClient(transport: { _ in throw URLError(.timedOut) })
    try await requireError(.timedOut, client: timeoutClient, "timeout uses a controlled category")
    let cancelledClient = LiveSubscriptionClient(transport: { _ in throw URLError(.cancelled) })
    do {
        _ = try await read(cancelledClient)
        throw LiveSubscriptionCheckFailure(message: "URLSession cancellation remains cancellation")
    } catch is CancellationError { }
    let cancellationProbe = LiveSubscriptionRequestProbe()
    let sleepingClient = LiveSubscriptionClient(transport: { request in
        await cancellationProbe.record(request)
        try await Task.sleep(for: .seconds(20))
        throw LiveSubscriptionCheckFailure(message: "cancelled transport unexpectedly continued")
    })
    let cancellationTask = Task {
        try await sleepingClient.readSubscription(credential: validCredential,
                                                  expectedAccountID: fixtureID, expectedEmail: fixtureEmail)
    }
    for _ in 0..<100 {
        if await cancellationProbe.count() > 0 { break }
        try await Task.sleep(for: .milliseconds(5))
    }
    cancellationTask.cancel()
    do {
        _ = try await cancellationTask.value
        throw LiveSubscriptionCheckFailure(message: "cancelled subscription request returned a result")
    } catch is CancellationError { }
    print("Live subscription checks passed")
}
