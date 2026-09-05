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

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.text("launch_at_login"))
                        if model.launchAtLoginRequiresApproval {
                            Text(model.text("launch_at_login_requires_approval"))
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else if model.launchAtLoginUnavailable {
                            Text(model.text("launch_at_login_unavailable"))
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.launchesAtLogin },
                        set: { enabled in model.setLaunchAtLogin(enabled) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .fixedSize()
                    .accessibilityLabel(Text(model.text("launch_at_login")))
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 44)

                if model.launchAtLoginRequiresApproval {
                    Button(model.text("open_system_settings")) {
                        model.openLoginItemsSettings()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()
                    .padding(.leading, 14)

                HStack {
                    Text(model.text("show_menu_bar_percentage"))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.settings.showsMenuBarPercentage },
                        set: { enabled in Task { await model.setShowsMenuBarPercentage(enabled) } }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .fixedSize()
                    .accessibilityLabel(Text(model.text("show_menu_bar_percentage")))
                }
                .padding(.horizontal, 14)
                .frame(height: 44)

                Divider()
                    .padding(.leading, 14)

                HStack {
                    Text(model.text("show_five_hour_usage"))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.settings.showsFiveHourUsage },
                        set: { enabled in Task { await model.setShowsFiveHourUsage(enabled) } }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .fixedSize()
                    .accessibilityLabel(Text(model.text("show_five_hour_usage")))
                }
                .padding(.horizontal, 14)
                .frame(height: 44)

                Divider()
                    .padding(.leading, 14)

                HStack {
                    Text(model.text("language"))
                    Spacer()
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
                .padding(.horizontal, 14)
                .frame(height: 44)
            }

            Divider()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(model.format("current_version", updater.currentVersion))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(model.text("check_for_updates")) { updater.checkForUpdates() }
                        .disabled((!updater.canCheckForUpdates && updater.availableVersion == nil)
                            || updater.isInstalling || model.isMutating || model.isAddingAccount)
                }
                Toggle(model.text("automatically_check_updates"), isOn: Binding(
                    get: { updater.automaticallyChecks },
                    set: { updater.setAutomaticallyChecks($0) }
                ))
                .toggleStyle(.switch)
                Text(model.text("update_check_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = updater.lastError {
                    Text(model.text("update_check_failed") + " " + error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.system(size: 11.5))
            .padding(14)
        }
        .onAppear {
            model.refreshLaunchAtLoginStatus()
        }
    }
}
