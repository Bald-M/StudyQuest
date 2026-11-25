import Foundation
import GRDB

public struct Mistake: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public var id: Int64?
    public var problemId: Int64
    public var sourceAttemptId: Int64
    public var step: Int
    public var streak: Int
    public var dueDay: Day
    public var graduated: Bool
    public var createdAt: Date
    public init(id: Int64? = nil, problemId: Int64, sourceAttemptId: Int64, step: Int, streak: Int, dueDay: Day, graduated: Bool, createdAt: Date) { self.id = id; self.problemId = problemId; self.sourceAttemptId = sourceAttemptId; self.step = step; self.streak = streak; self.dueDay = dueDay; self.graduated = graduated; self.createdAt = createdAt }
    public static let databaseTableName = "mistake"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public enum XPReason: String, Codable, DatabaseValueConvertible, Sendable {
    case problem, assignmentCompleted, reviewCleared, weeklyPassed, stagePassed, dailyNote
}

public struct XPEvent: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public var id: Int64?
    public var dedupKey: String
    public var amount: Int
    public var reason: XPReason
    public var day: Day
    public var createdAt: Date
    public init(id: Int64? = nil, dedupKey: String, amount: Int, reason: XPReason, day: Day, createdAt: Date) { self.id = id; self.dedupKey = dedupKey; self.amount = amount; self.reason = reason; self.day = day; self.createdAt = createdAt }
    public static let databaseTableName = "xpEvent"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct DailyNote: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    public var day: Day
    public var text: String
    public init(day: Day, text: String) { self.day = day; self.text = text }
    public var id: Day { day }
    public static let databaseTableName = "dailyNote"
}

public struct AutoGenRun: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    public var day: Day
    public var status: String
    public var errors: [String]
    public var createdAt: Date
    public init(day: Day, status: String, errors: [String], createdAt: Date) { self.day = day; self.status = status; self.errors = errors; self.createdAt = createdAt }
    public var id: Day { day }
    public static let databaseTableName = "autoGenRun"
}

public struct AppSetting: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    public var key: String
    public var value: String
    public init(key: String, value: String) { self.key = key; self.value = value }
    public var id: String { key }
    public static let databaseTableName = "appSetting"
}

public enum ProviderKind: String, Codable, DatabaseValueConvertible, Sendable { case openAICompatible, anthropic }

public struct ProviderConfig: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: ProviderKind
    public var name: String
    public var baseURL: String
    public var model: String
    public var effort: String?
    public init(id: String, kind: ProviderKind, name: String, baseURL: String, model: String, effort: String? = nil) { self.id = id; self.kind = kind; self.name = name; self.baseURL = baseURL; self.model = model; self.effort = effort }
    public static let databaseTableName = "providerConfig"
}
