import Foundation
import Testing
@testable import SwitcherCore

struct CodexConfigurationClientTests {
    @Test func discoversAndActivatesConfiguredProviders() async throws {
        let fixture = try ConfigScriptFixture()
        defer { fixture.remove() }
        let client = CodexConfigurationClient(
            codex: CodexClient(
                locator: CodexExecutableLocator(explicitURL: fixture.executable),
                requestTimeout: .seconds(2)
            )
        )

        let initial = try await client.readConfiguration(codexHome: fixture.root)
        #expect(initial.activeProviderID == "azure")
        #expect(initial.providers == [
            ProviderProfile(id: "azure", displayName: "Azure OpenAI"),
            ProviderProfile(id: "local_proxy", displayName: "Local Proxy"),
        ])

        try await client.activateProvider(id: "openai", codexHome: fixture.root)

        let updated = try await client.readConfiguration(codexHome: fixture.root)
        #expect(updated.activeProviderID == "openai")
    }

    @Test func rejectsUnknownProviderBeforeWriting() async throws {
        let fixture = try ConfigScriptFixture()
        defer { fixture.remove() }
        let client = CodexConfigurationClient(
            codex: CodexClient(
                locator: CodexExecutableLocator(explicitURL: fixture.executable),
                requestTimeout: .seconds(2)
            )
        )

        do {
            try await client.activateProvider(id: "missing", codexHome: fixture.root)
            Issue.record("Expected an unknown provider to be rejected")
        } catch let error as ProviderConfigurationError {
            #expect(error == .providerNotConfigured("missing"))
        } catch {
            Issue.record("Expected ProviderConfigurationError, got \(error)")
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.marker.path))
    }
}
