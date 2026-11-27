import Foundation
import GRDB

public enum SectionState: Sendable { case locked, unlocked, mastered }

public struct SectionRow: Sendable {
    public var section: TextbookSection
    public var state: SectionState
    public init(section: TextbookSection, state: SectionState) { self.section = section; self.state = state }
}

public struct SectionOrigin: Equatable, Sendable {
    public enum Availability: Sendable { case available, sectionRemoved, textbookDeleted }
    public var textbookTitle: String
    public var sectionTitle: String
    public var textbookId: Int64
    public var sectionId: Int64
    public var availability: Availability
}

extension StudyStore {
    public func importTextbook(_ parsed: ParsedTextbook, stageIndex: Int, sourcePath: String) throws -> Int64 {
        guard !parsed.sections.isEmpty else { throw StoreError.invalid("没有可导入的内容") }
        let now = clock.now()
        let id: Int64 = try pool.write { db in
            guard try Stage.fetchOne(db, key: stageIndex) != nil else { throw StoreError.notFound("阶段 \(stageIndex)") }
            var book = Textbook(stageIndex: stageIndex, title: parsed.title, sourceKind: parsed.sourceKind, sourcePath: sourcePath, pdfData: parsed.pdfData, importedAt: now)
            try book.insert(db)
            let bookId = book.id!
            for (index, s) in parsed.sections.enumerated() {
                var section = TextbookSection(textbookId: bookId, matchKey: s.matchKey, chapterTitle: s.chapterTitle, title: s.title, order: index, text: s.text, textHash: SectionText.hash(s.text), pageStart: s.pageStart, pageEnd: s.pageEnd)
                try section.insert(db)
            }
            for (ref, data) in parsed.assets {
                var asset = TextbookAsset(textbookId: bookId, ref: ref, data: data)
                try asset.insert(db)
            }
            return bookId
        }
        notifier.post()
        return id
    }

    public func textbooks(stage: Int) throws -> [Textbook] {
        try pool.read {
            try Textbook.filter(Column("stageIndex") == stage && Column("deletedAt") == nil).order(Column("importedAt"), Column("id")).fetchAll($0)
        }
    }

    public func sectionRows(textbookId: Int64) throws -> [SectionRow] {
        let sections = try pool.read {
            try TextbookSection.filter(Column("textbookId") == textbookId && Column("removedAt") == nil).order(Column("order")).fetchAll($0)
        }
        var previousMastered = true
        return sections.map { section in
            let state: SectionState = section.masteredAt != nil ? .mastered : (previousMastered ? .unlocked : .locked)
            previousMastered = section.masteredAt != nil
            return SectionRow(section: section, state: state)
        }
    }

    public func section(id: Int64) throws -> TextbookSection {
        guard let section = try pool.read({ try TextbookSection.fetchOne($0, key: id) }) else { throw StoreError.notFound("章节 \(id)") }
        return section
    }

    public func asset(textbookId: Int64, ref: String) throws -> Data? {
        try pool.read {
            try TextbookAsset.filter(Column("textbookId") == textbookId && Column("ref") == ref).fetchOne($0)?.data
        }
    }

    public func setSectionModules(_ mapping: [Int64: Int64?]) throws {
        try pool.write { db in
            for (sectionId, moduleId) in mapping {
                guard var section = try TextbookSection.fetchOne(db, key: sectionId),
                      let book = try Textbook.fetchOne(db, key: section.textbookId) else { throw StoreError.notFound("章节 \(sectionId)") }
                if let moduleId {
                    guard let module = try Module.fetchOne(db, key: moduleId) else { throw StoreError.notFound("模块 \(moduleId)") }
                    guard module.stageIndex == book.stageIndex else { throw StoreError.invalid("模块不属于该阶段") }
                }
                section.moduleId = moduleId
                try section.update(db)
            }
        }
        notifier.post()
    }

    public func setLastRead(textbookId: Int64, sectionId: Int64) throws {
        try pool.write { db in
            guard var book = try Textbook.fetchOne(db, key: textbookId) else { throw StoreError.notFound("教材 \(textbookId)") }
            guard let section = try TextbookSection.fetchOne(db, key: sectionId), section.textbookId == textbookId else {
                throw StoreError.notFound("章节 \(sectionId)")
            }
            book.lastSectionId = sectionId
            try book.update(db)
        }
        notifier.post()
    }

    public func deleteTextbook(id: Int64) throws {
        let now = clock.now()
        try pool.write { db in
            guard var book = try Textbook.fetchOne(db, key: id) else { throw StoreError.notFound("教材 \(id)") }
            book.deletedAt = now
            try book.update(db)
        }
        notifier.post()
    }

    public func origin(sectionId: Int64) throws -> SectionOrigin? {
        try pool.read { db in
            guard let section = try TextbookSection.fetchOne(db, key: sectionId),
                  let book = try Textbook.fetchOne(db, key: section.textbookId) else { return nil }
            let availability: SectionOrigin.Availability = book.deletedAt != nil ? .textbookDeleted : (section.removedAt != nil ? .sectionRemoved : .available)
            return SectionOrigin(textbookTitle: book.title, sectionTitle: section.title, textbookId: section.textbookId, sectionId: sectionId, availability: availability)
        }
    }

    public func masteredCount(moduleId: Int64) throws -> (mastered: Int, total: Int) {
        try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT s.masteredAt IS NOT NULL AS m FROM textbookSection s
                JOIN textbook t ON t.id = s.textbookId
                WHERE s.moduleId = ? AND s.removedAt IS NULL AND t.deletedAt IS NULL
                """, arguments: [moduleId])
            return (rows.filter { $0["m"] as Bool }.count, rows.count)
        }
    }
}
