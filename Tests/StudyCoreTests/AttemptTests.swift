import Foundation
import GRDB
import Testing
@testable import StudyCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let oneDay: TimeInterval = 24 * 3600

private func makeStore(clock: FixedClock) throws -> StudyStore {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("studyquest-test-\(UUID().uuidString)")
    return try StudyStore(database: AppDatabase(url: dir.appendingPathComponent("test.sqlite")), clock: clock, notifier: NoopChangeNotifier())
}

private func problem(stage: Int = 0, prompt: String, max: Double = 10, moduleKey: String? = nil) -> ProblemInput {
    ProblemInput(stageIndex: stage, moduleKey: moduleKey, kind: .shortAnswer, prompt: prompt, options: nil,
                 referenceAnswer: "答案", rubric: "评分标准", maxScore: max, difficulty: .medium, tags: nil)
}

/// 阶段 0 两区试卷：理论（终端）30 分权重、上机（Git）70 分权重，每区一道 10 分题。
private func stageZeroExam(_ store: StudyStore, title: String) throws -> Int64 {
    let theory = SectionInput(title: "理论", weight: 30, source: .problems, problemIds: nil,
                              problems: [problem(prompt: "\(title) 理论题", moduleKey: "s0.terminal")])
    let lab = SectionInput(title: "上机", weight: 70, source: .problems, problemIds: nil,
                           problems: [problem(prompt: "\(title) 上机题", moduleKey: "s0.git")])
    return try store.createExam(ExamInput(stageIndex: 0, kind: .stageExam, title: title, timeLimitMinutes: 60, sections: [theory, lab]),
                                source: "test").id
}

/// 交卷并按顺序给每道题打分（分数按题目顺序对应）。
private func submitAndGrade(_ store: StudyStore, _ attempt: Attempt, scores: [Double]) throws {
    try store.submit(attemptId: attempt.id!)
    let problems = try store.pendingGrading(attemptId: attempt.id!)
    #expect(problems.count == scores.count)
    for (p, s) in zip(problems, scores) {
        try store.recordGrade(attemptId: attempt.id!, problemId: p.id!, score: s, feedback: "", mistakes: [], grader: "test", raw: "")
    }
}

private func xpEvent(_ store: StudyStore, _ key: String) throws -> XPEvent? {
    try store.pool.read { try XPEvent.filter(Column("dedupKey") == key).fetchOne($0) }
}

/// 阶段 9 试卷（模拟面试 50 + 算法 50），算法满分。面试按给定顺序从旧到新、都早于交卷。
private func runStageNine(interviewScores: [Double]) throws -> (Attempt, AttemptDetail, StudyStore, FixedClock) {
    let clock = FixedClock(t0)
    let store = try makeStore(clock: clock)
    try store.pool.write { db in
        try db.execute(sql: "UPDATE stage SET status = ? WHERE \"index\" = 9", arguments: [StageStatus.inProgress.rawValue])
        for (i, score) in interviewScores.enumerated() {
            var m = MockInterview(transcript: [], score: score, createdAt: t0.addingTimeInterval(Double(i - 10)))
            try m.insert(db)
        }
    }
    let mock = SectionInput(title: "模拟面试", weight: 50, source: .mockInterviewAverage, problemIds: nil, problems: nil)
    let algo = SectionInput(title: "算法", weight: 50, source: .problems, problemIds: nil,
                            problems: [problem(stage: 9, prompt: "两数之和"), problem(stage: 9, prompt: "LRU")])
    let examId = try store.createExam(ExamInput(stageIndex: 9, kind: .stageExam, title: "阶段 9", timeLimitMinutes: 45, sections: [mock, algo]),
                                      source: "test").id
    let attempt = try store.startExam(id: examId)
    try submitAndGrade(store, attempt, scores: [10, 10])
    let detail = try store.attemptDetail(id: attempt.id!)
    return (detail.attempt, detail, store, clock)
}

