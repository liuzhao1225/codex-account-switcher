import Foundation
import Sparkle
import Testing
@testable import CodexAccountSwitcher

@MainActor
struct AppUpdaterTests {
    @Test func successfulBackgroundCheckClearsPreviousNetworkError() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let info: [String: String] = [
            "CFBundleIdentifier": "com.liuzhao.switcher-updater-tests",
            "CFBundleVersion": "7", "CFBundleName": "Updater tests",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: directory.appending(path: "Info.plist"))
        let bundle = try #require(Bundle(url: directory))
        let driver = SPUStandardUserDriver(hostBundle: bundle, delegate: nil)
        let engine = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: nil)
        let adapter = AppUpdater()

        adapter.updater(engine, didAbortWithError: URLError(.notConnectedToInternet))
        #expect(adapter.lastError != nil)
        adapter.updater(engine, didAbortWithError: NSError(
            domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue)
        ))
        #expect(adapter.lastError == nil)
        adapter.updater(engine, didAbortWithError: URLError(.timedOut))
        #expect(adapter.lastError != nil)
    }
}
