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
        let database = try AppDatabase(url: dbURL)
        let store = try StudyStore(database: database, clock: SystemClock(), notifier: NoopChangeNotifier())
        let exportedCards = try cardCount(dbURL)
        let backup = dir.appendingPathComponent("backup.sqlite")
        try BackupService.export(database: database, to: backup)

        _ = try store.createCards([CardInput(stageIndex: 0, moduleKey: nil, front: "新卡", back: "b", tags: nil)], source: "test")
        #expect(try cardCount(dbURL) == exportedCards + 1)

        try BackupService.scheduleRestore(from: backup, dbURL: dbURL)
        let pending = dir.appendingPathComponent("restore-pending.sqlite")
        #expect(FileManager.default.fileExists(atPath: pending.path))

        try BackupService.applyPendingRestore(at: dbURL)

        #expect(!FileManager.default.fileExists(atPath: pending.path))
        #expect(try cardCount(dbURL) == exportedCards)
        _ = try makeStore(at: dbURL)
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
