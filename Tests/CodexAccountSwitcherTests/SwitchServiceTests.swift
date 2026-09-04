import Foundation
import Testing
@testable import CodexAccountSwitcher

struct SwitchServiceTests {
    @Test func executesTheSixSwitchStagesInOrder() async throws {
        let fixture = SwitchFixture(failure: nil)

        try await fixture.service.switchAccount(to: fixture.target.id)

        #expect(await fixture.recorder.snapshot() == SwitchStage.allCases)
        #expect(await fixture.store.registryWasReadBeforeCredentialMutation())
        #expect(await fixture.store.credentialOwner() == fixture.target.id)
        #expect(await fixture.store.activeAccountID() == fixture.target.id)
        #expect(await fixture.store.restoredProfileIDs().isEmpty)
        #expect(await fixture.configuration.activeProviderID() == "openai")
    }

    @Test func stopsAtTheFirstFailedStage() async {
        for stage in SwitchStage.allCases {
            let fixture = SwitchFixture(failure: stage)
            do {
                try await fixture.service.switchAccount(to: fixture.target.id)
                Issue.record("Expected switch stage \(stage.rawValue) to fail")
            } catch let error as OperationError {
                #expect(error.stage == stage)
            } catch {
                Issue.record("Expected OperationError, got \(error)")
            }
            let index = SwitchStage.allCases.firstIndex(of: stage)!
            #expect(await fixture.recorder.snapshot() == Array(SwitchStage.allCases[...index]))
        }
    }

    @Test func restoresOriginalCredentialWhenIdentityVerificationFails() async {
        let fixture = SwitchFixture(failure: .verifyTargetIdentity)

        await expectFailure(fixture, stage: .verifyTargetIdentity)

        #expect(await fixture.store.credentialOwner() == fixture.original.id)
        #expect(await fixture.store.activeAccountID() == fixture.original.id)
        #expect(await fixture.store.restoredProfileIDs() == [fixture.original.id])
        #expect(await fixture.configuration.activeProviderID() == "azure")
    }

    @Test func restoresOriginalCredentialWhenRegistryCommitFails() async {
        let fixture = SwitchFixture(failure: .commitActiveAccountID)

        await expectFailure(fixture, stage: .commitActiveAccountID)

        #expect(await fixture.store.credentialOwner() == fixture.original.id)
        #expect(await fixture.store.activeAccountID() == fixture.original.id)
        #expect(await fixture.store.restoredProfileIDs() == [fixture.original.id])
        #expect(await fixture.configuration.activeProviderID() == "azure")
    }

    @Test func retryAfterVerificationFailureCannotOverwriteOriginalProfile() async {
        let fixture = SwitchFixture(failure: .verifyTargetIdentity)

        await expectFailure(fixture, stage: .verifyTargetIdentity)
        await expectFailure(fixture, stage: .verifyTargetIdentity)

        #expect(
            await fixture.store.savedCredentialOwner(for: fixture.original.id) == fixture.original.id
        )
        #expect(await fixture.store.restoredProfileIDs() == [fixture.original.id, fixture.original.id])
    }

    @Test func activationFailureBeforeReplacementDoesNotRestore() async {
        let fixture = SwitchFixture(failure: .activateTargetCredential)

        await expectFailure(fixture, stage: .activateTargetCredential)

        #expect(await fixture.store.credentialOwner() == fixture.original.id)
        #expect(await fixture.store.activeAccountID() == fixture.original.id)
        #expect(await fixture.store.restoredProfileIDs().isEmpty)
    }

    @Test func reopenFailureAfterCommitKeepsTargetAccount() async {
        let fixture = SwitchFixture(failure: .reopenDesktop)

        await expectFailure(fixture, stage: .reopenDesktop)

        #expect(await fixture.store.credentialOwner() == fixture.target.id)
        #expect(await fixture.store.activeAccountID() == fixture.target.id)
        #expect(await fixture.store.restoredProfileIDs().isEmpty)
    }

    @Test func reportsRestorationFailureAlongsideOriginalFailure() async {
        let fixture = SwitchFixture(failure: .verifyTargetIdentity, restoreFails: true)

        do {
            try await fixture.service.switchAccount(to: fixture.target.id)
            Issue.record("Expected identity verification to fail")
        } catch let error as OperationError {
            #expect(error.stage == .verifyTargetIdentity)
            #expect(error.message.contains("Injected verifyTargetIdentity failure"))
            #expect(error.message.contains("Injected credential restoration failure"))
            #expect(error.underlyingDescription?.contains("restoration:") == true)
        } catch {
            Issue.record("Expected OperationError, got \(error)")
        }
    }

    @Test func switchesConfiguredProviderInOrder() async throws {
        let fixture = SwitchFixture(failure: nil)
        let configuration = FakeConfiguration(
            recorder: fixture.recorder,
            failure: nil,
            providerID: "openai",
            targetProviderID: "azure"
        )
        let service = ProviderSwitchService(
            desktop: FakeDesktop(recorder: fixture.recorder, failure: nil),
            store: fixture.store,
            configuration: configuration
        )

        try await service.switchProvider(to: "azure")

        #expect(
            await fixture.recorder.snapshot()
                == [.closeDesktop, .activateTargetProvider, .reopenDesktop]
        )
        #expect(await configuration.activeProviderID() == "azure")
    }

    @Test func restoresProviderWhenActivationFailsAfterWriting() async {
        let fixture = SwitchFixture(failure: nil)
        let configuration = FakeConfiguration(
            recorder: fixture.recorder,
            failure: .activateTargetProvider,
            providerID: "openai",
            targetProviderID: "azure",
            mutatesBeforeFailure: true
        )
        let service = ProviderSwitchService(
            desktop: FakeDesktop(recorder: fixture.recorder, failure: nil),
            store: fixture.store,
            configuration: configuration
        )

        do {
            try await service.switchProvider(to: "azure")
            Issue.record("Expected provider activation to fail")
        } catch let error as OperationError {
            #expect(error.stage == .activateTargetProvider)
        } catch {
            Issue.record("Expected OperationError, got \(error)")
        }

        #expect(await configuration.activeProviderID() == "openai")
    }

    private func expectFailure(_ fixture: SwitchFixture, stage: SwitchStage) async {
        do {
            try await fixture.service.switchAccount(to: fixture.target.id)
            Issue.record("Expected switch stage \(stage.rawValue) to fail")
        } catch let error as OperationError {
            #expect(error.stage == stage)
        } catch {
            Issue.record("Expected OperationError, got \(error)")
        }
    }
}

