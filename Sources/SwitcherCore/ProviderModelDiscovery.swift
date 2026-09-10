import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol ProviderModelDiscovering: Sendable {
    func fetchModels(baseURL: String, apiKey: String) async throws -> [ProviderModel]
}

/// Keys are sent only to the user-entered origin. Redirects are reported, never followed with credentials.
public protocol ProviderConnectionValidating: Sendable {
    func validateConnection(baseURL: String, apiKey: String, model: String, effort: String?) async throws
}

public final class ProviderModelDiscovery: NSObject, ProviderModelDiscovering, ProviderConnectionValidating, URLSessionTaskDelegate, Sendable {
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

    public func fetchModels(baseURL: String, apiKey: String) async throws -> [ProviderModel] {
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
            if let cursor { components.queryItems = [URLQueryItem(name: "after", value: cursor)] }
            var request = URLRequest(url: components.url!)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
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

    public func validateConnection(baseURL: String, apiKey: String, model: String, effort: String?) async throws {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains("\n"), !key.contains("\r") else { throw ProviderSetupError.invalidKey }
        let url = try Self.endpoint(baseURL).deletingLastPathComponent().appendingPathComponent("responses")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        var body: [String: Any] = ["model": model, "input": "Reply with OK.", "store": false, "stream": false, "max_output_tokens": 512]
        if let effort { body["reasoning"] = ["effort": effort] }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ProviderSetupError.invalidResponse }
        if (300..<400).contains(response.statusCode) { throw ProviderSetupError.redirects }
        guard (200..<300).contains(response.statusCode) else { throw ProviderSetupError.http(response.statusCode) }
        try Self.checkValidationResponse(data)
    }

    public static func checkValidationResponse(_ data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["object"] as? String == "response", let status = root["status"] as? String else { throw ProviderSetupError.invalidResponse }
        guard status == "completed" else { throw ProviderSetupError.validationIncomplete }
        guard root["error"] == nil || root["error"] is NSNull,
              let output = root["output"] as? [[String: Any]], output.contains(where: { item in
                  guard item["type"] as? String == "message", let content = item["content"] as? [[String: Any]] else { return false }
                  return content.contains { $0["type"] as? String == "output_text" && ($0["text"] as? String)?.isEmpty == false }
              }) else { throw ProviderSetupError.invalidResponse }
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
