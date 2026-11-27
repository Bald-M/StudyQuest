import Foundation
import GRDB

public enum AttemptKind: String, Codable, DatabaseValueConvertible, Sendable { case assignment, exam, mistakeRedo, section }
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
    public var sectionChallengeId: Int64?
    public init(id: Int64? = nil, kind: AttemptKind, assignmentId: Int64? = nil, examId: Int64? = nil, mistakeId: Int64? = nil, status: AttemptStatus, startedAt: Date, deadline: Date? = nil, submittedAt: Date? = nil, gradedAt: Date? = nil, totalPercent: Double? = nil, passed: Bool? = nil, reflection: String? = nil, sectionChallengeId: Int64? = nil) { self.id = id; self.kind = kind; self.assignmentId = assignmentId; self.examId = examId; self.mistakeId = mistakeId; self.status = status; self.startedAt = startedAt; self.deadline = deadline; self.submittedAt = submittedAt; self.gradedAt = gradedAt; self.totalPercent = totalPercent; self.passed = passed; self.reflection = reflection; self.sectionChallengeId = sectionChallengeId }
    public static let databaseTableName = "attempt"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct AttemptAnswer: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public var id: Int64?
    public var attemptId: Int64
    public var problemId: Int64
    public var answer: String
    public var updatedAt: Date
    public init(id: Int64? = nil, attemptId: Int64, problemId: Int64, answer: String, updatedAt: Date) { self.id = id; self.attemptId = attemptId; self.problemId = problemId; self.answer = answer; self.updatedAt = updatedAt }
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
    public init(id: Int64? = nil, attemptId: Int64, problemId: Int64, score: Double, maxScore: Double, feedback: String, mistakes: [String], grader: String, raw: String, createdAt: Date) { self.id = id; self.attemptId = attemptId; self.problemId = problemId; self.score = score; self.maxScore = maxScore; self.feedback = feedback; self.mistakes = mistakes; self.grader = grader; self.raw = raw; self.createdAt = createdAt }
    public static let databaseTableName = "questionGrade"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct ChatTurn: Codable, Equatable, Sendable {
    public var role: String
    public var content: String
    public init(role: String, content: String) { self.role = role; self.content = content }
}

public struct MockInterview: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public var id: Int64?
    public var transcript: [ChatTurn]
    public var score: Double?
    public var feedback: String?
    public var grader: String?
    public var createdAt: Date
    public init(id: Int64? = nil, transcript: [ChatTurn], score: Double? = nil, feedback: String? = nil, grader: String? = nil, createdAt: Date) { self.id = id; self.transcript = transcript; self.score = score; self.feedback = feedback; self.grader = grader; self.createdAt = createdAt }
    public static let databaseTableName = "mockInterview"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
