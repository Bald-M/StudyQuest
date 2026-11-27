import Foundation
import GRDB
import Testing
@testable import StudyCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func makeStore() throws -> StudyStore {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("studyquest-test-\(UUID().uuidString)")
    return try StudyStore(database: AppDatabase(url: dir.appendingPathComponent("test.sqlite")), clock: FixedClock(t0), notifier: NoopChangeNotifier())
}

private func importBook(_ store: StudyStore, texts: [String]) throws -> [Int64] {
    let parsed = ParsedTextbook(title: "Git 入门", sourceKind: .markdownFile,
                                sections: texts.enumerated().map { ParsedSection(matchKey: "k\($0.offset)", chapterTitle: "第一章", title: "节\($0.offset)", text: $0.element) })
    let id = try store.importTextbook(parsed, stageIndex: 0, sourcePath: "")
    return try store.sectionRows(textbookId: id).map { $0.section.id! }
}

private func problemJSON(_ i: Int) -> String {
    #"{"stageIndex": 0, "moduleKey": null, "kind": "shortAnswer", "prompt": "题\#(i)", "referenceAnswer": "参考", "rubric": "评分", "maxScore": 10, "difficulty": "easy"}"#
}

private func reply(problems: Int = 5, points: Int? = 3) -> String {
    let ps = (1...max(problems, 1)).prefix(problems).map(problemJSON).joined(separator: ",")
    let kp = points.map { n in
        #","knowledgePoints": [\#((0..<n).map { #"{"front": "问\#($0)", "back": "答\#($0)"}"# }.joined(separator: ","))]"#
    } ?? ""
    return #"{"title": "闯关", "problems": [\#(ps)]\#(kp)}"#
}

