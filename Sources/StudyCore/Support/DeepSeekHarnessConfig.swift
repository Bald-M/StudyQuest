import Foundation

/// 把 studyquest-mcp 写进 DeepSeek Harness 的 `cordis.patch.yml`。
///
/// 用一段带起止标记的 `insert` 块追加一行 `dsh-mcp-client`，只增不改用户自己的条目；
/// 再次连接时替换旧块，路径变了也能更新。
public enum DeepSeekHarnessConfig {
    static let beginMarker = "# >>> studyquest MCP (managed by StudyQuest) >>>"
    static let endMarker = "# <<< studyquest MCP <<<"

    public static func block(command: String) -> String {
        """
        \(beginMarker)
        - insert:
            - id: mcp-studyquest
              name: "@deepseek-ai/dsh-mcp-client"
              config:
                serverName: studyquest
                transport: stdio
                command: \(yamlQuoted(command))
        \(endMarker)
        """
    }

    public struct BrokenMarkers: LocalizedError {
        public var errorDescription: String? { "cordis.patch.yml 里的 StudyQuest 标记不完整，请手动删掉残留的标记行后再连接。" }
    }

    /// 返回写入后的文件内容：已有 StudyQuest 块就原位替换，否则追加到末尾。
    /// 起止标记只剩一个时拒绝写入，免得下次替换时把中间的用户条目一起删掉。
    public static func upsert(into existing: String, command: String) throws -> String {
        let newBlock = block(command: command)
        if let begin = existing.range(of: beginMarker) {
            guard let end = existing.range(of: endMarker, range: begin.upperBound..<existing.endIndex) else { throw BrokenMarkers() }
            return existing.replacingCharacters(in: begin.lowerBound..<end.upperBound, with: newBlock)
        }
        if existing.contains(endMarker) { throw BrokenMarkers() }
        if existing.isEmpty { return newBlock + "\n" }
        let separator = existing.hasSuffix("\n") ? "" : "\n"
        return existing + separator + newBlock + "\n"
    }

    /// YAML 双引号字符串，只需转义反斜杠和双引号。
    static func yamlQuoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
