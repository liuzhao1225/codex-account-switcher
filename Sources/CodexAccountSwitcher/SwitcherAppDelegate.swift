import AppKit
import Combine
import UserNotifications

@MainActor
final class SwitcherAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
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
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
            model.onLowUsage = { [weak model] title, message in
                model?.postLowUsageNotification(title: title, message: message)
            }
        }
        updater.start()
        tiboForecast.start()
        wakeObservation = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.model.refreshWeeklyUsage() }
            }
        Task { await model.startBackgroundUsageRefresh() }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
