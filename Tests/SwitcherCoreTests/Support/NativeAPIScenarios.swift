import Foundation
import SwitcherCore

@MainActor
enum NativeAPIScenarios {
    static func run(check require: (Bool, String) throws -> Void) async throws {
        func check(_ condition: Bool, _ message: String) throws { try require(condition, message) }
        let files = FileManager.default
        let root = files.temporaryDirectory.appending(path: "native-api-checks-\(UUID())")
        let home = root.appending(path: "active")
        let support = root.appending(path: "store")
        try files.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        let activeFile = home.appending(path: "auth.json")
        let apiBytes = Data(#"{"auth_mode":"apikey","OPENAI_API_KEY":"fixture-only-native-api-value"}"#.utf8)
        let firstBytes = Data(#"{"auth_mode":"chatgpt","tokens":{"account_id":"first"}}"#.utf8)
        let secondBytes = Data(#"{"auth_mode":"chatgpt","tokens":{"account_id":"second"}}"#.utf8)
        let first = AccountProfile(id: UUID(), displayName: "First", email: nil, accountID: "first", createdAt: Date())
        let second = AccountProfile(id: UUID(), displayName: "Second", email: nil, accountID: "second", createdAt: Date())
        let store = AccountStore(baseURL: support, activeHomeURL: home)
        try firstBytes.write(to: activeFile)
        try await store.importCurrentProfile(first)
        let secondHome = try await store.createProfileDirectory(id: second.id)
        try secondBytes.write(to: secondHome.appending(path: "auth.json"))
        try await store.addProfile(second)
        try await store.cacheWeeklyUsage(WeeklyUsage(remainingPercent: 73,
            resetsAt: Date(timeIntervalSince1970: 2_000_000_000), fiveHourRemainingPercent: 22), profileID: first.id)
        let firstFile = await store.profileHome(id: first.id).appending(path: "auth.json")
        let apiFile = support.appending(path: "openai-api/auth.json")
        let client = NativeAPITestClient()
        let configuration = NativeAPITestConfiguration()
        let desktop = NativeAPITestDesktop()
        let model = AccountController(store: store, codex: client, configuration: configuration,
            switchService: SwitchService(desktop: desktop, store: store, codex: client, configuration: configuration),
            providerSwitchService: ProviderSwitchService(desktop: desktop, store: store, codex: client,
                                                         configuration: configuration))
        let api = ProviderProfile(id: "openai", displayName: "OpenAI API")
        try apiBytes.write(to: activeFile)
        await model.start()
        try require(model.visibleError == nil, "native API startup succeeds")
        try require(model.providers.contains(api), "native API login appears without a custom provider definition")
        try require(model.isProviderActive(api), "OpenAI API is identified as the active destination")
        try require(model.activeRemainingPercent == nil, "native API does not present ChatGPT quota")
        try require(!model.isAccountActive(first), "native API login does not mark the last saved account active")
        try require(model.snapshot.activeAccountID == nil, "native API login is not exported as an active ChatGPT account")
        try require(!files.fileExists(atPath: apiFile.path), "startup does not silently save an API key")

        await model.switchAccount(to: first.id)
        try require(model.visibleError == nil && model.isAccountActive(first), "API to the same saved account restores login")
        try check(Data(contentsOf: activeFile) == firstBytes, "saved ChatGPT credentials become active")
        try check(Data(contentsOf: firstFile) == firstBytes, "API key never overwrites a ChatGPT profile")
        try check(Data(contentsOf: apiFile) == apiBytes, "API login is saved separately before replacement")
        #if !os(Windows)
        let permissions = try files.attributesOfItem(atPath: apiFile.path)[.posixPermissions] as? NSNumber
        try require(permissions?.intValue == 0o600, "saved API login is owner-only")
        #endif
        try require(model.providers.contains(api), "saved API login stays selectable after returning to ChatGPT")
        try require(model.activeRemainingPercent == 73, "verified ChatGPT menu-bar percentage remains weekly")

        await model.setEnablesProviderSwitching(true)
        await model.switchProvider(to: api)
        try require(model.visibleError == nil && model.isProviderActive(api), "saved account to API restores API authentication")
        try check(Data(contentsOf: activeFile) == apiBytes, "API login survives a full round trip")
        await model.switchAccount(to: second.id)
        try require(model.visibleError == nil && model.isAccountActive(second), "API can switch to a different saved account")
        try check(Data(contentsOf: firstFile) == firstBytes, "other saved ChatGPT account stays intact")

        // The app was already open when the user signed out elsewhere.
        try files.removeItem(at: activeFile)
        let beforeLogoutRecovery = await desktop.counts()
        await model.switchAccount(to: second.id)
        let afterLogoutRecovery = await desktop.counts()
        try require(model.visibleError == nil && model.isAccountActive(second), "same saved account works after external logout")
        try require(afterLogoutRecovery.0 == beforeLogoutRecovery.0 + 1, "external logout does not trigger the stale selection no-op")
        try check(Data(contentsOf: activeFile) == secondBytes, "logout recovery restores saved credentials")

        // An API login may remain installed while a custom provider is selected.
        try apiBytes.write(to: activeFile)
        await configuration.activateProvider(id: "azure", codexHome: home)
        await model.start()
        try require(model.providers.contains(api) && !model.isProviderActive(api), "API login is available while Azure is active")
        await client.reject(accountID: "first")
        await model.switchAccount(to: first.id)
        let failedProvider = await configuration.selectedProvider()
        try require(model.visibleError != nil, "target verification failure remains visible")
        try require(failedProvider == "azure", "failed account switch restores Azure")
        try check(Data(contentsOf: activeFile) == apiBytes, "failed switch restores original API login, not last saved account")
        try check(Data(contentsOf: firstFile) == firstBytes, "failed switch does not damage target ChatGPT credentials")
        await client.reject(accountID: nil)
        await model.switchAccount(to: first.id)
        try require(model.visibleError == nil && model.isAccountActive(first), "retry from Azure and API login succeeds")

        await client.rejectAPI(true)
        await model.switchProvider(to: api)
        try require(model.visibleError != nil, "API verification failure remains visible")
        try check(Data(contentsOf: activeFile) == firstBytes, "failed API activation restores ChatGPT login")
        try require(!(model.visibleError?.message.contains("fixture-only-native-api-value") ?? false), "errors never expose API key")
        await client.rejectAPI(false)
        await model.switchProvider(to: api)
        try require(model.visibleError == nil && model.isProviderActive(api), "API activation can be retried")

        // Registering a ChatGPT login made outside the switcher updates the menu immediately.
        try firstBytes.write(to: activeFile)
        await model.registerCurrentAccount()
        try require(model.visibleError == nil && model.isAccountActive(first), "registration refreshes the native login state")
        try require(!model.isProviderActive(api), "registration clears the previously active API indicator")
        try require(model.providers.contains(api), "registration keeps the saved API login available")
        let counts = await desktop.counts()
        try require(counts.0 == counts.1, "every post-close path reopens Desktop")
        print("Native API switching checks passed")
    }
}
