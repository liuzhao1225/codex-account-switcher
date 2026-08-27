import Darwin
import Foundation
import Testing
@testable import CodexAccountSwitcher

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

    @Test func restoresSavedCredentialWithoutChangingActiveRegistryEntry() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let profiles = try await prepareSwitchProfiles(fixture)

        try await fixture.store.activateTargetCredential(id: profiles.target.id)
        try await fixture.store.restoreActiveCredential(id: profiles.original.id)

        let activeAuth = fixture.activeHome.appending(path: "auth.json")
        #expect(try Data(contentsOf: activeAuth) == profiles.originalBytes)
        #expect(try permissions(activeAuth) == 0o600)
        #expect(try await fixture.store.loadRegistry().activeAccountID == profiles.original.id)
    }

    @Test func realStoreRestoresAfterVerificationFailureAndRetryPreservesOriginal() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let profiles = try await prepareSwitchProfiles(fixture)
        let service = SwitchService(
            desktop: StoreTestDesktop(),
            store: fixture.store,
            codex: StoreTestFailingCodex()
        )

        for _ in 0..<2 {
            do {
                try await service.switchAccount(to: profiles.target.id)
                Issue.record("Expected identity verification to fail")
            } catch let error as OperationError {
                #expect(error.stage == .verifyTargetIdentity)
            } catch {
                Issue.record("Expected OperationError, got \(error)")
            }
        }

        let activeAuth = fixture.activeHome.appending(path: "auth.json")
        let originalProfileAuth = await fixture.store.profileHome(id: profiles.original.id)
            .appending(path: "auth.json")
        #expect(try Data(contentsOf: activeAuth) == profiles.originalBytes)
        #expect(try Data(contentsOf: originalProfileAuth) == profiles.originalBytes)
        #expect(try await fixture.store.loadRegistry().activeAccountID == profiles.original.id)
    }

    @Test func realStoreRestoresAfterRegistryCommitFailure() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        let profiles = try await prepareSwitchProfiles(fixture)
        let accountsURL = fixture.support.appending(path: "accounts.json")
        guard Darwin.chflags(accountsURL.path, UInt32(UF_IMMUTABLE)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { _ = Darwin.chflags(accountsURL.path, 0) }
        let service = SwitchService(
            desktop: StoreTestDesktop(),
            store: fixture.store,
            codex: StoreTestMatchingCodex(target: profiles.target)
        )

        do {
            try await service.switchAccount(to: profiles.target.id)
            Issue.record("Expected registry commit to fail")
        } catch let error as OperationError {
            #expect(error.stage == .commitActiveAccountID)
        } catch {
            Issue.record("Expected OperationError, got \(error)")
        }

        let activeAuth = fixture.activeHome.appending(path: "auth.json")
        #expect(try Data(contentsOf: activeAuth) == profiles.originalBytes)
        #expect(try await fixture.store.loadRegistry().activeAccountID == profiles.original.id)
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

    @Test func persistsSettingsAndLoadsLegacyDefaults() async throws {
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
        #expect(!legacySettings.showsFiveHourUsage)
        #expect(!AppSettings.default.showsFiveHourUsage)

        let updatedSettings = AppSettings(
            language: .simplifiedChinese,
            showsMenuBarPercentage: false,
            showsFiveHourUsage: true
        )
        try await fixture.store.saveSettings(updatedSettings)
        let reloadedStore = AccountStore(
            baseURL: fixture.support,
            activeHomeURL: fixture.activeHome
        )
        #expect(try await reloadedStore.loadSettings() == updatedSettings)
        #expect(try permissions(settingsURL) == 0o600)
    }

    @Test func decodesLegacyWeeklyOnlyUsageCache() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(
            at: fixture.support,
            withIntermediateDirectories: true
        )
        let accountID = UUID()
        let cacheURL = fixture.support.appending(path: "usage-cache.json")
        let legacyCache = """
        {"entries":[{"profileID":"\(accountID.uuidString)","usage":{"remainingPercent":73,"resetsAt":"2025-06-15T15:06:40Z"},"fetchedAt":"2025-06-04T01:20:00Z"}]}
        """
        try Data(legacyCache.utf8).write(to: cacheURL)

        let cache = try await fixture.store.loadUsageCache()
        #expect(cache.entries.count == 1)
        #expect(cache.entries[0].profileID == accountID)
        #expect(cache.entries[0].usage.remainingPercent == 73)
        #expect(cache.entries[0].usage.fiveHourRemainingPercent == nil)
        #expect(cache.entries[0].usage.fiveHourResetsAt == nil)
    }

    @Test func migratesLegacyApplicationSupportDirectory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "codex-switcher-migration-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appending(path: "Codex Account Switcher Lite", directoryHint: .isDirectory)
        let current = root.appending(path: "Codex Account Switcher", directoryHint: .isDirectory)
        let activeHome = root.appending(path: "active", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: activeHome, withIntermediateDirectories: true)
        try Data(#"{"accounts":[],"version":1}"#.utf8).write(
            to: legacy.appending(path: "accounts.json")
        )

        let store = AccountStore(
            baseURL: current,
            legacyBaseURL: legacy,
            activeHomeURL: activeHome
        )
        _ = try await store.loadRegistry()

        #expect(FileManager.default.fileExists(atPath: current.appending(path: "accounts.json").path))
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
    }

    private func permissions(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    private func prepareSwitchProfiles(
        _ fixture: StoreFixture
    ) async throws -> (original: AccountProfile, target: AccountProfile, originalBytes: Data) {
        let original = AccountProfile(
            id: UUID(), displayName: "Original", email: "original@example.com",
            accountID: "original-id", createdAt: Date(), lastUsedAt: nil
        )
        try await fixture.store.importCurrentProfile(original)
        let originalAuth = await fixture.store.profileHome(id: original.id).appending(path: "auth.json")
        let originalBytes = try Data(contentsOf: originalAuth)

        let target = AccountProfile(
            id: UUID(), displayName: "Target", email: "target@example.com",
            accountID: "target-id", createdAt: Date(), lastUsedAt: nil
        )
        let targetHome = try await fixture.store.createProfileDirectory(id: target.id)
        try Data("target-auth".utf8).write(to: targetHome.appending(path: "auth.json"))
        try await fixture.store.addProfile(target)
        return (original, target, originalBytes)
    }
}

private struct StoreTestDesktop: DesktopControlling {
    func closeDesktop() async throws {}
    func reopenDesktop() async throws {}
}

private struct StoreTestFailingCodex: CodexIdentityReading {
    func readIdentity(profileHome: URL) async throws -> AccountIdentity {
        throw CodexClientError.identityUnavailable
    }
}

private struct StoreTestMatchingCodex: CodexIdentityReading {
    let target: AccountProfile

    func readIdentity(profileHome: URL) async throws -> AccountIdentity {
        AccountIdentity(accountID: target.accountID, email: target.email)
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
