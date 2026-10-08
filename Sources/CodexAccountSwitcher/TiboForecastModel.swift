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

    private var pollingTask: Task<Void, Never>?
    private var lastAttempt: Date?

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
        if let lastAttempt, Date().timeIntervalSince(lastAttempt) < interval { return }
        isLoading = true
        lastAttempt = Date()
        defer { isLoading = false }

        do {
            async let forecastData = Self.fetch("https://codex-reset.com/api/forecast?tz=Asia%2FShanghai")
            async let timelineData = Self.fetch("https://codex-reset.com/api/timeline")
            let (forecastPayload, timelinePayload) = try await (forecastData, timelineData)
            let result = try TiboResetForecastReader.read(
                forecast: forecastPayload, timeline: timelinePayload
            )
            forecast = result
            Self.logger.info("Public forecast refreshed: updatedAtEpoch=\(Int(result.updatedAt.timeIntervalSince1970), privacy: .public), confirmedPosts=\(result.events.count, privacy: .public)")
        } catch {
            forecast = nil
            Self.logger.warning("Public forecast unavailable")
        }
    }

    private static func fetch(_ address: String) async throws -> Data {
        guard let url = URL(string: address) else { throw URLError(.badURL) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue(
            "CodexAccountSwitcher/0.1.17 (+https://github.com/liuzhao1225/codex-account-switcher)",
            forHTTPHeaderField: "User-Agent"
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              response.url?.host == "codex-reset.com",
              data.count <= 2_000_000
        else { throw URLError(.badServerResponse) }
        return data
    }
}
