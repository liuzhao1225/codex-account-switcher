import AppKit
import Foundation

enum JSONValue: Decodable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    var objectValue: [String: JSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case let .array(value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    var doubleValue: Double? {
        guard case let .number(value) = self else { return nil }
        return value
    }

    var intValue: Int? { doubleValue.map(Int.init) }

    var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }

    subscript(key: String) -> JSONValue? { objectValue?[key] }
}

private struct RPCRemoteError: Decodable, Sendable {
    let code: Int?
    let message: String
}

private struct RPCEnvelope: Decodable, Sendable {
    let id: Int?
    let method: String?
    let params: JSONValue?
    let result: JSONValue?
    let error: RPCRemoteError?
}

private final class LinePump: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var lines: [Data] = []
    private var waiters: [CheckedContinuation<Data?, any Error>] = []
    private var isFinished = false

    init(handle: FileHandle) {
        handle.readabilityHandler = { [weak self] readable in
            guard let self else { return }
            let data = readable.availableData
            guard !data.isEmpty else {
                self.finish()
                return
            }
            self.consume(data)
        }
    }

    private func consume(_ data: Data) {
        lock.lock()
        buffer.append(data)
        var parsedLines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if !line.isEmpty { parsedLines.append(line) }
        }
        lock.unlock()
        for line in parsedLines {
            deliver(line)
        }
    }

    func next() async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if !lines.isEmpty {
                let line = lines.removeFirst()
                lock.unlock()
                continuation.resume(returning: line)
            } else if isFinished {
                lock.unlock()
                continuation.resume(returning: nil)
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    private func deliver(_ line: Data) {
        lock.lock()
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            lock.unlock()
            waiter.resume(returning: line)
        } else {
            lines.append(line)
            lock.unlock()
        }
    }

    func finish() {
        lock.lock()
        let tail = buffer
        buffer.removeAll()
        isFinished = true
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        if !tail.isEmpty { deliver(tail) }
        pending.forEach { $0.resume(returning: nil) }
    }
}

private final class StderrDrain: @unchecked Sendable {
    private let lock = NSLock()
    private var tail = Data()
    private let maximumBytes = 4_096

    init(handle: FileHandle) {
        handle.readabilityHandler = { [weak self] readable in
            guard let self else { return }
            let data = readable.availableData
            guard !data.isEmpty else { return }
            self.lock.lock()
            self.tail.append(data)
            if self.tail.count > self.maximumBytes {
                self.tail.removeFirst(self.tail.count - self.maximumBytes)
            }
            self.lock.unlock()
        }
    }
}

