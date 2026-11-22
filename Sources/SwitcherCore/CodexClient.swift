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
    private let maximumQueuedLines = 256

    public init(handle: FileHandle) {
        handle.readabilityHandler = { [weak self] readable in
            guard let self else {
                readable.readabilityHandler = nil
                return
            }
            let data = readable.availableData
            guard !data.isEmpty else {
                // Must clear readabilityHandler on EOF to avoid Darwin EV_EOF spin loops.
                readable.readabilityHandler = nil
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
            if lines.count >= maximumQueuedLines {
                lines.removeFirst(lines.count - maximumQueuedLines + 1)
            }
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
            guard let self else {
                readable.readabilityHandler = nil
                return
            }
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
    private static let isolatedArguments = [
        "app-server",
        "-c", "cli_auth_credentials_store=\"file\"",
        "-c", "features.plugins=false",
        "-c", "features.remote_plugin=false",
        "-c", "features.apps=false",
        "-c", "features.shell_snapshot=false",
    ]

    private let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private let errorOutput: FileHandle
    private let pump: LinePump
    private let stderrDrain: StderrDrain
    private let decoder = JSONDecoder()
    private var didTimeout = false
    private var pendingNotifications: [RPCEnvelope] = []
    private let stopState = SessionStopState()
    private var didStop = false

    public init(executableURL: URL, profileHome: URL, environment inheritedEnvironment: [String: String]) throws {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = Self.isolatedArguments
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
            output.readabilityHandler = nil
            errorOutput.readabilityHandler = nil
            throw CodexClientError.processLaunchFailed(error.localizedDescription)
        }
    }

    deinit {
        output.readabilityHandler = nil
        errorOutput.readabilityHandler = nil
        try? input.close()
        if process.isRunning { process.terminate() }
        pump.finish()
        stderrDrain.finish()
    }

    public var isRunning: Bool { process.isRunning && !didStop }

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
        try Task.checkCancellation()
        try send(["method": method, "id": id, "params": params])
        let envelope = try await response(id: id, timeout: timeout)
        guard let result = envelope.result else { throw CodexClientError.malformedResponse }
        return result
    }

    public func notification(
        method: String,
        timeout: Duration,
        matching matches: @escaping @Sendable (JSONValue) -> Bool = { _ in true }
    ) async throws -> JSONValue {
        let envelope = try await receive(
            where: { $0.method == method && $0.id == nil && matches($0.params ?? .object([:])) },
            timeout: timeout
        )
        return envelope.params ?? .object([:])
    }

    @discardableResult
    public func stop() async -> Bool {
        didStop = true
        output.readabilityHandler = nil
        errorOutput.readabilityHandler = nil
        try? input.close()
        pump.finish()
        stderrDrain.finish()
        let process = process
        return await stopState.stop(isRunning: { process.isRunning }) {
            if process.isRunning { process.terminate() }
            for _ in 0..<100 {
                if !process.isRunning { return true }
                try? await Task.sleep(for: .milliseconds(20))
            }
            #if canImport(Darwin) || canImport(Glibc)
            if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
            #endif
            for _ in 0..<50 {
                if !process.isRunning { return true }
                try? await Task.sleep(for: .milliseconds(20))
            }
            return !process.isRunning
        }
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
            } catch {}
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
            if message.id == nil, message.method == "account/login/completed" || message.method == "turn/completed" {
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
        URL(fileURLWithPath: "/Applications/Codex.app"),
        URL(fileURLWithPath: "/Applications/ChatGPT.app"),
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
            let dirURL = URL(fileURLWithPath: String(directory))
            let candidate = dirURL.appendingPathComponent(
                executable.lowercased().hasSuffix(".exe") ? executable : executable + ".exe")
            if isExecutable(candidate.path) { return candidate }
            // Support standard Windows global npm installations (`codex.cmd` -> `@openai/codex` native binary).
            if command == nil || command == "" || executable.caseInsensitiveCompare("codex") == .orderedSame {
                let npmScript = dirURL.appendingPathComponent("node_modules/@openai/codex/bin/codex.js")
                if FileManager.default.fileExists(atPath: dirURL.appendingPathComponent("codex.cmd").path),
                   let native = try? unwrapOfficialNPMLauncher(npmScript) {
                    return native
                }
            }
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
            let resolved = try Self.readLoginShellEnvironmentSync(environment: environment)
            environment["PATH"] = resolved.path
            environment["CODEX_CLI_PATH"] = resolved.codexCLIPath
        }
        #endif
        return try finalizeLaunchConfiguration(environment: environment, requireDirectExecutable: requireDirectExecutable)
    }

    func launchConfigurationAsync(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        requireDirectExecutable: Bool = false,
        shellTimeout: Duration = .seconds(5)
    ) async throws -> (executable: URL, environment: [String: String]) {
        var environment = environment
        #if !os(Windows)
        if explicitURL == nil {
            let resolved = try await Self.readLoginShellEnvironmentAsync(environment: environment, timeout: shellTimeout)
            environment["PATH"] = resolved.path
            environment["CODEX_CLI_PATH"] = resolved.codexCLIPath
        }
        #endif
        return try finalizeLaunchConfiguration(environment: environment, requireDirectExecutable: requireDirectExecutable)
    }

    private func finalizeLaunchConfiguration(
        environment: [String: String],
        requireDirectExecutable: Bool
    ) throws -> (executable: URL, environment: [String: String]) {
        let located = try locate(environment: environment)
        if let native = try unwrapOfficialLauncher(located) {
            return (native, environment)
        }
        return (requireDirectExecutable ? try checkedNativeExecutable(located) : located, environment)
    }

    #if !os(Windows)
    private static func parseShellFields(_ bytes: Data, status: Int32) throws -> (path: String, codexCLIPath: String) {
        let fields = String(decoding: bytes, as: UTF8.self).split(separator: "\0", omittingEmptySubsequences: false)
        guard status == 0, fields.count >= 4 else {
            throw CodexClientError.processLaunchFailed("Could not read the login shell's Codex path.")
        }
        return (String(fields[fields.count - 3]), String(fields[fields.count - 2]))
    }

    private static func readLoginShellEnvironmentSync(environment: [String: String]) throws -> (path: String, codexCLIPath: String) {
        let shell = Process()
        let output = Pipe()
        shell.executableURL = URL(fileURLWithPath: environment["SHELL"] ?? "/bin/zsh")
        shell.arguments = ["-l", "-c", "printf '\\0%s\\0%s\\0' \"$PATH\" \"$CODEX_CLI_PATH\""]
        shell.environment = environment
        shell.standardOutput = output
        shell.standardError = FileHandle.nullDevice
        try shell.run()
        let bytes = output.fileHandleForReading.readDataToEndOfFile()
        shell.waitUntilExit()
        return try parseShellFields(bytes, status: shell.terminationStatus)
    }

    private static func readLoginShellEnvironmentAsync(
        environment: [String: String],
        timeout: Duration
    ) async throws -> (path: String, codexCLIPath: String) {
        let shell = Process()
        let output = Pipe()
        let handle = output.fileHandleForReading
        shell.executableURL = URL(fileURLWithPath: environment["SHELL"] ?? "/bin/zsh")
        shell.arguments = ["-l", "-c", "printf '\\0%s\\0%s\\0' \"$PATH\" \"$CODEX_CLI_PATH\""]
        shell.environment = environment
        shell.standardOutput = output
        shell.standardError = FileHandle.nullDevice

        let collector = ShellOutputCollector(handle: handle)
        let timeoutTask = Task {
            try? await Task.sleep(for: timeout)
            if shell.isRunning {
                shell.terminate()
                try? await Task.sleep(for: .milliseconds(100))
                if shell.isRunning { _ = kill(shell.processIdentifier, SIGKILL) }
            }
        }
        defer { timeoutTask.cancel() }

        return try await withTaskCancellationHandler {
            let status: Int32 = try await withCheckedThrowingContinuation { continuation in
                shell.terminationHandler = { finished in
                    continuation.resume(returning: finished.terminationStatus)
                }
                do {
                    try shell.run()
                } catch {
                    shell.terminationHandler = nil
                    handle.readabilityHandler = nil
                    collector.finish()
                    continuation.resume(throwing: CodexClientError.processLaunchFailed(error.localizedDescription))
                }
            }
            let bytes = await collector.bytes()
            return try parseShellFields(bytes, status: status)
        } onCancel: {
            if shell.isRunning { shell.terminate() }
        }
    }
    #endif

    /// Unwraps official Codex wrapper scripts (`@openai/codex` `bin/codex.js` or Desktop's
    /// `Contents/Resources/codex-cli/bin/codex`) to their underlying native binary so process
    /// lifecycle management tracks the actual `codex` process directly.
    private func unwrapOfficialLauncher(_ executable: URL) throws -> URL? {
        let resolved = executable.resolvingSymlinksInPath().standardizedFileURL
        if resolved.lastPathComponent == "codex",
           resolved.deletingLastPathComponent().lastPathComponent == "bin",
           resolved.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "codex-cli" {
            let bundled = resolved
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("CodexCLI.app/Contents/MacOS/codex")
            if isExecutable(bundled.path) {
                return try checkedNativeExecutable(bundled)
            }
        }
        return try unwrapOfficialNPMLauncher(executable)
    }

    private func unwrapOfficialNPMLauncher(_ executable: URL) throws -> URL? {
        let resolved = executable.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.lastPathComponent == "codex.js",
              resolved.deletingLastPathComponent().lastPathComponent == "bin" else {
            return nil
        }
        let root = resolved.deletingLastPathComponent().deletingLastPathComponent()
        guard let data = try? Data(contentsOf: root.appendingPathComponent("package.json")),
              let manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              manifest["name"] as? String == "@openai/codex",
              let bin = manifest["bin"] as? [String: Any],
              let entry = bin["codex"] as? String,
              root.appendingPathComponent(entry).resolvingSymlinksInPath().standardizedFileURL == resolved else {
            return nil
        }
        let (package, triple, name) = try npmPlatform()
        var vendor = root.appendingPathComponent("vendor")
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

    private func checkedNativeExecutable(_ executable: URL) throws -> URL {
        let resolved = executable.resolvingSymlinksInPath()
        let handle = try FileHandle(forReadingFrom: resolved)
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
        return resolved
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

    func isExecutable(_ path: String) -> Bool {
        #if os(Windows)
        var isDirectory: ObjCBool = false
        return path.lowercased().hasSuffix(".exe")
            && FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
        #else
        FileManager.default.isExecutableFile(atPath: path)
        #endif
    }
}

#if !os(Windows)
private final class ShellOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var finished = false
    private var waiters: [CheckedContinuation<Data, Never>] = []

    init(handle: FileHandle) {
        handle.readabilityHandler = { [weak self] readable in
            guard let self else {
                readable.readabilityHandler = nil
                return
            }
            let chunk = readable.availableData
            guard !chunk.isEmpty else {
                readable.readabilityHandler = nil
                self.finish()
                return
            }
            self.lock.lock()
            self.data.append(chunk)
            self.lock.unlock()
        }
    }

    func finish() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let snapshot = data
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        pending.forEach { $0.resume(returning: snapshot) }
    }

    func bytes() async -> Data {
        await withCheckedContinuation { continuation in
            lock.lock()
            if finished {
                let snapshot = data
                lock.unlock()
                continuation.resume(returning: snapshot)
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }
}
#endif

private actor LaunchConfigurationCache {
    private struct Entry {
        let executable: URL
        let environment: [String: String]
        let resolvedAt: ContinuousClock.Instant
    }

    private var cached: Entry?
    private let ttl: Duration = .seconds(300)

    func resolve(
        using locator: CodexExecutableLocator,
        requireDirectExecutable: Bool
    ) async throws -> (executable: URL, environment: [String: String]) {
        if locator.explicitURL != nil {
            return try await locator.launchConfigurationAsync(requireDirectExecutable: requireDirectExecutable)
        }
        if !requireDirectExecutable,
           let cached,
           ContinuousClock.now - cached.resolvedAt < ttl,
           locator.isExecutable(cached.executable.path) {
            return (cached.executable, cached.environment)
        }
        let fresh = try await locator.launchConfigurationAsync(requireDirectExecutable: requireDirectExecutable)
        if !requireDirectExecutable {
            cached = Entry(executable: fresh.executable, environment: fresh.environment, resolvedAt: .now)
        }
        return fresh
    }
}

public enum ResetCreditOutcome: String, Codable, Sendable {
    case reset, nothingToReset, noCredit, alreadyRedeemed
}

public protocol AccountClient: CodexIdentityReading {
    func readWeeklyUsage(profileHome: URL) async throws -> WeeklyUsage
    func stopUsageSessions() async throws
    func stopUsageSession(profileHome: URL) async throws
    func forgetUsageSession(profileHome: URL) async throws
    func consumeResetCredit(profileHome: URL, creditID: String, idempotencyKey: String) async throws -> ResetCreditOutcome
    func startWeeklyUsageWindow(profileHome: URL) async throws
    func refreshIdentity(profileHome: URL) async throws -> AccountIdentity
    func login(profileHome: URL) async throws -> AccountIdentity
}

extension AccountClient {
    public func stopUsageSessions() async throws {}
    public func stopUsageSession(profileHome: URL) async throws { try await stopUsageSessions() }
    public func forgetUsageSession(profileHome: URL) async throws { try await stopUsageSession(profileHome: profileHome) }

    public func startWeeklyUsageWindow(profileHome: URL) async throws {
        throw CodexClientError.remoteError(code: nil, message: "Starting a weekly usage window is unavailable.")
    }

    public func refreshIdentity(profileHome: URL) async throws -> AccountIdentity {
        throw CodexClientError.identityUnavailable
    }
}

public struct CodexClient: AccountClient {
    public let locator: CodexExecutableLocator
    public let requestTimeout: Duration
    public let clientVersion: String
    private let usageSessions: UsageSessions
    private let launchCache = LaunchConfigurationCache()
    private let openBrowser: @Sendable (URL) async throws -> Void

    public init(
        locator: CodexExecutableLocator = .init(),
        requestTimeout: Duration = .seconds(20),
        clientVersion: String = SwitcherVersion.current,
        usageSessionIdleTimeout: Duration = .seconds(90),
        openBrowser: @escaping @Sendable (URL) async throws -> Void = CodexClient.defaultOpenBrowser
    ) {
        self.usageSessions = UsageSessions(idleTimeout: usageSessionIdleTimeout)
        self.locator = locator
        self.requestTimeout = requestTimeout
        self.clientVersion = clientVersion
        self.openBrowser = openBrowser
    }

    @Sendable
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
        let worker = await usageSessions.worker(for: profileHome)
        let locator = locator
        let launchCache = launchCache
        let result = try await worker.read(
            resolveLaunch: {
                let launch = try await launchCache.resolve(using: locator, requireDirectExecutable: false)
                return (launch.executable, Self.profileEnvironment(launch.environment))
            },
            timeout: requestTimeout,
            clientVersion: clientVersion
        )
        let availableCount = result["rateLimitResetCredits"]?["availableCount"]?.intValue
        let credits: [BankedResetCredit]?
        switch result["rateLimitResetCredits"]?["credits"] {
        case let .array(rows):
            credits = try rows.map { row in
                guard let id = row["id"]?.stringValue, !id.isEmpty,
                      let status = row["status"]?.stringValue,
                      let resetType = row["resetType"]?.stringValue else {
                    throw CodexClientError.malformedResponse
                }
                let expiresAt: Date?
                switch row["expiresAt"] {
                case .none, .null: expiresAt = nil
                case let .number(seconds) where seconds.isFinite:
                    expiresAt = Date(timeIntervalSince1970: seconds)
                default: throw CodexClientError.malformedResponse
                }
                return BankedResetCredit(id: id, status: status, resetType: resetType, expiresAt: expiresAt)
            }
        case .none, .null: credits = nil
        default: throw CodexClientError.malformedResponse
        }
        let bucket = result["rateLimitsByLimitId"]?["codex"] ?? result["rateLimits"]
        return try WeeklyUsageNormalizer.normalize(
            [bucket?["primary"], bucket?["secondary"]].compactMap(parseWindow),
            resetCreditsRemaining: availableCount.flatMap { $0 >= 0 ? $0 : nil },
            resetCredits: credits,
            ordinaryUsageAllowed: bucket?["ordinaryUsageAllowed"]?.boolValue
        )
    }

    public func refreshIdentity(profileHome: URL) async throws -> AccountIdentity {
        let worker = await usageSessions.worker(for: profileHome)
        let result = try await worker.withStoppedSession {
            try await withSession(profileHome: profileHome, requireDirectExecutable: true) { session in
                try await session.request(method: "account/read", id: 1,
                                          params: ["refreshToken": true], timeout: requestTimeout)
            }
        }
        return try parseIdentity(result, profileHome: profileHome)
    }

    public func consumeResetCredit(profileHome: URL, creditID: String, idempotencyKey: String) async throws -> ResetCreditOutcome {
        let worker = await usageSessions.worker(for: profileHome)
        let result = try await worker.withStoppedSession {
            try await withSession(profileHome: profileHome) { session in
                try await session.request(
                    method: "account/rateLimitResetCredit/consume", id: 1,
                    params: ["creditId": creditID, "idempotencyKey": idempotencyKey],
                    timeout: requestTimeout
                )
            }
        }
        guard let value = result["outcome"]?.stringValue,
              let outcome = ResetCreditOutcome(rawValue: value) else {
            throw CodexClientError.malformedResponse
        }
        return outcome
    }

    public func startWeeklyUsageWindow(profileHome: URL) async throws {
        let worker = await usageSessions.worker(for: profileHome)
        try await worker.withStoppedSession {
            try await withSession(profileHome: profileHome, requireDirectExecutable: true,
                                  useProfileAuthenticationOnly: true) { session in
                let account = try await session.request(
                    method: "account/read", id: 1, params: ["refreshToken": false], timeout: requestTimeout
                )
                guard account["account"]?["type"]?.stringValue == "chatgpt" else {
                    throw CodexClientError.identityUnavailable
                }

                let thread = try await session.request(
                    method: "thread/start", id: 2,
                    params: [
                        "ephemeral": true,
                        "modelProvider": "openai",
                        "approvalPolicy": "never",
                        "sandbox": "read-only",
                        "cwd": FileManager.default.temporaryDirectory.path,
                        "baseInstructions": "Reply with exactly OK. Do not use tools.",
                    ],
                    timeout: requestTimeout
                )
                guard let threadID = thread["thread"]?["id"]?.stringValue else {
                    throw CodexClientError.malformedResponse
                }

                let started = try await session.request(
                    method: "turn/start", id: 3,
                    params: [
                        "threadId": threadID,
                        "input": [["type": "text", "text": "只回复 OK"]],
                        "serviceTier": "default",
                    ],
                    timeout: requestTimeout
                )
                guard let turnID = started["turn"]?["id"]?.stringValue else {
                    throw CodexClientError.malformedResponse
                }
                let completed = try await session.notification(method: "turn/completed", timeout: requestTimeout) {
                    $0["threadId"]?.stringValue == threadID && $0["turn"]?["id"]?.stringValue == turnID
                }
                guard let status = completed["turn"]?["status"]?.stringValue else {
                    throw CodexClientError.malformedResponse
                }
                guard status == "completed" else {
                    throw CodexClientError.remoteError(code: nil, message: "The weekly usage request ended with status \(status).")
                }
            }
        }
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

    public func stopUsageSessions() async throws {
        try await usageSessions.stop()
    }

    public func stopUsageSession(profileHome: URL) async throws {
        try await usageSessions.stop(for: profileHome)
    }

    public func forgetUsageSession(profileHome: URL) async throws {
        try await usageSessions.forget(for: profileHome)
    }

    var usageSessionCount: Int { get async { await usageSessions.count } }

    private func withSession<T: Sendable>(
        profileHome: URL,
        requireDirectExecutable: Bool = false,
        useProfileAuthenticationOnly: Bool = false,
        operation: (JSONRPCSession) async throws -> T
    ) async throws -> T {
        let launch = try await launchCache.resolve(using: locator, requireDirectExecutable: requireDirectExecutable)
        let environment = useProfileAuthenticationOnly ? Self.profileEnvironment(launch.environment) : launch.environment
        let session = try JSONRPCSession(executableURL: launch.executable, profileHome: profileHome,
                                         environment: environment)
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

    private static func profileEnvironment(_ environment: [String: String]) -> [String: String] {
        // Read quota and start turns for the saved profile even if the app inherited another login or endpoint.
        var isolated = environment
        for name in ["CODEX_API_KEY", "CODEX_ACCESS_TOKEN", "OPENAI_API_KEY", "OPENAI_BASE_URL",
                     "OPENAI_FEDERATION_RULE_ID", "OPENAI_IDENTITY_TOKEN_FILE", "CODEX_SQLITE_HOME",
                     "CODEX_REFRESH_TOKEN_URL_OVERRIDE", "CODEX_REVOKE_TOKEN_URL_OVERRIDE"] {
            isolated.removeValue(forKey: name)
        }
        return isolated
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

// One serialized quota channel per profile with genuine idle expiration between 5-minute polls.
private actor UsageSessions {
    private var workers: [URL: UsageSession] = [:]
    private let idleTimeout: Duration

    init(idleTimeout: Duration) { self.idleTimeout = idleTimeout }

    func worker(for home: URL) -> UsageSession {
        let key = home.standardizedFileURL
        if let worker = workers[key] { return worker }
        let worker = UsageSession(home: key, idleTimeout: idleTimeout)
        workers[key] = worker
        return worker
    }

    var count: Int { workers.count }

    func stop(for home: URL) async throws {
        try await workers[home.standardizedFileURL]?.stop()
    }

    func forget(for home: URL) async throws {
        let key = home.standardizedFileURL
        guard let worker = workers[key] else { return }
        try await worker.retire()
        if workers[key] === worker { workers.removeValue(forKey: key) }
    }

    func stop() async throws {
        let snapshot = Array(workers.values)
        var firstError: (any Error)?
        await withTaskGroup(of: (any Error)?.self) { group in
            for worker in snapshot {
                group.addTask {
                    do { try await worker.stop(); return nil }
                    catch { return error }
                }
            }
            for await error in group { if firstError == nil { firstError = error } }
        }
        if let firstError { throw firstError }
    }
}

private actor UsageSession {
    private let home: URL
    private let idleTimeout: Duration
    private var session: JSONRPCSession?
    private var credential: Data?
    private var executable: URL?
    private var tail: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var generation = 0
    private var nextID = 1
    private var retired = false

    init(home: URL, idleTimeout: Duration) { self.home = home; self.idleTimeout = idleTimeout }

    func read(
        resolveLaunch: @escaping @Sendable () async throws -> (executable: URL, environment: [String: String]),
        timeout: Duration,
        clientVersion: String
    ) async throws -> JSONValue {
        let previous = tail
        let task = Task {
            await previous?.value
            try Task.checkCancellation()
            return try await self.performRead(resolveLaunch: resolveLaunch, timeout: timeout, clientVersion: clientVersion)
        }
        tail = Task { _ = await task.result }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
    }

    func stop() async throws {
        let previous = tail
        let task = Task {
            await previous?.value
            try await self.close()
        }
        tail = Task { _ = await task.result }
        try await task.value
    }

    func withStoppedSession<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task {
            await previous?.value
            try Task.checkCancellation()
            guard !self.retired else { throw CodexClientError.connectionClosed }
            try await self.close()
            return try await operation()
        }
        tail = Task { _ = await task.result }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    func retire() async throws {
        let previous = tail
        let task = Task {
            await previous?.value
            try await self.close()
            self.retired = true
        }
        tail = Task { _ = await task.result }
        try await task.value
    }

    private func cleanup(after error: any Error) async throws -> Never {
        try await SessionFailure.finish(error, cancelled: Task.isCancelled || error is CancellationError) {
            try await self.close()
        }
    }

    private func close() async throws {
        idleTask?.cancel()
        idleTask = nil
        generation += 1
        if let session {
            guard await session.stop() else { throw CodexClientError.timeout }
        }
        session = nil
        credential = nil
        executable = nil
    }

    private func performRead(
        resolveLaunch: @Sendable () async throws -> (executable: URL, environment: [String: String]),
        timeout: Duration,
        clientVersion: String
    ) async throws -> JSONValue {
        guard !retired else { throw CodexClientError.connectionClosed }
        idleTask?.cancel()
        let currentCredential: Data?
        do {
            currentCredential = try readCredential()
        } catch {
            try await close()
            throw error
        }
        // Only tear down or resolve launch configuration when opening/replacing a session.
        if let existing = session {
            let running = await existing.isRunning
            let binaryStillExists = executable.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            if credential != currentCredential || !running || !binaryStillExists {
                try await close()
            }
        }
        if session == nil {
            let launch: (executable: URL, environment: [String: String])
            do {
                launch = try await resolveLaunch()
            } catch {
                try await close()
                throw error
            }
            let opened = try JSONRPCSession(executableURL: launch.executable, profileHome: home,
                                            environment: launch.environment)
            session = opened
            executable = launch.executable
            credential = currentCredential
            do {
                try await withTaskCancellationHandler {
                    try await opened.initialize(timeout: timeout, clientVersion: clientVersion)
                } onCancel: { Task { await opened.stop() } }
            } catch {
                try await cleanup(after: error)
            }
        }
        guard let session else { throw CodexClientError.connectionClosed }
        let id = nextID
        nextID += 1
        do {
            let value = try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await session.request(method: "account/rateLimits/read", id: id, timeout: timeout)
            } onCancel: { Task { await session.stop() } }
            credential = currentCredential
            generation += 1
            let token = generation
            let idleTimeout = idleTimeout
            idleTask = Task { [weak self] in
                do { try await Task.sleep(for: idleTimeout) } catch { return }
                await self?.expire(generation: token)
            }
            return value
        } catch {
            try await cleanup(after: error)
        }
    }

    private func readCredential() throws -> Data? {
        let url = home.appendingPathComponent("auth.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    private func expire(generation token: Int) async {
        let previous = tail
        let task = Task {
            await previous?.value
            if self.generation == token { try await self.close() }
        }
        tail = Task { _ = await task.result }
        _ = await task.result
    }
}

actor SessionStopState {
    private var task: Task<Bool, Never>?
    private var generation = 0

    func stop(isRunning: @escaping @Sendable () -> Bool,
              terminate: @escaping @Sendable () async -> Bool) async -> Bool {
        if !isRunning() { return true }
        let current: Task<Bool, Never>
        let token: Int
        if let task { current = task; token = generation }
        else {
            generation += 1
            token = generation
            current = Task.detached { await terminate() }
            task = current
        }
        let exited = await current.value || !isRunning()
        if !exited, generation == token { task = nil }
        return exited
    }
}

enum SessionFailure {
    static func finish(_ failure: any Error, cancelled: Bool,
                       cleanup: @Sendable () async throws -> Void) async throws -> Never {
        do { try await cleanup() }
        catch { if cancelled { throw CancellationError() }; throw error }
        if cancelled { throw CancellationError() }
        throw failure
    }
}