private struct InjectedFailure: LocalizedError, Sendable {
    let stage: SwitchStage
    var errorDescription: String? { "Injected \(stage.rawValue) failure" }
}

private struct InjectedRestorationFailure: LocalizedError, Sendable {
    var errorDescription: String? { "Injected credential restoration failure" }
}

private struct MissingOriginalPreflight: LocalizedError, Sendable {
    var errorDescription: String? { "Registry was not read before credential mutation" }
}

private actor CallRecorder {
    private var values: [SwitchStage] = []
    func append(_ value: SwitchStage) { values.append(value) }
    func snapshot() -> [SwitchStage] { values }
}

private struct FakeDesktop: DesktopControlling {
    let recorder: CallRecorder
    let failure: SwitchStage?
    func closeDesktop() async throws {
        await recorder.append(.closeDesktop)
        if failure == .closeDesktop { throw InjectedFailure(stage: .closeDesktop) }
    }
    func reopenDesktop() async throws {
        await recorder.append(.reopenDesktop)
        if failure == .reopenDesktop { throw InjectedFailure(stage: .reopenDesktop) }
    }
}

private actor FakeStore: AccountStoring {
    let recorder: CallRecorder
    let failure: SwitchStage?
    let restoreFails: Bool
    let original: AccountProfile
    let target: AccountProfile

    private var currentCredentialOwner: UUID
    private var registryActiveID: UUID
    private var restoreIDs: [UUID] = []
    private var savedCredentialOwners: [UUID: UUID]
    private var didReadRegistry = false
    private var readRegistryBeforeCredentialMutation = false

    init(
        recorder: CallRecorder,
        failure: SwitchStage?,
        restoreFails: Bool,
        original: AccountProfile,
        target: AccountProfile
    ) {
        self.recorder = recorder
        self.failure = failure
        self.restoreFails = restoreFails
        self.original = original
        self.target = target
        currentCredentialOwner = original.id
        registryActiveID = original.id
        savedCredentialOwners = [original.id: original.id, target.id: target.id]
    }

    func loadRegistry() -> AccountRegistry {
        didReadRegistry = true
        return AccountRegistry(activeAccountID: registryActiveID, accounts: [original, target])
    }

    func profile(id: UUID) throws -> AccountProfile {
        guard id == target.id else { throw AccountStoreError.profileNotFound }
        return target
    }

    func profileHome(id: UUID) -> URL { URL(fileURLWithPath: "/tmp/target") }
    func activeCodexHome() -> URL { URL(fileURLWithPath: "/tmp/active") }
    func activeCredentialExists() -> Bool { true }
    func createProfileDirectory(id: UUID) -> URL { URL(fileURLWithPath: "/tmp/target") }
    func importCurrentProfile(_ profile: AccountProfile) {}
    func addProfile(_ profile: AccountProfile) {}
    func removeAccount(id: UUID) {}

    func saveCurrentCredential() async throws {
        await recorder.append(.saveCurrentCredential)
        guard didReadRegistry else { throw MissingOriginalPreflight() }
        readRegistryBeforeCredentialMutation = true
        if failure == .saveCurrentCredential { throw InjectedFailure(stage: .saveCurrentCredential) }
        savedCredentialOwners[registryActiveID] = currentCredentialOwner
    }

    func activateTargetCredential(id: UUID) async throws {
        await recorder.append(.activateTargetCredential)
        if failure == .activateTargetCredential { throw InjectedFailure(stage: .activateTargetCredential) }
        currentCredentialOwner = id
    }

    func restoreActiveCredential(id: UUID) throws {
        if restoreFails { throw InjectedRestorationFailure() }
        restoreIDs.append(id)
        currentCredentialOwner = id
    }

    func commitActiveAccountID(_ id: UUID) async throws {
        await recorder.append(.commitActiveAccountID)
        if failure == .commitActiveAccountID { throw InjectedFailure(stage: .commitActiveAccountID) }
        registryActiveID = id
    }

    func credentialOwner() -> UUID { currentCredentialOwner }
    func activeAccountID() -> UUID { registryActiveID }
    func restoredProfileIDs() -> [UUID] { restoreIDs }
    func savedCredentialOwner(for id: UUID) -> UUID? { savedCredentialOwners[id] }
    func registryWasReadBeforeCredentialMutation() -> Bool { readRegistryBeforeCredentialMutation }
}

