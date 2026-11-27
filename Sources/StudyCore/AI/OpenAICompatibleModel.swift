import Foundation
import os

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
        let key = "\(baseURL.absoluteString)|\(model)"
        var style = Self.learned.withLock { $0[key] } ?? ParamStyle()
        // 新 OpenAI 模型拒绝 max_tokens（要 max_completion_tokens）与 temperature: 0（只接受默认值）。
        // 遇到这两种明确的参数错误就换写法重试，最多各一次，并按 baseURL+模型记住；其他错误照常抛出。
        while true {
            do {
                let used = style
                let text = try await send(request, style: used)
                Self.learned.withLock { $0[key] = used }
                return text
            } catch AIError.http(400, let body) {
                guard let next = style.adapted(toError: body) else { throw AIError.http(status: 400, body: body) }
                style = next
                // 服务端已明确指出不支持，马上记住，后续调用即使因别的原因失败也不再重复试错
                Self.learned.withLock { $0[key] = next }
            }
        }
    }

    /// 请求参数的写法；默认是传统 OpenAI 兼容写法（DeepSeek 等）。
    struct ParamStyle: Sendable {
        var completionTokens = false
        var temperature = true

        func adapted(toError body: String) -> ParamStyle? {
            guard let data = body.data(using: .utf8),
                  let error = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any],
                  let param = error["param"] as? String, let code = error["code"] as? String else { return nil }
            var next = self
            // 同时看 code：旧模型的“max_tokens 太大”等错误也带 param，但不是“不支持”，不能换写法
            switch (param, code) {
            case ("max_tokens", "unsupported_parameter") where !completionTokens: next.completionTokens = true
            case ("temperature", "unsupported_value") where temperature: next.temperature = false
            default: return nil
            }
            return next
        }
    }

    private static let learned = OSAllocatedUnfairLock<[String: ParamStyle]>(initialState: [:])

    private func send(_ request: ChatRequest, style: ParamStyle) async throws -> String {
        var system = request.system
        var body: [String: Any] = ["model": model]
        body[style.completionTokens ? "max_completion_tokens" : "max_tokens"] = request.maxTokens
        if style.temperature { body["temperature"] = 0 }
        if let schema = request.jsonSchema {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let text = String(decoding: try encoder.encode(schema), as: UTF8.self)
            system += "\n\n只输出一个符合下面 JSON Schema 的 JSON 对象，不要输出其他文字：\n\(text)"
            body["response_format"] = ["type": "json_object"]
        }
        body["messages"] =
            [["role": "system", "content": system]] + request.messages.map { ["role": $0.role, "content": $0.content] }

        var urlRequest = URLRequest(url: try joinURL(baseURL, "/chat/completions"))
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
