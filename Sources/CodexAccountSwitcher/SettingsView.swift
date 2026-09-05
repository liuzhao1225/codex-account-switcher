import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdater
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeader(
                title: model.text("settings"),
                backTitle: model.text("back"),
                onBack: onBack
            )
            Divider()

            sectionLabel("settings_general")
            settingRow("launch_at_login") {
                settingSwitch("launch_at_login", isOn: Binding(
                    get: { model.launchesAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
            }
            if model.launchAtLoginRequiresApproval || model.launchAtLoginUnavailable {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.text(model.launchAtLoginRequiresApproval
                        ? "launch_at_login_requires_approval" : "launch_at_login_unavailable"))
                        .foregroundStyle(.orange)
                    if model.launchAtLoginRequiresApproval {
                        Button(model.text("open_system_settings")) { model.openLoginItemsSettings() }
                            .buttonStyle(.link)
                    }
                }
                .modifier(SettingsDetail())
            }
            rowDivider
            settingRow("show_menu_bar_percentage") {
                settingSwitch("show_menu_bar_percentage", isOn: Binding(
                    get: { model.settings.showsMenuBarPercentage },
                    set: { enabled in Task { await model.setShowsMenuBarPercentage(enabled) } }
                ))
            }
            rowDivider
            settingRow("show_five_hour_usage") {
                settingSwitch("show_five_hour_usage", isOn: Binding(
                    get: { model.settings.showsFiveHourUsage },
                    set: { enabled in Task { await model.setShowsFiveHourUsage(enabled) } }
                ))
            }
            rowDivider
            settingRow("language") {
                Picker(model.text("language"), selection: Binding(
                    get: { model.settings.language },
                    set: { language in Task { await model.setLanguage(language) } }
                )) {
                    Text(model.text("system_default")).tag(AppLanguage.system)
                    Text(model.text("english")).tag(AppLanguage.english)
                    Text(model.text("simplified_chinese")).tag(AppLanguage.simplifiedChinese)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            sectionLabel("settings_updates")
            settingRow("automatically_check_updates") {
                settingSwitch("automatically_check_updates", isOn: Binding(
                    get: { updater.automaticallyChecks },
                    set: { updater.setAutomaticallyChecks($0) }
                ))
            }
            Text(model.text("update_check_hint"))
                .foregroundStyle(.secondary)
                .modifier(SettingsDetail())
            rowDivider
            HStack(spacing: 12) {
                Text(model.format("current_version", updater.currentVersion))
                    .monospacedDigit()
                Spacer(minLength: 8)
                Button(model.text("check_for_updates")) { updater.checkForUpdates() }
                    .buttonStyle(.bordered)
                    .fixedSize()
                    .disabled((!updater.canCheckForUpdates && updater.availableVersion == nil)
                        || updater.isInstalling || model.isMutating || model.isAddingAccount)
            }
            .modifier(SettingsRowLayout())
            if let error = updater.lastError {
                Text(model.text("update_check_failed") + " " + error)
                    .foregroundStyle(.orange)
                    .modifier(SettingsDetail())
            }
        }
        .padding(.bottom, 6)
        .font(.system(size: 13))
        .controlSize(.small)
        .onAppear { model.refreshLaunchAtLoginStatus() }
    }

    private var rowDivider: some View {
        Divider().padding(.horizontal, 14)
    }

    private func sectionLabel(_ key: String) -> some View {
        Text(model.text(key))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 2)
    }

    private func settingRow<Control: View>(
        _ key: String, @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 12) {
            Text(model.text(key))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            control()
        }
        .modifier(SettingsRowLayout())
    }

    private func settingSwitch(_ key: String, isOn: Binding<Bool>) -> some View {
        Toggle(model.text(key), isOn: isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .fixedSize()
    }
}

private struct SettingsRowLayout: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
    }
}

private struct SettingsDetail: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 11))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
    }
}
