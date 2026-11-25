import Foundation
import GRDB

public struct AttemptDetail: Sendable {
    public struct Item: Sendable {
        public var problem: Problem
        public var answer: String?
        /// 按判卷时间升序，最后一条为准。
        public var grades: [QuestionGrade]
    }
    public var attempt: Attempt
    public var sections: [SectionScore]
    public var items: [Item]
}

extension StudyStore {
    /// 截止后仍接受保存的宽限秒数：界面的自动保存有防抖，到点那一刻的最后几次输入可能稍晚才写入。
    public static let examSaveGrace: TimeInterval = 5

    // MARK: 开始作答

    public func startAssignment(id: Int64) throws -> Attempt {
        let now = clock.now()
        let attempt = try pool.write { db -> Attempt in
            guard try Assignment.exists(db, key: id) else { throw StoreError.notFound("作业 \(id)") }
            var attempt = Attempt(kind: .assignment, assignmentId: id, status: .inProgress, startedAt: now)
            try attempt.insert(db)
            return attempt
        }
        notifier.post()
        return attempt
    }

    /// 一张试卷只能作答一次；阶段考试须通过晋级门槛（冷却、重学、解锁）。
    public func startExam(id: Int64) throws -> Attempt {
        let now = clock.now()
        let today = clock.today()
        let calendar = clock.calendar
        let attempt = try pool.write { db -> Attempt in
            guard var exam = try Exam.fetchOne(db, key: id) else { throw StoreError.notFound("试卷 \(id)") }
            guard exam.status != .draft else { throw StoreError.invalid("试卷还是草稿，请先确认") }
            if try Attempt.filter(Column("examId") == id).fetchCount(db) > 0 {
                throw StoreError.invalid("这张试卷已经作答过，重考需要一张新卷")
            }
            if exam.kind == .stageExam {
                let status = try Self.syncStageGate(db, stageIndex: exam.stageIndex, today: today, calendar: calendar).status
                if let reason = try Self.blockedReason(db, status) { throw StoreError.blocked(reason) }
            }
            var attempt = Attempt(kind: .exam, examId: id, status: .inProgress, startedAt: now,
                                  deadline: now.addingTimeInterval(Double(exam.timeLimitMinutes) * 60))
            try attempt.insert(db)
            exam.status = .inProgress
            try exam.update(db)
            return attempt
        }
        notifier.post()
        return attempt
    }

    /// 按错题排期重做：未到期、已毕业、或已有未判完的重做时拒绝。
    public func startMistakeRedo(mistakeId: Int64) throws -> Attempt {
        let now = clock.now()
        let today = clock.today()
        let attempt = try pool.write { db -> Attempt in
            guard let mistake = try Mistake.fetchOne(db, key: mistakeId) else { throw StoreError.notFound("错题 \(mistakeId)") }
            guard !mistake.graduated else { throw StoreError.blocked("这道错题已经毕业") }
            guard mistake.dueDay <= today else { throw StoreError.blocked("还没到重做时间，\(mistake.dueDay) 起可以重做") }
            let open = try Attempt.filter(
                Column("mistakeId") == mistakeId
                    && [AttemptStatus.inProgress.rawValue, AttemptStatus.submitted.rawValue].contains(Column("status"))
            ).fetchCount(db)
            guard open == 0 else { throw StoreError.blocked("这道错题已有一次未判完的重做") }
            var attempt = Attempt(kind: .mistakeRedo, mistakeId: mistakeId, status: .inProgress, startedAt: now)
            try attempt.insert(db)
            return attempt
        }
        notifier.post()
        return attempt
    }

    // MARK: 作答与交卷

