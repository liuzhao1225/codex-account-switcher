import SwitcherCore
import Combine
import Foundation
import ServiceManagement

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
    let objectWillChange = ObservableObjectPublisher()
    @Published private(set) var launchAtLoginState: LaunchAtLoginState = .disabled

    override init(store: AccountStore, codex: any AccountClient,
                  configuration: any ProviderConfigurationServicing,
                  switchService: any SwitchServicing,
                  providerSwitchService: any ProviderSwitchServicing,
                  modelDiscovery: any ProviderModelDiscovering = ProviderModelDiscovery(),
                  connectionValidator: any ProviderConnectionValidating = ProviderModelDiscovery()) {
        super.init(store: store, codex: codex, configuration: configuration,
                   switchService: switchService, providerSwitchService: providerSwitchService, modelDiscovery: modelDiscovery, connectionValidator: connectionValidator)
        onChange = { [weak self] in self?.objectWillChange.send() }
        refreshLaunchAtLoginStatus()
    }

    static func live() -> AppModel {
        let store = AccountStore()
        let codex = CodexClient()
        let configuration = ProviderManager(store: store, codex: codex)
        let desktop = DesktopController()
        return AppModel(
            store: store,
            codex: codex,
            configuration: configuration,
            switchService: SwitchService(
                desktop: desktop,
                store: store,
                codex: codex,
                configuration: configuration
            ),
            providerSwitchService: ProviderSwitchService(
                desktop: desktop,
                store: store,
                codex: codex, configuration: configuration
            )
        )
    }

    var launchesAtLogin: Bool { launchAtLoginState.isOn }
    var launchAtLoginRequiresApproval: Bool { launchAtLoginState == .requiresApproval }
    var launchAtLoginUnavailable: Bool { launchAtLoginState == .unavailable }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginState = LaunchAtLoginState(status: SMAppService.mainApp.status)
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
}
