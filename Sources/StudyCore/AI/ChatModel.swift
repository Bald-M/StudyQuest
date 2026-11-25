import Foundation

public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        session = URLSession(configuration: config)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// 测试用：记录请求，按队列依次返回预设响应。队列用完后抛错。
public final class StubHTTPClient: HTTPClient, @unchecked Sendable {
    public enum Reply {
        case json(Any, status: Int = 200)
        case raw(Data, status: Int)
    }

    private let lock = NSLock()
    private var queue: [Reply]
    private var recorded: [URLRequest] = []

    public init(_ replies: [Reply]) { queue = replies }

    public var requests: [URLRequest] { lock.withLock { recorded } }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply: Reply = try lock.withLock {
            recorded.append(request)
            guard !queue.isEmpty else { throw URLError(.cannotConnectToHost) }
            return queue.removeFirst()
        }
        let (data, status): (Data, Int)
        switch reply {
        case .json(let object, let code): (data, status) = (try JSONSerialization.data(withJSONObject: object), code)
        case .raw(let bytes, let code): (data, status) = (bytes, code)
        }
        let url = request.url ?? URL(string: "https://stub.invalid")!
        return (data, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

public struct ChatMessage: Codable, Sendable {
    public var role: String  // "user" | "assistant"
    public var content: String
    public init(role: String, content: String) { self.role = role; self.content = content }
}

public struct ChatRequest: Sendable {
    public var system: String
    public var messages: [ChatMessage]
    public var jsonSchema: JSONValue?
    public var maxTokens: Int
    public init(system: String, messages: [ChatMessage], jsonSchema: JSONValue? = nil, maxTokens: Int = 16000) {
        self.system = system; self.messages = messages; self.jsonSchema = jsonSchema; self.maxTokens = maxTokens
    }
}

public protocol ChatModel: Sendable {
    /// "<kind>:<model>"
    var label: String { get }
    func complete(_ request: ChatRequest) async throws -> String
}

public enum AIError: Error, Equatable {
    case notConfigured(String)
    case http(status: Int, body: String)
    case refusal(category: String?)
    case truncated
    case emptyResponse
    case invalidJSON(String)
}

extension HTTPClient {
    /// 发送并要求 2xx；否则抛 `AIError.http`（body 截到 500 字符）。
    func sendChecked(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw AIError.http(status: response.statusCode, body: String(String(decoding: data, as: UTF8.self).prefix(500)))
        }
        return data
    }
}

func joinURL(_ base: URL, _ path: String) -> URL {
    var s = base.absoluteString
    while s.hasSuffix("/") { s.removeLast() }
    return URL(string: s + path)!
}
