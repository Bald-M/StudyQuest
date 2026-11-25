import Foundation
import Testing
@testable import StudyCore

private func okResponse(_ url: URL, status: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
}

private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private let schema: JSONValue = .object(["type": .string("object")])

private func anthropic(_ model: String, http: StubHTTPClient) -> AnthropicModel {
    AnthropicModel(model: model, apiKey: "k", effort: "medium", http: http)
}

private func makeStore() throws -> (StudyStore, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("studyquest-test-\(UUID().uuidString)")
    let url = dir.appendingPathComponent("test.sqlite")
    let store = try StudyStore(
        database: AppDatabase(url: url), clock: FixedClock(Date(timeIntervalSince1970: 1_800_000_000)),
        notifier: NoopChangeNotifier())
    return (store, url)
}

@Suite struct AIClientTests {
    @Test func anthropicRequestShape() async throws {
        let url = URL(string: "https://api.anthropic.com")!
        let ok = StubHTTPClient.Reply.json(["content": [["type": "text", "text": "hi"]], "stop_reason": "end_turn"])
        let http = StubHTTPClient([ok, ok])
        let opus = anthropic("claude-opus-5-5", http: http)
        _ = try await opus.complete(ChatRequest(system: "sys", messages: [ChatMessage(role: "user", content: "q")], jsonSchema: schema))
        let r = try #require(http.requests.first)
        #expect(r.url?.absoluteString.hasSuffix("/v1/messages") == true)
        #expect(r.url?.host == url.host)
        #expect(r.value(forHTTPHeaderField: "x-api-key") == "k")
        #expect(r.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        #expect(r.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
        let body = try jsonBody(r)
        #expect(body["temperature"] == nil)
        #expect(body["max_tokens"] as? Int == 16000)
        #expect(body["fallbacks"] as? String == "default")
        #expect(body["system"] as? String == "sys")
        let out = try #require(body["output_config"] as? [String: Any])
        #expect(out["effort"] as? String == "medium")
        #expect((out["format"] as? [String: Any])?["type"] as? String == "json_schema")

        let haiku = anthropic("claude-haiku-4-5", http: http)
        _ = try await haiku.complete(ChatRequest(system: "s", messages: [ChatMessage(role: "user", content: "q")]))
        let r2 = http.requests[1]
        let body2 = try jsonBody(r2)
        #expect(body2["fallbacks"] == nil)
        #expect(r2.value(forHTTPHeaderField: "anthropic-beta") == nil)
        #expect((body2["output_config"] as? [String: Any])?["format"] == nil)
    }

    @Test func anthropicParsesTextAndRefusal() async throws {
        let req = ChatRequest(system: "s", messages: [ChatMessage(role: "user", content: "q")])
        let two = StubHTTPClient([.json(["content": [["type": "text", "text": "ab"], ["type": "text", "text": "cd"]], "stop_reason": "end_turn"])])
        #expect(try await anthropic("claude-opus-5-5", http: two).complete(req) == "abcd")

        let refusal = StubHTTPClient([.json(["content": [], "stop_reason": "refusal", "stop_details": ["category": "cyber"]])])
        await #expect(throws: AIError.refusal(category: "cyber")) { try await anthropic("claude-opus-5-5", http: refusal).complete(req) }

        let cut = StubHTTPClient([.json(["content": [["type": "text", "text": "x"]], "stop_reason": "max_tokens"])])
        await #expect(throws: AIError.truncated) { try await anthropic("claude-opus-5-5", http: cut).complete(req) }

        let empty = StubHTTPClient([.json(["content": [], "stop_reason": "end_turn"])])
        await #expect(throws: AIError.emptyResponse) { try await anthropic("claude-opus-5-5", http: empty).complete(req) }
    }

