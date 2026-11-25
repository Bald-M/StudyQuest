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
    public static let databaseTableName = "card"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct CardReview: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public var id: Int64?
    public var cardId: Int64
    public var day: Day
    public var remembered: Bool
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
    public static let databaseTableName = "examSection"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
