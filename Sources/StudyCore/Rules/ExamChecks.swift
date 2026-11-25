import Foundation

public enum ExamChecks {
    /// 来自更早阶段的题占比超出 [min, max] 时返回警告；阶段 0 不检查。
    public static func cumulativeWarning(stageIndex: Int, problemStageIndices: [Int], min: Double, max: Double) -> String? {
        guard stageIndex > 0, !problemStageIndices.isEmpty else { return nil }
        let ratio = Double(problemStageIndices.filter { $0 < stageIndex }.count) / Double(problemStageIndices.count)
        guard ratio < min || ratio > max else { return nil }
        let pct = Int((ratio * 100).rounded())
        return "累积题占比 \(pct)%，不在建议的 \(Int((min * 100).rounded()))%–\(Int((max * 100).rounded()))% 范围内"
    }

    /// 新卷题目出现在旧卷中的比例超过阈值时返回警告。
    public static func overlapWarning(newPrompts: [String], previousPrompts: [String], threshold: Double = 0.3) -> String? {
        guard !newPrompts.isEmpty else { return nil }
        let old = Set(previousPrompts.map(normalize))
        let dup = newPrompts.filter { old.contains(normalize($0)) }.count
        let ratio = Double(dup) / Double(newPrompts.count)
        guard ratio > threshold else { return nil }
        return "有 \(dup) 道题（\(Int((ratio * 100).rounded()))%）与往期试卷重复，超过 \(Int((threshold * 100).rounded()))% 的阈值"
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
