import Foundation
import GRDB

public struct Card: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public var id: Int64?
    public var stageIndex: Int
    public var moduleId: Int64?
    public var front: String
    public var back: String
    public var tags: [String]
    public var step: Int?
    public var dueDay: Day
    public var createdAt: Date
    public var sectionId: Int64?
    public init(id: Int64? = nil, stageIndex: Int, moduleId: Int64? = nil, front: String, back: String, tags: [String], step: Int? = nil, dueDay: Day, createdAt: Date, sectionId: Int64? = nil) { self.id = id; self.stageIndex = stageIndex; self.moduleId = moduleId; self.front = front; self.back = back; self.tags = tags; self.step = step; self.dueDay = dueDay; self.createdAt = createdAt; self.sectionId = sectionId }
    public static let databaseTableName = "card"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct CardReview: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public var id: Int64?
    public var cardId: Int64
    public var day: Day
    public var remembered: Bool
    public init(id: Int64? = nil, cardId: Int64, day: Day, remembered: Bool) { self.id = id; self.cardId = cardId; self.day = day; self.remembered = remembered }
    public static let databaseTableName = "cardReview"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public enum ProblemKind: String, Codable, DatabaseValueConvertible, Sendable {
    case singleChoice, multipleChoice, shortAnswer, coding, project
}
public enum Difficulty: String, Codable, DatabaseValueConvertible, Sendable { case easy, medium, hard }

public struct Problem: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public var id: Int64?
    public var stageIndex: Int
    public var moduleId: Int64?
    public var kind: ProblemKind
    public var prompt: String
    public var options: [String]
    public var referenceAnswer: String
    public var rubric: String
    public var maxScore: Double
    public var difficulty: Difficulty
    public var tags: [String]
    public var source: String
    public var createdAt: Date
    public var sectionId: Int64?
    public init(id: Int64? = nil, stageIndex: Int, moduleId: Int64? = nil, kind: ProblemKind, prompt: String, options: [String], referenceAnswer: String, rubric: String, maxScore: Double, difficulty: Difficulty, tags: [String], source: String, createdAt: Date, sectionId: Int64? = nil) { self.id = id; self.stageIndex = stageIndex; self.moduleId = moduleId; self.kind = kind; self.prompt = prompt; self.options = options; self.referenceAnswer = referenceAnswer; self.rubric = rubric; self.maxScore = maxScore; self.difficulty = difficulty; self.tags = tags; self.source = source; self.createdAt = createdAt; self.sectionId = sectionId }
    public static let databaseTableName = "problem"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public enum AssignmentStatus: String, Codable, DatabaseValueConvertible, Sendable { case open, completed }

public struct Assignment: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public var id: Int64?
    public var stageIndex: Int
    public var moduleId: Int64?
    public var day: Day
    public var title: String
    public var problemIds: [Int64]
    public var status: AssignmentStatus
    public var source: String
    public var createdAt: Date
    public init(id: Int64? = nil, stageIndex: Int, moduleId: Int64? = nil, day: Day, title: String, problemIds: [Int64], status: AssignmentStatus, source: String, createdAt: Date) { self.id = id; self.stageIndex = stageIndex; self.moduleId = moduleId; self.day = day; self.title = title; self.problemIds = problemIds; self.status = status; self.source = source; self.createdAt = createdAt }
    public static let databaseTableName = "assignment"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public enum ExamKind: String, Codable, DatabaseValueConvertible, Sendable { case weeklyQuiz, stageExam }
public enum ExamStatus: String, Codable, DatabaseValueConvertible, Sendable {
    case draft, ready, inProgress, submitted, graded
}
public enum SectionSource: String, Codable, DatabaseValueConvertible, Sendable { case problems, mockInterviewAverage }

public struct Exam: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public var id: Int64?
    public var stageIndex: Int
    public var kind: ExamKind
    public var title: String
    public var timeLimitMinutes: Int
    public var status: ExamStatus
    public var warnings: [String]
    public var source: String
    public var createdAt: Date
    public init(id: Int64? = nil, stageIndex: Int, kind: ExamKind, title: String, timeLimitMinutes: Int, status: ExamStatus, warnings: [String], source: String, createdAt: Date) { self.id = id; self.stageIndex = stageIndex; self.kind = kind; self.title = title; self.timeLimitMinutes = timeLimitMinutes; self.status = status; self.warnings = warnings; self.source = source; self.createdAt = createdAt }
    public static let databaseTableName = "exam"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct ExamSection: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public var id: Int64?
    public var examId: Int64
    public var order: Int
    public var title: String
    public var weight: Double
    public var sourceKind: SectionSource
    public var problemIds: [Int64]
    public init(id: Int64? = nil, examId: Int64, order: Int, title: String, weight: Double, sourceKind: SectionSource, problemIds: [Int64]) { self.id = id; self.examId = examId; self.order = order; self.title = title; self.weight = weight; self.sourceKind = sourceKind; self.problemIds = problemIds }
    public static let databaseTableName = "examSection"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
