import Foundation

public enum ProviderAPIFormat: String, Codable, CaseIterable, Sendable {
    case responses
    case anthropic
}

public struct ProviderModel: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var displayName: String
    public var isEnabled: Bool
    public var reasoningOptions: [String]
    public var reasoningEffort: String?

    public init(id: String, displayName: String? = nil, isEnabled: Bool = false,
                reasoningOptions: [String] = [], reasoningEffort: String? = nil) {
        self.id = id; self.displayName = displayName ?? id; self.isEnabled = isEnabled
        self.reasoningOptions = reasoningOptions; self.reasoningEffort = reasoningEffort
    }
}

/// Secrets are stored only in Codex's private configuration, never in this library or UI snapshots.
public struct ManagedProvider: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var displayName: String
    public var baseURL: String
    public var apiFormat: ProviderAPIFormat
    public var models: [ProviderModel]
    public var defaultModelID: String
    public var sort: ProviderModelSort = .custom

    public init(id: String, displayName: String, baseURL: String, apiFormat: ProviderAPIFormat,
                models: [ProviderModel], defaultModelID: String, sort: ProviderModelSort = .custom) {
        self.id = id; self.displayName = displayName; self.baseURL = baseURL; self.apiFormat = apiFormat
        self.models = models; self.defaultModelID = defaultModelID; self.sort = sort
    }
}

public struct ProviderModelSelection: Codable, Equatable, Sendable {
    public var model: String?
    public var reasoningEffort: String?
    public var modelCatalogPath: String?

    public init(model: String?, reasoningEffort: String?, modelCatalogPath: String?) {
        self.model = model; self.reasoningEffort = reasoningEffort; self.modelCatalogPath = modelCatalogPath
    }
}

public struct ProviderLibrary: Codable, Equatable, Sendable {
    public var providers: [ManagedProvider] = []
    public var selections: [String: ProviderModelSelection] = [:]
    public init() {}
}

/// Private command input. API keys must not be copied into ProviderEditorState.
public struct ProviderConnectionInput: Decodable, Sendable {
    public var displayName: String
    public var baseURL: String
    public var apiFormat: ProviderAPIFormat
    public var apiKey: String?
    public init(displayName: String, baseURL: String, apiFormat: ProviderAPIFormat, apiKey: String?) {
        self.displayName = displayName; self.baseURL = baseURL; self.apiFormat = apiFormat; self.apiKey = apiKey
    }
}

public enum ProviderModelSort: String, Codable, CaseIterable, Sendable {
    case custom, nameAscending, nameDescending
}

public struct ProviderEditorState: Encodable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var baseURL: String
    public var apiFormat: ProviderAPIFormat
    public var hasStoredKey: Bool
    public var models: [ProviderModel]
    public var defaultModelID: String?
    public var query = ""
    public var sort: ProviderModelSort = .custom
    public var visibleModelIDs: [String] = []
    public var isBusy = false
    public var error: String?
    public var didSave = false

    public init(provider: ManagedProvider? = nil) {
        id = provider?.id ?? "switcher_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        displayName = provider?.displayName ?? ""
        baseURL = provider?.baseURL ?? "https://api.openai.com/v1"
        apiFormat = provider?.apiFormat ?? .responses
        hasStoredKey = provider != nil
        models = provider?.models ?? []
        defaultModelID = provider?.defaultModelID
        sort = provider?.sort ?? .custom
        updateVisibleModels()
    }

    public mutating func updateVisibleModels() {
        let candidates = models.enumerated().compactMap { index, model -> (Int, ProviderModel, Int)? in
            guard let score = ModelSearch.score(query, id: model.id, name: model.displayName) else { return nil }
            return (index, model, score)
        }
        visibleModelIDs = candidates.sorted { lhs, rhs in
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, lhs.2 != rhs.2 { return lhs.2 < rhs.2 }
            if sort != .custom {
                let comparison = lhs.1.id.localizedStandardCompare(rhs.1.id)
                if comparison != .orderedSame { return sort == .nameAscending ? comparison == .orderedAscending : comparison == .orderedDescending }
            }
            return lhs.0 < rhs.0
        }.map { $0.1.id }
    }
}

public enum ModelSearch {
    public static func score(_ query: String, id: String, name: String) -> Int? {
        let needle = normalized(query)
        guard !needle.isEmpty else { return 0 }
        return [normalized(id), normalized(name)].compactMap { candidate in
            if candidate == needle { return 0 }
            if candidate.hasPrefix(needle) { return 1 }
            if candidate.contains(needle) { return 2 }
            var cursor = candidate.startIndex
            var gaps = 0
            for letter in needle {
                guard let match = candidate[cursor...].firstIndex(of: letter) else { return nil }
                gaps += candidate.distance(from: cursor, to: match)
                cursor = candidate.index(after: match)
            }
            return 3 + gaps
        }.min()
    }
    private static func normalized(_ value: String) -> String {
        String(value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}

public enum ProviderSetupError: Error, LocalizedError, Sendable {
    case invalidURL, invalidKey, emptyName, noModels, selectDefault, unsupportedFormat, activeProvider, invalidResponse, http(Int), redirects, pagination
    public var errorDescription: String? {
        switch self {
        case .invalidURL: "provider_invalid_url"
        case .invalidKey: "provider_invalid_key"
        case .emptyName: "provider_empty_name"
        case .noModels: "provider_no_models"
        case .selectDefault: "provider_select_default"
        case .unsupportedFormat: "provider_anthropic_notice"
        case .activeProvider: "provider_edit_active"
        case .invalidResponse: "provider_invalid_response"
        case .http(let status): "HTTP \(status)"
        case .redirects: "provider_redirect_refused"
        case .pagination: "provider_pagination_failed"
        }
    }
}
