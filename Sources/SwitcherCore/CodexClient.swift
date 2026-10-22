import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
#if canImport(AppKit)
import AppKit
#endif

public enum JSONValue: Decodable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: any Decoder) throws {
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

    public var objectValue: [String: JSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    public var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    public var doubleValue: Double? {
        guard case let .number(value) = self else { return nil }
        return value
    }

    public var intValue: Int? { doubleValue.flatMap(Int.init(exactly:)) }

    public var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }

    subscript(key: String) -> JSONValue? { objectValue?[key] }
}

private struct RPCRemoteError: Decodable, Sendable {
    public let code: Int?
    public let message: String
}

private struct RPCEnvelope: Decodable, Sendable {
    public let id: Int?
    public let method: String?
    public let params: JSONValue?
    public let result: JSONValue?
    public let error: RPCRemoteError?
}

private final class LinePump: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var lines: [Data] = []
    private var waiters: [CheckedContinuation<Data?, Never>] = []
    private var isFinished = false

    public init(handle: FileHandle) {
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

    public func next() async -> Data? {
        await withCheckedContinuation { continuation in
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

    public func finish() {
        lock.lock()
        guard !isFinished else { lock.unlock(); return }
        isFinished = true
        if !buffer.isEmpty {
            lines.append(buffer)
            buffer.removeAll()
        }
        let pending = waiters
        waiters.removeAll()
        let deliveries = pending.map { _ in lines.isEmpty ? nil : lines.removeFirst() }
        lock.unlock()
        for (waiter, data) in zip(pending, deliveries) { waiter.resume(returning: data) }
    }
}

private final class StderrDrain: @unchecked Sendable {
    private let lock = NSLock()
    private var tail = Data()
    private let maximumBytes = 4_096

    private var isFinished = false
    private var waiters: [CheckedContinuation<String, Never>] = []

    public func finishedMessage() async -> String {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isFinished {
                let message = String(decoding: tail, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                lock.unlock()
                continuation.resume(returning: message)
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    public func finish() {
        lock.lock()
        guard !isFinished else { lock.unlock(); return }
        isFinished = true
        let message = String(decoding: tail, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        pending.forEach { $0.resume(returning: message) }
    }

    public init(handle: FileHandle) {
        handle.readabilityHandler = { [weak self] readable in
            guard let self else { return }
            let data = readable.availableData
            guard !data.isEmpty else {
                readable.readabilityHandler = nil
                self.finish()
                return
            }
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
    private var didTimeout = false
    private var pendingNotifications: [RPCEnvelope] = []
    private var stopTask: Task<Bool, Never>?

    public init(executableURL: URL, profileHome: URL, environment inheritedEnvironment: [String: String],
                fileCredentials: Bool = false) throws {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        if fileCredentials {
            process.arguments?.append(contentsOf: ["-c", "cli_auth_credentials_store=\"file\""])
        }
        var environment = inheritedEnvironment
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

    public func initialize(timeout: Duration, clientVersion: String) async throws {
        try send([
            "method": "initialize",
            "id": 0,
            "params": [
                "clientInfo": [
                    "name": "codex_account_switcher",
                    "title": "Codex Account Switcher",
                    "version": clientVersion,
                ],
            ],
        ])
        _ = try await response(id: 0, timeout: timeout)
        try send(["method": "initialized", "params": [:]])
    }

    public func request(
        method: String,
        id: Int,
        params: [String: Any] = [:],
        timeout: Duration
    ) async throws -> JSONValue {
        try send(["method": method, "id": id, "params": params])
        let envelope = try await response(id: id, timeout: timeout)
        guard let result = envelope.result else { throw CodexClientError.malformedResponse }
        return result
    }

    public func notification(method: String, timeout: Duration) async throws -> JSONValue {
        let envelope = try await receive(
            where: { $0.method == method && $0.id == nil },
            timeout: timeout
        )
        return envelope.params ?? .object([:])
    }

    @discardableResult
    public func stop() async -> Bool {
        if let stopTask { return await stopTask.value }
        output.readabilityHandler = nil
        errorOutput.readabilityHandler = nil
        try? input.close()
        pump.finish()
        stderrDrain.finish()
        let process = process
        // Cleanup must survive cancellation of the request that owns this session.
        let task = Task.detached {
            if process.isRunning { process.terminate() }
            for _ in 0..<100 {
                if !process.isRunning { return true }
                try? await Task.sleep(for: .milliseconds(20))
            }
            #if canImport(Darwin) || canImport(Glibc)
            if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
            #endif
            // Poll Foundation's exit state instead of blocking an executor with
            // waitUntilExit. Never report a successful refresh with a live writer.
            for _ in 0..<50 {
                if !process.isRunning { return true }
                try? await Task.sleep(for: .milliseconds(20))
            }
            return !process.isRunning
        }
        stopTask = task
        return await task.value
    }

    private func response(id: Int, timeout: Duration) async throws -> RPCEnvelope {
        try await receive(where: { $0.id == id }, timeout: timeout)
    }

    private func receive(
        where predicate: @escaping @Sendable (RPCEnvelope) -> Bool,
        timeout: Duration
    ) async throws -> RPCEnvelope {
        if let index = pendingNotifications.firstIndex(where: predicate) {
            return pendingNotifications.remove(at: index)
        }
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

        while let line = await pump.next() {
            let message: RPCEnvelope
            do {
                message = try decoder.decode(RPCEnvelope.self, from: line)
            } catch {
                throw CodexClientError.malformedResponse
            }
            if predicate(message) {
                if let error = message.error {
                    throw CodexClientError.remoteError(code: error.code, message: error.message)
                }
                return message
            }
            // Login completion can arrive before the login/start response.
            if message.method == "account/login/completed", message.id == nil {
                pendingNotifications.append(message)
                if pendingNotifications.count > 16 { pendingNotifications.removeFirst() }
            }
        }
        if didTimeout { throw CodexClientError.timeout }
        let details = await stderrDrain.finishedMessage()
        if didTimeout { throw CodexClientError.timeout }
        if !details.isEmpty { throw CodexClientError.connectionClosedWithDetails(details) }
        throw CodexClientError.connectionClosed
    }

    private func triggerTimeout() async {
        didTimeout = true
        await stop()
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

public struct CodexExecutableLocator: Sendable {
    public let explicitURL: URL?
    private let desktopApplicationURLs: [URL]

    public init(explicitURL: URL? = nil, desktopApplicationURLs: [URL] = [
        URL(fileURLWithPath: "/Applications/ChatGPT.app"),
        URL(fileURLWithPath: "/Applications/Codex.app"),
    ]) {
        self.explicitURL = explicitURL
        self.desktopApplicationURLs = desktopApplicationURLs
    }

    public func locate(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> URL {
        if let explicitURL, isExecutable(explicitURL.path) {
            return explicitURL
        }
        let command = environment["CODEX_CLI_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let executable = command.flatMap { $0.isEmpty ? nil : $0 } ?? "codex"
        #if os(Windows)
        if executable.contains("/") || executable.contains("\\") {
            guard URL(fileURLWithPath: executable).path == executable.replacingOccurrences(of: "\\", with: "/")
                    || (executable.count > 2 && executable[executable.index(after: executable.startIndex)] == ":") else {
                throw CodexClientError.executableNotFound
            }
            guard isExecutable(executable) else { throw CodexClientError.executableNotFound }
            return URL(fileURLWithPath: executable)
        }
        for directory in (environment["Path"] ?? environment["PATH"] ?? "").split(separator: ";") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(
                executable.lowercased().hasSuffix(".exe") ? executable : executable + ".exe")
            if isExecutable(candidate.path) { return candidate }
        }
        if let local = environment["LOCALAPPDATA"] {
            let bin = URL(fileURLWithPath: local).appendingPathComponent("OpenAI/Codex/bin")
            let versions = (try? FileManager.default.contentsOfDirectory(at: bin,
                includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for version in versions.sorted(by: {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }) {
                let candidate = version.appendingPathComponent("codex.exe")
                if isExecutable(candidate.path) { return candidate }
            }
        }
        #else
        if executable.contains("/") {
            guard executable.hasPrefix("/"), isExecutable(executable) else {
                throw CodexClientError.processLaunchFailed("CODEX_CLI_PATH is not executable: \(executable)")
            }
            return URL(fileURLWithPath: executable)
        }
        if let path = environment["PATH"]?
            .split(separator: ":")
            .filter({ $0.hasPrefix("/") })
            .map({ String($0) + "/" + executable })
            .first(where: isExecutable)
        {
            return URL(fileURLWithPath: path)
        }
        #if os(macOS)
        if command == nil || command == "" {
            for applicationURL in desktopApplicationURLs {
                for relativePath in [
                    "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
                    "Contents/Resources/codex",
                ] {
                    let bundledCLI = applicationURL.appendingPathComponent(relativePath)
                    if isExecutable(bundledCLI.path) { return bundledCLI }
                }
            }
        }
        #endif
        #endif
        throw CodexClientError.executableNotFound
    }

    public func launchConfiguration(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        requireDirectExecutable: Bool = false
    ) throws -> (executable: URL, environment: [String: String]) {
        var environment = environment
        #if !os(Windows)
        if explicitURL == nil {
            // GUI apps do not inherit the terminal's login PATH. Read the same shell settings
            // Desktop uses, and pass that PATH to npm's `#!/usr/bin/env node` launcher as well.
            let shell = Process()
            let output = Pipe()
            shell.executableURL = URL(fileURLWithPath: environment["SHELL"] ?? "/bin/zsh")
            // Quoted PATH is colon-separated in fish too. Keep defaulting in locate()
            // because fish does not support POSIX ${VAR:-default} expansion.
            shell.arguments = ["-l", "-c", "printf '\\0%s\\0%s\\0' \"$PATH\" \"$CODEX_CLI_PATH\""]
            shell.environment = environment
            shell.standardOutput = output
            shell.standardError = FileHandle.nullDevice
            try shell.run()
            let bytes = output.fileHandleForReading.readDataToEndOfFile()
            shell.waitUntilExit()
            let fields = String(decoding: bytes, as: UTF8.self).split(separator: "\0", omittingEmptySubsequences: false)
            guard shell.terminationStatus == 0, fields.count >= 4 else {
                throw CodexClientError.processLaunchFailed("Could not read the login shell's Codex path.")
            }
            environment["PATH"] = String(fields[fields.count - 3])
            environment["CODEX_CLI_PATH"] = String(fields[fields.count - 2])
        }
        #endif
        let executable = try locate(environment: environment)
        return (requireDirectExecutable ? try credentialRefreshExecutable(executable) : executable, environment)
    }

    private func credentialRefreshExecutable(_ executable: URL) throws -> URL {
        let resolved = executable.resolvingSymlinksInPath().standardizedFileURL
        // The official npm entry spawns a native child. Launch that child directly
        // so the session's exit wait covers the process that can write auth.json.
        if resolved.lastPathComponent == "codex.js", resolved.deletingLastPathComponent().lastPathComponent == "bin" {
            let root = resolved.deletingLastPathComponent().deletingLastPathComponent()
            if let data = try? Data(contentsOf: root.appendingPathComponent("package.json")),
               let manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               manifest["name"] as? String == "@openai/codex",
               let bin = manifest["bin"] as? [String: Any],
               let entry = bin["codex"] as? String,
               root.appendingPathComponent(entry).resolvingSymlinksInPath().standardizedFileURL == resolved {
                let (package, triple, name) = try npmPlatform()
                var vendor = root.appendingPathComponent("vendor")
                // Match Node's ancestor node_modules lookup, including hoisted
                // dependencies and symlinked pnpm package directories.
                var directory = root.standardizedFileURL
                for _ in 0..<256 {
                    if directory.lastPathComponent != "node_modules" {
                        let dependency = directory.appendingPathComponent("node_modules/\(package)")
                        if FileManager.default.fileExists(atPath: dependency.appendingPathComponent("package.json").path) {
                            vendor = dependency.appendingPathComponent("vendor")
                            break
                        }
                    }
                    if directory.path == "/" { break }
                    let parent = directory.deletingLastPathComponent().standardizedFileURL
                    if parent.path == directory.path { break }
                    directory = parent
                }
                for folder in ["bin", "codex"] {
                    let native = vendor.appendingPathComponent("\(triple)/\(folder)/\(name)")
                    if isExecutable(native.path) {
                        return try checkedNativeExecutable(native.resolvingSymlinksInPath())
                    }
                }
                throw CodexClientError.processLaunchFailed("The official Codex npm package is missing its native executable.")
            }
        }
        return try checkedNativeExecutable(executable)
    }

    private func checkedNativeExecutable(_ executable: URL) throws -> URL {
        let handle = try FileHandle(forReadingFrom: executable)
        defer { try? handle.close() }
        let prefix = Array(try handle.read(upToCount: 4) ?? Data())
        let machHeaders: [[UInt8]] = [
            [0xfe, 0xed, 0xfa, 0xce], [0xce, 0xfa, 0xed, 0xfe],
            [0xfe, 0xed, 0xfa, 0xcf], [0xcf, 0xfa, 0xed, 0xfe],
            [0xca, 0xfe, 0xba, 0xbe], [0xbe, 0xba, 0xfe, 0xca],
            [0xca, 0xfe, 0xba, 0xbf], [0xbf, 0xba, 0xfe, 0xca],
        ]
        let isNative = machHeaders.contains(prefix) || prefix == [0x7f, 0x45, 0x4c, 0x46]
            || prefix.starts(with: [0x4d, 0x5a])
        guard isNative else {
            throw CodexClientError.processLaunchFailed("Credential renewal requires a native Codex executable or its official npm launcher.")
        }
        return executable
    }

    private func npmPlatform() throws -> (package: String, triple: String, name: String) {
        #if arch(arm64)
        let cpu = "arm64"
        let machine = "aarch64"
        #elseif arch(x86_64)
        let cpu = "x64"
        let machine = "x86_64"
        #else
        throw CodexClientError.processLaunchFailed("Unsupported Codex npm architecture.")
        #endif
        #if os(macOS)
        return ("@openai/codex-darwin-\(cpu)", "\(machine)-apple-darwin", "codex")
        #elseif os(Windows)
        return ("@openai/codex-win32-\(cpu)", "\(machine)-pc-windows-msvc", "codex.exe")
        #elseif os(Linux)
        return ("@openai/codex-linux-\(cpu)", "\(machine)-unknown-linux-musl", "codex")
        #else
        throw CodexClientError.processLaunchFailed("Unsupported Codex npm platform.")
        #endif
    }

    private func isExecutable(_ path: String) -> Bool {
        #if os(Windows)
        var isDirectory: ObjCBool = false
        return path.lowercased().hasSuffix(".exe")
            && FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
        #else
        FileManager.default.isExecutableFile(atPath: path)
        #endif
    }
}

public protocol AccountClient: CodexIdentityReading {
    func readWeeklyUsage(profileHome: URL) async throws -> WeeklyUsage
    func refreshIdentity(profileHome: URL) async throws -> AccountIdentity
    func login(profileHome: URL) async throws -> AccountIdentity
}

extension AccountClient {
    public func refreshIdentity(profileHome: URL) async throws -> AccountIdentity {
        throw CodexClientError.identityUnavailable
    }
}

public struct CodexClient: AccountClient {
    public let locator: CodexExecutableLocator
    public let requestTimeout: Duration
    public let clientVersion: String
    private let openBrowser: @Sendable (URL) async throws -> Void

    public init(locator: CodexExecutableLocator = .init(), requestTimeout: Duration = .seconds(20),
                clientVersion: String = "0.1.21",
                openBrowser: @escaping @Sendable (URL) async throws -> Void = CodexClient.defaultOpenBrowser) {
        self.locator = locator
        self.requestTimeout = requestTimeout
        self.clientVersion = clientVersion
        self.openBrowser = openBrowser
    }

    public static func defaultOpenBrowser(_ url: URL) async throws {
        #if canImport(AppKit)
        guard await MainActor.run(body: { NSWorkspace.shared.open(url) }) else {
            throw CodexClientError.loginFailed("The sign-in page could not be opened.")
        }
        #else
        throw CodexClientError.loginFailed("A native browser adapter is required.")
        #endif
    }

    public func readIdentity(profileHome: URL) async throws -> AccountIdentity {
        let result = try await withSession(profileHome: profileHome) { session in
            try await session.request(
                method: "account/read",
                id: 1,
                params: ["refreshToken": false],
                timeout: requestTimeout
            )
        }
        return try parseIdentity(result, profileHome: profileHome)
    }

    public func readWeeklyUsage(profileHome: URL) async throws -> WeeklyUsage {
        let result = try await withSession(profileHome: profileHome) { session in
            try await session.request(
                method: "account/rateLimits/read",
                id: 1,
                timeout: requestTimeout
            )
        }
        let availableCount = result["rateLimitResetCredits"]?["availableCount"]?.intValue
        return try WeeklyUsageNormalizer.normalize(
            parseWindows(result),
            resetCreditsRemaining: availableCount.flatMap { $0 >= 0 ? $0 : nil }
        )
    }

    public func refreshIdentity(profileHome: URL) async throws -> AccountIdentity {
        let result = try await withSession(profileHome: profileHome, fileCredentials: true) { session in
            try await session.request(method: "account/read", id: 1,
                                      params: ["refreshToken": true], timeout: requestTimeout)
        }
        return try parseIdentity(result, profileHome: profileHome)
    }

    public func login(profileHome: URL) async throws -> AccountIdentity {
        try await withSession(profileHome: profileHome) { session in
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
            try await openBrowser(authURL)

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
            return try parseIdentity(identityValue, profileHome: profileHome)
        }
    }

    private func withSession<T: Sendable>(
        profileHome: URL,
        fileCredentials: Bool = false,
        operation: (JSONRPCSession) async throws -> T
    ) async throws -> T {
        let launch = try locator.launchConfiguration(requireDirectExecutable: fileCredentials)
        let session = try JSONRPCSession(executableURL: launch.executable, profileHome: profileHome,
                                         environment: launch.environment, fileCredentials: fileCredentials)
        return try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                try await session.initialize(timeout: requestTimeout, clientVersion: clientVersion)
                let result = try await operation(session)
                guard await session.stop() else { throw CodexClientError.timeout }
                try Task.checkCancellation()
                return result
            } catch {
                await session.stop()
                if Task.isCancelled { throw CancellationError() }
                throw error
            }
        } onCancel: {
            Task { await session.stop() }
        }
    }

    private func parseIdentity(_ value: JSONValue, profileHome: URL) throws -> AccountIdentity {
        guard let account = value["account"]?.objectValue else {
            throw CodexClientError.identityUnavailable
        }
        var accountID = account["accountId"]?.stringValue
            ?? account["accountID"]?.stringValue
            ?? account["chatgptAccountId"]?.stringValue
            ?? account["id"]?.stringValue
        let email = account["email"]?.stringValue
        if accountID == nil, let credential = try CredentialIdentity.read(from: profileHome) {
            if let email, let credentialEmail = credential.email,
               email.caseInsensitiveCompare(credentialEmail) != .orderedSame {
                throw CodexClientError.identityUnavailable
            }
            accountID = credential.accountID
        }
        guard accountID != nil || email != nil else {
            throw CodexClientError.identityUnavailable
        }
        return AccountIdentity(accountID: accountID, email: email)
    }

    private func parseWindows(_ value: JSONValue) -> [RateLimitWindow] {
        guard let bucket = value["rateLimitsByLimitId"]?["codex"] ?? value["rateLimits"] else {
            return []
        }
        return [bucket["primary"], bucket["secondary"]].compactMap(parseWindow)
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
