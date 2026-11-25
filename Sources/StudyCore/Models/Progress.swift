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
    public static let databaseTableName = "xpEvent"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct DailyNote: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    public var day: Day
    public var text: String
    public var id: Day { day }
    public static let databaseTableName = "dailyNote"
}

public struct AutoGenRun: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    public var day: Day
    public var status: String
    public var errors: [String]
    public var createdAt: Date
    public var id: Day { day }
    public static let databaseTableName = "autoGenRun"
}

public struct AppSetting: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    public var key: String
    public var value: String
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
    public static let databaseTableName = "providerConfig"
}
