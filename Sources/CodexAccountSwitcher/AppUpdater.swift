import AppKit
import Combine
import Sparkle

/// Owns only Switcher's update lifecycle; account credentials and Codex stay outside it.
@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    @Published private(set) var availableVersion: String?
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var isInstalling = false
    @Published private(set) var lastError: String?
    var automaticallyChecks: Bool { controller?.updater.automaticallyChecksForUpdates ?? true }

    var accountOperationInProgress = false {
        didSet {
            if !accountOperationInProgress, let pendingRelaunch {
                self.pendingRelaunch = nil
                pendingRelaunch()
            }
        }
    }

    private var controller: SPUStandardUpdaterController?
    private var observations: [NSKeyValueObservation] = []
    private var pendingRelaunch: (() -> Void)?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    }

    func start() {
        guard controller == nil else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: self
        )
        self.controller = controller
        let updater = controller.updater
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
            },
        ]
        do {
            try updater.start()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func checkForUpdates() {
        guard !accountOperationInProgress, !isInstalling else { return }
        lastError = nil
        // Sparkle also brings back a pending gentle reminder through this action.
        controller?.checkForUpdates(nil)
    }

    func setAutomaticallyChecks(_ enabled: Bool) {
        objectWillChange.send()
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        availableVersion = update.displayVersionString
        lastError = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
        isInstalling = false
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        isInstalling = true
    }

    func updater(
        _ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        guard accountOperationInProgress else { return false }
        pendingRelaunch = installHandler
        return true
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        isInstalling = false
        let error = error as NSError
        lastError = error.domain == SUSparkleErrorDomain && error.code == SUError.noUpdateError.rawValue
            ? nil : error.localizedDescription
    }
}
