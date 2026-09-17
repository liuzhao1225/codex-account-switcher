import Foundation
import SwitcherCore

actor NativeAPITestClient: AccountClient {
    var rejectedAccountID: String?
    var rejectsAPI = false

    func reject(accountID: String?) { rejectedAccountID = accountID }
    func rejectAPI(_ value: Bool) { rejectsAPI = value }

    func readAuthentication(profileHome: URL) throws -> CodexAuthenticationState {
        let file = profileHome.appending(path: "auth.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return .signedOut }
        let fields = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        if fields["auth_mode"] as? String == "apikey" {
            if rejectsAPI { throw CodexClientError.identityUnavailable }
            return .apiKey
        }
        let tokens = fields["tokens"] as! [String: String]
        return .chatGPT(AccountIdentity(accountID: tokens["account_id"], email: nil))
    }

    func readIdentity(profileHome: URL) throws -> AccountIdentity {
        guard let identity = try readAuthentication(profileHome: profileHome).identity,
              identity.accountID != rejectedAccountID else { throw CodexClientError.identityUnavailable }
        return identity
    }

    func readWeeklyUsage(profileHome: URL) throws -> WeeklyUsage { throw CodexClientError.weeklyUsageUnavailable }
    func login(profileHome: URL) throws -> AccountIdentity { throw CodexClientError.loginFailed("Fixture login disabled") }
}
