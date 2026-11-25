import Foundation
import MCP
import StudyCore

/// stdio MCP 服务：工具与提示模板都委托给 ToolHandlers / PromptCatalog，这里只做协议接线与 JSONValue ↔ Value 转换。
public struct MCPServer {
    static let databaseReplacedMessage = "数据库已被替换（可能刚做过恢复），请重启 MCP 服务"

    private let store: StudyStore
    private let databaseIdentity: DatabaseFileIdentity

    /// `databaseURL`：store 打开的数据库文件，用来发现它被恢复备份替换。
    public init(store: StudyStore, databaseURL: URL) {
        self.store = store
        databaseIdentity = DatabaseFileIdentity(path: databaseURL.path)
    }

    public func run() async throws {
        let clientName = ClientNameBox()
        let handlers = ToolHandlers(store: store, clientName: { clientName.value })
        let store = self.store
        let identity = databaseIdentity
        /// 数据库文件被替换时写 stderr、稍后退出（先让这次的错误响应发出去），返回 false。
        @Sendable func databaseStillValid() -> Bool {
            guard !identity.isUnchanged else { return true }
            FileHandle.standardError.write(Data("studyquest-mcp: \(Self.databaseReplacedMessage)\n".utf8))
            Task.detached {
                try? await Task.sleep(for: .milliseconds(500))
                exit(0)
            }
            return false
        }
        let server = Server(
            name: "studyquest", version: "1.0.0",
            capabilities: .init(prompts: .init(listChanged: false), tools: .init(listChanged: false)))

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: ToolCatalog.tools.map {
                Tool(name: $0.name, description: $0.description, inputSchema: Self.value($0.inputSchema))
            })
        }
        await server.withMethodHandler(CallTool.self) { params in
            guard databaseStillValid() else {
                return CallTool.Result(content: [.text(Self.databaseReplacedMessage)], isError: true)
            }
            let arguments = (params.arguments ?? [:]).mapValues(Self.json)
            let result = handlers.call(name: params.name, arguments: arguments)
            return CallTool.Result(content: [.text(result.text)], isError: result.isError)
        }
        await server.withMethodHandler(ListPrompts.self) { _ in
            ListPrompts.Result(prompts: PromptCatalog.prompts.map { spec in
                Prompt(name: spec.name, description: spec.description,
                       arguments: spec.arguments.map { .init(name: $0.name, description: $0.description, required: $0.required) })
            })
        }
        await server.withMethodHandler(GetPrompt.self) { params in
            guard databaseStillValid() else { throw MCPError.internalError(Self.databaseReplacedMessage) }
            let arguments = (params.arguments ?? [:]).mapValues(Self.json)
            let text: String
            do {
                text = try PromptCatalog.render(name: params.name, arguments: arguments, store: store)
            } catch StoreError.notFound(let what) {
                throw MCPError.invalidParams("未找到\(what)")
            } catch StoreError.invalid(let message) {
                throw MCPError.invalidParams(message)
            }
            let description = PromptCatalog.prompts.first { $0.name == params.name }?.description
            return GetPrompt.Result(description: description, messages: [.user(.text(text: text))])
        }

        try await server.start(transport: StdioTransport()) { info, _ in
            clientName.value = info.name
        }
        await server.waitUntilCompleted()
    }

    // MARK: JSONValue ↔ Value

    static func value(_ json: JSONValue) -> Value {
        switch json {
        case .null: return .null
        case .bool(let b): return .bool(b)
        case .number(let n):
            if n.rounded() == n, abs(n) < 1e15 { return .int(Int(n)) }
            return .double(n)
        case .string(let s): return .string(s)
        case .array(let a): return .array(a.map(value))
        case .object(let o): return .object(o.mapValues(value))
        }
    }

    static func json(_ value: Value) -> JSONValue {
        switch value {
        case .null: return .null
        case .bool(let b): return .bool(b)
        case .int(let i): return .number(Double(i))
        case .double(let d): return .number(d)
        case .string(let s): return .string(s)
        case .data(_, let d): return .string(d.base64EncodedString())
        case .array(let a): return .array(a.map(json))
        case .object(let o): return .object(o.mapValues(json))
        }
    }
}

/// initialize 时由 SDK 回调写入，工具调用时读取；初始化前为 "unknown"。
private final class ClientNameBox: @unchecked Sendable {
    private let lock = NSLock()
    private var name = "unknown"

    var value: String {
        get { lock.withLock { name } }
        set { lock.withLock { name = newValue } }
    }
}
