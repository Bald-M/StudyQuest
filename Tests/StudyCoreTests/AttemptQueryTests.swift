import Foundation
import Testing
@testable import StudyCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func makeStore(clock: FixedClock) throws -> StudyStore {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("studyquest-test-\(UUID().uuidString)")
    return try StudyStore(database: AppDatabase(url: dir.appendingPathComponent("test.sqlite")), clock: clock, notifier: NoopChangeNotifier())
}

private func assignment(_ store: StudyStore, title: String) throws -> Int64 {
    let input = ProblemInput(stageIndex: 0, moduleKey: nil, kind: .shortAnswer, prompt: title, options: nil,
                             referenceAnswer: "答案", rubric: "评分标准", maxScore: 10, difficulty: .medium, tags: nil)
    return try store.createAssignment(AssignmentInput(stageIndex: 0, moduleKey: nil, title: title, problemIds: nil, problems: [input]),
                                      source: "test")
}

private func grade(_ store: StudyStore, _ attempt: Attempt, score: Double) throws {
    try store.submit(attemptId: attempt.id!)
    let problem = try #require(store.pendingGrading(attemptId: attempt.id!).first)
    try store.recordGrade(attemptId: attempt.id!, problemId: problem.id!, score: score, feedback: "", mistakes: [], grader: "test", raw: "")
}

struct AttemptQueryTests {
    @Test func attemptsByAssignmentNewestFirst() throws {
        let clock = FixedClock(t0)
        let store = try makeStore(clock: clock)
        let id = try assignment(store, title: "甲")
        let other = try assignment(store, title: "乙")
        let first = try store.startAssignment(id: id)
        clock.current = t0.addingTimeInterval(60)
        let second = try store.startAssignment(id: id)
        _ = try store.startAssignment(id: other)

        #expect(try store.attempts(assignmentId: id).map(\.id) == [second.id, first.id])
        #expect(try store.attempts(assignmentId: 9999).isEmpty)
    }

    @Test func openRedoAttemptOnlyWhileUnfinished() throws {
        let clock = FixedClock(t0)
        let store = try makeStore(clock: clock)
        let id = try assignment(store, title: "甲")
        try grade(store, try store.startAssignment(id: id), score: 5)
        let mistake = try #require(store.mistakes(includeGraduated: false).first)
        #expect(try store.openRedoAttempt(mistakeId: mistake.id!) == nil)

        clock.current = t0.addingTimeInterval(24 * 3600)
        let redo = try store.startMistakeRedo(mistakeId: mistake.id!)
        #expect(try store.openRedoAttempt(mistakeId: mistake.id!)?.id == redo.id)

        try store.submit(attemptId: redo.id!)
        #expect(try store.openRedoAttempt(mistakeId: mistake.id!)?.status == .submitted)

        let problem = try #require(store.pendingGrading(attemptId: redo.id!).first)
        try store.recordGrade(attemptId: redo.id!, problemId: problem.id!, score: 10, feedback: "", mistakes: [], grader: "test", raw: "")
        #expect(try store.openRedoAttempt(mistakeId: mistake.id!) == nil)
    }

    @Test func completedAssignmentsOnly() throws {
        let store = try makeStore(clock: FixedClock(t0))
        let done = try assignment(store, title: "已完成")
        let open = try assignment(store, title: "未完成")
        try grade(store, try store.startAssignment(id: done), score: 10)

        #expect(try store.completedAssignments().map(\.id) == [done])
        #expect(try store.openAssignments().map(\.id) == [open])
    }
}
