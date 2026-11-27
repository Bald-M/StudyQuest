import Foundation
import GRDB
import Testing
@testable import StudyCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func makeStore() throws -> StudyStore {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("studyquest-test-\(UUID().uuidString)")
    return try StudyStore(database: AppDatabase(url: dir.appendingPathComponent("test.sqlite")), clock: FixedClock(t0), notifier: NoopChangeNotifier())
}

private func sec(_ key: String, _ text: String? = nil, title: String? = nil) -> ParsedSection {
    ParsedSection(matchKey: key, chapterTitle: "章", title: title ?? key, text: text ?? "正文\(key)")
}

private func book(_ sections: [ParsedSection], title: String = "教材", kind: TextbookSourceKind = .markdownFile, assets: [String: Data] = [:], pdf: Data? = nil) -> ParsedTextbook {
    ParsedTextbook(title: title, sourceKind: kind, sections: sections, assets: assets, pdfData: pdf)
}

private func allSections(_ store: StudyStore, _ id: Int64) throws -> [TextbookSection] {
    try store.pool.read { try TextbookSection.filter(Column("textbookId") == id).order(Column("id")).fetchAll($0) }
}

@Suite struct TextbookSyncTests {
    @Test func unchangedKeepsEverything() throws {
        let store = try makeStore()
        let p = book([sec("a"), sec("b")])
        let id = try store.importTextbook(p, stageIndex: 0, sourcePath: "/x.md")
        let before = try allSections(store, id)
        let plan = try store.syncPreview(textbookId: id, parsed: p)
        #expect(plan == SyncPlan(unchanged: before.map { $0.id! }, changed: [], added: [], removed: [], newOrder: ["a", "b"]))
        try store.applySync(textbookId: id, parsed: p)
        #expect(try allSections(store, id) == before)
    }

    @Test func changedKeepsMasteryAndStalesChallenges() throws {
        let store = try makeStore()
        let id = try store.importTextbook(book([sec("a"), sec("b")]), stageIndex: 0, sourcePath: "")
        let a = try #require(try allSections(store, id).first)
        try store.pool.write { db in
            try db.execute(sql: "UPDATE textbookSection SET masteredAt = ?, moduleId = NULL WHERE id = ?", arguments: [t0, a.id])
            var c = SectionChallenge(sectionId: a.id!, problemIds: [], createdAt: t0, source: "x")
            try c.insert(db)
        }
        let p = ParsedTextbook(title: "新名", sourceKind: .markdownFile, sections: [ParsedSection(matchKey: "a", chapterTitle: "章", title: "a", text: "改了", pageStart: 3, pageEnd: 4), sec("b")])
        let plan = try store.syncPreview(textbookId: id, parsed: p)
        #expect(plan.changed == [a.id!])
        try store.applySync(textbookId: id, parsed: p)
        let after = try #require(try allSections(store, id).first)
        #expect(after.text == "改了" && after.textHash == SectionText.hash("改了"))
        #expect(after.pageStart == 3 && after.pageEnd == 4)
        #expect(after.masteredAt == t0)
        let stale = try store.pool.read { try SectionChallenge.fetchAll($0).map(\.stale) }
        #expect(stale == [true])
        #expect(try store.textbooks(stage: 0).first?.title == "新名")
    }

    @Test func addedAfterMasteredIsUnlocked() throws {
        let store = try makeStore()
        let id = try store.importTextbook(book([sec("a"), sec("b")]), stageIndex: 0, sourcePath: "")
        try store.pool.write { try $0.execute(sql: "UPDATE textbookSection SET masteredAt = ?", arguments: [t0]) }
        let p = book([sec("a"), sec("b"), sec("c")])
        #expect(try store.syncPreview(textbookId: id, parsed: p).added.map(\.matchKey) == ["c"])
        try store.applySync(textbookId: id, parsed: p)
        let rows = try store.sectionRows(textbookId: id)
        #expect(rows.map(\.state) == [.mastered, .mastered, .unlocked])
        #expect(rows[2].section.codeLevelsEnabled && rows[2].section.moduleId == nil && rows[2].section.order == 2)
    }

