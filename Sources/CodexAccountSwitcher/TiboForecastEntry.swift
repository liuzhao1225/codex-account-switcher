import SwitcherCore
import SwiftUI

struct TiboForecastEntry: View {
    @ObservedObject var model: AppModel
    @ObservedObject var forecastModel: TiboForecastModel

    var body: some View {
        Link(destination: URL(string: "https://codex-reset.com/")!) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 13))
                    .accessibilityHidden(true)
                Text(model.text("tibo_title"))
                    .font(.system(size: 10.5, weight: .medium))
                    .fixedSize()
                probability(model.text("tibo_24h"), forecastModel.forecast?.next24HourPercent)
                probability(model.text("tibo_48h"), forecastModel.forecast?.next48HourPercent)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.text("tibo_title"))
        .accessibilityValue(summary)
        .help(forecastModel.forecast == nil
              ? model.text(forecastModel.isLoading ? "tibo_loading" : "tibo_unavailable")
                + (forecastModel.failureMessage.map { "\n" + $0 } ?? "")
                + "\n" + model.text("tibo_source_hint")
              : model.text("tibo_source_hint"))
    }

    private func probability(_ label: String, _ value: Int?) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize()
            Text(value.map { "\($0)%" } ?? (forecastModel.isLoading ? "…" : "—"))
                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
    }

    private var summary: String {
        guard let forecast = forecastModel.forecast else {
            return model.text(forecastModel.isLoading ? "tibo_loading" : "tibo_unavailable")
        }
        return "\(model.text("tibo_24h")) \(forecast.next24HourPercent)% · "
            + "\(model.text("tibo_48h")) \(forecast.next48HourPercent)%"
    }
}
