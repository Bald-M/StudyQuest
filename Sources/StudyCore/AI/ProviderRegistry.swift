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
        if let apiKey { try secrets.set(apiKey, for: config.id) }
        try store.saveProviderConfig(config)
    }

    public func delete(id: String) throws {
        try store.deleteProviderConfig(id: id)
        try secrets.delete(id)
    }

    public func configs() throws -> [ProviderConfig] { try store.providerConfigs() }

    /// 发一个极小请求；失败原样抛出模型的错误。
    public func testConnection(id: String) async throws {
        guard let config = try store.providerConfigs().first(where: { $0.id == id }) else {
            throw AIError.notConfigured(id)
        }
        let model = try makeModel(config, role: config.name)
        _ = try await model.complete(ChatRequest(system: "", messages: [ChatMessage(role: "user", content: "ping")], maxTokens: 16))
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