    /// 截止后 `examSaveGrace` 秒内仍保存；再晚则不保存：先自动交卷（与 `expireOverdueAttempts` 相同），提交后再抛 `.blocked`。
    public func saveAnswer(attemptId: Int64, problemId: Int64, answer: String) throws {
        let now = clock.now()
        let expired = try pool.write { db -> Bool in
            let attempt = try Self.fetchAttempt(db, id: attemptId)
            guard attempt.status == .inProgress else { throw StoreError.invalid("作答已提交，不能再修改答案") }
            if let deadline = attempt.deadline, deadline.addingTimeInterval(Self.examSaveGrace) < now {
                try Self.submit(db, attemptId: attemptId, now: now)
                return true
            }
            guard try Self.problemIds(db, of: attempt).contains(problemId) else {
                throw StoreError.invalid("题目 \(problemId) 不在这次作答中")
            }
            try db.execute(
                sql: """
                    INSERT INTO attemptAnswer (attemptId, problemId, answer, updatedAt) VALUES (?, ?, ?, ?)
                    ON CONFLICT(attemptId, problemId) DO UPDATE SET answer = excluded.answer, updatedAt = excluded.updatedAt
                    """,
                arguments: [attemptId, problemId, answer, now])
            return false
        }
        notifier.post()
        if expired { throw StoreError.blocked("考试时间已到，已自动交卷，本次答案未保存") }
    }

    public func submit(attemptId: Int64) throws {
        let now = clock.now()
        try pool.write { try Self.submit($0, attemptId: attemptId, now: now) }
        notifier.post()
    }

    /// 已过截止时间（含保存宽限）仍在作答中的作答自动交卷（保留已保存的答案），返回其 id。
    public func expireOverdueAttempts() throws -> [Int64] {
        let now = clock.now()
        let cutoff = now.addingTimeInterval(-Self.examSaveGrace)
        let ids = try pool.write { db -> [Int64] in
            let overdue = try Attempt
                .filter(Column("status") == AttemptStatus.inProgress.rawValue && Column("deadline") < cutoff)
                .order(Column("id")).fetchAll(db)
            for attempt in overdue { try Self.submit(db, attemptId: attempt.id!, now: now) }
            return overdue.map { $0.id! }
        }
        if !ids.isEmpty { notifier.post() }
        return ids
    }

    public func saveReflection(attemptId: Int64, text: String) throws {
        try pool.write { db in
            var attempt = try Self.fetchAttempt(db, id: attemptId)
            attempt.reflection = text
            try attempt.update(db)
        }
        notifier.post()
    }

    // MARK: 判卷

    /// 尚无任何判卷记录的题（含参考答案，供判卷者使用）。
    public func pendingGrading(attemptId: Int64) throws -> [Problem] {
        try pool.read { db in
            let attempt = try Self.fetchAttempt(db, id: attemptId)
            guard attempt.status != .inProgress else { throw StoreError.invalid("作答尚未提交，不能判卷") }
            let graded = Set(try Self.latestGrades(db, attemptId: attemptId).keys)
            return try Self.orderedProblems(db, ids: Self.problemIds(db, of: attempt).filter { !graded.contains($0) })
        }
    }

    /// 新增一条判卷记录（复判不覆盖旧记录，以最新一条为准）；所有题都有成绩后立即结算。
    public func recordGrade(attemptId: Int64, problemId: Int64, score: Double, feedback: String, mistakes: [String],
                            grader: String, raw: String) throws {
        let now = clock.now()
        let today = clock.today()
        let calendar = clock.calendar
        try pool.write { db in
            let attempt = try Self.fetchAttempt(db, id: attemptId)
            guard attempt.status != .inProgress else { throw StoreError.invalid("作答尚未提交，不能判卷") }
            let ids = try Self.problemIds(db, of: attempt)
            guard ids.contains(problemId), let problem = try Problem.fetchOne(db, key: problemId) else {
                throw StoreError.invalid("题目 \(problemId) 不在这次作答中")
            }
            var grade = QuestionGrade(
                attemptId: attemptId, problemId: problemId, score: min(max(score, 0), problem.maxScore), maxScore: problem.maxScore,
                feedback: feedback, mistakes: mistakes, grader: grader, raw: raw, createdAt: now)
            try grade.insert(db)
            let graded = try Self.latestGrades(db, attemptId: attemptId)
            if ids.allSatisfy({ graded[$0] != nil }) {
                try Self.finalize(db, attemptId: attemptId, now: now, today: today, calendar: calendar)
            }
        }
        notifier.post()
    }

