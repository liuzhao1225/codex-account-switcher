import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum LiveSubscriptionError: Error, Equatable, Sendable, LocalizedError {
    case invalidCredential
    case unauthenticated
    case forbidden
    case rateLimited
    case serverUnavailable
    case redirected
    case responseTooLarge
    case invalidResponse
    case timedOut
    case requestFailed

    public var errorDescription: String? {
        switch self {
        case .invalidCredential: "The saved login does not match this account or lacks the required credentials."
        case .unauthenticated: "The subscription service requires a renewed login."
        case .forbidden: "The subscription service did not allow this account query."
        case .rateLimited: "The subscription service is temporarily rate limited."
        case .serverUnavailable: "The subscription service is temporarily unavailable."
        case .redirected: "The subscription service returned an unexpected redirect."
        case .responseTooLarge: "The subscription service response exceeded the size limit."
        case .invalidResponse: "The subscription service returned incomplete or invalid subscription information."
        case .timedOut: "The subscription query timed out."
        case .requestFailed: "The subscription query could not be completed."
        }
    }
}

public struct LiveSubscriptionClient: SubscriptionClient {
    /// Injection keeps checks offline. Production uses a bounded, redirect-blocking session.
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let transport: Transport
    private let now: @Sendable () -> Date
    private static let maximumResponseBytes = 1_048_576

    public init() {
        self.transport = { request in try await BoundedSubscriptionRequest.perform(request) }
        self.now = { Date() }
    }

    public init(transport: @escaping Transport, now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
        self.now = now
    }

