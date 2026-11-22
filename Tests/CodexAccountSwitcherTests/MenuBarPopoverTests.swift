import AppKit
import SwiftUI
import Testing
import SwitcherCore
@testable import CodexAccountSwitcher

@MainActor
struct MenuBarPopoverTests {
    @Test(arguments: [false, true])
    func accountHeightIsIndependentOfPreviousPageAndCappedAtThreeRows(
        expandedUsage: Bool
    ) async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "popover-layout-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        var heights: [Int: CGFloat] = [:]
        var manageHeights: [Int: CGFloat] = [:]
        var settingsHeights: [Int: CGFloat] = [:]
        for count in [0, 1, 2, 3, 4, 6, 20] {
            let model = try await makeModel(root: root.appending(path: "\(count)"), accountCount: count)
            await model.setShowsFiveHourUsage(expandedUsage)
            let updater = AppUpdater()
            let host = NSHostingController(rootView: MenuBarPopover(
                model: model, updater: updater
            ))
            let maximumSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
            let manageHost = NSHostingController(rootView: ManageAccountsView(model: model, onBack: {}).frame(width: 400))
            let manageSize = manageHost.sizeThatFits(in: maximumSize)
            manageHeights[count] = manageSize.height
            let settingsSize = NSHostingController(rootView: SettingsView(model: model, updater: updater, onBack: {}))
                .sizeThatFits(in: maximumSize)
            settingsHeights[count] = settingsSize.height

            let firstSize = host.sizeThatFits(in: NSSize(width: 400, height: 0))
            heights[count] = firstSize.height
            for proposal in [manageSize, settingsSize, maximumSize] {
                let size = host.sizeThatFits(in: proposal)
                #expect(abs(size.height - firstSize.height) < 1)
                #expect(size.width == 400)
            }
        }
        let empty = try #require(heights[0])
        let one = try #require(heights[1])
        let two = try #require(heights[2])
        let three = try #require(heights[3])
        #expect(one > empty)
        #expect(two > one)
        #expect(three > two)
        #expect(heights[4] == three)
        #expect(heights[20] == three)
        // ManageAccountsView also caps its list height at 6 rows instead of overflowing off-screen.
        #expect(manageHeights[20] == manageHeights[6])
        // The global automation switch takes the same space regardless of account count.
        let emptySettings = try #require(settingsHeights[0])
        #expect((400..<450).contains(emptySettings))
        #expect(settingsHeights.values.allSatisfy { abs($0 - emptySettings) < 1 })
    }

    @Test func settingsScrollsWithANativeOverlayWithoutReducingContentWidth() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "settings-scroll-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try await makeModel(root: root, accountCount: 2)
        await model.setLanguage(.simplifiedChinese)
        let host = NSHostingController(rootView: SettingsView(model: model, updater: AppUpdater(), onBack: {})
            .frame(width: 400))
        let size = host.sizeThatFits(in: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.contentViewController = host
        window.layoutIfNeeded()
        host.view.layoutSubtreeIfNeeded()

        let scrollView = try #require(firstScrollView(in: host.view))
        #expect(scrollView.scrollerStyle == .overlay)
        #expect(scrollView.verticalScroller?.scrollerStyle == .overlay)
        #expect(scrollView.verticalScroller?.controlSize == .small)
        #expect(abs(scrollView.contentSize.width - 400) < 1)
        #expect(abs(scrollView.contentSize.height - 400) < 1)

        let document = try #require(scrollView.documentView)
        #expect(document.bounds.height > scrollView.contentSize.height)
        document.scrollToVisible(NSRect(x: 0, y: document.bounds.maxY - 1, width: 1, height: 1))
        #expect(abs(scrollView.documentVisibleRect.maxY - document.bounds.maxY) < 1)
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        (view as? NSScrollView) ?? view.subviews.lazy.compactMap { firstScrollView(in: $0) }.first
    }

    private func makeModel(root: URL, accountCount: Int) async throws -> AppModel {
        let store = AccountStore(baseURL: root.appending(path: "store"), activeHomeURL: root.appending(path: "home"))
        for index in 0..<accountCount {
            let profile = AccountProfile(id: UUID(), displayName: "Account \(index)",
                                         email: "account\(index)@example.test", accountID: "account-\(index)",
                                         createdAt: Date())
            let home = try await store.createProfileDirectory(id: profile.id)
            try Data("fixture".utf8).write(to: home.appending(path: "auth.json"))
            try await store.addProfile(profile)
            try await store.cacheWeeklyUsage(
                WeeklyUsage(remainingPercent: 72, resetsAt: Date().addingTimeInterval(86_400),
                            fiveHourRemainingPercent: 85, fiveHourResetsAt: Date().addingTimeInterval(3_600)),
                profileID: profile.id
            )
        }
        let model = AppModel(store: store, codex: LayoutClient(), switchService: LayoutSwitch())
        await model.start()
        #expect(model.accounts.count == accountCount)
        #expect(model.visibleError == nil)
        return model
    }
}

private struct LayoutClient: AccountClient {
    func readIdentity(profileHome: URL) async throws -> AccountIdentity {
        throw CodexClientError.loginFailed("Layout test must not read an identity")
    }
    func consumeResetCredit(profileHome: URL, creditID: String, idempotencyKey: String) async throws -> ResetCreditOutcome {
        throw CodexClientError.remoteError(code: nil, message: "Unexpected reset consumption in this fixture.")
    }
    func readWeeklyUsage(profileHome: URL) async throws -> WeeklyUsage {
        throw CodexClientError.loginFailed("Layout test must not request usage")
    }
    func login(profileHome: URL) async throws -> AccountIdentity {
        throw CodexClientError.loginFailed("Layout test must not log in")
    }
}

private struct LayoutSwitch: SwitchServicing {
    func switchAccount(to targetID: UUID) async throws {
        throw CodexClientError.loginFailed("Layout test must not switch accounts")
    }
}
