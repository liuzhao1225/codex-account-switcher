import AppKit
import SwiftUI

@main
struct SwitcherApp: App {
    @StateObject private var model = AppModel.live()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(model: model)
        } label: {
            Image(systemName: "person.2.circle")
                .accessibilityLabel("Codex Account Switcher Lite")
                .task {
                    await model.start()
                    model.refreshWeeklyUsage()
                }
        }
        .menuBarExtraStyle(.window)
        .commands {
            QuitApplicationCommands(title: model.text("quit"))
        }
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
