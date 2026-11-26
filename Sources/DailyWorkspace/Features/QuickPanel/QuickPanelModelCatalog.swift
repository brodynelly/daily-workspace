import DailyCore
import Foundation

/// Lists models with the user's own key, only after they open the model picker.
enum QuickPanelModelCatalog {
    static func request(provider: AssistantProvider, key: String) -> URLRequest {
        var request: URLRequest
        switch provider {
        case .anthropic:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=1000")!)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue(AnthropicClient.apiVersion, forHTTPHeaderField: "anthropic-version")
        case .openRouter:
            request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/models")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    /// Both APIs answer `{"data": [{"id": …, "display_name" | "name": …}]}`.
    static func parse(_ data: Data, provider: AssistantProvider) throws -> [QuickPanelModelOption] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let items = root["data"] as? [[String: Any]]
        else { throw URLError(.cannotParseResponse) }
        let options = items.compactMap { item -> QuickPanelModelOption? in
            guard let id = item["id"] as? String, !id.isEmpty, id.count <= 200 else { return nil }
            let name = (item["display_name"] as? String) ?? (item["name"] as? String) ?? id
            return QuickPanelModelOption(id: id, name: name)
        }
        // Anthropic lists newest first; OpenRouter's list is long, so sort it for scanning.
        return provider == .openRouter ? options.sorted { $0.id < $1.id } : options
    }

    static func fetch(provider: AssistantProvider, key: String) async throws -> [QuickPanelModelOption] {
        let (data, response) = try await URLSession.shared.data(for: request(provider: provider, key: key))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try parse(data, provider: provider)
    }
}
