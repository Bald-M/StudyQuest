import Foundation

/// 今日页需要的全部数据：复习 → 错题 → 作业 → 考试 → 总结。
public struct TodaySummary: Sendable {
    public var dueCards: Int
    public var deferredCards: Int
    public var dueMistakes: Int
    public var assignments: [Assignment]
    public var readyExams: [Exam]
    /// 待确认的草稿试卷数。
    public var draftExams: Int
    public var pendingGradingAttempts: Int
    public var autoGen: AutoGenStatus
    public var noteWritten: Bool
    public var progress: ProgressSummary
}

public enum TodayBuilder {
    /// 只读。
    public static func build(store: StudyStore, autoGen: AutoGenStatus) throws -> TodaySummary {
        let today = store.clock.today()
        let queue = try store.reviewQueue()
        let exams = try store.exams(stage: nil)
        return TodaySummary(
            dueCards: queue.cards.count,
            deferredCards: queue.deferred,
            dueMistakes: try store.dueMistakes().count,
            assignments: try store.assignments(day: today),
            readyExams: exams.filter { $0.status == .ready },
            draftExams: exams.filter { $0.status == .draft }.count,
            pendingGradingAttempts: try store.attempts(examId: nil, status: .submitted).count,
            autoGen: autoGen,
            noteWritten: try store.dailyNote(day: today) != nil,
            progress: try store.progressSummary())
    }
}
