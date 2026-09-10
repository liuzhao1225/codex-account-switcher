import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol ProviderModelDiscovering: Sendable {
    func fetchModels(baseURL: String, apiKey: String, format: ProviderAPIFormat) async throws -> [ProviderModel]
}

/// Keys are sent only to the user-entered origin. Redirects are reported, never followed with credentials.
public final class ProviderModelDiscovery: NSObject, ProviderModelDiscovering, URLSessionTaskDelegate, Sendable {
    public static func endpoint(_ raw: String) throws -> URL {
        guard var parts = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.scheme == "https" || (parts.scheme == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host))
        else { throw ProviderSetupError.invalidURL }
        let path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        parts.path = "/" + (path.isEmpty ? "v1/models" : path + "/models")
        guard let url = parts.url else { throw ProviderSetupError.invalidURL }
        return url
    }

    public func fetchModels(baseURL: String, apiKey: String, format: ProviderAPIFormat) async throws -> [ProviderModel] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains("\n"), !key.contains("\r") else { throw ProviderSetupError.invalidKey }
        let url = try Self.endpoint(baseURL)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var models: [ProviderModel] = []
        var seenModels = Set<String>()
        var seenCursors = Set<String>()
        var cursor: String?
        repeat {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            if let cursor { components.queryItems = [URLQueryItem(name: format == .anthropic ? "after_id" : "after", value: cursor)] }
            var request = URLRequest(url: components.url!)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if format == .anthropic {
                request.setValue(key, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            } else { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw ProviderSetupError.invalidResponse }
            if (300..<400).contains(response.statusCode) { throw ProviderSetupError.redirects }
            guard (200..<300).contains(response.statusCode) else { throw ProviderSetupError.http(response.statusCode) }
            let page = try Self.parse(data)
            for model in page.models where seenModels.insert(model.id).inserted { models.append(model) }
            cursor = page.nextCursor
            if let cursor, !seenCursors.insert(cursor).inserted { throw ProviderSetupError.pagination }
        } while cursor != nil
        guard !models.isEmpty else { throw ProviderSetupError.noModels }
        return models
    }

    public static func parse(_ data: Data) throws -> (models: [ProviderModel], nextCursor: String?) {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["data"] as? [[String: Any]] else { throw ProviderSetupError.invalidResponse }
        let models = try rows.map { row -> ProviderModel in
            guard let id = row["id"] as? String, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ProviderSetupError.invalidResponse }
            let options = (row["supported_reasoning_efforts"] as? [String])
                ?? (row["supportedReasoningEfforts"] as? [[String: Any]])?.compactMap { $0["reasoningEffort"] as? String } ?? []
            return ProviderModel(id: id, displayName: row["display_name"] as? String ?? row["name"] as? String ?? id, reasoningOptions: options)
        }
        var cursor: String?
        if root["has_more"] as? Bool == true {
            guard let last = root["last_id"] as? String, !last.isEmpty else { throw ProviderSetupError.pagination }
            cursor = last
        }
        return (models, cursor)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
