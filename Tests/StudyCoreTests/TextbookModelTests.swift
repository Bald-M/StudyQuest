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

    @Test func textbookRecordsRoundTrip() throws {
        let store = try makeStore()
        let pdf = Data([0x25, 0x50, 0x44, 0x46, 0x00, 0xFF])
        try store.pool.write { db in
            var book = Textbook(stageIndex: 0, title: "Git 教程", sourceKind: .pdf, sourcePath: "/tmp/git.pdf", pdfData: pdf, importedAt: t0)
            try book.insert(db)
            let bookId = try #require(book.id)
            var s1 = TextbookSection(textbookId: bookId, matchKey: "a/1", chapterTitle: "入门", title: "安装", order: 0, text: "正文一", textHash: "h1", pageStart: 1, pageEnd: 3)
            var s2 = TextbookSection(textbookId: bookId, matchKey: "a/2", chapterTitle: "入门", title: "提交", order: 1, text: "正文二", textHash: "h2")
            try s1.insert(db); try s2.insert(db)
            var asset = TextbookAsset(textbookId: bookId, ref: "img/a.png", data: Data([1, 2, 3]))
            try asset.insert(db)
            var challenge = SectionChallenge(sectionId: s1.id!, problemIds: [7, 8, 9], createdAt: t0, source: "app_ai")
            try challenge.insert(db)

            #expect(try Textbook.fetchOne(db, key: bookId) == book)
            #expect(try Textbook.fetchOne(db, key: bookId)?.pdfData == pdf)
            #expect(try TextbookSection.fetchAll(db).sorted { $0.order < $1.order } == [s1, s2])
            #expect(try TextbookAsset.fetchOne(db, key: asset.id!) == asset)
            let back = try #require(try SectionChallenge.fetchOne(db, key: challenge.id!))
            #expect(back.problemIds == [7, 8, 9])
            #expect(back == challenge)
        }
    }
}
