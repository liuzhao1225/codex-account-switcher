import AppKit
import SwiftUI

@main
struct SwitcherApp: App {
    @StateObject private var model = AppModel.live()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(model: model)
        } label: {
            MenuBarLogo()
                .accessibilityLabel("Codex Account Switcher Lite")
                .task {
                    await model.startBackgroundUsageRefresh()
                }
        }
        .menuBarExtraStyle(.window)
        .commands {
            QuitApplicationCommands(title: model.text("quit"))
        }
    }
}

private struct MenuBarLogo: View {
    private static let image: NSImage = {
        let resourceBundleName = "CodexAccountSwitcherLite_CodexAccountSwitcherLite.bundle"
        let resourceBundle = [Bundle.main.resourceURL, Bundle.main.bundleURL]
            .compactMap { $0 }
            .map { $0.appending(path: resourceBundleName) }
            .compactMap { Bundle(url: $0) }
            .first
        guard let url = resourceBundle?.url(
            forResource: "openai-account-switcher",
            withExtension: "svg"
        ), let image = NSImage(contentsOf: url) else {
            preconditionFailure("Missing openai-account-switcher.svg")
        }
        image.isTemplate = true
        return image
    }()

    var body: some View {
        Image(nsImage: Self.image)
            .resizable()
            .scaledToFit()
            .frame(width: 10, height: 10)
    }
}

private struct QuitApplicationCommands: Commands {
    let title: String

    var body: some Commands {
        CommandGroup(replacing: .appTermination) {
            Button(title) {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
