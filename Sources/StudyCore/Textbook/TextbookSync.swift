import Foundation

/// 从原文件更新教材时，新旧章节的对照结果。
public struct SyncPlan: Equatable, Sendable {
    /// 匹配上且正文未变的旧节 id（含重新出现而恢复的节）。
    public var unchanged: [Int64]
    /// 匹配上但正文已变的旧节 id（含重新出现而恢复的节）。
    public var changed: [Int64]
    public var added: [ParsedSection]
    /// 新结果里不再出现、且此前未被移除的旧节 id。
    public var removed: [Int64]
    /// 新解析结果中 matchKey 的顺序。
    public var newOrder: [String]
}

public enum TextbookSync {
    public static func plan(existing: [TextbookSection], parsed: [ParsedSection]) -> SyncPlan {
        var parsedByKey: [String: ParsedSection] = [:]
        for s in parsed where parsedByKey[s.matchKey] == nil { parsedByKey[s.matchKey] = s }
        var plan = SyncPlan(unchanged: [], changed: [], added: [], removed: [], newOrder: parsed.map(\.matchKey))
        var existingKeys = Set<String>()
        for old in existing {
            guard let id = old.id else { continue }
            existingKeys.insert(old.matchKey)
            if let new = parsedByKey[old.matchKey] {
                if old.textHash == SectionText.hash(new.text) { plan.unchanged.append(id) } else { plan.changed.append(id) }
            } else if old.removedAt == nil {
                plan.removed.append(id)
            }
        }
        var seen = Set<String>()
        for s in parsed where !existingKeys.contains(s.matchKey) && seen.insert(s.matchKey).inserted { plan.added.append(s) }
        return plan
    }
}
