import SwitcherCore
import Combine
import Foundation
import ServiceManagement
import AppKit

enum LaunchAtLoginState: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    init(status: SMAppService.Status) {
        switch status {
        case .notRegistered:
            self = .disabled
        case .enabled:
            self = .enabled
        case .requiresApproval:
            self = .requiresApproval
        case .notFound:
            self = .unavailable
        @unknown default:
            self = .unavailable
        }
    }

    var isOn: Bool {
        self == .enabled || self == .requiresApproval
    }
}

@MainActor
final class AppModel: AccountController, @MainActor ObservableObject {
    @Published private(set) var launchAtLoginState: LaunchAtLoginState = .disabled
    var onSettledChange: (@MainActor () -> Void)?

    override init(store: AccountStore, codex: any AccountClient, switchService: any SwitchServicing,
                  subscriptionClient: (any SubscriptionClient)? = nil) {
        super.init(store: store, codex: codex, switchService: switchService, subscriptionClient: subscriptionClient)
        onWillChange = { [weak self] in self?.objectWillChange.send() }
        onChange = { [weak self] in self?.onSettledChange?() }
        refreshLaunchAtLoginStatus()
    }

    static func live() -> AppModel {
        let store = AccountStore()
        let codex = CodexClient(locator: .init(prefersBundledDesktop: true))
        return AppModel(
            store: store,
            codex: codex,
            switchService: SwitchService(desktop: DesktopController(), store: store, codex: CredentialIdentity()),
            subscriptionClient: LiveSubscriptionClient()
        )
    }

    var launchesAtLogin: Bool { launchAtLoginState.isOn }
    var launchAtLoginRequiresApproval: Bool { launchAtLoginState == .requiresApproval }
    var launchAtLoginUnavailable: Bool { launchAtLoginState == .unavailable }

    func refreshLaunchAtLoginStatus() {
        let next = LaunchAtLoginState(status: SMAppService.mainApp.status)
        if next != launchAtLoginState {
            launchAtLoginState = next
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            visibleError = OperationError(stage: nil, titleKey: "operation_failed", messageKey: nil,
                                          message: error.localizedDescription, underlyingDescription: nil)
        }
        refreshLaunchAtLoginStatus()
    }

    func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }

    func revealResetExpiryLog() {
        if FileManager.default.fileExists(atPath: resetExpiryLogURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([resetExpiryLogURL])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([resetExpiryLogURL.deletingLastPathComponent()])
        }
    }
}
