import Foundation

/// Experimental global-reset probabilities from codex-reset.com.
public struct TiboResetForecast: Equatable, Sendable {
    public let next24HourPercent: Int
    public let next48HourPercent: Int
}

public enum TiboResetForecastReader {
    public enum DataError: Error {
        case invalidResponse
    }

    public static func read(forecast: Data) throws -> TiboResetForecast {
        let forecast = try JSONDecoder().decode(ForecastWire.self, from: forecast)
        guard (0...100).contains(forecast.probabilities.rounded24h),
              (0...100).contains(forecast.probabilities.rounded48h)
        else { throw DataError.invalidResponse }

        return TiboResetForecast(
            next24HourPercent: forecast.probabilities.rounded24h,
            next48HourPercent: forecast.probabilities.rounded48h
        )
    }

    private struct ForecastWire: Decodable {
        let probabilities: Probabilities

        struct Probabilities: Decodable {
            let rounded24h: Int
            let rounded48h: Int

            enum CodingKeys: String, CodingKey {
                case rounded24h = "rounded_24h"
                case rounded48h = "rounded_48h"
            }
        }
    }
}