    /// 结算：分区得分、过关、错题、经验、阶段解锁、重学标记。可重复调用，结果幂等。
    func finalize(attemptId: Int64) throws {
        let now = clock.now()
        let today = clock.today()
        let calendar = clock.calendar
        try pool.write { try Self.finalize($0, attemptId: attemptId, now: now, today: today, calendar: calendar) }
        notifier.post()
    }

    // MARK: 查询

    public func attempts(examId: Int64?, status: AttemptStatus?) throws -> [Attempt] {
        try pool.read { db in
            var request = Attempt.order(Column("startedAt").desc, Column("id").desc)
            if let examId { request = request.filter(Column("examId") == examId) }
            if let status { request = request.filter(Column("status") == status.rawValue) }
            return try request.fetchAll(db)
        }
    }

    /// 某份作业的全部作答，最新的在前。
    public func attempts(assignmentId: Int64) throws -> [Attempt] {
        try pool.read {
            try Attempt.filter(Column("assignmentId") == assignmentId).order(Column("startedAt").desc, Column("id").desc).fetchAll($0)
        }
    }

    /// 某道错题尚未判完（作答中或已交卷）的重做。
    public func openRedoAttempt(mistakeId: Int64) throws -> Attempt? {
        try pool.read {
            try Attempt.filter(
                Column("mistakeId") == mistakeId
                    && [AttemptStatus.inProgress.rawValue, AttemptStatus.submitted.rawValue].contains(Column("status"))
            ).order(Column("id").desc).fetchOne($0)
        }
    }

    /// 作答中隐藏参考答案与评分标准；交卷后才包含。
    public func attemptDetail(id: Int64) throws -> AttemptDetail {
        try pool.read { db in
            let attempt = try Self.fetchAttempt(db, id: id)
            var problems = try Self.orderedProblems(db, ids: Self.problemIds(db, of: attempt))
            let answers = try AttemptAnswer.filter(Column("attemptId") == id).fetchAll(db)
                .reduce(into: [Int64: String]()) { $0[$1.problemId] = $1.answer }
            let grades = try QuestionGrade.filter(Column("attemptId") == id).order(Column("createdAt"), Column("id")).fetchAll(db)
            let gradesByProblem = Dictionary(grouping: grades, by: \.problemId)
            let latest = gradesByProblem.compactMapValues(\.last)
            let sections = try Self.sectionScores(db, attempt: attempt, problems: problems, latest: latest)
            if attempt.status == .inProgress {
                for i in problems.indices { problems[i].referenceAnswer = ""; problems[i].rubric = "" }
            }
            let items = problems.map {
                AttemptDetail.Item(problem: $0, answer: answers[$0.id!], grades: gradesByProblem[$0.id!] ?? [])
            }
            return AttemptDetail(attempt: attempt, sections: sections, items: items)
        }
    }

    public func mistakes(includeGraduated: Bool) throws -> [Mistake] {
        try pool.read { db in
            var request = Mistake.order(Column("dueDay"), Column("id"))
            if !includeGraduated { request = request.filter(Column("graduated") == false) }
            return try request.fetchAll(db)
        }
    }

    public func dueMistakes() throws -> [Mistake] {
        let today = clock.today()
        return try pool.read {
            try Mistake.filter(Column("graduated") == false && Column("dueDay") <= today.rawValue)
                .order(Column("dueDay"), Column("id")).fetchAll($0)
        }
    }

    /// 该阶段已判卷的阶段考试，按判卷时间升序。
    public func stageExamHistory(stage: Int) throws -> [StageExamRecord] {
        let calendar = clock.calendar
        return try pool.read { try Self.stageHistory($0, stageIndex: stage, calendar: calendar).map(\.record) }
    }

