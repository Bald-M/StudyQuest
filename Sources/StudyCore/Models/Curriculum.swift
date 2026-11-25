import Foundation
import GRDB

public enum StageStatus: String, Codable, DatabaseValueConvertible, Sendable { case locked, inProgress, passed }
public enum ModuleStatus: String, Codable, DatabaseValueConvertible, Sendable { case notStarted, learning, done }

public struct Stage: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public var index: Int
    public var title: String
    public var summary: String
    public var estimatedWeeks: String
    public var passLine: Double
    public var minSectionRatio: Double
    public var cumulativeMin: Double
    public var cumulativeMax: Double
    public var cooldownDays: Int
    public var reward: String?
    public var status: StageStatus
    public var passedAt: Date?
    public var id: Int { index }
    public static let databaseTableName = "stage"
}

public struct Module: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public var id: Int64?
    public var stageIndex: Int
    public var key: String
    public var title: String
    public var points: String
    public var resources: [String]
    public var gameTasks: [String]
    public var lifeProblems: [String]
    public var order: Int
    public var status: ModuleStatus
    public var startedAt: Date?
    public var completedAt: Date?
    public var needsRelearn: Bool
    public static let databaseTableName = "module"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
