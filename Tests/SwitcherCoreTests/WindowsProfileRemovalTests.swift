#if os(Windows)
import Foundation
import Testing
import WinSDK
import SwitcherPlatform
@testable import SwitcherCore

struct WindowsProfileRemovalTests {
    @Test(arguments: [false, true])
    func removesLongPluginCacheAndPreservesTheActiveAccount(readOnly: Bool) async throws {
        let fixture = try RemovalFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let home = await fixture.store.profileHome(id: fixture.target.id)
        let cachedFile = try fixture.longCache(in: home, readOnly: readOnly)
        #expect(cachedFile.path.utf16.count > 300)

        try await fixture.store.removeAccount(id: fixture.target.id)

        #expect(!FileManager.default.fileExists(atPath: home.path))
        try await fixture.expectOnlyActiveAccount()
        #expect(try await fixture.store.loadUsageCache().entries.map(\.profileID) == [fixture.active.id])
    }

    @Test func cancelledLoginCleanupRemovesLongPluginCache() async throws {
        let fixture = try RemovalFixture()
        defer { fixture.clean() }
        let home = try await fixture.store.createProfileDirectory(id: fixture.target.id)
        _ = try fixture.longCache(in: home, readOnly: true)

        try await fixture.store.discardUnregisteredProfile(id: fixture.target.id)

        #expect(!FileManager.default.fileExists(atPath: home.path))
        #expect(try await fixture.store.loadRegistry().accounts.isEmpty)
    }

    @Test func activeAccountRemainsProtectedWithLongPluginCache() async throws {
        let fixture = try RemovalFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let home = await fixture.store.profileHome(id: fixture.active.id)
        _ = try fixture.longCache(in: home)

        await #expect(throws: AccountStoreError.cannotRemoveActiveAccount) {
            try await fixture.store.removeAccount(id: fixture.active.id)
        }

        #expect(try await fixture.store.loadRegistry().accounts.count == 2)
        #expect(try Data(contentsOf: home.appending(path: "auth.json")) == fixture.activeCredential)
        #expect(try Data(contentsOf: fixture.live.appending(path: "auth.json")) == fixture.activeCredential)
    }

    @Test func lockedCredentialRestoresRegistryAndCanBeRetried() async throws {
        let fixture = try RemovalFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let home = await fixture.store.profileHome(id: fixture.target.id)
        let credential = home.appending(path: "auth.json")
        var handle: HANDLE? = try fixture.open(credential, share: 0)
        defer { if let handle { CloseHandle(handle) } }

        await #expect(throws: (any Error).self) {
            try await fixture.store.removeAccount(id: fixture.target.id)
        }

        #expect(try await fixture.store.loadRegistry().accounts.contains(fixture.target))
        let reopened = AccountStore(baseURL: fixture.base, activeHomeURL: fixture.live)
        #expect(try await reopened.loadRegistry().accounts.contains(fixture.target))
        #expect(try await reopened.loadRegistry().activeAccountID == fixture.active.id)
        #expect(try Data(contentsOf: fixture.live.appending(path: "auth.json")) == fixture.activeCredential)
        CloseHandle(handle)
        handle = nil

        try await fixture.store.removeAccount(id: fixture.target.id)
        try await fixture.expectOnlyActiveAccount()
    }

    @Test func junctionIsRejectedBeforeDeletingCredentialsOrExternalFiles() async throws {
        let fixture = try RemovalFixture()
        defer { fixture.clean() }
        try await fixture.prepare()
        let home = await fixture.store.profileHome(id: fixture.target.id)
        let external = fixture.root.appending(path: "outside")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let sentinel = external.appending(path: "keep.txt")
        try Data("must survive".utf8).write(to: sentinel)
        let junction = home.appending(path: "linked-cache")
        try fixture.createJunction(junction, to: external)
        defer { _ = fixture.wide(junction) { RemoveDirectoryW($0) } }

        await #expect(throws: (any Error).self) {
            try await fixture.store.removeAccount(id: fixture.target.id)
        }

        #expect(try Data(contentsOf: sentinel) == Data("must survive".utf8))
        #expect(try Data(contentsOf: home.appending(path: "auth.json")) == fixture.targetCredential)
        let reopened = AccountStore(baseURL: fixture.base, activeHomeURL: fixture.live)
        #expect(try await reopened.loadRegistry().accounts.contains(fixture.target))
    }
}