@Suite struct AttemptTests {
    @Test func stageExamPassUnlocksNext() throws {
        let clock = FixedClock(t0)
        let store = try makeStore(clock: clock)
        let examId = try stageZeroExam(store, title: "阶段 0 考试")
        let attempt = try store.startExam(id: examId)
        #expect(try store.examDetail(id: examId, revealAnswers: false).exam.status == .inProgress)
        try submitAndGrade(store, attempt, scores: [10, 10])

        let graded = try store.attemptDetail(id: attempt.id!)
        #expect(graded.attempt.status == .graded)
        #expect(graded.attempt.passed == true)
        #expect(graded.attempt.totalPercent == 100)
        #expect(graded.sections.map(\.title) == ["理论", "上机"])
        #expect(try store.examDetail(id: examId, revealAnswers: false).exam.status == .graded)
        let s0 = try store.stage(0)
        #expect(s0.status == .passed && s0.passedAt == t0)
        #expect(try store.stage(1).status == .inProgress)
        #expect(try xpEvent(store, "stage:0")?.amount == 500)

        // 复判导致不通过：只改作答记录，不回退阶段
        let lab = try #require(graded.items.last)
        try store.recordGrade(attemptId: attempt.id!, problemId: lab.problem.id!, score: 0, feedback: "", mistakes: [], grader: "test", raw: "")
        #expect(try store.attemptDetail(id: attempt.id!).attempt.passed == false)
        #expect(try store.stage(0).status == .passed)
        #expect(try store.stage(1).status == .inProgress)
        #expect(try store.totalXP() == 25 * 2 + 500)
    }

    @Test func failStartsCooldownAndBlocksRetake() throws {
        let clock = FixedClock(t0)
        let store = try makeStore(clock: clock)
        let first = try store.startExam(id: try stageZeroExam(store, title: "第一次"))
        try submitAndGrade(store, first, scores: [5, 5])
        #expect(try store.attemptDetail(id: first.id!).attempt.passed == false)
        #expect(try store.stage(0).status == .inProgress)

        let second = try stageZeroExam(store, title: "第二次")
        clock.current = t0.addingTimeInterval(oneDay)
        do {
            _ = try store.startExam(id: second)
            Issue.record("冷却期内应当拒绝开考")
        } catch let StoreError.blocked(message) {
            #expect(message.contains("冷却"))
        }
        clock.current = t0.addingTimeInterval(3 * oneDay)
        #expect(try store.startExam(id: second).status == .inProgress)
    }

    @Test func twoFailsFlagWeakestModule() throws {
        let clock = FixedClock(t0)
        let store = try makeStore(clock: clock)
        let git = try #require(try store.module(key: "s0.git"))
        // 理论（终端）满分、上机（Git）2 分：Git 为最弱模块
        try submitAndGrade(store, try store.startExam(id: try stageZeroExam(store, title: "一")), scores: [10, 2])
        clock.current = t0.addingTimeInterval(3 * oneDay)
        try submitAndGrade(store, try store.startExam(id: try stageZeroExam(store, title: "二")), scores: [10, 2])

        let history = try store.stageExamHistory(stage: 0)
        #expect(history.map(\.passed) == [false, false])
        #expect(history.allSatisfy { $0.weakestModuleId == git.id })
        #expect(try store.module(id: git.id!).needsRelearn)

        let third = try stageZeroExam(store, title: "三")
        clock.current = t0.addingTimeInterval(6 * oneDay)
        #expect(try store.stageGateStatus(stage: 0) == .needsRelearn(moduleId: git.id!))
        do {
            _ = try store.startExam(id: third)
            Issue.record("需重学时应当拒绝开考")
        } catch let StoreError.blocked(message) {
            #expect(message.contains("Git"))
            #expect(message.contains("上次未通过之后新生成"))
        }

        let assignmentId = try store.createAssignment(
            AssignmentInput(stageIndex: 0, moduleKey: "s0.git", title: "Git 重学", problemIds: nil, problems: [problem(prompt: "重学题")]),
            source: "test")
        try submitAndGrade(store, try store.startAssignment(id: assignmentId), scores: [10])
        #expect(try store.module(id: git.id!).needsRelearn == false)
        #expect(try store.stageGateStatus(stage: 0) == .open)
        #expect(try store.startExam(id: third).status == .inProgress)
    }

