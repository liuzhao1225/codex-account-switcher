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

            VStack(alignment: .leading, spacing: 7) {
                Text(model.text("language"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                Picker(model.text("language"), selection: Binding(
                    get: { model.settings.language },
                    set: { language in Task { await model.setLanguage(language) } }
                )) {
                    Text(model.text("system_default")).tag(AppLanguage.system)
                    Text(model.text("english")).tag(AppLanguage.english)
                    Text(model.text("simplified_chinese")).tag(AppLanguage.simplifiedChinese)
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }
}