private actor JSONRPCSession {
    private let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private let errorOutput: FileHandle
    private let pump: LinePump
    private let stderrDrain: StderrDrain
    private let decoder = JSONDecoder()
    private let encoder = JSONSerialization.self
    private var didTimeout = false

    init(executableURL: URL, profileHome: URL) throws {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = profileHome.path
        process.environment = environment
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let pump = LinePump(handle: outputPipe.fileHandleForReading)
        let stderrDrain = StderrDrain(handle: errorPipe.fileHandleForReading)
        self.process = process
        input = inputPipe.fileHandleForWriting
        output = outputPipe.fileHandleForReading
        errorOutput = errorPipe.fileHandleForReading
        self.pump = pump
        self.stderrDrain = stderrDrain

        do {
            try process.run()
        } catch {
            throw CodexClientError.processLaunchFailed(error.localizedDescription)
        }
    }

    func initialize(timeout: Duration) async throws {
        try send([
            "method": "initialize",
            "id": 0,
            "params": [
                "clientInfo": [
                    "name": "codex_account_switcher_lite",
                    "title": "Codex Account Switcher Lite",
                    "version": "0.1.1",
                ],
            ],
        ])
        _ = try await response(id: 0, timeout: timeout)
        try send(["method": "initialized", "params": [:]])
    }

    func request(
        method: String,
        id: Int,
        params: [String: Any] = [:],
        timeout: Duration
    ) async throws -> JSONValue {
        try send(["method": method, "id": id, "params": params])
        let envelope = try await response(id: id, timeout: timeout)
        if let error = envelope.error {
            throw CodexClientError.remoteError(code: error.code, message: error.message)
        }
        guard let result = envelope.result else { throw CodexClientError.malformedResponse }
        return result
    }

    func notification(method: String, timeout: Duration) async throws -> JSONValue {
        let envelope = try await receive(
            where: { $0.method == method && $0.id == nil },
            timeout: timeout
        )
        return envelope.params ?? .object([:])
    }

    func stop() {
        output.readabilityHandler = nil
        errorOutput.readabilityHandler = nil
        try? input.close()
        if process.isRunning {
            process.terminate()
        }
        pump.finish()
    }

    private func response(id: Int, timeout: Duration) async throws -> RPCEnvelope {
        try await receive(where: { $0.id == id }, timeout: timeout)
    }

    private func receive(
        where predicate: @escaping @Sendable (RPCEnvelope) -> Bool,
        timeout: Duration
    ) async throws -> RPCEnvelope {
        didTimeout = false
        let timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
                await self?.triggerTimeout()
            } catch {
                // Cancellation means a response arrived before the deadline.
            }
        }
        defer { timeoutTask.cancel() }

        while let line = try await nextLine() {
            let message: RPCEnvelope
            do {
                message = try decoder.decode(RPCEnvelope.self, from: line)
            } catch {
                throw CodexClientError.malformedResponse
            }
            if let error = message.error, message.id != nil {
                throw CodexClientError.remoteError(code: error.code, message: error.message)
            }
            if predicate(message) { return message }
        }
        if didTimeout { throw CodexClientError.timeout }
        throw CodexClientError.connectionClosed
    }

    private func triggerTimeout() {
        didTimeout = true
        output.readabilityHandler = nil
        errorOutput.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        pump.finish()
    }

    private func nextLine() async throws -> Data? {
        try await pump.next()
    }

    private func send(_ object: [String: Any]) throws {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw CodexClientError.malformedResponse
        }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try input.write(contentsOf: data)
    }
}

struct CodexExecutableLocator: Sendable {
    let explicitURL: URL?

    init(explicitURL: URL? = nil) {
        self.explicitURL = explicitURL
    }

    func locate() throws -> URL {
        if let explicitURL, isExecutable(explicitURL.path) {
            return explicitURL
        }
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["CODEX_SWITCHER_CODEX_PATH"], isExecutable(override) {
            return URL(fileURLWithPath: override)
        }
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "codex"), isExecutable(bundled.path) {
            return bundled
        }

        let knownPaths = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
        ]
        if let path = knownPaths.first(where: isExecutable) {
            return URL(fileURLWithPath: path)
        }

        if let path = environment["PATH"]?
            .split(separator: ":")
            .map({ String($0) + "/codex" })
            .first(where: isExecutable)
        {
            return URL(fileURLWithPath: path)
        }
        throw CodexClientError.executableNotFound
    }

    private func isExecutable(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }
}

protocol WeeklyUsageReading: Sendable {
    func readWeeklyUsage(profileHome: URL) async throws -> WeeklyUsage
}

protocol LoginServicing: Sendable {
    func login(profileHome: URL) async throws -> AccountIdentity
}

struct CodexClient: CodexIdentityReading, WeeklyUsageReading, LoginServicing {
    let locator: CodexExecutableLocator
    let requestTimeout: Duration

    init(locator: CodexExecutableLocator = .init(), requestTimeout: Duration = .seconds(20)) {
        self.locator = locator
        self.requestTimeout = requestTimeout
    }

    func readIdentity(profileHome: URL) async throws -> AccountIdentity {
        let result = try await withSession(profileHome: profileHome) { session in
            try await session.request(
                method: "account/read",
                id: 1,
                params: ["refreshToken": false],
                timeout: requestTimeout
            )
        }
        return try parseIdentity(result)
    }

