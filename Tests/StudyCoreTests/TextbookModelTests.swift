import Foundation
import GRDB
import Testing
@testable import StudyCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func makeStore() throws -> StudyStore {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("studyquest-test-\(UUID().uuidString)")
    return try StudyStore(database: AppDatabase(url: dir.appendingPathComponent("test.sqlite")), clock: FixedClock(t0), notifier: NoopChangeNotifier())
}

@Suite struct TextbookModelTests {
    @Test func migrationV2AddsTablesAndColumns() throws {
        let store = try makeStore()
        try store.pool.read { db in
            for table in ["textbook", "textbookSection", "textbookAsset", "sectionChallenge"] {
                #expect(try db.tableExists(table), "缺少表 \(table)")
            }
            #expect(try db.columns(in: "problem").contains { $0.name == "sectionId" })
            #expect(try db.columns(in: "card").contains { $0.name == "sectionId" })
            #expect(try db.columns(in: "attempt").contains { $0.name == "sectionChallengeId" })
            #expect(try db.indexes(on: "problem").contains { $0.columns == ["sectionId"] })
            #expect(try db.indexes(on: "card").contains { $0.columns == ["sectionId"] })
            let problems = try Problem.fetchAll(db)
            #expect(!problems.isEmpty)
            #expect(problems.allSatisfy { $0.sectionId == nil })
        }
    }

    /// v3 把 pdf 原文件挪进单独的表：改教材行的小字段（如阅读位置）时不再连带重写几十 MB 的 pdf。
    @Test func migrationV3MovesPdfOutOfTextbookRow() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("studyquest-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: dir.appendingPathComponent("v2.sqlite").path)
        try Migrations.make().migrate(queue, upTo: "v2")
        let pdf = Data([0x25, 0x50, 0x44, 0x46, 9, 9])
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO textbook (stageIndex, title, sourceKind, sourcePath, pdfData, importedAt) VALUES
                (0, 'P', 'pdf', '/p.pdf', ?, ?), (0, 'M', 'markdownFile', '/m.md', NULL, ?)
                """, arguments: [pdf, t0, t0])
        }
        try Migrations.make().migrate(queue)
        let (columns, moved, pdfRows, books) = try queue.read { db in
            (try db.columns(in: "textbook").map(\.name),
             try Data.fetchOne(db, sql: "SELECT data FROM textbookPdf WHERE textbookId = 1"),
             try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM textbookPdf"),
             try Textbook.fetchCount(db))
        }
        #expect(!columns.contains("pdfData"))
        #expect(moved == pdf)
        #expect(pdfRows == 1)
        #expect(books == 2)
    }

    @Test func textbookRecordsRoundTrip() throws {
        let store = try makeStore()
        let pdf = Data([0x25, 0x50, 0x44, 0x46, 0x00, 0xFF])
        try store.pool.write { db in
            var book = Textbook(stageIndex: 0, title: "Git 教程", sourceKind: .pdf, sourcePath: "/tmp/git.pdf", importedAt: t0)
            try book.insert(db)
            let bookId = try #require(book.id)
            try TextbookPdf(textbookId: bookId, data: pdf).insert(db)
            var s1 = TextbookSection(textbookId: bookId, matchKey: "a/1", chapterTitle: "入门", title: "安装", order: 0, text: "正文一", textHash: "h1", pageStart: 1, pageEnd: 3)
            var s2 = TextbookSection(textbookId: bookId, matchKey: "a/2", chapterTitle: "入门", title: "提交", order: 1, text: "正文二", textHash: "h2")
            try s1.insert(db); try s2.insert(db)
            var asset = TextbookAsset(textbookId: bookId, ref: "img/a.png", data: Data([1, 2, 3]))
            try asset.insert(db)
            var challenge = SectionChallenge(sectionId: s1.id!, problemIds: [7, 8, 9], createdAt: t0, source: "app_ai")
            try challenge.insert(db)

            #expect(try Textbook.fetchOne(db, key: bookId) == book)
            #expect(try TextbookPdf.fetchOne(db, key: bookId)?.data == pdf)
            #expect(try TextbookSection.fetchAll(db).sorted { $0.order < $1.order } == [s1, s2])
            #expect(try TextbookAsset.fetchOne(db, key: asset.id!) == asset)
            let back = try #require(try SectionChallenge.fetchOne(db, key: challenge.id!))
            #expect(back.problemIds == [7, 8, 9])
            #expect(back == challenge)
        }
    }
}
