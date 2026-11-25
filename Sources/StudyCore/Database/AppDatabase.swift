import Foundation
import GRDB

public final class AppDatabase: Sendable {
    public let pool: DatabasePool

    public static func defaultURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return support.appendingPathComponent("StudyQuest/studyquest.sqlite")
    }

    /// 建目录、打开 WAL 数据库（busyTimeout 5 秒）并运行迁移。
    public init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var config = Configuration()
        config.busyMode = .timeout(5)
        pool = try DatabasePool(path: url.path, configuration: config)
        try Migrations.make().migrate(pool)
    }
}

/// 日期列直接存 "yyyy-MM-dd" 文本，便于 SQL 比较。
extension Day: DatabaseValueConvertible {
    public var databaseValue: DatabaseValue { rawValue.databaseValue }

    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> Day? {
        String.fromDatabaseValue(dbValue).flatMap { Day(rawValue: $0) }
    }
}
