import Foundation
import GRDB
import Testing
@testable import StudyCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func makeStore() throws -> StudyStore {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("studyquest-test-\(UUID().uuidString)")
    return try StudyStore(database: AppDatabase(url: dir.appendingPathComponent("test.sqlite")), clock: FixedClock(t0), notifier: NoopChangeNotifier())
}

private func parsed(count: Int = 3, kind: TextbookSourceKind = .markdownFile, pdf: Data? = nil, assets: [String: Data] = [:]) -> ParsedTextbook {
    ParsedTextbook(title: "教材", sourceKind: kind,
                   sections: (0..<count).map { ParsedSection(matchKey: "k\($0)", chapterTitle: "章", title: "节\($0)", text: "正文\($0)") },
                   assets: assets, pdfData: pdf)
}

@Suite struct TextbookStoreTests {
    @Test func importStoresEverything() throws {
        let store = try makeStore()
        let img = Data([1, 2, 3])
        let pdf = Data([9, 9])
        let id = try store.importTextbook(parsed(kind: .pdf, pdf: pdf, assets: ["a/b.png": img]), stageIndex: 0, sourcePath: "/x.pdf")
        let rows = try store.sectionRows(textbookId: id)
        #expect(rows.map(\.section.title) == ["节0", "节1", "节2"])
        #expect(rows.map(\.section.order) == [0, 1, 2])
        #expect(rows[1].section.textHash == SectionText.hash("正文1"))
        #expect(try store.asset(textbookId: id, ref: "a/b.png") == img)
        #expect(try store.asset(textbookId: id, ref: "nope") == nil)
        let book = try #require(try store.textbooks(stage: 0).first)
        #expect(book.pdfData == pdf)
        #expect(book.sourcePath == "/x.pdf")
        #expect(throws: StoreError.notFound("阶段 99")) { try store.importTextbook(parsed(), stageIndex: 99, sourcePath: "") }
        #expect(throws: StoreError.invalid("没有可导入的内容")) { try store.importTextbook(parsed(count: 0), stageIndex: 0, sourcePath: "") }
    }

    @Test func stateDerivesFromPreviousMastered() throws {
        let store = try makeStore()
        let id = try store.importTextbook(parsed(), stageIndex: 0, sourcePath: "")
        #expect(try store.sectionRows(textbookId: id).map(\.state) == [.unlocked, .locked, .locked])
        let first = try #require(try store.sectionRows(textbookId: id).first?.section.id)
        try store.pool.write { try $0.execute(sql: "UPDATE textbookSection SET masteredAt = ? WHERE id = ?", arguments: [t0, first]) }
        #expect(try store.sectionRows(textbookId: id).map(\.state) == [.mastered, .unlocked, .locked])
    }

    @Test func moduleMappingDoesNotTouchModuleStatus() throws {
        let store = try makeStore()
        let id = try store.importTextbook(parsed(count: 1), stageIndex: 0, sourcePath: "")
        let sid = try #require(try store.sectionRows(textbookId: id).first?.section.id)
        let module = try #require(try store.modules(stage: 0).first)
        let mid = try #require(module.id)
        try store.setSectionModules([sid: mid])
        #expect(try store.module(id: mid).status == module.status)
        let counts = try store.masteredCount(moduleId: mid)
        #expect(counts.mastered == 0 && counts.total == 1)
        let other = try #require(try store.modules(stage: 1).first?.id)
        #expect(throws: StoreError.invalid("模块不属于该阶段")) { try store.setSectionModules([sid: other]) }
        #expect(throws: StoreError.notFound("章节 9999")) { try store.setSectionModules([9999: mid]) }
        try store.setSectionModules([sid: nil])
        #expect(try store.section(id: sid).moduleId == nil)
    }

    @Test func lastReadOnlyAcceptsOwnSection() throws {
        let store = try makeStore()
        let a = try store.importTextbook(parsed(count: 1), stageIndex: 0, sourcePath: "")
        let b = try store.importTextbook(parsed(count: 1), stageIndex: 0, sourcePath: "")
        let sb = try #require(try store.sectionRows(textbookId: b).first?.section.id)
        #expect(throws: StoreError.self) { try store.setLastRead(textbookId: a, sectionId: sb) }
        try store.setLastRead(textbookId: b, sectionId: sb)
        #expect(try store.textbooks(stage: 0).first { $0.id == b }?.lastSectionId == sb)
    }

    @Test func deletedTextbookIsHiddenButOriginsRemain() throws {
        let store = try makeStore()
        let id = try store.importTextbook(parsed(count: 1), stageIndex: 0, sourcePath: "")
        let sid = try #require(try store.sectionRows(textbookId: id).first?.section.id)
        try store.pool.write { db in
            var p = Problem(stageIndex: 0, kind: .shortAnswer, prompt: "q", options: [], referenceAnswer: "a", rubric: "r", maxScore: 1, difficulty: .medium, tags: [], source: "t", createdAt: t0, sectionId: sid)
            try p.insert(db)
        }
        #expect(try store.origin(sectionId: sid)?.availability == .available)
        try store.deleteTextbook(id: id)
        #expect(try store.textbooks(stage: 0).isEmpty)
        let origin = try #require(try store.origin(sectionId: sid))
        #expect(origin.availability == .textbookDeleted)
        #expect(origin.textbookTitle == "教材" && origin.sectionTitle == "节0")
        #expect(try store.pool.read { try Problem.filter(Column("sectionId") == sid).fetchCount($0) } == 1)
        #expect(try store.origin(sectionId: 12345) == nil)
        #expect(try store.masteredCount(moduleId: 1).total == 0)
    }
}
