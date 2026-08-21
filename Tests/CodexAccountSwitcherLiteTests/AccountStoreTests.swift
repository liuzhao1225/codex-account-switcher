import Foundation
import Testing
@testable import CodexAccountSwitcherLite

struct AccountStoreTests {
    @Test func persistsProfilesAndEnforcesLifecycleRules() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = fixture.store
        let first = AccountProfile(
            id: UUID(), displayName: "First", email: "first@example.com",
            accountID: "account-first", createdAt: Date(timeIntervalSince1970: 1), lastUsedAt: nil
        )
        try await store.importCurrentProfile(first)
        var registry = try await store.loadRegistry()
        #expect(registry.activeAccountID == first.id)
        #expect(registry.accounts == [first])

        do {
            try await store.removeAccount(id: first.id)
            Issue.record("The active account should not be removable")
        } catch let error as AccountStoreError {
            #expect(error == .cannotRemoveActiveAccount)
        }

        let second = AccountProfile(
            id: UUID(), displayName: "Second", email: "second@example.com",
            accountID: "account-second", createdAt: Date(timeIntervalSince1970: 2), lastUsedAt: nil
        )
        let secondHome = try await store.createProfileDirectory(id: second.id)
        try Data("second-auth".utf8).write(to: secondHome.appending(path: "auth.json"))
        try await store.addProfile(second)
        try await store.removeAccount(id: second.id)
        registry = try await store.loadRegistry()
        #expect(registry.accounts.count == 1)
        #expect(!FileManager.default.fileExists(atPath: secondHome.path))
    }

    @Test func writesCredentialsWithRestrictedPermissionsAndAtomicTargetName() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let store = fixture.store
        let first = AccountProfile(
            id: UUID(), displayName: "First", email: "first@example.com",
            accountID: "account-first", createdAt: Date(), lastUsedAt: nil
        )
        try await store.importCurrentProfile(first)
        let firstHome = await store.profileHome(id: first.id)
        #expect(try permissions(firstHome.appending(path: "auth.json")) == 0o600)

        let second = AccountProfile(
            id: UUID(), displayName: "Second", email: "second@example.com",
            accountID: "account-second", createdAt: Date(), lastUsedAt: nil
        )
        let secondHome = try await store.createProfileDirectory(id: second.id)
        let secondBytes = Data("{\"account\":\"second\"}".utf8)
        try secondBytes.write(to: secondHome.appending(path: "auth.json"))
        try await store.addProfile(second)
        try await store.activateTargetCredential(id: second.id)

        let activeAuth = fixture.activeHome.appending(path: "auth.json")
        #expect(try Data(contentsOf: activeAuth) == secondBytes)
        #expect(try permissions(activeAuth) == 0o600)
        let credentialTemps = try FileManager.default.contentsOfDirectory(atPath: fixture.activeHome.path)
            .filter { $0.hasPrefix("auth.json.switcher-") }
        #expect(credentialTemps.isEmpty)
        let unexpected = try FileManager.default.contentsOfDirectory(atPath: fixture.activeHome.path)
            .filter { $0.contains("backup") || $0.contains("rollback") || $0.contains("journal") }
        #expect(unexpected.isEmpty)
    }

    @Test func persistsWeeklyUsageCacheWithRestrictedPermissions() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let accountID = UUID()
        let usage = WeeklyUsage(
            remainingPercent: 64,
            resetsAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
        let fetchedAt = Date(timeIntervalSince1970: 1_749_000_000)
        let profile = AccountProfile(
            id: accountID,
            displayName: "Cached",
            email: "cached@example.com",
            accountID: "cached-account",
            createdAt: Date(),
            lastUsedAt: nil
        )

        try await fixture.store.importCurrentProfile(profile)
        try await fixture.store.cacheWeeklyUsage(usage, profileID: accountID, fetchedAt: fetchedAt)
        let reloadedStore = AccountStore(baseURL: fixture.support, activeHomeURL: fixture.activeHome)
        let cache = try await reloadedStore.loadUsageCache()

        #expect(cache.entries == [UsageCacheEntry(profileID: accountID, usage: usage, fetchedAt: fetchedAt)])
        #expect(try permissions(fixture.support.appending(path: "usage-cache.json")) == 0o600)
    }

    @Test func persistsSettingsAndLoadsLegacySettingsWithPercentageEnabled() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(
            at: fixture.support,
            withIntermediateDirectories: true
        )
        let settingsURL = fixture.support.appending(path: "settings.json")
        try Data(#"{"language":"english"}"#.utf8).write(to: settingsURL)

        let legacySettings = try await fixture.store.loadSettings()
        #expect(legacySettings.language == .english)
        #expect(legacySettings.showsMenuBarPercentage)

        let updatedSettings = AppSettings(
            language: .simplifiedChinese,
            showsMenuBarPercentage: false
        )
        try await fixture.store.saveSettings(updatedSettings)
        let reloadedStore = AccountStore(
            baseURL: fixture.support,
            activeHomeURL: fixture.activeHome
        )
        #expect(try await reloadedStore.loadSettings() == updatedSettings)
        #expect(try permissions(settingsURL) == 0o600)
    }

    private func permissions(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}

private struct StoreFixture {
    let root: URL
    let activeHome: URL
    let support: URL
    let store: AccountStore

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "codex-switcher-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        activeHome = root.appending(path: "active", directoryHint: .isDirectory)
        support = root.appending(path: "support", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: activeHome, withIntermediateDirectories: true)
        try Data("{\"account\":\"first\"}".utf8).write(to: activeHome.appending(path: "auth.json"))
        store = AccountStore(baseURL: support, activeHomeURL: activeHome)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
