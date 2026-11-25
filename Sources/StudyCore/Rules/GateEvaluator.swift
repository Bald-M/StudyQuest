import Foundation

public struct SectionScore: Equatable, Sendable {
    public var title: String
    public var earned: Double
    public var max: Double
    public var weight: Double
    public init(title: String, earned: Double, max: Double, weight: Double) {
        self.title = title; self.earned = earned; self.max = max; self.weight = weight
    }
    /// 得分百分比，0...100。
    public var percent: Double { max > 0 ? earned / max * 100 : 0 }
}

public struct GateOutcome: Equatable, Sendable {
    public var totalPercent: Double
    public var passed: Bool
    public var failingSections: [String]
}

public enum GateEvaluator {
    /// 总分 = Σ(weight × percent) / Σweight；通过 = 总分 ≥ passLine（百分数）且每区 percent ≥ minSectionRatio（比例）× 100。
    public static func evaluate(sections: [SectionScore], passLine: Double, minSectionRatio: Double) -> GateOutcome {
        let totalWeight = sections.reduce(0) { $0 + $1.weight }
        let total = totalWeight > 0 ? sections.reduce(0) { $0 + $1.weight * $1.percent } / totalWeight : 0
        let failing = sections.filter { $0.percent < minSectionRatio * 100 }.map(\.title)
        return GateOutcome(totalPercent: total, passed: total >= passLine && failing.isEmpty, failingSections: failing)
    }
}