private struct RemovalFixture {
    let root: URL
    let base: URL
    let live: URL
    let store: AccountStore
    let active = AccountProfile(id: UUID(), displayName: "Active", email: "active@example.test", accountID: "active", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
    let target = AccountProfile(id: UUID(), displayName: "Inactive", email: "inactive@example.test", accountID: "inactive", createdAt: Date(timeIntervalSince1970: 1_700_000_001))
    let activeCredential = Data(#"{"tokens":{"account_id":"active","access_token":"synthetic-active"}}"#.utf8)
    let targetCredential = Data(#"{"tokens":{"account_id":"inactive","access_token":"synthetic-inactive"}}"#.utf8)

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "profile-removal-\(UUID())")
        base = root.appending(path: "store")
        live = root.appending(path: "live")
        try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
        store = AccountStore(baseURL: base, activeHomeURL: live)
    }

    func prepare() async throws {
        try activeCredential.write(to: live.appending(path: "auth.json"))
        try await store.importCurrentProfile(active)
        let home = try await store.createProfileDirectory(id: target.id)
        try targetCredential.write(to: home.appending(path: "auth.json"))
        try await store.addProfile(target)
        for profile in [active, target] {
            try await store.cacheWeeklyUsage(WeeklyUsage(remainingPercent: 50, resetsAt: Date(timeIntervalSince1970: 2_000_000_000)), profileID: profile.id)
        }
    }

    func expectOnlyActiveAccount() async throws {
        let reopened = AccountStore(baseURL: base, activeHomeURL: live)
        let registry = try await reopened.loadRegistry()
        #expect(registry.accounts == [active])
        #expect(registry.activeAccountID == active.id)
        #expect(try Data(contentsOf: live.appending(path: "auth.json")) == activeCredential)
        let home = await store.profileHome(id: active.id)
        #expect(try Data(contentsOf: home.appending(path: "auth.json")) == activeCredential)
    }

    func wide<T>(_ url: URL, _ body: (UnsafePointer<WCHAR>) -> T) -> T {
        let path = "\\\\?\\" + url.path.replacingOccurrences(of: "/", with: "\\")
        return Array((path + "\0").utf16).withUnsafeBufferPointer { body($0.baseAddress!) }
    }

    func open(_ url: URL, share: DWORD = DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE), create: Bool = false) throws -> HANDLE {
        let handle = wide(url) { CreateFileW($0, DWORD(GENERIC_READ) | DWORD(GENERIC_WRITE), share, nil,
                                             DWORD(create ? CREATE_NEW : OPEN_EXISTING), DWORD(FILE_ATTRIBUTE_NORMAL), nil) }
        guard let handle, handle != INVALID_HANDLE_VALUE else { throw winError() }
        return handle
    }

    func longCache(in home: URL, readOnly: Bool = false) throws -> URL {
        var directory = home
        var components = [".tmp", "plugins", "unicode-鴨-é"]
        while directory.path.utf16.count < 310 || !components.isEmpty {
            directory.append(path: components.isEmpty ? "nested-plugin-reference" : components.removeFirst())
            guard wide(directory, { CreateDirectoryW($0, nil) }) else { throw winError() }
        }
        let file = directory.appending(path: "synthetic-cache.txt")
        CloseHandle(try open(file, create: true))
        if readOnly, !wide(file, { SetFileAttributesW($0, DWORD(FILE_ATTRIBUTE_READONLY)) }) { throw winError() }
        return file
    }

    // Mount-point junctions do not require Developer Mode or symlink privileges.
    // Build REPARSE_DATA_BUFFER explicitly so the test does not depend on cmd.exe
    // quoting or on Foundation's treatment of Windows path separators.
    func createJunction(_ junction: URL, to target: URL) throws {
        guard wide(junction, { CreateDirectoryW($0, nil) }) else { throw winError() }
        let handle = wide(junction) {
            CreateFileW($0, DWORD(GENERIC_WRITE), 0, nil, DWORD(OPEN_EXISTING),
                        DWORD(FILE_FLAG_OPEN_REPARSE_POINT) | DWORD(FILE_FLAG_BACKUP_SEMANTICS), nil)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else { throw winError() }
        defer { CloseHandle(handle) }
        let path = target.path.replacingOccurrences(of: "/", with: "\\")
        let substitute = Array(("\\??\\" + path + "\0").utf16)
        let printName = Array((path + "\0").utf16)
        var buffer = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { buffer.append(contentsOf: $0) }
        }
        append(UInt32(0xA0000003)) // IO_REPARSE_TAG_MOUNT_POINT
        append(UInt16(8 + 2 * (substitute.count + printName.count)))
        append(UInt16(0)) // Reserved
        append(UInt16(0)) // SubstituteNameOffset
        append(UInt16(2 * (substitute.count - 1)))
        append(UInt16(2 * substitute.count)) // PrintNameOffset
        append(UInt16(2 * (printName.count - 1)))
        for character in substitute + printName { append(character) }
        var returned: DWORD = 0
        let success = buffer.withUnsafeMutableBytes { bytes in
            DeviceIoControl(handle, DWORD(0x000900A4), bytes.baseAddress, DWORD(bytes.count),
                            nil, 0, &returned, nil) // FSCTL_SET_REPARSE_POINT
        }
        guard success else { throw winError() }
    }

    func winError() -> NSError { NSError(domain: "WindowsProfileRemovalTests", code: Int(GetLastError())) }
    func clean() { _ = switcher_remove_directory(root.path) }
}
#endif
