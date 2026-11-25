import Foundation

public struct OpenAICompatibleModel: ChatModel {
    let baseURL: URL
    let model: String
    let apiKey: String
    let http: HTTPClient

    public init(baseURL: URL, model: String, apiKey: String, http: HTTPClient) {
        self.baseURL = baseURL; self.model = model; self.apiKey = apiKey; self.http = http
    }

    public var label: String { "\(ProviderKind.openAICompatible.rawValue):\(model)" }

    public func complete(_ request: ChatRequest) async throws -> String {
        var system = request.system
        var body: [String: Any] = ["model": model, "temperature": 0, "max_tokens": request.maxTokens]
        if let schema = request.jsonSchema {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let text = String(decoding: try encoder.encode(schema), as: UTF8.self)
            system += "\n\n只输出一个符合下面 JSON Schema 的 JSON 对象，不要输出其他文字：\n\(text)"
            body["response_format"] = ["type": "json_object"]
        }
        body["messages"] =
            [["role": "system", "content": system]] + request.messages.map { ["role": $0.role, "content": $0.content] }

        var urlRequest = URLRequest(url: joinURL(baseURL, "/chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await http.sendChecked(urlRequest)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (root["choices"] as? [[String: Any]])?.first
        else { throw AIError.emptyResponse }
        if choice["finish_reason"] as? String == "length" { throw AIError.truncated }
        guard let text = (choice["message"] as? [String: Any])?["content"] as? String, !text.isEmpty
        else { throw AIError.emptyResponse }
        return text
    }
}
