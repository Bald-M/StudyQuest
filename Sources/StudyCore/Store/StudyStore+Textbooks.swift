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

/// 教材列表一行：不含 pdf 数据与正文，阶段详情每次刷新都会读。
public struct TextbookSummary: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var title: String
    public var sourceKind: TextbookSourceKind
    public var sourcePath: String
    public var mastered: Int
    public var total: Int
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

    /// 未删除教材及其未移除节的掌握数；不读 pdfData 与正文。
    public func textbookSummaries(stage: Int) throws -> [TextbookSummary] {
        try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT t.id, t.title, t.sourceKind, t.sourcePath,
                       COUNT(s.id) AS total, COUNT(s.masteredAt) AS mastered
                FROM textbook t
                LEFT JOIN textbookSection s ON s.textbookId = t.id AND s.removedAt IS NULL
                WHERE t.stageIndex = ? AND t.deletedAt IS NULL
                GROUP BY t.id
                ORDER BY t.importedAt, t.id
                """, arguments: [stage]).map {
                TextbookSummary(id: $0["id"], title: $0["title"], sourceKind: $0["sourceKind"], sourcePath: $0["sourcePath"], mastered: $0["mastered"], total: $0["total"])
            }
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

    /// 不读 pdfData（总是 nil）；已删除的教材也返回，由调用方看 `deletedAt`。
    public func textbook(id: Int64) throws -> Textbook? {
        try pool.read {
            try Textbook.select(Column("id"), Column("stageIndex"), Column("title"), Column("sourceKind"), Column("sourcePath"),
                                Column("language"), Column("lastSectionId"), Column("importedAt"), Column("deletedAt"))
                .filter(key: id).fetchOne($0)
        }
    }

    public func pdfData(textbookId: Int64) throws -> Data? {
        try pool.read { try Data.fetchOne($0, sql: "SELECT pdfData FROM textbook WHERE id = ?", arguments: [textbookId]) }
    }

    public func assetRefs(textbookId: Int64) throws -> [String] {
        try pool.read { try String.fetchAll($0, sql: "SELECT ref FROM textbookAsset WHERE textbookId = ? ORDER BY ref", arguments: [textbookId]) }
    }

    /// 闯关所属的节；闯关不存在时返回 nil。
    public func section(challengeId: Int64) throws -> TextbookSection? {
        try pool.read { db in
            guard let challenge = try SectionChallenge.fetchOne(db, key: challengeId) else { return nil }
            return try TextbookSection.fetchOne(db, key: challenge.sectionId)
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

    public func syncPreview(textbookId: Int64, parsed: ParsedTextbook) throws -> SyncPlan {
        guard !parsed.sections.isEmpty else { throw StoreError.invalid("没有可导入的内容") }
        return try pool.read { db in
            guard let book = try Textbook.fetchOne(db, key: textbookId), book.deletedAt == nil else { throw StoreError.notFound("教材 \(textbookId)") }
            let existing = try TextbookSection.filter(Column("textbookId") == textbookId).order(Column("order"), Column("id")).fetchAll(db)
            return TextbookSync.plan(existing: existing, parsed: parsed.sections)
        }
    }

    /// `sourcePath` 非 nil 时（用户重新选择了原文件位置）在同一事务里一并保存。
    public func applySync(textbookId: Int64, parsed: ParsedTextbook, sourcePath: String? = nil) throws {
        guard !parsed.sections.isEmpty else { throw StoreError.invalid("没有可导入的内容") }
        let now = clock.now()
        try pool.write { db in
            guard var book = try Textbook.fetchOne(db, key: textbookId), book.deletedAt == nil else { throw StoreError.notFound("教材 \(textbookId)") }
            let existing = try TextbookSection.filter(Column("textbookId") == textbookId).order(Column("order"), Column("id")).fetchAll(db)
            let plan = TextbookSync.plan(existing: existing, parsed: parsed.sections)
            var parsedByKey: [String: ParsedSection] = [:]
            for s in parsed.sections where parsedByKey[s.matchKey] == nil { parsedByKey[s.matchKey] = s }
            let changedIds = Set(plan.changed), removedIds = Set(plan.removed)
            var idByKey: [String: Int64] = [:]
            for var section in existing {
                guard let id = section.id else { continue }
                if removedIds.contains(id) {
                    section.removedAt = now
                } else if let new = parsedByKey[section.matchKey] {
                    section.removedAt = nil
                    section.chapterTitle = new.chapterTitle
                    section.title = new.title
                    section.pageStart = new.pageStart
                    section.pageEnd = new.pageEnd
                    if changedIds.contains(id) {
                        section.text = new.text
                        section.textHash = SectionText.hash(new.text)
                        try db.execute(sql: "UPDATE sectionChallenge SET stale = 1 WHERE sectionId = ?", arguments: [id])
                    }
                    idByKey[section.matchKey] = id
                }
                try section.update(db)
            }
            for new in plan.added {
                var section = TextbookSection(textbookId: textbookId, matchKey: new.matchKey, chapterTitle: new.chapterTitle, title: new.title, order: 0, text: new.text, textHash: SectionText.hash(new.text), pageStart: new.pageStart, pageEnd: new.pageEnd)
                try section.insert(db)
                idByKey[new.matchKey] = section.id!
            }
            for (index, key) in plan.newOrder.enumerated() {
                guard let id = idByKey[key] else { continue }
                try db.execute(sql: "UPDATE textbookSection SET \"order\" = ? WHERE id = ?", arguments: [index, id])
            }
            if parsed.sourceKind == .pdf {
                book.pdfData = parsed.pdfData
            } else {
                try TextbookAsset.filter(Column("textbookId") == textbookId).deleteAll(db)
                for (ref, data) in parsed.assets {
                    var asset = TextbookAsset(textbookId: textbookId, ref: ref, data: data)
                    try asset.insert(db)
                }
            }
            book.title = parsed.title
            if let sourcePath { book.sourcePath = sourcePath }
            if let last = book.lastSectionId, removedIds.contains(last) { book.lastSectionId = nil }
            try book.update(db)
        }
        notifier.post()
    }

    // MARK: 章节闯关

    /// 一个写事务里插入本节的题目、卡片（sectionId 指向本节）和闯关记录。
    public func createSectionChallenge(sectionId: Int64, problems: [ProblemInput], cards: [CardInput], source: String) throws -> Int64 {
        let (stages, modules) = try catalog()
        var errors = problems.isEmpty ? ["闯关至少需要 1 道题"] : []
        errors += problems.flatMap { ContentValidator.validate($0, stages: stages, modules: modules) }
        errors += cards.flatMap { ContentValidator.validate($0, stages: stages, modules: modules) }
        try Self.require(errors)
        let now = clock.now()
        let today = clock.today()
        let id = try pool.write { db -> Int64 in
            guard try TextbookSection.exists(db, key: sectionId) else { throw StoreError.notFound("章节 \(sectionId)") }
            let problemIds = try Self.insertProblems(problems, source: source, modules: modules, now: now, sectionId: sectionId, db: db)
            for input in cards {
                var card = Card(
                    stageIndex: input.stageIndex, moduleId: Self.moduleId(input.moduleKey, in: modules),
                    front: input.front, back: input.back, tags: input.tags ?? [], step: nil, dueDay: today, createdAt: now,
                    sectionId: sectionId)
                try card.insert(db)
            }
            var challenge = SectionChallenge(sectionId: sectionId, problemIds: problemIds, createdAt: now, source: source)
            try challenge.insert(db)
            return challenge.id!
        }
        notifier.post()
        return id
    }

    /// 最新一个未过期的闯关。
    public func latestChallenge(sectionId: Int64) throws -> SectionChallenge? {
        try pool.read { try Self.latestChallenge($0, sectionId: sectionId) }
    }

    public func hasSectionCards(sectionId: Int64) throws -> Bool {
        try pool.read { try Card.filter(Column("sectionId") == sectionId).fetchCount($0) > 0 }
    }

    /// 没有可用的闯关，或节未掌握且最新闯关最近一次已判卷的作答没过线时，需要生成新闯关。
    public func challengeNeedsGeneration(sectionId: Int64) throws -> Bool {
        try pool.read { db in
            guard let challenge = try Self.latestChallenge(db, sectionId: sectionId) else { return true }
            guard try TextbookSection.fetchOne(db, key: sectionId)?.masteredAt == nil else { return false }
            let lastGraded = try Attempt.filter(
                Column("sectionChallengeId") == challenge.id! && Column("status") == AttemptStatus.graded.rawValue
            ).order(Column("gradedAt").desc, Column("id").desc).fetchOne(db)
            return lastGraded?.passed == false
        }
    }

    /// 阶段未解锁或闯关已过期时拒绝；同一闯关有未判完的作答时直接返回它。
    public func startSectionChallenge(challengeId: Int64) throws -> Attempt {
        let now = clock.now()
        let attempt = try pool.write { db -> Attempt in
            guard let challenge = try SectionChallenge.fetchOne(db, key: challengeId) else { throw StoreError.notFound("闯关 \(challengeId)") }
            guard !challenge.stale else { throw StoreError.invalid("本节内容已更新，请重新闯关") }
            guard let section = try TextbookSection.fetchOne(db, key: challenge.sectionId),
                  let book = try Textbook.fetchOne(db, key: section.textbookId) else { throw StoreError.notFound("章节 \(challenge.sectionId)") }
            guard let stage = try Stage.fetchOne(db, key: book.stageIndex) else { throw StoreError.notFound("阶段 \(book.stageIndex)") }
            guard stage.status != .locked else { throw StoreError.blocked("该阶段尚未解锁，可以先阅读，解锁后再闯关") }
            if let open = try Attempt.filter(
                Column("sectionChallengeId") == challengeId
                    && [AttemptStatus.inProgress.rawValue, AttemptStatus.submitted.rawValue].contains(Column("status"))
            ).order(Column("id").desc).fetchOne(db) {
                return open
            }
            var attempt = Attempt(kind: .section, status: .inProgress, startedAt: now, sectionChallengeId: challengeId)
            try attempt.insert(db)
            return attempt
        }
        notifier.post()
        return attempt
    }

    private static func latestChallenge(_ db: Database, sectionId: Int64) throws -> SectionChallenge? {
        try SectionChallenge.filter(Column("sectionId") == sectionId && Column("stale") == false)
            .order(Column("createdAt").desc, Column("id").desc).fetchOne(db)
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
