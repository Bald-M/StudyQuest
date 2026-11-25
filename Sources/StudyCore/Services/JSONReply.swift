import Foundation

/// 模型回复里的 JSON 解码：剥掉首尾的 ```json / ``` 围栏与空白后解码。
enum JSONReply {
    /// 失败抛 `AIError.invalidJSON`（带原文片段）。
    static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("```") {
            body.removeFirst(3)
            if body.lowercased().hasPrefix("json") { body.removeFirst(4) }
        }
        if body.hasSuffix("```") { body.removeLast(3) }
        body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            return try JSONDecoder().decode(type, from: Data(body.utf8))
        } catch {
            throw AIError.invalidJSON(String(text.prefix(200)))
        }
    }
}
