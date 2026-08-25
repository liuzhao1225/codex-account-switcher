import Foundation
import Testing
@testable import CodexAccountSwitcher

struct SwitchServiceTests {
    @Test func executesTheSixSwitchStagesInOrder() async throws {
        let fixture = SwitchFixture(failure: nil)
        try await fixture.service.switchAccount(to: fixture.target.id)
        let stages = await fixture.recorder.snapshot()
        #expect(stages == SwitchStage.allCases)
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
            let recordedStages = await fixture.recorder.snapshot()
            #expect(recordedStages == Array(SwitchStage.allCases[...index]))
        }
    }
}

private struct InjectedFailure: LocalizedError, Sendable {
    let stage: SwitchStage
    var errorDescription: String? { "Injected \(stage.rawValue) failure" }
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
    let target: AccountProfile
    init(recorder: CallRecorder, failure: SwitchStage?, target: AccountProfile) {
        self.recorder = recorder; self.failure = failure; self.target = target
    }
    func loadRegistry() -> AccountRegistry { .empty }
    func profile(id: UUID) throws -> AccountProfile { target }
    func profileHome(id: UUID) -> URL { URL(fileURLWithPath: "/tmp/target") }
    func activeCodexHome() -> URL { URL(fileURLWithPath: "/tmp/active") }
    func activeCredentialExists() -> Bool { true }
    func createProfileDirectory(id: UUID) -> URL { URL(fileURLWithPath: "/tmp/target") }
    func importCurrentProfile(_ profile: AccountProfile) {}
    func addProfile(_ profile: AccountProfile) {}
    func removeAccount(id: UUID) {}
    func saveCurrentCredential() async throws {
        await recorder.append(.saveCurrentCredential)
        if failure == .saveCurrentCredential { throw InjectedFailure(stage: .saveCurrentCredential) }
    }
    func activateTargetCredential(id: UUID) async throws {
        await recorder.append(.activateTargetCredential)
        if failure == .activateTargetCredential { throw InjectedFailure(stage: .activateTargetCredential) }
    }
    func commitActiveAccountID(_ id: UUID) async throws {
        await recorder.append(.commitActiveAccountID)
        if failure == .commitActiveAccountID { throw InjectedFailure(stage: .commitActiveAccountID) }
    }
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

private struct SwitchFixture {
    let recorder = CallRecorder()
    let target: AccountProfile
    let service: SwitchService
    init(failure: SwitchStage?) {
        let target = AccountProfile(
            id: UUID(), displayName: "Target", email: "target@example.com",
            accountID: "target-id", createdAt: Date(), lastUsedAt: nil
        )
        self.target = target
        let store = FakeStore(recorder: recorder, failure: failure, target: target)
        service = SwitchService(
            desktop: FakeDesktop(recorder: recorder, failure: failure),
            store: store,
            codex: FakeCodex(recorder: recorder, failure: failure, target: target)
        )
    }
}
