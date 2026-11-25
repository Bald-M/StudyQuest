import Foundation
import GRDB

public enum AttemptKind: String, Codable, DatabaseValueConvertible, Sendable { case assignment, exam, mistakeRedo }
public enum AttemptStatus: String, Codable, DatabaseValueConvertible, Sendable { case inProgress, submitted, graded }

public struct Attempt: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public var id: Int64?
    public var kind: AttemptKind
    public var assignmentId: Int64?
    public var examId: Int64?
    public var mistakeId: Int64?
    public var status: AttemptStatus
    public var startedAt: Date
    public var deadline: Date?
    public var submittedAt: Date?
    public var gradedAt: Date?
    public var totalPercent: Double?
    public var passed: Bool?
    public var reflection: String?
    public static let databaseTableName = "attempt"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct AttemptAnswer: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public var id: Int64?
    public var attemptId: Int64
    public var problemId: Int64
    public var answer: String
    public var updatedAt: Date
    public static let databaseTableName = "attemptAnswer"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// 同一题可有多条评分，以 createdAt 最新者为准。
public struct QuestionGrade: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public var id: Int64?
    public var attemptId: Int64
    public var problemId: Int64
    public var score: Double
    public var maxScore: Double
    public var feedback: String
    public var mistakes: [String]
    public var grader: String
    public var raw: String
    public var createdAt: Date
    public static let databaseTableName = "questionGrade"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct ChatTurn: Codable, Equatable, Sendable {
    public var role: String
    public var content: String
}

public struct MockInterview: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public var id: Int64?
    public var transcript: [ChatTurn]
    public var score: Double?
    public var feedback: String?
    public var grader: String?
    public var createdAt: Date
    public static let databaseTableName = "mockInterview"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
