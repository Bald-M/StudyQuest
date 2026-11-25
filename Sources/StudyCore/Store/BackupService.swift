import Foundation
import GRDB

public enum BackupError: Error, Equatable {
    case invalidBackup(String)
    case destinationIsLiveDatabase
    case pendingRestoreInvalid(String)
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
    /// 先写到目标同目录的临时文件，成功后再原子替换，失败时原目标不受影响；拒绝把正在用的库（及其 -wal/-shm）当作目标。
    /// 副本改回 DELETE 日志模式：WAL 模式的库没有 -shm 时无法只读打开，也不是单个文件。
    public static func export(database: AppDatabase, to url: URL) throws {
        let live = resolvedPath(URL(fileURLWithPath: database.pool.path))
        let target = resolvedPath(url)
        guard ![live, live + "-wal", live + "-shm"].contains(target) else { throw BackupError.destinationIsLiveDatabase }

        let fm = FileManager.default
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            let copy = try DatabaseQueue(path: temp.path)
            try database.pool.backup(to: copy)
            try copy.writeWithoutTransaction { try $0.execute(sql: "PRAGMA journal_mode = DELETE") }
            try copy.close()
            if fm.fileExists(atPath: url.path) {
                _ = try fm.replaceItemAt(url, withItemAt: temp)
            } else {
                try fm.moveItem(at: temp, to: url)
            }
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }

    private static func resolvedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
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

    /// 原库在恢复时被挪到这里（连同未合并的 -wal），以防备份有问题还能找回。
    public static func preRestoreURL(for dbURL: URL) -> URL {
        URL(fileURLWithPath: dbURL.path + ".pre-restore")
    }

    /// 启动时、打开数据库之前调用。有待恢复文件时先校验：不合格就删掉它并抛错，原库不动；
    /// 合格则把原库挪到 `<db>.pre-restore`（其 -wal 改名为 `<db>.pre-restore-wal`，SQLite 打开时会自动合并；
    /// 旧的 pre-restore 被替换），删掉 -shm，再把待恢复文件移进来；这一步失败时把原库挪回去再抛错。
    public static func applyPendingRestore(at dbURL: URL) throws {
        try applyPendingRestore(at: dbURL) { try FileManager.default.moveItem(at: $0, to: $1) }
    }

    /// `moveItem` 可替换，供测试模拟最后一步移动失败。
    static func applyPendingRestore(at dbURL: URL, moveItem: (_ from: URL, _ to: URL) throws -> Void) throws {
        let pending = pendingRestoreURL(for: dbURL)
        let fm = FileManager.default
        guard fm.fileExists(atPath: pending.path) else { return }
        do {
            try validate(backup: pending)
        } catch {
            try? fm.removeItem(at: pending)
            throw BackupError.pendingRestoreInvalid("待恢复的备份无法使用，已丢弃，继续使用现有数据：\(error)")
        }

        let preRestore = preRestoreURL(for: dbURL)
        let preRestoreWAL = URL(fileURLWithPath: preRestore.path + "-wal")
        let wal = URL(fileURLWithPath: dbURL.path + "-wal")
        for path in [preRestore.path, preRestoreWAL.path, preRestore.path + "-shm"] where fm.fileExists(atPath: path) {
            try fm.removeItem(atPath: path)
        }
        var movedDB = false, movedWAL = false
        if fm.fileExists(atPath: dbURL.path) {
            try moveItem(dbURL, preRestore)
            movedDB = true
        }
        if fm.fileExists(atPath: wal.path) {
            try moveItem(wal, preRestoreWAL)
            movedWAL = true
        }
        if fm.fileExists(atPath: dbURL.path + "-shm") {
            try fm.removeItem(atPath: dbURL.path + "-shm")
        }
        do {
            try moveItem(pending, dbURL)
        } catch {
            // 最后一步失败：把原库与 -wal 放回原处，保持恢复前的样子；待恢复文件留着，下次启动再试
            if movedDB { try? moveItem(preRestore, dbURL) }
            if movedWAL { try? moveItem(preRestoreWAL, wal) }
            throw error
        }
    }
}
