import Foundation
#if canImport(Darwin)
import Darwin
#endif
#if os(Windows)
import SwitcherPlatform
#endif

public protocol AccountStoring: Sendable {
    func loadRegistry() async throws -> AccountRegistry
    func profile(id: UUID) async throws -> AccountProfile
    func activeCredentialExists() async -> Bool
    func hasOpenAIAPICredential() async -> Bool
    func saveOpenAIAPICredential() async throws
    func activateOpenAIAPICredential() async throws
    func clearActiveCredential() async throws
    func activeCodexHome() async -> URL
    func saveCurrentCredential() async throws
    func activateTargetCredential(id: UUID) async throws
    func restoreActiveCredential(id: UUID) async throws
    func commitActiveAccountID(_ id: UUID) async throws
}

public actor AccountStore: AccountStoring {
    public let baseURL: URL
    public let activeHomeURL: URL

    private let fileManager: FileManager
    private let legacyBaseURL: URL?
    private var registry: AccountRegistry?
    private var usageCache: UsageCache?

    public init(
        baseURL: URL? = nil,
        legacyBaseURL: URL? = nil,
        activeHomeURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        #if os(Windows)
        let applicationSupportURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LOCALAPPDATA"]
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("AppData/Local").path)
        #else
        let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        #endif
        if let baseURL {
            self.baseURL = baseURL
            self.legacyBaseURL = legacyBaseURL
        } else {
            self.baseURL = applicationSupportURL.appending(
                path: "Codex Account Switcher",
                directoryHint: .isDirectory
            )
            self.legacyBaseURL = applicationSupportURL.appending(
                path: "Codex Account Switcher Lite",
                directoryHint: .isDirectory
            )
        }
        self.activeHomeURL = activeHomeURL
            ?? ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? fileManager.homeDirectoryForCurrentUser.appending(path: ".codex", directoryHint: .isDirectory)
    }

    private var accountsURL: URL { baseURL.appending(path: "accounts.json") }
    private var settingsURL: URL { baseURL.appending(path: "settings.json") }
    private var usageCacheURL: URL { baseURL.appending(path: "usage-cache.json") }
    private var profilesURL: URL { baseURL.appending(path: "accounts", directoryHint: .isDirectory) }

    public func loadRegistry() throws -> AccountRegistry {
        try prepareDirectories()
        if let registry { return registry }
        guard fileManager.fileExists(atPath: accountsURL.path) else {
            registry = .empty
            return .empty
        }
        let loaded = try Self.decoder.decode(AccountRegistry.self, from: readChecked(accountsURL))
        registry = loaded
        return loaded
    }

    public func loadSettings() throws -> AppSettings {
        try prepareDirectories()
        guard fileManager.fileExists(atPath: settingsURL.path) else { return .default }
        return try Self.decoder.decode(AppSettings.self, from: readChecked(settingsURL))
    }

    public func saveSettings(_ settings: AppSettings) throws {
        try prepareDirectories()
        try writeJSON(settings, to: settingsURL)
    }

    public func loadProviderLibrary() throws -> ProviderLibrary {
        let url = baseURL.appending(path: "providers.json")
        guard fileManager.fileExists(atPath: url.path) else { return ProviderLibrary() }
        return try Self.decoder.decode(ProviderLibrary.self, from: readChecked(url))
    }

    public func saveProviderLibrary(_ library: ProviderLibrary) throws {
        try prepareDirectories()
        try writeJSON(library, to: baseURL.appending(path: "providers.json"))
    }

    public func protectProviderConfiguration() throws {
        let url = activeHomeURL.appending(path: "config.toml")
        try checkPath(url)
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: activeHomeURL, withIntermediateDirectories: true)
            try secureAtomicWrite(Data(), to: url)
        }
        try restrictPermissions(url, directory: false)
    }

    public func loadUsageCache() throws -> UsageCache {
        try prepareDirectories()
        if let usageCache { return usageCache }
        guard fileManager.fileExists(atPath: usageCacheURL.path) else {
            usageCache = .empty
            return .empty
        }
        let loaded = try Self.decoder.decode(UsageCache.self, from: readChecked(usageCacheURL))
        usageCache = loaded
        return loaded
    }

    public func cacheWeeklyUsage(_ usage: WeeklyUsage, profileID: UUID, fetchedAt: Date = Date()) throws {
        let registry = try loadRegistry()
        guard registry.accounts.contains(where: { $0.id == profileID }) else { return }
        var cache = try loadUsageCache()
        let entry = UsageCacheEntry(profileID: profileID, usage: usage, fetchedAt: fetchedAt)
        if let index = cache.entries.firstIndex(where: { $0.profileID == profileID }) {
            cache.entries[index] = entry
        } else {
            cache.entries.append(entry)
        }
        try saveUsageCache(cache)
    }

    public func profile(id: UUID) throws -> AccountProfile {
        let registry = try loadRegistry()
        guard let profile = registry.accounts.first(where: { $0.id == id }) else {
            throw AccountStoreError.profileNotFound
        }
        return profile
    }

    public func profileHome(id: UUID) -> URL {
        profilesURL.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    public func activeCodexHome() -> URL { activeHomeURL }

    public func activeCredentialExists() -> Bool {
        fileManager.fileExists(atPath: activeHomeURL.appending(path: "auth.json").path)
    }

    public func createProfileDirectory(id: UUID) throws -> URL {
        try prepareDirectories()
        let directory = profileHome(id: id)
        try checkPath(directory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        try restrictPermissions(directory, directory: true)
        return directory
    }

    public func importCurrentProfile(_ profile: AccountProfile) throws {
        let source = activeHomeURL.appending(path: "auth.json")
        guard fileManager.fileExists(atPath: source.path) else {
            throw AccountStoreError.activeCredentialMissing
        }
        _ = try createProfileDirectory(id: profile.id)
        try copyCredential(from: source, to: profileHome(id: profile.id).appending(path: "auth.json"))

        var current = try loadRegistry()
        current.accounts.append(profile)
        current.activeAccountID = profile.id
        try saveRegistry(current)
    }

    public func addProfile(_ profile: AccountProfile) throws {
        let authURL = profileHome(id: profile.id).appending(path: "auth.json")
        guard fileManager.fileExists(atPath: authURL.path) else {
            throw AccountStoreError.targetCredentialMissing
        }
        try restrictPermissions(authURL, directory: false)
        var current = try loadRegistry()
        let identity = AccountIdentity(accountID: profile.accountID, email: profile.email)
        guard !current.accounts.contains(where: { identity.matches($0) }) else {
            throw AccountStoreError.duplicateAccount
        }
        current.accounts.append(profile)
        try saveRegistry(current)
    }

    public func discardUnregisteredProfile(id: UUID) throws {
        guard try !loadRegistry().accounts.contains(where: { $0.id == id }) else { return }
        let directory = profileHome(id: id)
        if fileManager.fileExists(atPath: directory.path) { try removeProfileDirectory(directory) }
    }

    public func registerActiveIdentity(_ identity: AccountIdentity) throws {
        let current = try loadRegistry()
        if let profile = current.accounts.first(where: { identity.matches($0) }) {
            try copyCredential(from: activeHomeURL.appending(path: "auth.json"),
                               to: profileHome(id: profile.id).appending(path: "auth.json"))
            try commitActiveAccountID(profile.id)
        } else {
            try importCurrentProfile(AccountProfile(id: UUID(), displayName: identity.suggestedDisplayName,
                email: identity.email, accountID: identity.accountID, createdAt: Date(), lastUsedAt: Date()))
        }
    }

    public func removeAccount(id: UUID, activeAuthentication: CodexAuthenticationState) throws {
        var current = try loadRegistry()
        guard let profile = current.accounts.first(where: { $0.id == id }) else {
            throw AccountStoreError.profileNotFound
        }
        guard activeAuthentication.identity?.matches(profile) != true else {
            throw AccountStoreError.cannotRemoveActiveAccount
        }
        var cache = try loadUsageCache()
        if cache.entries.contains(where: { $0.profileID == id }) {
            cache.entries.removeAll(where: { $0.profileID == id })
            try saveUsageCache(cache)
        }
        let original = current
        current.accounts.removeAll(where: { $0.id == id })
        if current.activeAccountID == id { current.activeAccountID = nil }
        try saveRegistry(current)
        do {
            try removeProfileDirectory(profileHome(id: id))
        } catch {
            let removalError = error
            do {
                try saveRegistry(original)
            } catch {
                throw NSError(domain: "CodexAccountSwitcher.AccountStore", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "\(removalError.localizedDescription) Restoring the account list also failed: \(error.localizedDescription)",
                ])
            }
            throw removalError
        }
    }

    public func saveCurrentCredential() throws {
        let current = try loadRegistry()
        guard let activeID = current.activeAccountID else {
            throw AccountStoreError.activeProfileMissing
        }
        guard current.accounts.contains(where: { $0.id == activeID }) else {
            throw AccountStoreError.activeProfileMissing
        }
        let source = activeHomeURL.appending(path: "auth.json")
        guard fileManager.fileExists(atPath: source.path) else {
            throw AccountStoreError.activeCredentialMissing
        }
        try copyCredential(from: source, to: profileHome(id: activeID).appending(path: "auth.json"))
    }

    public func activateTargetCredential(id: UUID) throws {
        try installCredential(id: id)
    }

    public func clearActiveCredential() throws {
        try checkPath(activeHomeURL.appending(path: "auth.json"))
        let credential = activeHomeURL.appending(path: "auth.json")
        if fileManager.fileExists(atPath: credential.path) { try fileManager.removeItem(at: credential) }
    }

    private var openAIAPICredentialURL: URL {
        baseURL.appending(path: "openai-api", directoryHint: .isDirectory).appending(path: "auth.json")
    }

    public func hasOpenAIAPICredential() -> Bool {
        fileManager.fileExists(atPath: openAIAPICredentialURL.path)
    }

    public func saveOpenAIAPICredential() throws {
        let bytes = try readOpenAIAPICredential(activeHomeURL.appending(path: "auth.json"))
        try prepareDirectories()
        let directory = openAIAPICredentialURL.deletingLastPathComponent()
        try checkPath(directory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try restrictPermissions(directory, directory: true)
        try secureAtomicWrite(bytes, to: openAIAPICredentialURL)
    }

    public func activateOpenAIAPICredential() throws {
        let bytes = try readOpenAIAPICredential(openAIAPICredentialURL)
        try checkPath(activeHomeURL)
        try fileManager.createDirectory(at: activeHomeURL, withIntermediateDirectories: true)
        try secureAtomicWrite(bytes, to: activeHomeURL.appending(path: "auth.json"))
    }

    private func readOpenAIAPICredential(_ url: URL) throws -> Data {
        guard fileManager.fileExists(atPath: url.path) else {
            throw NativeAPIAuthenticationError.savedLoginUnavailable
        }
        let bytes = try readChecked(url)
        guard let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let key = object["OPENAI_API_KEY"] as? String, !key.isEmpty,
              object["auth_mode"] == nil || object["auth_mode"] as? String == "apikey" else {
            throw NativeAPIAuthenticationError.savedLoginUnavailable
        }
        return bytes
    }

    public func restoreActiveCredential(id: UUID) throws {
        try installCredential(id: id)
    }

    private func installCredential(id: UUID) throws {
        _ = try profile(id: id)
        let source = profileHome(id: id).appending(path: "auth.json")
        guard fileManager.fileExists(atPath: source.path) else {
            throw AccountStoreError.targetCredentialMissing
        }

        try checkPath(activeHomeURL)
        try fileManager.createDirectory(at: activeHomeURL, withIntermediateDirectories: true)
        let destination = activeHomeURL.appending(path: "auth.json")
        let bytes = try readChecked(source)
        try secureAtomicWrite(bytes, to: destination)
    }

    public func commitActiveAccountID(_ id: UUID) throws {
        var current = try loadRegistry()
        guard let index = current.accounts.firstIndex(where: { $0.id == id }) else {
            throw AccountStoreError.profileNotFound
        }
        current.activeAccountID = id
        current.accounts[index].lastUsedAt = Date()
        try saveRegistry(current)
    }

    private func saveRegistry(_ value: AccountRegistry) throws {
        try writeJSON(value, to: accountsURL)
        registry = value
    }

    private func saveUsageCache(_ value: UsageCache) throws {
        try writeJSON(value, to: usageCacheURL)
        usageCache = value
    }

    private func prepareDirectories() throws {
        try checkPath(baseURL)
        try checkPath(profilesURL)
        if !fileManager.fileExists(atPath: baseURL.path),
           let legacyBaseURL,
           fileManager.fileExists(atPath: legacyBaseURL.path) {
            try checkPath(legacyBaseURL)
            try fileManager.moveItem(at: legacyBaseURL, to: baseURL)
        }
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try restrictPermissions(baseURL, directory: true)
        try fileManager.createDirectory(at: profilesURL, withIntermediateDirectories: true)
        try restrictPermissions(profilesURL, directory: true)
    }

    private func copyCredential(from source: URL, to destination: URL) throws {
        let bytes = try readChecked(source)
        try secureAtomicWrite(bytes, to: destination)
    }

    private func checkPath(_ path: URL) throws {
        #if os(Windows)
        let error = switcher_check_path(path.path)
        guard error == 0 else { throw windowsError(error) }
        #endif
    }

    private func readChecked(_ path: URL) throws -> Data {
        try checkPath(path)
        return try Data(contentsOf: path)
    }

    private func removeProfileDirectory(_ path: URL) throws {
        #if os(Windows)
        func checkTree(_ directory: URL) throws {
            try checkPath(directory)
            for child in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) {
                try checkPath(child)
                if try child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true { try checkTree(child) }
            }
        }
        try checkTree(path)
        #endif
        try fileManager.removeItem(at: path)
    }

    private func secureAtomicWrite(_ bytes: Data, to destination: URL) throws {
        #if os(Windows)
        let error = bytes.withUnsafeBytes { buffer in
            switcher_atomic_write(destination.path, buffer.baseAddress, buffer.count)
        }
        guard error == 0 else { throw windowsError(error) }
        #else
        let temporary = destination
            .deletingLastPathComponent()
            .appending(path: "\(destination.lastPathComponent).switcher-\(UUID().uuidString).tmp")
        let descriptor = Darwin.open(
            temporary.path,
            O_WRONLY | O_CREAT | O_EXCL,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else { throw currentPOSIXError() }

        do {
            try bytes.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return }
                var offset = 0
                while offset < rawBuffer.count {
                    let count = Darwin.write(
                        descriptor,
                        baseAddress.advanced(by: offset),
                        rawBuffer.count - offset
                    )
                    guard count > 0 else { throw currentPOSIXError() }
                    offset += count
                }
            }
            guard Darwin.fsync(descriptor) == 0 else { throw currentPOSIXError() }
            guard Darwin.close(descriptor) == 0 else { throw currentPOSIXError() }
        } catch {
            _ = Darwin.close(descriptor)
            try? fileManager.removeItem(at: temporary)
            throw error
        }

        if Darwin.rename(temporary.path, destination.path) != 0 {
            let error = currentPOSIXError()
            try? fileManager.removeItem(at: temporary)
            throw error
        }
        #endif
    }

    private func restrictPermissions(_ path: URL, directory: Bool) throws {
        #if os(Windows)
        let error = switcher_restrict_path(path.path, directory ? 1 : 0)
        guard error == 0 else { throw windowsError(error) }
        #else
        try fileManager.setAttributes([.posixPermissions: directory ? 0o700 : 0o600], ofItemAtPath: path.path)
        #endif
    }

    #if os(Windows)
    private func windowsError(_ code: UInt32) -> NSError {
        NSError(domain: "CodexAccountSwitcher.Windows", code: Int(code), userInfo: [
            NSLocalizedDescriptionKey: "Windows could not access private account storage (error \(code)).",
        ])
    }
    #else
    private func currentPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    #endif

    private func writeJSON<T: Encodable>(_ value: T, to destination: URL) throws {
        let bytes = try Self.encoder.encode(value)
        try secureAtomicWrite(bytes, to: destination)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
