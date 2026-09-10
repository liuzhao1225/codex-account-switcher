import AppKit
import SwiftUI
import SwitcherCore

@MainActor
final class ProviderManagementWindow: NSObject, NSWindowDelegate {
    static let shared = ProviderManagementWindow()
    private var window: NSWindow?
    private weak var model: AppModel?

    func show(model: AppModel, providerID: String? = nil) {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        Task {
            await model.openProviderEditor(id: providerID)
            guard model.providerEditor != nil else { return }
            self.model = model
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = model.text("provider_manager_title")
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 620, height: 620)
            window.delegate = self
            window.contentView = NSHostingView(rootView: ProviderManagementView(model: model) { [weak window] in window?.close() })
            self.window = window
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { model?.isMutating != true }
    func windowWillClose(_ notification: Notification) { model?.closeProviderEditor(); window = nil }
}

struct ProviderManagementView: View {
    @ObservedObject var model: AppModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(model.text("provider_manager_title")).font(.title2.bold())
                Spacer()
                Menu(model.text("provider_saved")) {
                    ForEach(model.managedProviders) { provider in
                        Button(provider.displayName) { Task { await model.openProviderEditor(id: provider.id) } }
                    }
                }.disabled(model.managedProviders.isEmpty || model.providerEditor?.isBusy == true || model.isMutating)
                Button(model.text("provider_new"), systemImage: "plus") { Task { await model.openProviderEditor() } }
                    .disabled(model.providerEditor?.isBusy == true || model.isMutating)
            }.padding(22)
            Divider()
            if let editor = model.providerEditor {
                ProviderEditorForm(model: model, initial: editor, onClose: onClose).id(editor.id)
            }
        }
        .frame(minWidth: 600, minHeight: 560)
    }
}

private struct ProviderEditorForm: View {
    @ObservedObject var model: AppModel
    let onClose: () -> Void
    let state: ProviderEditorState
    @State private var name: String
    @State private var baseURL: String
    @State private var apiKey = ""
    @State private var query = ""
    @State private var manualModelID = ""
    @State private var effort = ""

