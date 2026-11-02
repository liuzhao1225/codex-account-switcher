import Combine
import Foundation
import OSLog
import SwitcherCore

@MainActor
final class TiboForecastModel: ObservableObject {
    private static let logger = Logger(
        subsystem: "com.liuzhao.codex-account-switcher", category: "TiboForecast"
    )
    @Published private(set) var forecast: TiboResetForecast?
    @Published private(set) var isLoading = false
    @Published private(set) var failureMessage: String?

    private var pollingTask: Task<Void, Never>?
    private var lastSuccess: Date?
    private let fetchForecast: @Sendable () async throws -> Data

    init(fetchForecast: @escaping @Sendable () async throws -> Data = {
        try await TiboForecastModel.fetch()
    }) {
        self.fetchForecast = fetchForecast
    }

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard self != nil else { return }
                await self?.refreshIfDue(after: 900)
                try? await Task.sleep(for: .seconds(900))
            }
        }
    }

    func refreshIfDue(after interval: TimeInterval = 900) async {
        guard !isLoading else { return }
        if let lastSuccess, Date().timeIntervalSince(lastSuccess) < interval { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let forecastPayload = try await fetchForecast()
            let result = try TiboResetForecastReader.read(forecast: forecastPayload)
            forecast = result
            lastSuccess = Date()
            failureMessage = nil
            Self.logger.info("Public forecast refreshed: 24h=\(result.next24HourPercent, privacy: .public)%, 48h=\(result.next48HourPercent, privacy: .public)%")
        } catch {
            forecast = nil
            lastSuccess = nil
            failureMessage = error.localizedDescription
            Self.logger.warning("Public forecast unavailable: \(String(describing: error), privacy: .public)")
        }
    }

    private static func fetch() async throws -> Data {
        let url = URL(string: "https://codex-reset.com/api/forecast")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue(
            "CodexAccountSwitcher/\(CodexClient().clientVersion) (+https://github.com/liuzhao1225/codex-account-switcher)",
            forHTTPHeaderField: "User-Agent"
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard response.statusCode == 200 else {
            Self.logger.warning("Forecast HTTP \(response.statusCode, privacy: .public): \(String(decoding: data.prefix(1_024), as: UTF8.self), privacy: .public)")
            throw URLError(.badServerResponse, userInfo: [
                NSLocalizedDescriptionKey: "codex-reset.com: HTTP \(response.statusCode)",
            ])
        }
        return data
    }
}
