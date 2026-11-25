import Foundation
import GRDB
import Testing
@testable import StudyCore

private func makeTempDir() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("studyquest-test-\(UUID().uuidString)")
}

private func makeStore(at url: URL) throws -> StudyStore {
    try StudyStore(database: AppDatabase(url: url), clock: SystemClock(), notifier: NoopChangeNotifier())
}

private func cardCount(_ url: URL) throws -> Int {
    try AppDatabase(url: url).pool.read { try Card.fetchCount($0) }
}

@Suite struct BackupTests {
    @Test func exportProducesOpenableCopy() throws {
        let dir = makeTempDir()
        let dbURL = dir.appendingPathComponent("studyquest.sqlite")
        let database = try AppDatabase(url: dbURL)
        _ = try StudyStore(database: database, clock: SystemClock(), notifier: NoopChangeNotifier())
        let backup = dir.appendingPathComponent("backup.sqlite")

        try BackupService.export(database: database, to: backup)

        try BackupService.validate(backup: backup)
        let stages = try DatabaseQueue(path: backup.path).read { try Stage.fetchCount($0) }
        #expect(stages == 10)
    }

    @Test func restoreReplacesOnNextLaunch() throws {
        let dir = makeTempDir()
        let dbURL = dir.appendingPathComponent("studyquest.sqlite")
        let backup = dir.appendingPathComponent("backup.sqlite")
        let exportedCards: Int
        do {
            let database = try AppDatabase(url: dbURL)
            let store = try StudyStore(database: database, clock: SystemClock(), notifier: NoopChangeNotifier())
            exportedCards = try database.pool.read { try Card.fetchCount($0) }
            try BackupService.export(database: database, to: backup)
            _ = try store.createCards([CardInput(stageIndex: 0, moduleKey: nil, front: "新卡", back: "b", tags: nil)], source: "test")
            #expect(try database.pool.read { try Card.fetchCount($0) } == exportedCards + 1)
            try BackupService.scheduleRestore(from: backup, dbURL: dbURL)
            // 模拟退出：关闭连接后才应用恢复，与启动时的真实顺序一致。
            try database.pool.close()
        }
        let pending = dir.appendingPathComponent("restore-pending.sqlite")
        #expect(FileManager.default.fileExists(atPath: pending.path))
        #expect(FileManager.default.fileExists(atPath: dbURL.path + "-wal"))

        try BackupService.applyPendingRestore(at: dbURL)

        #expect(!FileManager.default.fileExists(atPath: pending.path))
        #expect(!FileManager.default.fileExists(atPath: dbURL.path + "-wal"))
        #expect(!FileManager.default.fileExists(atPath: dbURL.path + "-shm"))
        #expect(FileManager.default.fileExists(atPath: dbURL.path + ".pre-restore"))
        #expect(try cardCount(dbURL) == exportedCards)
        // 挪开的旧库（含 -wal）仍能打开，且保留恢复前新增的卡片。
        #expect(try cardCount(URL(fileURLWithPath: dbURL.path + ".pre-restore")) == exportedCards + 1)
        _ = try makeStore(at: dbURL)
    }

    @Test func failedFinalMoveRestoresOriginal() throws {
        struct MoveFailed: Error {}
        let dir = makeTempDir()
        let dbURL = dir.appendingPathComponent("studyquest.sqlite")
        let backup = dir.appendingPathComponent("backup.sqlite")
        let before: Int
        do {
            let database = try AppDatabase(url: dbURL)
            let store = try StudyStore(database: database, clock: SystemClock(), notifier: NoopChangeNotifier())
            try BackupService.export(database: database, to: backup)
            _ = try store.createCards([CardInput(stageIndex: 0, moduleKey: nil, front: "恢复前新增", back: "b", tags: nil)], source: "test")
            before = try database.pool.read { try Card.fetchCount($0) }
            try BackupService.scheduleRestore(from: backup, dbURL: dbURL)
            try database.pool.close()
        }
        #expect(FileManager.default.fileExists(atPath: dbURL.path + "-wal"))
        let pending = BackupService.pendingRestoreURL(for: dbURL)

        #expect(throws: MoveFailed.self) {
            try BackupService.applyPendingRestore(at: dbURL) { from, to in
                if from == pending { throw MoveFailed() }
                try FileManager.default.moveItem(at: from, to: to)
            }
        }