    @Test func lowScoresCreateMistakes() throws {
        let clock = FixedClock(t0)
        let store = try makeStore(clock: clock)
        let id = try store.createAssignment(
            AssignmentInput(stageIndex: 0, moduleKey: nil, title: "作业", problemIds: nil,
                            problems: [problem(prompt: "一"), problem(prompt: "二")]),
            source: "test")
        let attempt = try store.startAssignment(id: id)
        try submitAndGrade(store, attempt, scores: [5, 9])

        let firstProblem = try #require(store.attemptDetail(id: attempt.id!).items.first).problem
        let mistakes = try store.mistakes(includeGraduated: true)
        #expect(mistakes.count == 1)
        #expect(mistakes.first?.problemId == firstProblem.id)
        #expect(mistakes.first?.dueDay == clock.today().adding(days: 1, calendar: clock.calendar))
        #expect(mistakes.first?.step == 0 && mistakes.first?.streak == 0)
        #expect(try store.dueMistakes().isEmpty)
        #expect(try store.openAssignments().isEmpty)
        #expect(try xpEvent(store, "assignment:\(id)")?.amount == 50)

        // 重复结算幂等
        let xpBefore = try store.totalXP()
        let gradedAt = try store.attemptDetail(id: attempt.id!).attempt.gradedAt
        clock.current = t0.addingTimeInterval(60)
        try store.finalize(attemptId: attempt.id!)
        #expect(try store.totalXP() == xpBefore)
        #expect(try store.mistakes(includeGraduated: true).count == 1)
        #expect(try store.attemptDetail(id: attempt.id!).attempt.gradedAt == gradedAt)

        clock.current = t0.addingTimeInterval(oneDay)
        #expect(try store.dueMistakes().count == 1)
    }

    @Test func mistakeRedoGraduates() throws {
        let clock = FixedClock(t0)
        let store = try makeStore(clock: clock)
        let id = try store.createAssignment(
            AssignmentInput(stageIndex: 0, moduleKey: nil, title: "作业", problemIds: nil, problems: [problem(prompt: "一")]),
            source: "test")
        try submitAndGrade(store, try store.startAssignment(id: id), scores: [5])
        let mistake = try #require(store.mistakes(includeGraduated: false).first)

        clock.current = t0.addingTimeInterval(oneDay)
        let redo1 = try store.startMistakeRedo(mistakeId: mistake.id!)
        #expect(redo1.kind == .mistakeRedo)
        try submitAndGrade(store, redo1, scores: [8])
        let afterFirst = try #require(store.mistakes(includeGraduated: true).first)
        #expect(afterFirst.streak == 1 && afterFirst.graduated == false)
        #expect(try store.attemptDetail(id: redo1.id!).attempt.passed == nil)

        clock.current = t0.addingTimeInterval(4 * oneDay)
        try submitAndGrade(store, try store.startMistakeRedo(mistakeId: mistake.id!), scores: [10])
        #expect(try store.mistakes(includeGraduated: true).first?.graduated == true)
        #expect(try store.mistakes(includeGraduated: false).isEmpty)
    }

