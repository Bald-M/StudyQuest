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
    public init(index: Int, title: String, summary: String, estimatedWeeks: String, passLine: Double, minSectionRatio: Double, cumulativeMin: Double, cumulativeMax: Double, cooldownDays: Int, reward: String? = nil, status: StageStatus, passedAt: Date? = nil) { self.index = index; self.title = title; self.summary = summary; self.estimatedWeeks = estimatedWeeks; self.passLine = passLine; self.minSectionRatio = minSectionRatio; self.cumulativeMin = cumulativeMin; self.cumulativeMax = cumulativeMax; self.cooldownDays = cooldownDays; self.reward = reward; self.status = status; self.passedAt = passedAt }
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
    public init(id: Int64? = nil, stageIndex: Int, key: String, title: String, points: String, resources: [String], gameTasks: [String], lifeProblems: [String], order: Int, status: ModuleStatus, startedAt: Date? = nil, completedAt: Date? = nil, needsRelearn: Bool) { self.id = id; self.stageIndex = stageIndex; self.key = key; self.title = title; self.points = points; self.resources = resources; self.gameTasks = gameTasks; self.lifeProblems = lifeProblems; self.order = order; self.status = status; self.startedAt = startedAt; self.completedAt = completedAt; self.needsRelearn = needsRelearn }
    public static let databaseTableName = "module"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
