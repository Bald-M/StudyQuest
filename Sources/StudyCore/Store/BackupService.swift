import Foundation
import GRDB

public enum BackupError: Error, Equatable {
    case invalidBackup(String)
}

/// 整库 SQLite 副本的导出与恢复。恢复分两步：先把备份放到数据库旁边待命，下次启动、打开数据库之前再替换，
/// 避免替换正被 App 或 MCP 进程打开的库文件。
public enum BackupService {
    static let pendingFileName = "restore-pending.sqlite"

    /// 待恢复文件与数据库在同一目录。
    public static func pendingRestoreURL(for dbURL: URL) -> URL {
        dbURL.deletingLastPathComponent().appendingPathComponent(pendingFileName)
    }

    /// 用 SQLite 在线备份写出一致的单文件副本；目标已存在则覆盖。
    /// 副本改回 DELETE 日志模式：WAL 模式的库没有 -shm 时无法只读打开，也不是单个文件。
    public static func export(database: AppDatabase, to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let copy = try DatabaseQueue(path: url.path)
        try database.pool.backup(to: copy)
        try copy.writeWithoutTransaction { try $0.execute(sql: "PRAGMA journal_mode = DELETE") }
        try copy.close()
    }

    /// 只读打开，确认是 StudyQuest 的库：有 stage 表且有数据。
    public static func validate(backup url: URL) throws {
        var config = Configuration()
        config.readonly = true
        let ok = try DatabaseQueue(path: url.path, configuration: config).read { db in
            try db.tableExists("stage") && Int.fetchOne(db, sql: "SELECT COUNT(*) FROM stage") ?? 0 > 0
        }
        guard ok else { throw BackupError.invalidBackup("备份里没有阶段数据") }
    }

    /// 校验后复制到数据库旁的 restore-pending.sqlite，下次启动时生效。
    public static func scheduleRestore(from url: URL, dbURL: URL) throws {
        try validate(backup: url)
        let pending = pendingRestoreURL(for: dbURL)
        let fm = FileManager.default
        try fm.createDirectory(at: pending.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: pending.path) { try fm.removeItem(at: pending) }
        try fm.copyItem(at: url, to: pending)
    }

    /// 启动时、打开数据库之前调用：有待恢复文件就替换原库，并删掉旧库的 -wal/-shm。
    public static func applyPendingRestore(at dbURL: URL) throws {
        let pending = pendingRestoreURL(for: dbURL)
        let fm = FileManager.default
        guard fm.fileExists(atPath: pending.path) else { return }
        for suffix in ["", "-wal", "-shm"] {
            let path = dbURL.path + suffix
            if fm.fileExists(atPath: path) { try fm.removeItem(atPath: path) }
        }
        try fm.moveItem(at: pending, to: dbURL)
    }
}