    /// 阶段考试门槛。会顺带同步该阶段模块的 needsRelearn 标记（与结算时的同步规则相同），因此是一次写操作。
    public func stageGateStatus(stage: Int) throws -> StageGateStatus {
        let today = clock.today()
        let calendar = clock.calendar
        let (status, changed) = try pool.write { try Self.syncStageGate($0, stageIndex: stage, today: today, calendar: calendar) }
        if changed { notifier.post() }
        return status
    }

    // MARK: 内部：作答

    private static func fetchAttempt(_ db: Database, id: Int64) throws -> Attempt {
        guard let attempt = try Attempt.fetchOne(db, key: id) else { throw StoreError.notFound("作答 \(id)") }
        return attempt
    }

    private static func submit(_ db: Database, attemptId: Int64, now: Date) throws {
        var attempt = try fetchAttempt(db, id: attemptId)
        guard attempt.status == .inProgress else { throw StoreError.invalid("作答已经提交") }
        attempt.status = .submitted
        attempt.submittedAt = now
        try attempt.update(db)
        if let examId = attempt.examId, var exam = try Exam.fetchOne(db, key: examId) {
            exam.status = .submitted
            try exam.update(db)
        }
    }

    /// 作答包含的题目 id：作业的题、试卷各分区的题、错题重做的那一道题。
    private static func problemIds(_ db: Database, of attempt: Attempt) throws -> [Int64] {
        switch attempt.kind {
        case .assignment:
            guard let id = attempt.assignmentId, let assignment = try Assignment.fetchOne(db, key: id) else {
                throw StoreError.notFound("作业 \(attempt.assignmentId ?? 0)")
            }
            return assignment.problemIds
        case .exam:
            guard let id = attempt.examId else { throw StoreError.notFound("试卷") }
            return try ExamSection.filter(Column("examId") == id).order(Column("order")).fetchAll(db).flatMap(\.problemIds)
        case .mistakeRedo:
            guard let id = attempt.mistakeId, let mistake = try Mistake.fetchOne(db, key: id) else {
                throw StoreError.notFound("错题 \(attempt.mistakeId ?? 0)")
            }
            return [mistake.problemId]
        }
    }

    private static func orderedProblems(_ db: Database, ids: [Int64]) throws -> [Problem] {
        let found = try Problem.fetchAll(db, keys: ids)
        let byId = Dictionary(uniqueKeysWithValues: found.compactMap { p in p.id.map { ($0, p) } })
        return ids.compactMap { byId[$0] }
    }

    /// 每题最新一条判卷记录。
    private static func latestGrades(_ db: Database, attemptId: Int64) throws -> [Int64: QuestionGrade] {
        try QuestionGrade.filter(Column("attemptId") == attemptId).order(Column("createdAt"), Column("id")).fetchAll(db)
            .reduce(into: [:]) { $0[$1.problemId] = $1 }
    }

    /// 试卷按分区计分；作业与错题重做视为一个隐含分区。
    private static func sectionScores(_ db: Database, attempt: Attempt, problems: [Problem],
                                      latest: [Int64: QuestionGrade]) throws -> [SectionScore] {
        let maxById = problems.reduce(into: [Int64: Double]()) { $0[$1.id!] = $1.maxScore }
        func earned(_ ids: [Int64]) -> Double { ids.reduce(0) { $0 + (latest[$1]?.score ?? 0) } }
        func maxScore(_ ids: [Int64]) -> Double { ids.reduce(0) { $0 + (maxById[$1] ?? 0) } }
        guard attempt.kind == .exam, let examId = attempt.examId else {
            let ids = problems.map { $0.id! }
            return [SectionScore(title: "全部", earned: earned(ids), max: maxScore(ids), weight: 1)]
        }
        return try ExamSection.filter(Column("examId") == examId).order(Column("order")).fetchAll(db).map { section in
            switch section.sourceKind {
            case .problems:
                return SectionScore(title: section.title, earned: earned(section.problemIds), max: maxScore(section.problemIds),
                                    weight: section.weight)
            case .mockInterviewAverage:
                return SectionScore(title: section.title, earned: try mockInterviewAverage(db, asOf: attempt.submittedAt), max: 100, weight: section.weight)
            }
        }
    }