    @Test func redoingSameProblemAwardsXPOnce() throws {
        let clock = FixedClock(t0)
        let store = try makeStore(clock: clock)
        let id = try store.createAssignment(
            AssignmentInput(stageIndex: 0, moduleKey: nil, title: "作业", problemIds: nil, problems: [problem(prompt: "一")]),
            source: "test")
        try submitAndGrade(store, try store.startAssignment(id: id), scores: [5])
        // 中等题 25 × 5/10 = 12.5 → 13，加作业完成 50
        #expect(try store.totalXP() == 13 + 50)

        // 错题重做答对：同一道题不再给题目经验
        clock.current = t0.addingTimeInterval(oneDay)
        let mistake = try #require(store.mistakes(includeGraduated: false).first)
        try submitAndGrade(store, try store.startMistakeRedo(mistakeId: mistake.id!), scores: [10])
        #expect(try store.totalXP() == 13 + 50)

        // 同一道题出现在另一份作业里：只有作业完成的 50
        let problemId = mistake.problemId
        let second = try store.createAssignment(
            AssignmentInput(stageIndex: 0, moduleKey: nil, title: "复用", problemIds: [problemId], problems: nil), source: "test")
        try submitAndGrade(store, try store.startAssignment(id: second), scores: [10])
        #expect(try store.totalXP() == 13 + 50 + 50)
    }

    @Test func zeroScoreDoesNotUseUpProblemXP() throws {
        let clock = FixedClock(t0)
        let store = try makeStore(clock: clock)
        let id = try store.createAssignment(
            AssignmentInput(stageIndex: 0, moduleKey: nil, title: "作业", problemIds: nil, problems: [problem(prompt: "一")]),
            source: "test")
        try submitAndGrade(store, try store.startAssignment(id: id), scores: [0])
        #expect(try store.totalXP() == 50)

        // 第一次 0 分没拿到经验，之后重做答对仍然可以拿到这道题的经验
        clock.current = t0.addingTimeInterval(oneDay)
        let mistake = try #require(store.mistakes(includeGraduated: false).first)
        try submitAndGrade(store, try store.startMistakeRedo(mistakeId: mistake.id!), scores: [10])
        #expect(try store.totalXP() == 50 + 25)
    }

    @Test func regradeLatestWinsAndXPNotDoubled() throws {
        let clock = FixedClock(t0)
        let store = try makeStore(clock: clock)
        let id = try store.createAssignment(
            AssignmentInput(stageIndex: 0, moduleKey: nil, title: "作业", problemIds: nil, problems: [problem(prompt: "一")]),
            source: "test")
        let attempt = try store.startAssignment(id: id)
        try submitAndGrade(store, attempt, scores: [4])
        #expect(try store.attemptDetail(id: attempt.id!).attempt.totalPercent == 40)
        let xpAfterFirst = try store.totalXP()
        #expect(xpAfterFirst == 10 + 50)

        clock.current = t0.addingTimeInterval(60)
        let problemId = try #require(store.attemptDetail(id: attempt.id!).items.first).problem.id!
        try store.recordGrade(attemptId: attempt.id!, problemId: problemId, score: 9, feedback: "复判", mistakes: [], grader: "test", raw: "")
        let detail = try store.attemptDetail(id: attempt.id!)
        #expect(detail.attempt.totalPercent == 90)
        #expect(detail.items.first?.grades.count == 2)
        #expect(try store.totalXP() == xpAfterFirst)
        #expect(try store.mistakes(includeGraduated: true).count == 1)
    }

