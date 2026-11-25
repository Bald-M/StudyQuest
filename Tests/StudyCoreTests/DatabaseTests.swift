import Foundation
import GRDB
import Testing
@testable import StudyCore

private func makeTempDB() throws -> (AppDatabase, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("studyquest-test-\(UUID().uuidString)")
    let url = dir.appendingPathComponent("test.sqlite")
    return (try AppDatabase(url: url), url)
}

private func writeSettings(_ db: AppDatabase, prefix: String) async throws {
    for i in 0..<200 {
        try await db.pool.write { try AppSetting(key: "\(prefix)\(i)", value: "v").insert($0) }
    }
}

@Suite struct DatabaseTests {
    @Test func migrationCreatesAllTables() throws {
        let (db, _) = try makeTempDB()
        let tables = try db.pool.read { try String.fetchAll($0, sql: "SELECT name FROM sqlite_master WHERE type = 'table'") }
        for name in ["stage", "module", "card", "cardReview", "problem", "assignment", "exam", "examSection",
                     "attempt", "attemptAnswer", "questionGrade", "mistake", "mockInterview", "xpEvent",
                     "dailyNote", "autoGenRun", "appSetting", "providerConfig"] {
            #expect(tables.contains(name), "缺少表 \(name)")
        }
    }

    @Test func recordsRoundTrip() throws {
        let (db, _) = try makeTempDB()
        var problem = Problem(
            id: nil, stageIndex: 2, moduleId: nil, kind: .multipleChoice, prompt: "哈希冲突如何解决？",
            options: ["链地址法", "开放寻址"], referenceAnswer: "A,B", rubric: "全对满分", maxScore: 10,
            difficulty: .medium, tags: ["hash"], source: "test", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        try db.pool.write { try problem.insert($0) }
        #expect(problem.id != nil)
        let loaded = try db.pool.read { try Problem.fetchOne($0, key: problem.id!) }
        #expect(loaded == problem)

        let card = Card(id: nil, stageIndex: 1, moduleId: nil, front: "f", back: "b", tags: ["t"], step: nil,
                        dueDay: Day(rawValue: "2026-11-25")!, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        var c = card
        try db.pool.write { try c.insert($0) }
        let due = try db.pool.read {
            try String.fetchOne($0, sql: "SELECT dueDay FROM card WHERE id = ?", arguments: [c.id])
        }
        #expect(due == "2026-11-25")
    }

    @Test func xpDedupKeyIsUnique() throws {
        let (db, _) = try makeTempDB()
        let day = Day(rawValue: "2026-11-25")!
        func event() -> XPEvent {
            XPEvent(id: nil, dedupKey: "problem:1", amount: 10, reason: .problem, day: day, createdAt: Date())
        }
        try db.pool.write { var e = event(); try e.insert($0) }
        #expect(throws: (any Error).self) {
            try db.pool.write { var e = event(); try e.insert($0) }
        }
    }

    @Test func openMistakeIsUniquePerProblem() throws {
        let (db, _) = try makeTempDB()
        let day = Day(rawValue: "2026-11-25")!
        func mistake(graduated: Bool) -> Mistake {
            Mistake(id: nil, problemId: 7, sourceAttemptId: 1, step: 0, streak: 0, dueDay: day,
                    graduated: graduated, createdAt: Date())
        }
        try db.pool.write { var m = mistake(graduated: true); try m.insert($0) }
        try db.pool.write { var m = mistake(graduated: false); try m.insert($0) }
        #expect(throws: (any Error).self) {
            try db.pool.write { var m = mistake(graduated: false); try m.insert($0) }
        }
    }

    @Test func concurrentWritersFromTwoPools() async throws {
        let (db1, url) = try makeTempDB()
        let db2 = try AppDatabase(url: url)
        async let a: Void = writeSettings(db1, prefix: "a")
        async let b: Void = writeSettings(db2, prefix: "b")
        try await a
        try await b
        let count = try await db1.pool.read { try AppSetting.fetchCount($0) }
        #expect(count == 400)
    }
}