    /// 交卷时（含）之前最近 3 次已打分模拟面试的平均分；不足 3 次记 0。
    /// 以交卷时间为界，复判重新结算时不会用到交卷之后的面试；未交卷时不设界。
    private static func mockInterviewAverage(_ db: Database, asOf submittedAt: Date?) throws -> Double {
        let scores = try Double.fetchAll(
            db,
            sql: """
                SELECT score FROM mockInterview WHERE score IS NOT NULL AND (? IS NULL OR createdAt <= ?)
                ORDER BY createdAt DESC, id DESC LIMIT 3
                """,
            arguments: [submittedAt, submittedAt])
        return scores.count == 3 ? scores.reduce(0, +) / 3 : 0
    }

    // MARK: 内部：结算

    private static func finalize(_ db: Database, attemptId: Int64, now: Date, today: Day, calendar: Calendar) throws {
        var attempt = try fetchAttempt(db, id: attemptId)
        guard attempt.status != .inProgress else { throw StoreError.invalid("作答尚未提交，不能结算") }
        let problems = try orderedProblems(db, ids: problemIds(db, of: attempt))
        let latest = try latestGrades(db, attemptId: attemptId)
        guard problems.allSatisfy({ latest[$0.id!] != nil }) else { throw StoreError.invalid("还有题目未判卷") }
        let isFirstFinalize = attempt.status == .submitted
        let sections = try sectionScores(db, attempt: attempt, problems: problems, latest: latest)

        // 1. 总分与过关：阶段考试用阶段过关线与分区最低线，周测只看总分 75，作业与错题重做不判过关
        let exam = try attempt.examId.flatMap { try Exam.fetchOne(db, key: $0) }
        let stage = try exam.flatMap { try Stage.fetchOne(db, key: $0.stageIndex) }
        switch exam?.kind {
        case .stageExam?:
            let outcome = GateEvaluator.evaluate(sections: sections, passLine: stage!.passLine, minSectionRatio: stage!.minSectionRatio)
            attempt.totalPercent = outcome.totalPercent
            attempt.passed = outcome.passed
        case .weeklyQuiz?:
            let outcome = GateEvaluator.evaluate(sections: sections, passLine: 75, minSectionRatio: 0)
            attempt.totalPercent = outcome.totalPercent
            attempt.passed = outcome.passed
        case nil:
            attempt.totalPercent = GateEvaluator.evaluate(sections: sections, passLine: 0, minSectionRatio: 0).totalPercent
            attempt.passed = nil
        }

        // 2. 错题
        switch attempt.kind {
        case .assignment, .exam:
            for problem in problems where !ReviewScheduler.isCorrect(score: latest[problem.id!]!.score, max: problem.maxScore) {
                // 已有未毕业错题，或本次作答已为该题建过错题（重复结算）时跳过
                let exists = try Mistake.filter(
                    Column("problemId") == problem.id! && (Column("graduated") == false || Column("sourceAttemptId") == attemptId)
                ).fetchCount(db) > 0
                if !exists {
                    var mistake = Mistake(problemId: problem.id!, sourceAttemptId: attemptId, step: 0, streak: 0,
                                          dueDay: today.adding(days: 1, calendar: calendar), graduated: false, createdAt: now)
                    try mistake.insert(db)
                }
            }
        case .mistakeRedo:
            // 只在首次结算时推进排期；复判不重复推进
            if isFirstFinalize, let id = attempt.mistakeId, var mistake = try Mistake.fetchOne(db, key: id), !mistake.graduated,
               let problem = problems.first {
                let next = ReviewScheduler.nextMistake(
                    step: mistake.step, streak: mistake.streak,
                    correct: ReviewScheduler.isCorrect(score: latest[problem.id!]!.score, max: problem.maxScore),
                    today: today, calendar: calendar)
                mistake.step = next.step
                mistake.streak = next.streak
                mistake.dueDay = next.due
                mistake.graduated = next.graduated
                try mistake.update(db)
            }
        }

        // 3. 经验（去重键保证只给一次）与作业完成、阶段解锁
        for problem in problems {
            try insertXP(db, dedupKey: "problem:\(attemptId):\(problem.id!)",
                         amount: XPRules.problemXP(difficulty: problem.difficulty, score: latest[problem.id!]!.score, max: problem.maxScore),
                         reason: .problem, day: today, now: now)
        }
        var relearnStage: Int?
        if attempt.kind == .assignment, let id = attempt.assignmentId, var assignment = try Assignment.fetchOne(db, key: id) {
            if assignment.status != .completed {
                assignment.status = .completed
                try assignment.update(db)
            }
            try insertXP(db, dedupKey: "assignment:\(id)", amount: XPRules.assignmentCompleted, reason: .assignmentCompleted,
                         day: today, now: now)
            relearnStage = try assignment.moduleId.flatMap { try Module.fetchOne(db, key: $0) }?.stageIndex
        }
        if let exam, attempt.passed == true {
            if exam.kind == .weeklyQuiz {
                try insertXP(db, dedupKey: "exam:\(exam.id!)", amount: XPRules.weeklyPassed, reason: .weeklyPassed, day: today, now: now)
            } else if var passedStage = stage, passedStage.status != .passed {
                passedStage.status = .passed
                passedStage.passedAt = now
                try passedStage.update(db)
                if var next = try Stage.fetchOne(db, key: passedStage.index + 1), next.status == .locked {
                    next.status = .inProgress
                    try next.update(db)
                }
                try insertXP(db, dedupKey: "stage:\(passedStage.index)", amount: XPRules.stagePassed, reason: .stagePassed,
                             day: today, now: now)
            }
        }

        // 4. 作答与试卷状态；gradedAt 保留首次结算时间，使冷却起点不因复判移动
        attempt.status = .graded
        attempt.gradedAt = attempt.gradedAt ?? now
        try attempt.update(db)
        if var exam {
            exam.status = .graded
            try exam.update(db)
            if exam.kind == .stageExam { relearnStage = exam.stageIndex }
        }

        // 5. 重学标记：阶段考试结算、或完成了带模块的作业时同步
        if let relearnStage {
            _ = try syncStageGate(db, stageIndex: relearnStage, today: today, calendar: calendar)
        }
    }

