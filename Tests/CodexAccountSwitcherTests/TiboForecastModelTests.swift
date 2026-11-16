import Foundation
import Testing
@testable import CodexAccountSwitcher

@MainActor
struct TiboForecastModelTests {
    @Test func reopeningAfterFailureFetchesAgainImmediately() async throws {
        let response = try payload()
        let source = ForecastSource(responses: [.failure, .success(response)])
        let model = TiboForecastModel(fetchForecast: { try await source.fetch() })

        await model.refreshIfDue()
        #expect(model.forecast == nil)
        #expect(model.failureMessage == "codex-reset.com: HTTP 503")
        #expect(!model.isLoading)

        await model.refreshIfDue()
        #expect(model.forecast?.next24HourPercent == 32)
        #expect(model.forecast?.next48HourPercent == 53)
        #expect(model.failureMessage == nil)
        #expect(await source.calls == 2)
    }

    @Test func reopeningWithSuccessfulDataDoesNotFetchAgain() async throws {
        let source = ForecastSource(responses: [.success(try payload())])
        let model = TiboForecastModel(fetchForecast: { try await source.fetch() })
        await model.refreshIfDue()
        await model.refreshIfDue()
        #expect(await source.calls == 1)
        #expect(model.forecast?.next24HourPercent == 32)
    }

    @Test func failedRefreshShowsFailureAndAllowsTheNextOpenToRecover() async throws {
        let response = try payload()
        let source = ForecastSource(responses: [.success(response), .failure, .success(response)])
        let model = TiboForecastModel(fetchForecast: { try await source.fetch() })
        await model.refreshIfDue()
        await model.refreshIfDue(after: 0)
        #expect(model.forecast == nil)
        #expect(model.failureMessage == "codex-reset.com: HTTP 503")
        await model.refreshIfDue()
        #expect(model.forecast?.next48HourPercent == 53)
        #expect(model.failureMessage == nil)
        #expect(await source.calls == 3)
    }

    private func payload() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "probabilities": ["rounded_24h": 32, "rounded_48h": 53],
        ])
    }
}

private actor ForecastSource {
    enum Response: Sendable {
        case success(Data)
        case failure
    }
    private var responses: [Response]
    private(set) var calls = 0

    init(responses: [Response]) { self.responses = responses }

    func fetch() throws -> Data {
        calls += 1
        switch responses.removeFirst() {
        case .success(let data): return data
        case .failure:
            throw URLError(.badServerResponse, userInfo: [
                NSLocalizedDescriptionKey: "codex-reset.com: HTTP 503",
            ])
        }
    }
}
