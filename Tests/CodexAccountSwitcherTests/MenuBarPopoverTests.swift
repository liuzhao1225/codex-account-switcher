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
        for count in [0, 1, 2, 3, 4, 20] {
            let model = try await makeModel(root: root.appending(path: "\(count)"), accountCount: count)
            await model.setShowsFiveHourUsage(expandedUsage)
            let updater = AppUpdater()
            let host = NSHostingController(rootView: MenuBarPopover(
                model: model, updater: updater, tiboForecast: TiboForecastModel()
            ))
            let maximumSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
            let manageSize = NSHostingController(rootView: ManageAccountsView(model: model, onBack: {}))
                .sizeThatFits(in: maximumSize)
            let settingsSize = NSHostingController(rootView: SettingsView(model: model, updater: updater, onBack: {}))
                .sizeThatFits(in: maximumSize)

            // Exercise the first minimum-size probe, then heights left by both subpages.
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
