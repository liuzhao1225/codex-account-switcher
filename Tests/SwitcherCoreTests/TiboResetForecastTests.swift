import Foundation
import Testing
@testable import SwitcherCore

struct TiboResetForecastTests {
    private func payload(h24: Int = 32, h48: Int = 53) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "probabilities": ["rounded_24h": h24, "rounded_48h": h48],
        ])
    }

    @Test func readsOnlyTheDisplayedProbabilities() throws {
        let result = try TiboResetForecastReader.read(forecast: payload())
        #expect(result.next24HourPercent == 32)
        #expect(result.next48HourPercent == 53)
    }

    @Test(arguments: ["2000-01-01T00:00:00Z", "2099-01-01T00:00:00Z", "invalid"])
    func unrelatedResetMetadataDoesNotBlockProbabilities(updatedAt: String) throws {
        var object = try JSONSerialization.jsonObject(with: payload()) as! [String: Any]
        object["updated_at"] = updatedAt
        object["last_reset_at"] = "2026-10-22T17:10:01.000Z"
        object["time_window"] = NSNull()
        let result = try TiboResetForecastReader.read(
            forecast: JSONSerialization.data(withJSONObject: object)
        )
        #expect(result.next24HourPercent == 32)
        #expect(result.next48HourPercent == 53)
    }

    @Test func displaysProbabilitiesWithoutImposingAnOrder() throws {
        let result = try TiboResetForecastReader.read(forecast: payload(h24: 54, h48: 53))
        #expect(result.next24HourPercent == 54)
        #expect(result.next48HourPercent == 53)
    }

    @Test(arguments: [(-1, 53), (32, 101)])
    func rejectsInvalidProbabilities(h24: Int, h48: Int) throws {
        let data = try payload(h24: h24, h48: h48)
        #expect(throws: TiboResetForecastReader.DataError.invalidResponse) {
            try TiboResetForecastReader.read(forecast: data)
        }
    }

    @Test func missingProbabilityPreservesTheDecodingFailure() {
        let data = Data(#"{"probabilities":{"rounded_24h":32}}"#.utf8)
        #expect(throws: DecodingError.self) {
            try TiboResetForecastReader.read(forecast: data)
        }
    }
}
