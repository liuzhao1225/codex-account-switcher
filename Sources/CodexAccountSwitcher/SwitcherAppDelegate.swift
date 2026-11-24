import AppKit
import Combine
import UserNotifications

@MainActor
final class SwitcherAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let model = AppModel.live()
    let updater = AppUpdater()

    private var wakeObservation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.onSettledChange = { [weak self] in
            guard let self else { return }
            self.updater.accountOperationInProgress = self.model.isMutating || self.model.isAddingAccount
        }
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
            model.onLowUsage = { [weak model] title, message in
                model?.postLowUsageNotification(title: title, message: message)
            }
        }
        updater.start()
        wakeObservation = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.model.refreshWeeklyUsage() }
            }
        Task { await model.startBackgroundUsageRefresh() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.cancelAddingAccount()
        model.stopBackgroundUsageRefresh()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