    init(model: AppModel, initial: ProviderEditorState, onClose: @escaping () -> Void) {
        self.model = model; self.onClose = onClose; state = initial
        _name = State(initialValue: initial.displayName)
        _baseURL = State(initialValue: initial.baseURL)
        _query = State(initialValue: initial.query)
        _effort = State(initialValue: initial.models.first { $0.id == initial.defaultModelID }?.reasoningEffort ?? "")
    }
    private var busy: Bool { state.isBusy || model.isMutating }
    private var connection: ProviderConnectionInput { ProviderConnectionInput(displayName: name, baseURL: baseURL, apiFormat: .responses, apiKey: apiKey) }
    private func t(_ key: String) -> String { model.text(key) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow { Text(t("provider_name")); TextField(t("provider_name_placeholder"), text: $name) }
                        GridRow { Text("Base URL"); TextField("https://api.example.com/v1", text: Binding(get: { baseURL }, set: { baseURL = $0.trimmingCharacters(in: .whitespacesAndNewlines) })).textContentType(.URL) }
                        GridRow {
                            Text("API Key")
                            SecureField(t(state.hasStoredKey ? "provider_keep_key" : "provider_key_placeholder"), text: Binding(get: { apiKey }, set: { apiKey = $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
                        }
                    }.textFieldStyle(.roundedBorder).disabled(busy)
                    Text(t("provider_responses_notice"))
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Text(t("provider_models")).font(.headline)
                        Spacer()
                        if state.isBusy { ProgressView().controlSize(.small) }
                        Button(t("provider_fetch"), systemImage: "arrow.clockwise") {
                            Task { await model.fetchProviderModels(connection) }
                        }.disabled(busy)
                    }
                    HStack {
                        TextField(t("provider_search"), text: $query)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: query) { _, value in model.searchProviderModels(value) }
                        Picker(t("provider_sort"), selection: Binding(get: { state.sort }, set: { model.sortProviderModels($0) })) {
                            Text(t("provider_sort_custom")).tag(ProviderModelSort.custom)
                            Text("A → Z").tag(ProviderModelSort.nameAscending)
                            Text("Z → A").tag(ProviderModelSort.nameDescending)
                        }.labelsHidden().frame(width: 120)
                    }
                    ScrollView { modelList }.frame(height: min(280, CGFloat(max(1, state.visibleModelIDs.count)) * 58))
                    HStack {
                        TextField(t("provider_manual_id"), text: $manualModelID).textFieldStyle(.roundedBorder)
                        Button(t("provider_add_model")) {
                            model.addProviderModel(id: manualModelID, connection: connection)
                            manualModelID = ""; query = ""
                        }.disabled(busy || manualModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let selected = state.models.first(where: { $0.id == state.defaultModelID }) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(t("provider_default_model") + ": " + selected.id).font(.callout.bold()).textSelection(.enabled)
                            HStack {
                                Text("Thinking / effort")
                                TextField(t("provider_effort_default"), text: $effort)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: effort) { _, value in model.setProviderReasoning(value) }
                                if !selected.reasoningOptions.isEmpty {
                                    Menu(t("provider_effort_options")) {
                                        Button(t("provider_effort_default")) { effort = "" }
                                        ForEach(selected.reasoningOptions, id: \.self) { value in Button(value) { effort = value } }
                                    }
                                }
                            }.disabled(busy)
                            Text(t(selected.reasoningOptions.isEmpty ? "provider_effort_manual_hint" : "provider_effort_advertised_hint"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Button(t("provider_validate"), systemImage: "checkmark.shield") { Task { await model.validateProviderConnection(connection) } }
                            .disabled(busy || state.defaultModelID == nil)
                        Text(t("provider_validation_hint")).font(.caption).foregroundStyle(.secondary)
                    }
                    if state.connectionVerified { Text(t("provider_validation_success")).font(.callout).foregroundStyle(.green) }
                    if let error = state.error { Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled) }
                }.padding(22)
            }
            Divider()
            HStack(alignment: .center) {
                Text(t("provider_storage_notice")).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                Button(t("cancel"), action: onClose).disabled(model.isMutating)
                Button(t("provider_save")) {
                    Task {
                        await model.saveProvider(connection)
                        if model.providerEditor?.didSave == true { apiKey = ""; onClose() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || state.defaultModelID == nil)
            }.padding(18)
        }
        .onChange(of: baseURL) { _, _ in model.invalidateProviderValidation() }
        .onChange(of: apiKey) { _, _ in model.invalidateProviderValidation() }
        .onChange(of: state.defaultModelID) { _, value in
            effort = state.models.first { $0.id == value }?.reasoningEffort ?? ""
        }
    }

    private var modelList: some View {
        VStack(spacing: 0) {
            if state.visibleModelIDs.isEmpty {
                Text(t(state.models.isEmpty ? "provider_fetch_hint" : "provider_no_match"))
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(26)
            } else {
                ForEach(state.visibleModelIDs, id: \.self) { id in
                    if let row = state.models.first(where: { $0.id == id }), let index = state.visibleModelIDs.firstIndex(of: id) {
                        HStack(spacing: 10) {
                            Toggle("", isOn: Binding(get: { row.isEnabled }, set: { model.enableProviderModel(id: id, enabled: $0) }))
                                .labelsHidden().toggleStyle(.checkbox).help(t("provider_enable_model"))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.id).font(.system(.body, design: .monospaced)).lineLimit(1).help(row.id)
                                if row.displayName != row.id { Text(row.displayName).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            }
                            Spacer(minLength: 4)
                            Button { model.chooseProviderDefaultModel(id: id) } label: {
                                Image(systemName: state.defaultModelID == id ? "star.fill" : "star")
                                    .foregroundStyle(state.defaultModelID == id ? Color.accentColor : Color.secondary)
                            }.help(t("provider_set_default"))
                            Button { model.moveProviderModel(id: id, offset: -1) } label: { Image(systemName: "arrow.up") }
                                .disabled(index == 0).help(t("provider_move_up"))
                            Button { model.moveProviderModel(id: id, offset: 1) } label: { Image(systemName: "arrow.down") }
                                .disabled(index == state.visibleModelIDs.count - 1).help(t("provider_move_down"))
                        }.buttonStyle(.borderless).padding(10).disabled(busy)
                        if id != state.visibleModelIDs.last { Divider() }
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
    }
}