private struct FakeCodex: CodexIdentityReading {
    let recorder: CallRecorder
    let failure: SwitchStage?
    let target: AccountProfile
    func readIdentity(profileHome: URL) async throws -> AccountIdentity {
        await recorder.append(.verifyTargetIdentity)
        if failure == .verifyTargetIdentity { throw InjectedFailure(stage: .verifyTargetIdentity) }
        return AccountIdentity(accountID: target.accountID, email: target.email)
    }
}

private actor FakeConfiguration: ProviderConfigurationServicing {
    let recorder: CallRecorder
    let failure: SwitchStage?
    let targetProviderID: String
    let mutatesBeforeFailure: Bool
    private var providerID: String

    init(
        recorder: CallRecorder,
        failure: SwitchStage?,
        providerID: String = "azure",
        targetProviderID: String = CodexConfigurationClient.openAIProviderID,
        mutatesBeforeFailure: Bool = false
    ) {
        self.recorder = recorder
        self.failure = failure
        self.providerID = providerID
        self.targetProviderID = targetProviderID
        self.mutatesBeforeFailure = mutatesBeforeFailure
    }

    func readConfiguration(codexHome: URL) -> ProviderConfigurationSnapshot {
        ProviderConfigurationSnapshot(
            activeProviderID: providerID,
            providers: [ProviderProfile(id: "azure", displayName: "Azure OpenAI")]
        )
    }

    func activateProvider(id: String, codexHome: URL) async throws {
        if id == targetProviderID {
            await recorder.append(.activateTargetProvider)
            if failure == .activateTargetProvider {
                if mutatesBeforeFailure { providerID = id }
                throw InjectedFailure(stage: .activateTargetProvider)
            }
        }
        providerID = id
    }

    func activeProviderID() -> String { providerID }
}

private struct SwitchFixture {
    let recorder = CallRecorder()
    let original: AccountProfile
    let target: AccountProfile
    let store: FakeStore
    let configuration: FakeConfiguration
    let service: SwitchService

    init(failure: SwitchStage?, restoreFails: Bool = false) {
        let original = AccountProfile(
            id: UUID(), displayName: "Original", email: "original@example.com",
            accountID: "original-id", createdAt: Date(), lastUsedAt: nil
        )
        let target = AccountProfile(
            id: UUID(), displayName: "Target", email: "target@example.com",
            accountID: "target-id", createdAt: Date(), lastUsedAt: nil
        )
        self.original = original
        self.target = target
        let store = FakeStore(
            recorder: recorder,
            failure: failure,
            restoreFails: restoreFails,
            original: original,
            target: target
        )
        self.store = store
        let configuration = FakeConfiguration(recorder: recorder, failure: failure)
        self.configuration = configuration
        service = SwitchService(
            desktop: FakeDesktop(recorder: recorder, failure: failure),
            store: store,
            codex: FakeCodex(recorder: recorder, failure: failure, target: target),
            configuration: configuration
        )
    }
}
