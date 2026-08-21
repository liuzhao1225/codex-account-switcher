import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
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
                    Text(model.text("show_menu_bar_percentage"))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.settings.showsMenuBarPercentage },
                        set: { enabled in Task { await model.setShowsMenuBarPercentage(enabled) } }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .fixedSize()
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
        }
    }
}