private func counts(_ store: StudyStore) throws -> [Int] {
    try store.pool.read { db in
        try ["sectionChallenge", "problem", "card"].map { try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \($0)")! }
    }
}

private func markMastered(_ store: StudyStore, _ id: Int64) throws {
    try store.pool.write { try $0.execute(sql: "UPDATE textbookSection SET masteredAt = ? WHERE id = ?", arguments: [t0, id]) }
}

private func schemaHasKnowledgePoints(_ request: ChatRequest) -> Bool {
    guard case .object(let root)? = request.jsonSchema, case .object(let props)? = root["properties"] else { return false }
    return props["knowledgePoints"] != nil
}

@Suite struct SectionChallengeServiceTests {
    @Test func promptCarriesSectionTextAndLimit() async throws {
        let store = try makeStore()
        let sid = try importBook(store, texts: [String(repeating: "甲", count: SectionText.aiLimit) + String(repeating: "乙", count: 5_000)])[0]
        let model = FakeModel([.text(reply())])
        let result = try await SectionChallengeService(store: store, model: { model }).prepareChallenge(sectionId: sid)
        #expect(result.truncated)
        let prompt = model.requests[0].messages[0].content
        #expect(prompt.contains(String(repeating: "甲", count: SectionText.aiLimit)))
        #expect(!prompt.contains("乙"))
        #expect(prompt.contains("<正文>") && prompt.contains("</正文>"))
        #expect(prompt.contains("Git 入门") && prompt.contains("节0"))
        #expect(prompt.contains("只根据下面的正文出题，不要考正文没有讲到的内容"))
        #expect(prompt.contains("knowledgePoints"))
        #expect(schemaHasKnowledgePoints(model.requests[0]))
        #expect(try store.latestChallenge(sectionId: sid)?.id == result.challengeId)
        #expect(try store.hasSectionCards(sectionId: sid))
    }

    @Test func shortTextIsNotTruncated() async throws {
        let store = try makeStore()
        let sid = try importBook(store, texts: ["短正文"])[0]
        let model = FakeModel([.text(reply())])
        let result = try await SectionChallengeService(store: store, model: { model }).prepareChallenge(sectionId: sid)
        #expect(!result.truncated)
    }

    @Test func cardsOnlyFirstTime() async throws {
        let store = try makeStore()
        let sid = try importBook(store, texts: ["正文"])[0]
        let baseCards = try counts(store)[2]
        let model = FakeModel([.text(reply()), .text(reply(points: nil))])
        let service = SectionChallengeService(store: store, model: { model })
        _ = try await service.prepareChallenge(sectionId: sid)
        let cardsAfterFirst = try counts(store)[2]
        #expect(cardsAfterFirst == baseCards + 3)
        // 没过线，需要再生成一个
        let first = try #require(try store.latestChallenge(sectionId: sid))
        let attempt = try store.startSectionChallenge(challengeId: first.id!)
        try store.submit(attemptId: attempt.id!)
        for p in try store.pendingGrading(attemptId: attempt.id!) {
            try store.recordGrade(attemptId: attempt.id!, problemId: p.id!, score: 0, feedback: "", mistakes: [], grader: "test", raw: "")
        }
        #expect(try store.challengeNeedsGeneration(sectionId: sid))
        _ = try await service.prepareChallenge(sectionId: sid)
        #expect(model.calls == 2)
        #expect(!schemaHasKnowledgePoints(model.requests[1]))
        #expect(!model.requests[1].messages[0].content.contains("knowledgePoints"))
        #expect(try counts(store)[2] == cardsAfterFirst)
    }

    @Test func wrongCountGetsOneFix() async throws {
        let store = try makeStore()
        let sid = try importBook(store, texts: ["正文"])[0]
        let model = FakeModel([.text(reply(problems: 4)), .text(reply())])
        _ = try await SectionChallengeService(store: store, model: { model }).prepareChallenge(sectionId: sid)
        #expect(model.calls == 2)
        #expect(model.requests[1].messages.last?.content.contains("题目数量应为 5 道，实际 4 道") == true)
        #expect(try store.latestChallenge(sectionId: sid)?.problemIds.count == 5)
    }

    @Test func badKnowledgePointCountIsRejected() async throws {
        let store = try makeStore()
        let sid = try importBook(store, texts: ["正文"])[0]
        let before = try counts(store)
        let model = FakeModel([.text(reply(points: 2)), .text(reply(points: 9))])
        await #expect(throws: StoreError.self) {
            _ = try await SectionChallengeService(store: store, model: { model }).prepareChallenge(sectionId: sid)
        }
        #expect(try counts(store) == before)
    }

    @Test func noProviderLeavesNothingBehind() async throws {
        let store = try makeStore()
        let sid = try importBook(store, texts: ["正文"])[0]
        let before = try counts(store)
        await #expect(throws: AIError.notConfigured("generation")) {
            _ = try await SectionChallengeService(store: store, model: { throw AIError.notConfigured("generation") }).prepareChallenge(sectionId: sid)
        }
        #expect(try counts(store) == before)
    }

    @Test func masteredSectionDoesNotCallAI() async throws {
        let store = try makeStore()
        let sid = try importBook(store, texts: ["正文"])[0]
        let cid = try store.createSectionChallenge(sectionId: sid, problems: (0..<5).map { _ in
            ProblemInput(stageIndex: 0, moduleKey: nil, kind: .shortAnswer, prompt: "题", options: nil, referenceAnswer: "答", rubric: "", maxScore: 10, difficulty: .easy, tags: nil)
        }, cards: [], source: "test")
        try markMastered(store, sid)
        let model = FakeModel([])
        let result = try await SectionChallengeService(store: store, model: { model }).prepareChallenge(sectionId: sid)
        #expect(result.challengeId == cid && !result.truncated)
        #expect(model.calls == 0)
    }

    @Test func blankSectionIsRejectedBeforeAI() async throws {
        let store = try makeStore()
        let sid = try importBook(store, texts: [" \n\t "])[0]
        let model = FakeModel([.text(reply())])
        let before = try counts(store)
        await #expect(throws: StoreError.invalid("这一节没有可提取的文字，无法出题")) {
            try await SectionChallengeService(store: store, model: { model }).prepareChallenge(sectionId: sid)
        }
        #expect(model.requests.isEmpty)
        #expect(try counts(store) == before)
    }

    @Test func challengeFlowDoesNotReadPdfData() async throws {
        let store = try makeStore()
        let parsed = ParsedTextbook(title: "书", sourceKind: .pdf,
                                    sections: [ParsedSection(matchKey: "k", chapterTitle: "章", title: "节", text: "正文", pageStart: 0, pageEnd: 0)],
                                    pdfData: Data([1]))
        let id = try store.importTextbook(parsed, stageIndex: 0, sourcePath: "")
        let sid = try #require(try store.sectionRows(textbookId: id).first?.section.id)
        let reads = try FullTextbookReads(store)
        let model = FakeModel([.text(reply()), .text(#"{"mappings": []}"#)])
        let service = SectionChallengeService(store: store, model: { model })
        let result = try await service.prepareChallenge(sectionId: sid)
        #expect(result.challengeId > 0)
        let suggested = try await service.suggestModules(textbookId: id)
        #expect(suggested.count == 1 && suggested[sid] == .some(nil))
        // 闯关结算也不读 pdfData
        let attempt = try store.startSectionChallenge(challengeId: result.challengeId)
        try store.submit(attemptId: attempt.id!)
        for p in try store.pendingGrading(attemptId: attempt.id!) {
            try store.recordGrade(attemptId: attempt.id!, problemId: p.id!, score: 10, feedback: "", mistakes: [], grader: "test", raw: "")
        }
        #expect(try store.attemptDetail(id: attempt.id!).attempt.passed == true)
        #expect(try store.section(id: sid).masteredAt == t0)
        #expect(reads.all.isEmpty, "\(reads.all)")
    }

    @Test func suggestModulesSendsTitlesOnly() async throws {
        let store = try makeStore()
        let ids = try importBook(store, texts: ["绝密正文甲", "绝密正文乙", "绝密正文丙"])
        let git = try #require(try store.module(key: "s0.git"))
        let json = #"{"mappings": [{"sectionId": \#(ids[0]), "moduleKey": "s0.git"}, {"sectionId": \#(ids[1]), "moduleKey": "no.such"}, {"sectionId": 99999, "moduleKey": "s0.git"}]}"#
        let model = FakeModel([.text(json)])
        let book = try #require(try store.textbooks(stage: 0).first)
        let result = try await SectionChallengeService(store: store, model: { model }).suggestModules(textbookId: book.id!)
        let prompt = model.requests[0].messages[0].content
        #expect(!prompt.contains("绝密"))
        #expect(prompt.contains("\(ids[0]). 第一章 / 节0"))
        #expect(prompt.contains("s0.git（\(git.title)）"))
        #expect(result.count == 3)
        #expect(result[ids[0]] == .some("s0.git"))
        #expect(result[ids[1]] == .some(nil))
        #expect(result[ids[2]] == .some(nil))
        #expect(result[99999] == nil)
        #expect(try store.sectionRows(textbookId: book.id!).allSatisfy { $0.section.moduleId == nil })
    }

    @Test func problemsArePinnedToSectionStageAndModule() async throws {
        let store = try makeStore()
        let sid = try importBook(store, texts: ["正文"])[0]
        let git = try #require(try store.module(key: "s0.git"))
        try store.setSectionModules([sid: git.id!])
        let model = FakeModel([.text(reply())])
        let result = try await SectionChallengeService(store: store, model: { model }).prepareChallenge(sectionId: sid)
        let problems = try store.problems(ids: try #require(try store.latestChallenge(sectionId: sid)).problemIds)
        #expect(problems.allSatisfy { $0.moduleId == git.id })
        #expect(model.requests[0].messages[0].content.contains(git.title))
        #expect(result.challengeId > 0)
    }
}