    // MARK: 内部：晋级门槛

    private static func stageHistory(_ db: Database, stageIndex: Int, calendar: Calendar) throws -> [(record: StageExamRecord, gradedAt: Date)] {
        let attempts = try Attempt.fetchAll(
            db,
            sql: """
                SELECT attempt.* FROM attempt JOIN exam ON exam.id = attempt.examId
                WHERE exam.kind = ? AND exam.stageIndex = ? AND attempt.status = ? AND attempt.gradedAt IS NOT NULL
                ORDER BY attempt.gradedAt, attempt.id
                """,
            arguments: [ExamKind.stageExam.rawValue, stageIndex, AttemptStatus.graded.rawValue])
        return try attempts.map { attempt in
            let gradedAt = attempt.gradedAt!
            let record = StageExamRecord(day: Day.of(gradedAt, calendar: calendar), passed: attempt.passed ?? false,
                                         weakestModuleId: try weakestModule(db, attempt: attempt))
            return (record, gradedAt)
        }
    }

    /// 按模块汇总得分率最低的模块；题目都没有模块时为 nil。得分率相同取 id 较小者。
    private static func weakestModule(_ db: Database, attempt: Attempt) throws -> Int64? {
        let latest = try latestGrades(db, attemptId: attempt.id!)
        var totals: [Int64: (earned: Double, max: Double)] = [:]
        for problem in try orderedProblems(db, ids: problemIds(db, of: attempt)) {
            guard let moduleId = problem.moduleId else { continue }
            totals[moduleId, default: (0, 0)].earned += latest[problem.id!]?.score ?? 0
            totals[moduleId, default: (0, 0)].max += problem.maxScore
        }
        return totals.filter { $0.value.max > 0 }
            .min { ($0.value.earned / $0.value.max, $0.key) < ($1.value.earned / $1.value.max, $1.key) }?.key
    }

