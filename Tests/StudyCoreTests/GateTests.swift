import Testing
import Foundation
@testable import StudyCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return c
}()
private func day(_ s: String) -> Day { Day(rawValue: s)! }

private func stage(status: StageStatus = .inProgress, cooldown: Int = 3) -> Stage {
    Stage(index: 3, title: "t", summary: "s", estimatedWeeks: "2", passLine: 80, minSectionRatio: 0.6,
          cumulativeMin: 0.2, cumulativeMax: 0.3, cooldownDays: cooldown, status: status)
}

@Suite struct GateTests {
    @Test func passRequiresTotalAndEverySection() {
        func sections(_ a: Double, _ b: Double) -> [SectionScore] {
            [SectionScore(title: "理论", earned: a, max: 100, weight: 30),
             SectionScore(title: "上机", earned: b, max: 100, weight: 70)]
        }
        let r1 = GateEvaluator.evaluate(sections: sections(90, 70), passLine: 80, minSectionRatio: 0.6)
        #expect(abs(r1.totalPercent - 76) < 0.001)
        #expect(!r1.passed)

        let r2 = GateEvaluator.evaluate(sections: sections(95, 78), passLine: 80, minSectionRatio: 0.6)
        #expect(abs(r2.totalPercent - 83.1) < 0.001)
        #expect(r2.passed)

        let r3 = GateEvaluator.evaluate(sections: sections(100, 55), passLine: 60, minSectionRatio: 0.6)
        #expect(abs(r3.totalPercent - 68.5) < 0.001)
        #expect(!r3.passed)
        #expect(r3.failingSections == ["上机"])
    }

    @Test func coolingDownAfterFail() {
        let history = [StageExamRecord(day: day("2026-11-25"), passed: false, weakestModuleId: nil)]
        #expect(StageGate.status(stage: stage(), history: history, relearnSatisfied: false, today: day("2026-11-27"), calendar: cal) == .coolingDown(until: day("2026-11-28")))
        #expect(StageGate.status(stage: stage(), history: history, relearnSatisfied: false, today: day("2026-11-28"), calendar: cal) == .open)
    }

    @Test func twoFailsRequireRelearn() {
        let history = [
            StageExamRecord(day: day("2026-11-10"), passed: false, weakestModuleId: 2),
            StageExamRecord(day: day("2026-11-20"), passed: false, weakestModuleId: 7),
        ]
        #expect(StageGate.status(stage: stage(), history: history, relearnSatisfied: false, today: day("2026-11-25"), calendar: cal) == .needsRelearn(moduleId: 7))
        #expect(StageGate.status(stage: stage(), history: history, relearnSatisfied: true, today: day("2026-11-25"), calendar: cal) == .open)
    }

    @Test func lockedAndPassed() {
        #expect(StageGate.status(stage: stage(status: .locked), history: [], relearnSatisfied: false, today: day("2026-11-25"), calendar: cal) == .locked)
        #expect(StageGate.status(stage: stage(status: .passed), history: [], relearnSatisfied: false, today: day("2026-11-25"), calendar: cal) == .alreadyPassed)
    }

    @Test func cumulativeRatio() {
        #expect(ExamChecks.cumulativeWarning(stageIndex: 3, problemStageIndices: [3,3,3,3,3,3,3,3,1,2], min: 0.2, max: 0.3) == nil)
        let w = ExamChecks.cumulativeWarning(stageIndex: 3, problemStageIndices: [3,3,3,3,3,3,3,3,3,1], min: 0.2, max: 0.3)
        #expect(w != nil)
        #expect(w?.contains("10%") == true)
        #expect(ExamChecks.cumulativeWarning(stageIndex: 0, problemStageIndices: [0,0,0], min: 0.2, max: 0.3) == nil)
    }

    @Test func overlapNormalizesWhitespace() {
        let w = ExamChecks.overlapWarning(newPrompts: ["两数之和", "  反转 链表 "], previousPrompts: ["反转 链表"])
        #expect(w != nil)
        #expect(ExamChecks.overlapWarning(newPrompts: ["a", "b", "c", "d"], previousPrompts: ["a"]) == nil)
    }
}