        // 原库与 -wal 已放回原处，恢复前新增的卡片还在；待恢复文件保留，下次启动再试
        #expect(!FileManager.default.fileExists(atPath: dbURL.path + ".pre-restore"))
        #expect(!FileManager.default.fileExists(atPath: dbURL.path + ".pre-restore-wal"))
        #expect(FileManager.default.fileExists(atPath: pending.path))
        #expect(try cardCount(dbURL) == before)
    }

    @Test func corruptPendingRestoreKeepsLiveDB() throws {
        let dir = makeTempDir()
        let dbURL = dir.appendingPathComponent("studyquest.sqlite")
        do {
            let store = try makeStore(at: dbURL)
            _ = try store.createCards([CardInput(stageIndex: 0, moduleKey: nil, front: "原有", back: "b", tags: nil)], source: "test")
        }
        let before = try cardCount(dbURL)
        let pending = dir.appendingPathComponent("restore-pending.sqlite")
        try Data("损坏的备份".utf8).write(to: pending)

        #expect(throws: (any Error).self) { try BackupService.applyPendingRestore(at: dbURL) }

        #expect(!FileManager.default.fileExists(atPath: pending.path))
        #expect(!FileManager.default.fileExists(atPath: dbURL.path + ".pre-restore"))
        #expect(try cardCount(dbURL) == before)
    }

    @Test func exportRefusesLiveDatabasePath() throws {
        let dir = makeTempDir()
        let dbURL = dir.appendingPathComponent("studyquest.sqlite")
        let database = try AppDatabase(url: dbURL)
        let store = try StudyStore(database: database, clock: SystemClock(), notifier: NoopChangeNotifier())
        _ = try store.createCards([CardInput(stageIndex: 0, moduleKey: nil, front: "f", back: "b", tags: nil)], source: "test")
        let before = try database.pool.read { try Card.fetchCount($0) }

        for target in [dbURL.path, dbURL.path + "-wal", dbURL.path + "-shm", dir.path + "/./studyquest.sqlite"] {
            #expect(throws: BackupError.destinationIsLiveDatabase) {
                try BackupService.export(database: database, to: URL(fileURLWithPath: target))
            }
        }
        #expect(try database.pool.read { try Card.fetchCount($0) } == before)
    }

    @Test func exportOverwritesExistingDestination() throws {
        let dir = makeTempDir()
        let database = try AppDatabase(url: dir.appendingPathComponent("studyquest.sqlite"))
        _ = try StudyStore(database: database, clock: SystemClock(), notifier: NoopChangeNotifier())
        let backup = dir.appendingPathComponent("backup.sqlite")
        try Data("旧内容".utf8).write(to: backup)

        try BackupService.export(database: database, to: backup)

        try BackupService.validate(backup: backup)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".tmp") }
        #expect(leftovers.isEmpty)
    }

    @Test func applyWithoutPendingRestoreLeavesDatabase() throws {
        let dir = makeTempDir()
        let dbURL = dir.appendingPathComponent("studyquest.sqlite")
        let store = try makeStore(at: dbURL)
        _ = try store.createCards([CardInput(stageIndex: 0, moduleKey: nil, front: "f", back: "b", tags: nil)], source: "test")
        let before = try cardCount(dbURL)

        try BackupService.applyPendingRestore(at: dbURL)

        #expect(try cardCount(dbURL) == before)
    }

    @Test func invalidBackupRejected() throws {
        let dir = makeTempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let text = dir.appendingPathComponent("notes.txt")
        try Data("这不是数据库".utf8).write(to: text)

        #expect(throws: (any Error).self) { try BackupService.validate(backup: text) }
        #expect(throws: (any Error).self) {
            try BackupService.scheduleRestore(from: text, dbURL: dir.appendingPathComponent("studyquest.sqlite"))
        }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("restore-pending.sqlite").path))
    }
}
