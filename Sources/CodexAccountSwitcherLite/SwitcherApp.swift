import AppKit
import SwiftUI

@main
struct SwitcherApp: App {
    @StateObject private var model = AppModel.live()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(model: model)
        } label: {
            HStack(spacing: 4) {
                MenuBarLogo()
                if model.settings.showsMenuBarPercentage,
                   let remainingPercent = model.activeRemainingPercent {
                    Text("\(remainingPercent)%")
                        .monospacedDigit()
                }
            }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(menuBarAccessibilityLabel)
                .task {
                    await model.startBackgroundUsageRefresh()
                }
        }
        .menuBarExtraStyle(.window)
        .commands {
            QuitApplicationCommands(title: model.text("quit"))
        }
    }

    private var menuBarAccessibilityLabel: String {
        guard model.settings.showsMenuBarPercentage,
              let remainingPercent = model.activeRemainingPercent
        else {
            return "Codex Account Switcher Lite"
        }
        return "Codex Account Switcher Lite, \(remainingPercent)%"
    }
}

private struct MenuBarLogo: View {
    private static let logicalSize = NSSize(width: 16, height: 16)

    private static let image: NSImage = {
        let resourceBundleName = "CodexAccountSwitcherLite_CodexAccountSwitcherLite.bundle"
        let resourceBundle = [Bundle.main.resourceURL, Bundle.main.bundleURL]
            .compactMap { $0 }
            .map { $0.appending(path: resourceBundleName) }
            .compactMap { Bundle(url: $0) }
            .first
        guard let url = resourceBundle?.url(
            forResource: "account-switcher-logo",
            withExtension: "png"
        ), let image = NSImage(contentsOf: url) else {
            preconditionFailure("Missing account-switcher-logo.png")
        }
        image.size = logicalSize
        image.isTemplate = true
        return image
    }()

    var body: some View {
        Image(nsImage: Self.image)
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
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