    public func readSubscription(credential: Data, expectedAccountID: String?,
                                 expectedEmail: String?) async throws -> LiveSubscription {
        try Task.checkCancellation()
        let login = try Self.matchingLogin(credential, accountID: expectedAccountID, email: expectedEmail)
        var components = URLComponents(string: "https://chatgpt.com/backend-api/subscriptions")!
        components.queryItems = [URLQueryItem(name: "account_id", value: login.accountID)]
        guard let url = components.url else { throw LiveSubscriptionError.invalidCredential }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue("Bearer \(login.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(login.accountID, forHTTPHeaderField: "ChatGPT-Account-ID")
        request.setValue("codex-1", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue("codex-account-switcher", forHTTPHeaderField: "Originator")
        request.setValue("codex-account-switcher/0.1.21", forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport(request)
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LiveSubscriptionError {
            throw error
        } catch let error as URLError {
            if error.code == .cancelled || Task.isCancelled { throw CancellationError() }
            if error.code == .timedOut { throw LiveSubscriptionError.timedOut }
            throw LiveSubscriptionError.requestFailed
        } catch {
            if Task.isCancelled { throw CancellationError() }
            // Never expose transport diagnostics: they may include the URL or headers.
            throw LiveSubscriptionError.requestFailed
        }
        guard response.url == url else { throw LiveSubscriptionError.redirected }
        switch response.statusCode {
        case 200: break
        case 300..<400: throw LiveSubscriptionError.redirected
        case 401: throw LiveSubscriptionError.unauthenticated
        case 403: throw LiveSubscriptionError.forbidden
        case 429: throw LiveSubscriptionError.rateLimited
        case 500...599: throw LiveSubscriptionError.serverUnavailable
        default: throw LiveSubscriptionError.requestFailed
        }
        guard data.count <= Self.maximumResponseBytes else { throw LiveSubscriptionError.responseTooLarge }
        do {
            let payload = try JSONDecoder().decode(ResponsePayload.self, from: data)
            let plan = payload.planType.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !plan.isEmpty else { throw LiveSubscriptionError.invalidResponse }
            var activeUntil: Date?
            if let text = payload.activeUntil {
                activeUntil = Self.parseDate(text)
                guard activeUntil != nil else { throw LiveSubscriptionError.invalidResponse }
            }
            guard !payload.isActive || plan.lowercased() == "free" || activeUntil != nil else {
                throw LiveSubscriptionError.invalidResponse
            }
            return LiveSubscription(activeUntil: activeUntil, planType: plan, isActive: payload.isActive,
                                    willRenew: payload.willRenew, isDelinquent: payload.isDelinquent,
                                    fetchedAt: now())
        } catch {
            // Decoder diagnostics can quote server content. Return only a controlled category.
            throw LiveSubscriptionError.invalidResponse
        }
    }

    private struct Login {
        let accountID: String
        let accessToken: String
    }

    private static func matchingLogin(_ data: Data, accountID: String?, email: String?) throws -> Login {
        do {
            guard data.count <= maximumResponseBytes,
                  let accountID, validHeaderValue(accountID) else {
                throw LiveSubscriptionError.invalidCredential
            }
            let credential = try JSONDecoder().decode(Credential.self, from: data)
            let tokens = credential.tokens
            guard validHeaderValue(tokens.accessToken) else {
                throw LiveSubscriptionError.invalidCredential
            }
            // A selected workspace may differ from the ID token's default
            // account. Reuse the registry's identity rules rather than imposing
            // a second interpretation of the credential.
            guard let identity = try CredentialIdentity.decode(data), identity.accountID == accountID else {
                throw LiveSubscriptionError.invalidCredential
            }
            if let email, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               identity.email?.caseInsensitiveCompare(email) != .orderedSame {
                throw LiveSubscriptionError.invalidCredential
            }
            return Login(accountID: accountID, accessToken: tokens.accessToken)
        } catch {
            throw LiveSubscriptionError.invalidCredential
        }
    }

    private static func validHeaderValue(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { $0 > 32 && $0 < 127 }
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    private struct Credential: Decodable { let tokens: Tokens }
    private struct Tokens: Decodable {
        let accessToken: String
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
        }
    }
    private struct ResponsePayload: Decodable {
        let activeUntil: String?
        let planType: String
        let isActive: Bool
        let willRenew: Bool?
        let isDelinquent: Bool?
        enum CodingKeys: String, CodingKey {
            case activeUntil = "active_until", planType = "plan_type", isActive = "is_active"
            case willRenew = "will_renew", isDelinquent = "is_delinquent"
        }
    }
}

/// One ephemeral session per request. All mutable state is protected by the lock;
/// delegate callbacks and cancellation may arrive on different executors.
private final class BoundedSubscriptionRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), any Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var response: HTTPURLResponse?
    private var data = Data()
    private var completed = false
    private let limit = 1_048_576

    static func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let operation = BoundedSubscriptionRequest()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                operation.start(request, continuation: continuation)
            }
        } onCancel: {
            operation.finish(.failure(CancellationError()))
        }
    }

    private func start(_ request: URLRequest,
                       continuation: CheckedContinuation<(Data, HTTPURLResponse), any Error>) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: request)
        self.continuation = continuation
        self.session = session
        self.task = task
        lock.unlock()
        task.resume()
    }

    private func finish(_ result: Result<(Data, HTTPURLResponse), any Error>) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        let continuation = self.continuation
        let session = self.session
        self.continuation = nil
        self.session = nil
        task = nil
        lock.unlock()
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
        finish(.failure(LiveSubscriptionError.redirected))
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(.failure(LiveSubscriptionError.invalidResponse))
            return
        }
        guard response.expectedContentLength <= Int64(limit) else {
            completionHandler(.cancel)
            finish(.failure(LiveSubscriptionError.responseTooLarge))
            return
        }
        lock.lock()
        self.response = response
        let completed = self.completed
        lock.unlock()
        completionHandler(completed ? .cancel : .allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive bytes: Data) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        guard bytes.count <= limit - data.count else {
            lock.unlock()
            finish(.failure(LiveSubscriptionError.responseTooLarge))
            return
        }
        data.append(bytes)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error { finish(.failure(error)); return }
        lock.lock()
        let response = self.response
        let data = self.data
        lock.unlock()
        guard let response else { finish(.failure(LiveSubscriptionError.invalidResponse)); return }
        finish(.success((data, response)))
    }
}