    @Test func overdueAttemptIsAutoSubmitted() throws {
        let clock = FixedClock(t0)
        let store = try makeStore(clock: clock)
        let section = SectionInput(title: "A", weight: 100, source: .problems, problemIds: nil,
                                   problems: [problem(prompt: "一"), problem(prompt: "二")])
        let examId = try store.createExam(ExamInput(stageIndex: 0, kind: .weeklyQuiz, title: "周测", timeLimitMinutes: 30, sections: [section]),
                                          source: "test").id
        let attempt = try store.startExam(id: examId)
        #expect(attempt.deadline == t0.addingTimeInterval(30 * 60))
        #expect(throws: StoreError.self) { try store.startExam(id: examId) }
        let first = try #require(store.attemptDetail(id: attempt.id!).items.first)
        #expect(first.problem.referenceAnswer == "")
        try store.saveAnswer(attemptId: attempt.id!, problemId: first.problem.id!, answer: "我的答案")

        clock.current = t0.addingTimeInterval(31 * 60)
        #expect(try store.expireOverdueAttempts() == [attempt.id!])
        let detail = try store.attemptDetail(id: attempt.id!)
        #expect(detail.attempt.status == .submitted)
        #expect(detail.items.first?.answer == "我的答案")
        #expect(detail.items.first?.problem.referenceAnswer == "答案")
        #expect(try store.examDetail(id: examId, revealAnswers: false).exam.status == .submitted)
        #expect(throws: StoreError.self) {
            try store.saveAnswer(attemptId: attempt.id!, problemId: first.problem.id!, answer: "迟到")
        }
        #expect(try store.expireOverdueAttempts().isEmpty)
    }

    @Test func weeklyQuizPassAwardsExamXP() throws {
        let clock = FixedClock(t0)
        let store = try makeStore(clock: clock)
        let section = SectionInput(title: "A", weight: 100, source: .problems, problemIds: nil,
                                   problems: [problem(prompt: "一"), problem(prompt: "二")])
        let examId = try store.createExam(ExamInput(stageIndex: 0, kind: .weeklyQuiz, title: "周测", timeLimitMinutes: 30, sections: [section]),
                                          source: "test").id
        let attempt = try store.startExam(id: examId)
        try submitAndGrade(store, attempt, scores: [10, 6])
        #expect(try store.attemptDetail(id: attempt.id!).attempt.passed == true)
        #expect(try xpEvent(store, "exam:\(examId)")?.amount == 100)
        #expect(try store.mistakes(includeGraduated: false).count == 1)
        #expect(try store.stage(0).status == .inProgress)
        #expect(try store.attempts(examId: examId, status: .graded).map(\.id) == [attempt.id])
    }

    @Test func weeklyQuizIgnoresSectionFloor() throws {
        let store = try makeStore(clock: FixedClock(t0))
        #expect(try store.stage(9).minSectionRatio == 0.8)
        let section = SectionInput(title: "综合", weight: 100, source: .problems, problemIds: nil,
                                   problems: [problem(stage: 9, prompt: "周测题", max: 100)])
        let examId = try store.createExam(ExamInput(stageIndex: 9, kind: .weeklyQuiz, title: "周测", timeLimitMinutes: 30, sections: [section]),
                                          source: "test").id
        let attempt = try store.startExam(id: examId)
        try submitAndGrade(store, attempt, scores: [76])
        let graded = try store.attemptDetail(id: attempt.id!).attempt
        #expect(graded.totalPercent == 76)
        #expect(graded.passed == true)
    }

    @Test func stageNineUsesMockInterviewAverage() throws {
        let (passed, passedDetail, _, _) = try runStageNine(interviewScores: [5, 90, 80, 70])
        #expect(passedDetail.sections.first?.percent == 80)
        #expect(passed.totalPercent == 90)
        #expect(passed.passed == true)

        let (failed, failedDetail, _, _) = try runStageNine(interviewScores: [90, 80])
        #expect(failedDetail.sections.first?.percent == 0)
        #expect(failed.passed == false)
    }

    @Test func stageNineRequiresEachSection80() throws {
        let (attempt, detail, _, _) = try runStageNine(interviewScores: [100, 80, 70, 60])
        #expect(detail.sections.first?.percent == 70)
        #expect(attempt.totalPercent == 85)
        #expect(attempt.passed == false)
        let stage9 = try makeStore(clock: FixedClock(t0)).stage(9)
        let outcome = GateEvaluator.evaluate(sections: detail.sections, passLine: stage9.passLine, minSectionRatio: stage9.minSectionRatio)
        #expect(outcome.failingSections == ["模拟面试"])
    }

    @Test func saveAnswerAfterDeadlineAutoSubmits() throws {
        let clock = FixedClock(t0)
        let store = try makeStore(clock: clock)
        let section = SectionInput(title: "A", weight: 100, source: .problems, problemIds: nil, problems: [problem(prompt: "一")])
        let examId = try store.createExam(ExamInput(stageIndex: 0, kind: .weeklyQuiz, title: "周测", timeLimitMinutes: 30, sections: [section]),
                                          source: "test").id
        let attempt = try store.startExam(id: examId)
        let problemId = try #require(store.attemptDetail(id: attempt.id!).items.first).problem.id!
        try store.saveAnswer(attemptId: attempt.id!, problemId: problemId, answer: "按时")

        clock.current = t0.addingTimeInterval(31 * 60)
        do {
            try store.saveAnswer(attemptId: attempt.id!, problemId: problemId, answer: "超时")
            Issue.record("超时后应当拒绝保存")
        } catch let StoreError.blocked(message) {
            #expect(message.contains("时间已到"))
        }
        let detail = try store.attemptDetail(id: attempt.id!)
        #expect(detail.attempt.status == .submitted)
        #expect(detail.attempt.submittedAt == clock.current)
        #expect(detail.items.first?.answer == "按时")
        #expect(try store.examDetail(id: examId, revealAnswers: false).exam.status == .submitted)
        #expect(try store.expireOverdueAttempts().isEmpty)

        try store.recordGrade(attemptId: attempt.id!, problemId: problemId, score: 3, feedback: "", mistakes: [], grader: "test", raw: "")
        #expect(try store.attemptDetail(id: attempt.id!).attempt.passed == false)
        #expect(try xpEvent(store, "exam:\(examId)") == nil)
    }

    @Test func saveWithinGraceWindowIsStored() throws {
        let clock = FixedClock(t0)
        let store = try makeStore(clock: clock)
        let section = SectionInput(title: "A", weight: 100, source: .problems, problemIds: nil, problems: [problem(prompt: "一")])
        let examId = try store.createExam(ExamInput(stageIndex: 0, kind: .weeklyQuiz, title: "周测", timeLimitMinutes: 30, sections: [section]),
                                          source: "test").id
        let attempt = try store.startExam(id: examId)
        let problemId = try #require(store.attemptDetail(id: attempt.id!).items.first).problem.id!

        // 截止后 4 秒内（宽限 5 秒）仍可保存，作答保持进行中，过期扫描也不提前交卷
        clock.current = t0.addingTimeInterval(30 * 60 + 4)
        try store.saveAnswer(attemptId: attempt.id!, problemId: problemId, answer: "最后一句")
        #expect(try store.expireOverdueAttempts().isEmpty)
        var detail = try store.attemptDetail(id: attempt.id!)
        #expect(detail.attempt.status == .inProgress)
        #expect(detail.items.first?.answer == "最后一句")

        // 超过宽限：拒绝并自动交卷，保留宽限内保存的答案
        clock.current = t0.addingTimeInterval(30 * 60 + 6)
        #expect(throws: StoreError.self) { try store.saveAnswer(attemptId: attempt.id!, problemId: problemId, answer: "太迟") }
        detail = try store.attemptDetail(id: attempt.id!)
        #expect(detail.attempt.status == .submitted)
        #expect(detail.items.first?.answer == "最后一句")
    }

    @Test func stageNineRegradeDoesNotUseLaterInterviews() throws {
        let (failed, detail, store, clock) = try runStageNine(interviewScores: [90, 80])
        #expect(failed.passed == false)
        clock.current = t0.addingTimeInterval(3600)
        try store.pool.write { db in
            var later = MockInterview(transcript: [], score: 100, createdAt: clock.current)
            try later.insert(db)
        }
        let algoProblem = try #require(detail.items.first).problem
        try store.recordGrade(attemptId: failed.id!, problemId: algoProblem.id!, score: 10, feedback: "复判", mistakes: [], grader: "test", raw: "")
        let regraded = try store.attemptDetail(id: failed.id!)
        #expect(regraded.items.first?.grades.count == 2)
        #expect(regraded.sections.first?.percent == 0)
        #expect(regraded.attempt.passed == false)
        #expect(try store.stage(9).status == .inProgress)
        #expect(try xpEvent(store, "stage:9") == nil)
    }

    @Test func mistakeRedoRespectsSchedule() throws {
        let clock = FixedClock(t0)
        let store = try makeStore(clock: clock)
        let id = try store.createAssignment(
            AssignmentInput(stageIndex: 0, moduleKey: nil, title: "作业", problemIds: nil, problems: [problem(prompt: "一")]),
            source: "test")
        try submitAndGrade(store, try store.startAssignment(id: id), scores: [5])
        let mistake = try #require(store.mistakes(includeGraduated: false).first)

        func expectBlocked(_ fragment: String) {
            do {
                _ = try store.startMistakeRedo(mistakeId: mistake.id!)
                Issue.record("应当拒绝重做：\(fragment)")
            } catch let StoreError.blocked(message) {
                #expect(message.contains(fragment))
            } catch {
                Issue.record("意外错误 \(error)")
            }
        }

        expectBlocked("还没到")
        clock.current = t0.addingTimeInterval(oneDay)
        let redo = try store.startMistakeRedo(mistakeId: mistake.id!)
        expectBlocked("未判完")
        try store.submit(attemptId: redo.id!)
        expectBlocked("未判完")
        let problemId = try #require(store.pendingGrading(attemptId: redo.id!).first).id!
        try store.recordGrade(attemptId: redo.id!, problemId: problemId, score: 10, feedback: "", mistakes: [], grader: "test", raw: "")
        expectBlocked("还没到")

        clock.current = t0.addingTimeInterval(4 * oneDay)
        try submitAndGrade(store, try store.startMistakeRedo(mistakeId: mistake.id!), scores: [10])
        expectBlocked("毕业")
    }

    @Test func pendingGradingRejectsInProgress() throws {
        let clock = FixedClock(t0)
        let store = try makeStore(clock: clock)
        let id = try store.createAssignment(
            AssignmentInput(stageIndex: 0, moduleKey: nil, title: "作业", problemIds: nil, problems: [problem(prompt: "一")]),
            source: "test")
        let attempt = try store.startAssignment(id: id)
        let problemId = try #require(store.attemptDetail(id: attempt.id!).items.first).problem.id!
        #expect(throws: StoreError.self) { try store.pendingGrading(attemptId: attempt.id!) }
        #expect(throws: StoreError.self) {
            try store.recordGrade(attemptId: attempt.id!, problemId: problemId, score: 5, feedback: "", mistakes: [], grader: "test", raw: "")
        }

        try store.submit(attemptId: attempt.id!)
        #expect(try store.pendingGrading(attemptId: attempt.id!).first?.referenceAnswer == "答案")
        try store.recordGrade(attemptId: attempt.id!, problemId: problemId, score: 15, feedback: "", mistakes: [], grader: "test", raw: "")
        #expect(try store.attemptDetail(id: attempt.id!).items.first?.grades.last?.score == 10)
        try store.recordGrade(attemptId: attempt.id!, problemId: problemId, score: -3, feedback: "", mistakes: [], grader: "test", raw: "")
        #expect(try store.attemptDetail(id: attempt.id!).items.first?.grades.last?.score == 0)
    }

    @Test func gradedProblemsCountAsStudiedThisWeek() throws {
        let clock = FixedClock(t0)
        let store = try makeStore(clock: clock)
        let id = try store.createAssignment(
            AssignmentInput(stageIndex: 0, moduleKey: "s0.terminal", title: "作业", problemIds: nil,
                            problems: [problem(prompt: "一", moduleKey: "s0.terminal")]),
            source: "test")
        #expect(try store.modulesStudiedThisWeek().isEmpty)
        let attempt = try store.startAssignment(id: id)
        try submitAndGrade(store, attempt, scores: [10])
        try store.saveReflection(attemptId: attempt.id!, text: "反思")
        #expect(try store.attemptDetail(id: attempt.id!).attempt.reflection == "反思")
        #expect(try store.modulesStudiedThisWeek().map(\.key) == ["s0.terminal"])
        clock.current = t0.addingTimeInterval(8 * oneDay)
        #expect(try store.modulesStudiedThisWeek().isEmpty)
    }
}
