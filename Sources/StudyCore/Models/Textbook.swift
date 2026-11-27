import Foundation
import GRDB

public enum TextbookSourceKind: String, Codable, DatabaseValueConvertible, Sendable {
    case markdownFile, markdownFolder, pdf
}

public struct Textbook: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public var id: Int64?
    public var stageIndex: Int
    public var title: String
    public var sourceKind: TextbookSourceKind
    public var sourcePath: String
    /// 项目二用，本项目始终为 nil。
    public var language: String?
    public var lastSectionId: Int64?
    public var importedAt: Date
    public var deletedAt: Date?
    public init(id: Int64? = nil, stageIndex: Int, title: String, sourceKind: TextbookSourceKind, sourcePath: String, language: String? = nil, lastSectionId: Int64? = nil, importedAt: Date, deletedAt: Date? = nil) { self.id = id; self.stageIndex = stageIndex; self.title = title; self.sourceKind = sourceKind; self.sourcePath = sourcePath; self.language = language; self.lastSectionId = lastSectionId; self.importedAt = importedAt; self.deletedAt = deletedAt }
    public static let databaseTableName = "textbook"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// pdf 教材的原文件。单独一张表：教材行常被改小字段（阅读位置、删除标记、标题），
/// 和几十 MB 的 BLOB 放在同一行时，SQLite 每次都要连 BLOB 一起重写。
public struct TextbookPdf: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    public var textbookId: Int64
    public var data: Data
    public init(textbookId: Int64, data: Data) { self.textbookId = textbookId; self.data = data }
    public static let databaseTableName = "textbookPdf"
}

public struct TextbookSection: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public var id: Int64?
    public var textbookId: Int64
    public var matchKey: String
    public var chapterTitle: String
    public var title: String
    public var order: Int
    public var moduleId: Int64?
    public var text: String
    public var textHash: String
    public var pageStart: Int?
    public var pageEnd: Int?
    public var masteredAt: Date?
    public var removedAt: Date?
    /// 项目二用，默认 true。
    public var codeLevelsEnabled: Bool
    public init(id: Int64? = nil, textbookId: Int64, matchKey: String, chapterTitle: String, title: String, order: Int, moduleId: Int64? = nil, text: String, textHash: String, pageStart: Int? = nil, pageEnd: Int? = nil, masteredAt: Date? = nil, removedAt: Date? = nil, codeLevelsEnabled: Bool = true) { self.id = id; self.textbookId = textbookId; self.matchKey = matchKey; self.chapterTitle = chapterTitle; self.title = title; self.order = order; self.moduleId = moduleId; self.text = text; self.textHash = textHash; self.pageStart = pageStart; self.pageEnd = pageEnd; self.masteredAt = masteredAt; self.removedAt = removedAt; self.codeLevelsEnabled = codeLevelsEnabled }
    public static let databaseTableName = "textbookSection"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct TextbookAsset: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public var id: Int64?
    public var textbookId: Int64
    public var ref: String
    public var data: Data
    public init(id: Int64? = nil, textbookId: Int64, ref: String, data: Data) { self.id = id; self.textbookId = textbookId; self.ref = ref; self.data = data }
    public static let databaseTableName = "textbookAsset"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct SectionChallenge: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public var id: Int64?
    public var sectionId: Int64
    public var problemIds: [Int64]
    public var stale: Bool
    public var createdAt: Date
    public var source: String
    public init(id: Int64? = nil, sectionId: Int64, problemIds: [Int64], stale: Bool = false, createdAt: Date, source: String) { self.id = id; self.sectionId = sectionId; self.problemIds = problemIds; self.stale = stale; self.createdAt = createdAt; self.source = source }
    public static let databaseTableName = "sectionChallenge"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
