import Foundation
import GRDB
import Testing
@testable import StudyCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func makeStore(clock: FixedClock) throws -> StudyStore {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("studyquest-test-\(UUID().uuidString)")
    return try StudyStore(database: AppDatabase(url: dir.appendingPathComponent("test.sqlite")), clock: clock, notifier: NoopChangeNotifier())
}

private func problem(_ prompt: String) -> ProblemInput {
    ProblemInput(stageIndex: 0, moduleKey: nil, kind: .shortAnswer, prompt: prompt, options: nil,
                 referenceAnswer: "答案", rubric: "评分标准", maxScore: 10, difficulty: .medium, tags: nil)
}

@Suite struct TodayBuilderTests {
    @Test func todaySummaryCounts() throws {
        let clock = FixedClock(t0)
        let store = try makeStore(clock: clock)
        // 昨天：一份作业答错一题 → 今天到期 1 道错题
        let old = try store.createAssignment(
            AssignmentInput(stageIndex: 0, moduleKey: nil, title: "昨天作业", problemIds: nil, problems: [problem("一")]), source: "test")
        let attempt = try store.startAssignment(id: old)
        try store.submit(attemptId: attempt.id!)
        let first = try #require(try store.pendingGrading(attemptId: attempt.id!).first)
        try store.recordGrade(attemptId: attempt.id!, problemId: first.id!, score: 0, feedback: "", mistakes: [], grader: "test", raw: "")

        clock.current = t0.addingTimeInterval(24 * 3600)
        let today = clock.today()
        try store.pool.write { db in
            try db.execute(sql: "DELETE FROM card")
            for i in 0..<2 {
                var c = Card(stageIndex: 0, front: "f\(i)", back: "b", tags: [], step: 0, dueDay: today, createdAt: t0)
                try c.insert(db)
            }
        }
        let todayAssignment = try store.createAssignment(
            AssignmentInput(stageIndex: 0, moduleKey: nil, title: "今天作业", problemIds: nil, problems: [problem("二")]), source: "test")
        let section = SectionInput(title: "综合", weight: 100, source: .problems, problemIds: nil, problems: [problem("周测题")])
        _ = try store.createExam(ExamInput(stageIndex: 0, kind: .weeklyQuiz, title: "周测", timeLimitMinutes: 30, sections: [section]), source: "test")
        let pending = try store.startAssignment(id: todayAssignment)
        try store.submit(attemptId: pending.id!)

        let summary = try TodayBuilder.build(store: store, autoGen: .running)
        #expect(summary.dueCards == 2 && summary.deferredCards == 0)
        #expect(summary.dueMistakes == 1)
        #expect(summary.assignments.map(\.id) == [todayAssignment])
        #expect(summary.readyExams.count == 1 && summary.readyExams[0].title == "周测")
        #expect(summary.pendingGradingAttempts == 1)
        #expect(summary.autoGen == .running)
        #expect(summary.noteWritten == false)
        let totalXP = try store.totalXP()
        #expect(summary.progress.xp == totalXP)

        try store.saveDailyNote("今天学了 Git")
        #expect(try TodayBuilder.build(store: store, autoGen: .done).noteWritten == true)
    }
}