    func readWeeklyUsage(profileHome: URL) async throws -> WeeklyUsage {
        let result = try await withSession(profileHome: profileHome) { session in
            try await session.request(
                method: "account/rateLimits/read",
                id: 1,
                timeout: requestTimeout
            )
        }
        return try WeeklyUsageNormalizer.normalize(parseWindows(result))
    }

    func login(profileHome: URL) async throws -> AccountIdentity {
        let executable = try locator.locate()
        let session = try JSONRPCSession(executableURL: executable, profileHome: profileHome)
        do {
            try await session.initialize(timeout: requestTimeout)
            let start = try await session.request(
                method: "account/login/start",
                id: 1,
                params: [
                    "type": "chatgpt",
                    "useHostedLoginSuccessPage": true,
                    "appBrand": "codex",
                ],
                timeout: requestTimeout
            )
            guard let authURLString = start["authUrl"]?.stringValue,
                  let authURL = URL(string: authURLString)
            else {
                throw CodexClientError.malformedResponse
            }
            let opened = await MainActor.run { NSWorkspace.shared.open(authURL) }
            guard opened else { throw CodexClientError.loginFailed("The sign-in page could not be opened.") }

            let completion = try await session.notification(
                method: "account/login/completed",
                timeout: .seconds(600)
            )
            guard completion["success"]?.boolValue == true else {
                throw CodexClientError.loginFailed(
                    completion["error"]?.stringValue ?? "The sign-in did not complete."
                )
            }
            let identityValue = try await session.request(
                method: "account/read",
                id: 2,
                params: ["refreshToken": false],
                timeout: requestTimeout
            )
            let identity = try parseIdentity(identityValue)
            await session.stop()
            return identity
        } catch {
            await session.stop()
            throw error
        }
    }

    private func withSession<T: Sendable>(
        profileHome: URL,
        operation: (JSONRPCSession) async throws -> T
    ) async throws -> T {
        let executable = try locator.locate()
        let session = try JSONRPCSession(executableURL: executable, profileHome: profileHome)
        do {
            try await session.initialize(timeout: requestTimeout)
            let result = try await operation(session)
            await session.stop()
            return result
        } catch {
            await session.stop()
            throw error
        }
    }

    private func parseIdentity(_ value: JSONValue) throws -> AccountIdentity {
        guard let account = value["account"]?.objectValue else {
            throw CodexClientError.identityUnavailable
        }
        let accountID = account["accountId"]?.stringValue
            ?? account["accountID"]?.stringValue
            ?? account["chatgptAccountId"]?.stringValue
            ?? account["id"]?.stringValue
        let email = account["email"]?.stringValue
        guard accountID != nil || email != nil else {
            throw CodexClientError.identityUnavailable
        }
        return AccountIdentity(accountID: accountID, email: email)
    }

    private func parseWindows(_ value: JSONValue) -> [RateLimitWindow] {
        var buckets: [JSONValue] = []
        if let rateLimits = value["rateLimits"] { buckets.append(rateLimits) }
        if let map = value["rateLimitsByLimitId"]?.objectValue {
            buckets.append(contentsOf: map.values)
        }
        return buckets.flatMap { bucket in
            [bucket["primary"], bucket["secondary"]].compactMap(parseWindow)
        }
    }

    private func parseWindow(_ value: JSONValue?) -> RateLimitWindow? {
        guard let value,
              let used = value["usedPercent"]?.doubleValue,
              let duration = value["windowDurationMins"]?.intValue
                ?? value["durationMinutes"]?.intValue,
              let reset = value["resetsAt"]?.doubleValue
        else {
            return nil
        }
        return RateLimitWindow(
            usedPercent: used,
            windowDurationMins: duration,
            resetsAt: reset
        )
    }
}
