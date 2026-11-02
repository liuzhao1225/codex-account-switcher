import AppKit
import Combine

@MainActor
final class SwitcherAppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel.live()
    let updater = AppUpdater()
    let tiboForecast = TiboForecastModel()

    private var modelObservation: AnyCancellable?
    private var wakeObservation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        modelObservation = model.objectWillChange.sink { [weak self] in
            guard let self else { return }
            updater.accountOperationInProgress = model.isMutating || model.isAddingAccount
        }
        updater.start()
        tiboForecast.start()
        wakeObservation = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.model.refreshWeeklyUsage() }
            }
        Task { await model.startBackgroundUsageRefresh() }
    }
}
