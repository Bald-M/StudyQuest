import Foundation

public enum AIRole: String, Sendable {
    case grading, generation

    var settingKey: SettingKey {
        switch self {
        case .grading: .gradingProviderId
        case .generation: .generationProviderId
        }
    }
}

public struct ProviderRegistry: Sendable {
    let store: StudyStore
    let secrets: SecretStore
    let http: HTTPClient

    public init(store: StudyStore, secrets: SecretStore, http: HTTPClient) {
        self.store = store; self.secrets = secrets; self.http = http
    }

    public func model(for role: AIRole) throws -> ChatModel {
        let id = try store.setting(role.settingKey)
        guard !id.isEmpty, let config = try store.providerConfigs().first(where: { $0.id == id }) else {
            throw AIError.notConfigured(role.rawValue)
        }
        return try makeModel(config, role: role.rawValue)
    }

    public func isConfigured(_ role: AIRole) -> Bool {
        (try? model(for: role)) != nil
    }

    public func save(_ config: ProviderConfig, apiKey: String?) throws {
        let existed = try store.providerConfigs().contains { $0.id == config.id }
        try store.saveProviderConfig(config)
        guard let apiKey else { return }
        do {
            try secrets.set(apiKey, for: config.id)
        } catch {
            if !existed { try? store.deleteProviderConfig(id: config.id) }
            throw error
        }
    }

    public func delete(id: String) throws {
        try store.deleteProviderConfig(id: id)
        try secrets.delete(id)
    }

    public func configs() throws -> [ProviderConfig] { try store.providerConfigs() }

    /// 发一个极小请求；失败原样抛出模型的错误，截断视为成功。
    public func testConnection(id: String) async throws {
        guard let config = try store.providerConfigs().first(where: { $0.id == id }) else {
            throw AIError.notConfigured(id)
        }
        let model = try makeModel(config, role: config.name)
        do {
            _ = try await model.complete(ChatRequest(system: "", messages: [ChatMessage(role: "user", content: "ping")], maxTokens: 16))
        } catch AIError.truncated {
            // 撞到 16 token 上限说明鉴权、地址、模型都正常。
        }
    }

    /// 向服务商查询可用模型 id（OpenAI 兼容：`GET {base}/models`；Anthropic：`GET {base}/v1/models`）。
    /// `apiKey` 为空时用已保存的 Key。
    public func availableModels(for config: ProviderConfig, apiKey: String?) async throws -> [String] {
        let key: String
        if let apiKey, !apiKey.isEmpty {
            key = apiKey
        } else {
            guard let saved = try secrets.get(config.id), !saved.isEmpty else { throw AIError.notConfigured(config.name) }
            key = saved
        }
        guard let base = URL(string: config.baseURL) else { throw AIError.notConfigured("baseURL") }
        var request: URLRequest
        switch config.kind {
        case .openAICompatible:
            request = URLRequest(url: try joinURL(base, "/models"))
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            var parts = URLComponents(url: try joinURL(base, "/v1/models"), resolvingAgainstBaseURL: false)!
            parts.queryItems = [URLQueryItem(name: "limit", value: "1000")]
            request = URLRequest(url: parts.url!)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        }
        let data = try await http.sendChecked(request)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["data"] as? [[String: Any]]
        else { throw AIError.emptyResponse }
        return items.compactMap { $0["id"] as? String }.sorted()
    }

    private func makeModel(_ config: ProviderConfig, role: String) throws -> ChatModel {
        guard let key = try secrets.get(config.id), !key.isEmpty, let url = URL(string: config.baseURL) else {
            throw AIError.notConfigured(role)
        }
        switch config.kind {
        case .openAICompatible:
            return OpenAICompatibleModel(baseURL: url, model: config.model, apiKey: key, http: http)
        case .anthropic:
            return AnthropicModel(baseURL: url, model: config.model, apiKey: key, effort: config.effort ?? "medium", http: http)
        }
    }
}
