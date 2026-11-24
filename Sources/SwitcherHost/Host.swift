import Foundation
import SwitcherCore

private struct Request: Decodable, Sendable {
    let id: Int
    let command: String
    var accountID: UUID?
    var targetAccountID: UUID?
    var value: Bool?
    var language: String?
    var error: String?
}

private struct SnapshotEnvelope: Encodable {
    let kind = "snapshot"
    let state: AccountSnapshot
}

private struct CompletedEnvelope: Encodable {
    let kind = "completed"
    let id: Int
    let error: String?
}

private struct PlatformEnvelope: Encodable {
    let kind = "platform"
    let id: Int
    let method: String
    let url: String?
}

private struct ProtocolErrorEnvelope: Encodable {
    let kind = "protocolError"
    let error: String
}

private struct DesktopAdapter: DesktopControlling {
    let host: Host
    func closeDesktop() async throws { try await host.platform("closeDesktop") }
    func reopenDesktop() async throws { try await host.platform("reopenDesktop") }
}

@MainActor
final class Host {
    private let environment: [String: String]
    private let writeOutput: @Sendable (Data) throws -> Void
    private(set) var controller: AccountController?
    private var lastSentLanguage: AppLanguage?
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var commands: [Int: Task<Void, Never>] = [:]
    private var snapshotTask: Task<Void, Never>?
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        writeOutput: @escaping @Sendable (Data) throws -> Void = { try FileHandle.standardOutput.write(contentsOf: $0) }
    ) {
        self.environment = environment
        self.writeOutput = writeOutput
    }

    func waitForIdle() async {
        while let task = commands.values.first ?? snapshotTask {
            await task.value
        }
    }

    func platform(_ method: String, url: URL? = nil) async throws {
        nextID += 1
        let id = nextID
        try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            send(PlatformEnvelope(id: id, method: method, url: url?.absoluteString))
        }
    }

    func accept(_ line: String) {
        do {
            let request = try JSONDecoder().decode(Request.self, from: Data(line.utf8))
            if request.command == "platformReply" {
                guard let continuation = pending.removeValue(forKey: request.id) else { return }
                if let error = request.error { continuation.resume(throwing: HostError.message(error)) }
                else { continuation.resume() }
                return
            }
            guard commands[request.id] == nil else { return }
            commands[request.id] = Task {
                do {
                    try await execute(request)
                    flushPendingSnapshot()
                    send(CompletedEnvelope(id: request.id, error: nil))
                } catch {
                    flushPendingSnapshot()
                    send(CompletedEnvelope(id: request.id, error: error.localizedDescription))
                }
                commands[request.id] = nil
            }
        } catch {
            send(ProtocolErrorEnvelope(error: "Invalid host command."))
        }
    }

    private func execute(_ request: Request) async throws {
        if request.command == "initialize" {
            guard controller == nil else { throw HostError.message("Already initialized.") }
            let store = AccountStore(
                baseURL: environment["CODEX_SWITCHER_DATA_HOME"].map { URL(fileURLWithPath: $0) },
                activeHomeURL: environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            )
            let codex = CodexClient(openBrowser: { [self] url in
                guard CodexClient.isSafeSignInURL(url) else {
                    throw HostError.message("Unsupported sign-in URL.")
                }
                try await platform("openBrowser", url: url)
            })
            let model = AccountController(
                store: store,
                codex: codex,
                switchService: SwitchService(desktop: DesktopAdapter(host: self), store: store, codex: CredentialIdentity()),
                subscriptionClient: LiveSubscriptionClient()
            )
            controller = model
            await model.start()
            guard !Task.isCancelled else { return }
            model.onChange = { [weak self] in self?.scheduleSnapshot() }
            sendSnapshot(forceStrings: true)
            await model.startBackgroundUsageRefresh()
            return
        }
        guard let model = controller else { throw HostError.message("Initialize the host first.") }
        switch request.command {
        case "refresh": model.refreshWeeklyUsage()
        case "add": model.addAccount()
        case "cancelAdd": model.cancelAddingAccount()
        case "register": await model.registerCurrentAccount()
        case "switch":
            guard let id = request.accountID else { throw HostError.message("Missing account ID.") }
            await model.switchAccount(to: id)
        case "remove":
            guard let id = request.accountID else { throw HostError.message("Missing account ID.") }
            await model.removeAccount(id: id)
        case "move":
            guard let id = request.accountID, let targetID = request.targetAccountID else {
                throw HostError.message("Missing account ID.")
            }
            await model.moveAccount(id: id, to: targetID)
        case "language":
            guard let raw = request.language, let language = AppLanguage(rawValue: raw) else {
                throw HostError.message("Invalid language.")
            }
            await model.setLanguage(language)
        case "percentage":
            guard let value = request.value else { throw HostError.message("Missing setting.") }
            await model.setShowsMenuBarPercentage(value)
        case "fiveHour":
            guard let value = request.value else { throw HostError.message("Missing setting.") }
            await model.setShowsFiveHourUsage(value)
        case "autoReset":
            guard let value = request.value else { throw HostError.message("Missing setting.") }
            await model.setAutoResetEnabled(value)
        case "statusBarUsageWindow":
            guard let raw = request.language, let window = StatusBarUsageWindow(rawValue: raw) else {
                throw HostError.message("Invalid status bar usage window.")
            }
            await model.setStatusBarUsageWindow(window)
        case "dismissError": model.dismissError()
        default: throw HostError.message("Unknown host command.")
        }
    }

    private func scheduleSnapshot() {
        guard snapshotTask == nil else { return }
        snapshotTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            self.snapshotTask = nil
            self.sendSnapshot()
        }
    }

    private func flushPendingSnapshot() {
        guard let task = snapshotTask else { return }
        task.cancel()
        snapshotTask = nil
        sendSnapshot()
    }

    private func sendSnapshot(forceStrings: Bool = false) {
        guard let model = controller else { return }
        let includeStrings = forceStrings || lastSentLanguage != model.settings.language
        let state = model.snapshot(includeStrings: includeStrings)
        lastSentLanguage = model.settings.language
        send(SnapshotEnvelope(state: state))
    }

    private func send<T: Encodable>(_ message: T) {
        do {
            var bytes = try encoder.encode(message)
            bytes.append(0x0A)
            try writeOutput(bytes)
        } catch {
            if !(message is ProtocolErrorEnvelope) {
                send(ProtocolErrorEnvelope(error: "Could not encode host message."))
            }
        }
    }

    func shutdown() {
        snapshotTask?.cancel()
        snapshotTask = nil
        controller?.cancelAddingAccount()
        controller?.stopBackgroundUsageRefresh()
        for task in commands.values { task.cancel() }
        for continuation in pending.values { continuation.resume(throwing: CancellationError()) }
        pending.removeAll()
    }
}

private enum HostError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case let .message(value): value } }
}

@main
struct SwitcherHost {
    static func main() async {
        let host = Host()
        await Task.detached {
            while let line = readLine() { await host.accept(line) }
        }.value
        host.shutdown()
    }
}
