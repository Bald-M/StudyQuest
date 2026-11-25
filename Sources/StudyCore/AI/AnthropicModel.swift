import Foundation

public struct AnthropicModel: ChatModel {
    static let fallbackModels: Set<String> = [
        "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5", "claude-fable-5-1", "claude-fable-5-2",
    ]

    let baseURL: URL
    let model: String
    let apiKey: String
    let effort: String
    let http: HTTPClient

    public init(
        baseURL: URL = URL(string: "https://api.anthropic.com")!, model: String, apiKey: String,
        effort: String, http: HTTPClient
    ) {
        self.baseURL = baseURL; self.model = model; self.apiKey = apiKey; self.effort = effort; self.http = http
    }

    public var label: String { "\(ProviderKind.anthropic.rawValue):\(model)" }

    public func complete(_ request: ChatRequest) async throws -> String {
        var outputConfig: [String: Any] = ["effort": effort]
        if let schema = request.jsonSchema {
            let schemaObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(schema))
            outputConfig["format"] = ["type": "json_schema", "schema": schemaObject]
        }
        var body: [String: Any] = [
            "model": model,
            "max_tokens": request.maxTokens,
            "system": request.system,
            "messages": request.messages.map { ["role": $0.role, "content": $0.content] },
            "output_config": outputConfig,
        ]
        var urlRequest = URLRequest(url: try joinURL(baseURL, "/v1/messages"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        if Self.fallbackModels.contains(model) {
            body["fallbacks"] = "default"
            urlRequest.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await http.sendChecked(urlRequest)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIError.emptyResponse }
        switch root["stop_reason"] as? String {
        case "refusal":
            throw AIError.refusal(category: (root["stop_details"] as? [String: Any])?["category"] as? String)
        case "max_tokens":
            throw AIError.truncated
        default:
            break
        }
        let text = (root["content"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        guard !text.isEmpty else { throw AIError.emptyResponse }
        return text
    }
}