    @Test func openAIRequestShape() async throws {
        let http = StubHTTPClient([.json(["choices": [["message": ["content": "{}"], "finish_reason": "stop"]]])])
        let model = OpenAICompatibleModel(baseURL: URL(string: "https://example.com/v1")!, model: "m", apiKey: "k", http: http)
        let out = try await model.complete(ChatRequest(system: "sys", messages: [ChatMessage(role: "user", content: "q")], jsonSchema: schema))
        #expect(out == "{}")
        let r = try #require(http.requests.first)
        #expect(r.url?.absoluteString == "https://example.com/v1/chat/completions")
        #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer k")
        let body = try jsonBody(r)
        #expect(body["temperature"] as? Double == 0)
        #expect((body["response_format"] as? [String: Any])?["type"] as? String == "json_object")
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.first?["role"] as? String == "system")
        #expect((messages.first?["content"] as? String)?.contains("\"type\"") == true)
        #expect(messages.last?["content"] as? String == "q")
        #expect(model.label == "openAICompatible:m")
    }

    @Test func openAITruncated() async throws {
        let http = StubHTTPClient([.json(["choices": [["message": ["content": "x"], "finish_reason": "length"]]])])
        let model = OpenAICompatibleModel(baseURL: URL(string: "https://example.com/v1")!, model: "m", apiKey: "k", http: http)
        await #expect(throws: AIError.truncated) { try await model.complete(ChatRequest(system: "s", messages: [])) }
    }

    @Test func httpErrorSurfacesStatus() async throws {
        let http = StubHTTPClient([.raw(Data(String(repeating: "e", count: 900).utf8), status: 429)])
        let model = anthropic("claude-opus-5-5", http: http)
        do {
            _ = try await model.complete(ChatRequest(system: "s", messages: []))
            Issue.record("应当抛错")
        } catch let AIError.http(status, body) {
            #expect(status == 429)
            #expect(body.count == 500)
        }
    }

    @Test func keyNeverStoredInDatabase() throws {
        let (store, dbURL) = try makeStore()
        let secrets = InMemorySecretStore()
        let registry = ProviderRegistry(store: store, secrets: secrets, http: StubHTTPClient([]))
        let config = ProviderConfig(id: UUID().uuidString, kind: .anthropic, name: "A", baseURL: "https://api.anthropic.com", model: "claude-opus-5-5", effort: "medium")
        try registry.save(config, apiKey: "sk-secret")
        #expect(try secrets.get(config.id) == "sk-secret")
        #expect(try registry.configs() == [config])
        for suffix in ["", "-wal"] {
            let path = dbURL.path + suffix
            guard let data = FileManager.default.contents(atPath: path) else { continue }
            #expect(data.range(of: Data("sk-secret".utf8)) == nil)
        }
    }

    @Test func registryResolvesRolesAndDeletes() throws {
        let (store, _) = try makeStore()
        let secrets = InMemorySecretStore()
        let registry = ProviderRegistry(store: store, secrets: secrets, http: StubHTTPClient([]))
        #expect(!registry.isConfigured(.grading))
        #expect(throws: AIError.notConfigured("grading")) { try registry.model(for: .grading) }

        let config = ProviderConfig(id: UUID().uuidString, kind: .openAICompatible, name: "O", baseURL: "https://example.com/v1", model: "m")
        try registry.save(config, apiKey: "k")
        try store.setSetting(.gradingProviderId, config.id)
        #expect(registry.isConfigured(.grading))
        #expect(try registry.model(for: .grading).label == "openAICompatible:m")
        #expect(!registry.isConfigured(.generation))

        try registry.delete(id: config.id)
        #expect(try secrets.get(config.id) == nil)
        #expect(try store.setting(.gradingProviderId) == "")
        #expect(!registry.isConfigured(.grading))
    }

    @Test func testConnectionSendsPing() async throws {
        let (store, _) = try makeStore()
        let http = StubHTTPClient([.json(["choices": [["message": ["content": "pong"], "finish_reason": "stop"]]])])
        let registry = ProviderRegistry(store: store, secrets: InMemorySecretStore(), http: http)
        let config = ProviderConfig(id: UUID().uuidString, kind: .openAICompatible, name: "O", baseURL: "https://example.com/v1", model: "m")
        try registry.save(config, apiKey: "k")
        try await registry.testConnection(id: config.id)
        let body = try jsonBody(try #require(http.requests.first))
        #expect(body["max_tokens"] as? Int == 16)
    }
}