    /// 存在最弱模块的、已完成的、创建于最近一次失败判卷之后的作业。
    private static func relearnSatisfied(_ db: Database, history: [(record: StageExamRecord, gradedAt: Date)]) throws -> Bool {
        guard let last = history.last, !last.record.passed, let moduleId = last.record.weakestModuleId else { return false }
        return try Assignment.filter(
            Column("moduleId") == moduleId && Column("status") == AssignmentStatus.completed.rawValue
                && Column("createdAt") > last.gradedAt
        ).fetchCount(db) > 0
    }

    /// 计算门槛状态，并同步该阶段模块的 needsRelearn：最近两次都失败且尚未完成重学作业时标记最弱模块，其余清除。
    /// 由结算（阶段考试、带模块的作业）、`stageGateStatus` 与 `startExam` 共用，规则只在这里。
    private static func syncStageGate(_ db: Database, stageIndex: Int, today: Day, calendar: Calendar) throws
        -> (status: StageGateStatus, changed: Bool) {
        guard let stage = try Stage.fetchOne(db, key: stageIndex) else { throw StoreError.notFound("阶段 \(stageIndex)") }
        let history = try stageHistory(db, stageIndex: stageIndex, calendar: calendar)
        let records = history.map(\.record)
        let satisfied = try relearnSatisfied(db, history: history)
        var flagged: Int64?
        if records.count >= 2, !records[records.count - 1].passed, !records[records.count - 2].passed, !satisfied {
            flagged = records.last?.weakestModuleId
        }
        var changed = false
        for var module in try Module.filter(Column("stageIndex") == stageIndex).fetchAll(db) {
            let needsRelearn = module.id == flagged
            if module.needsRelearn != needsRelearn {
                module.needsRelearn = needsRelearn
                try module.update(db)
                changed = true
            }
        }
        let status = StageGate.status(stage: stage, history: records, relearnSatisfied: satisfied, today: today, calendar: calendar)
        return (status, changed)
    }

    private static func blockedReason(_ db: Database, _ status: StageGateStatus) throws -> String? {
        switch status {
        case .open:
            return nil
        case .coolingDown(let until):
            return "阶段考试冷却期中，\(until) 起可以重考"
        case .needsRelearn(let moduleId):
            let title = try Module.fetchOne(db, key: moduleId)?.title ?? "模块 \(moduleId)"
            return "连续两次未通过：需要先完成模块「\(title)」的至少一份作业"
        case .locked:
            return "该阶段尚未解锁"
        case .alreadyPassed:
            return "该阶段已经通过"
        }
    }
}

// MARK: 模拟面试

extension StudyStore {
    /// 新建（无 id）或更新一场模拟面试，返回带 id 的记录。
    public func saveMockInterview(_ interview: MockInterview) throws -> MockInterview {
        var record = interview
        try pool.write { db in
            if record.id == nil { try record.insert(db) } else { try record.update(db) }
        }
        notifier.post()
        return record
    }

    public func mockInterview(id: Int64) throws -> MockInterview? {
        try pool.read { try MockInterview.fetchOne($0, key: id) }
    }

    /// 阶段通过奖励弹窗是否已对该作答弹过；记在 AppSetting（键 `rewardSeen.<attemptId>`）。
    public func hasSeenReward(attemptId: Int64) throws -> Bool {
        try pool.read { try AppSetting.fetchOne($0, key: "rewardSeen.\(attemptId)") } != nil
    }

    public func markRewardSeen(attemptId: Int64) throws {
        try pool.write { try AppSetting(key: "rewardSeen.\(attemptId)", value: "1").save($0) }
    }

    /// 全部模拟面试，最新的在前。
    public func mockInterviews() throws -> [MockInterview] {
        try pool.read { try MockInterview.order(Column("createdAt").desc, Column("id").desc).fetchAll($0) }
    }
}