    @Test func removedIsHiddenAndQuestionsKept() throws {
        let store = try makeStore()
        let id = try store.importTextbook(book([sec("a"), sec("b")]), stageIndex: 0, sourcePath: "")
        let b = try #require(try allSections(store, id).last)
        try store.pool.write { db in
            try db.execute(sql: "UPDATE textbook SET lastSectionId = ? WHERE id = ?", arguments: [b.id, id])
            try db.execute(sql: "UPDATE problem SET sectionId = ? WHERE id = (SELECT MIN(id) FROM problem)", arguments: [b.id])
        }
        let problemsBefore = try store.pool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM problem") }
        let p = book([sec("a")])
        #expect(try store.syncPreview(textbookId: id, parsed: p).removed == [b.id!])
        try store.applySync(textbookId: id, parsed: p)
        #expect(try store.sectionRows(textbookId: id).map(\.section.matchKey) == ["a"])
        #expect(try store.section(id: b.id!).removedAt == t0)
        #expect(try store.origin(sectionId: b.id!)?.availability == .sectionRemoved)
        #expect(try store.textbooks(stage: 0).first?.lastSectionId == nil)
        #expect(try store.pool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM problem") } == problemsBefore)
        // already removed stays out of `removed`
        #expect(try store.syncPreview(textbookId: id, parsed: p).removed.isEmpty)
    }

    @Test func renamedTitleIsRemoveAndAdd() throws {
        let store = try makeStore()
        let id = try store.importTextbook(book([sec("旧名")]), stageIndex: 0, sourcePath: "")
        let old = try #require(try allSections(store, id).first)
        let plan = try store.syncPreview(textbookId: id, parsed: book([sec("新名")]))
        #expect(plan.removed == [old.id!] && plan.added.map(\.matchKey) == ["新名"] && plan.changed.isEmpty && plan.unchanged.isEmpty)
    }

    @Test func duplicateTitlesMatchByOrdinal() throws {
        let store = try makeStore()
        let id = try store.importTextbook(book([sec("概述#1", "甲"), sec("概述#2", "乙")]), stageIndex: 0, sourcePath: "")
        let ids = try allSections(store, id).map { $0.id! }
        let plan = try store.syncPreview(textbookId: id, parsed: book([sec("概述#1", "甲"), sec("概述#2", "乙改")]))
        #expect(plan.unchanged == [ids[0]] && plan.changed == [ids[1]] && plan.added.isEmpty && plan.removed.isEmpty)
    }

    @Test func reappearingSectionIsRestored() throws {
        let store = try makeStore()
        let id = try store.importTextbook(book([sec("a"), sec("b")]), stageIndex: 0, sourcePath: "")
        try store.applySync(textbookId: id, parsed: book([sec("a")]))
        let b = try #require(try allSections(store, id).last)
        #expect(b.removedAt != nil)
        let plan = try store.syncPreview(textbookId: id, parsed: book([sec("b"), sec("a")]))
        #expect(plan.unchanged.contains(b.id!) && plan.removed.isEmpty && plan.added.isEmpty)
        try store.applySync(textbookId: id, parsed: book([sec("b"), sec("a")]))
        #expect(try store.sectionRows(textbookId: id).map(\.section.matchKey) == ["b", "a"])
        #expect(try store.section(id: b.id!).removedAt == nil)
    }

    @Test func assetsAndPdfReplacedAndGuards() throws {
        let store = try makeStore()
        let md = try store.importTextbook(book([sec("a")], assets: ["old.png": Data([1])]), stageIndex: 0, sourcePath: "")
        try store.applySync(textbookId: md, parsed: book([sec("a")], assets: ["new.png": Data([2])]))
        #expect(try store.asset(textbookId: md, ref: "old.png") == nil)
        #expect(try store.asset(textbookId: md, ref: "new.png") == Data([2]))
        let pdf = try store.importTextbook(book([sec("a")], kind: .pdf, pdf: Data([1])), stageIndex: 0, sourcePath: "")
        try store.applySync(textbookId: pdf, parsed: book([sec("a")], kind: .pdf, pdf: Data([7, 7])))
        #expect(try store.pdfData(textbookId: pdf) == Data([7, 7]))
        #expect(throws: StoreError.invalid("没有可导入的内容")) { try store.applySync(textbookId: md, parsed: book([])) }
        #expect(throws: StoreError.invalid("没有可导入的内容")) { _ = try store.syncPreview(textbookId: md, parsed: book([])) }
        #expect(throws: StoreError.notFound("教材 999")) { _ = try store.syncPreview(textbookId: 999, parsed: book([sec("a")])) }
        try store.deleteTextbook(id: md)
        #expect(throws: StoreError.notFound("教材 \(md)")) { try store.applySync(textbookId: md, parsed: book([sec("a")])) }
    }
}
