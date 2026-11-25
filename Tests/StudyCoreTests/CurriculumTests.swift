import Foundation
import GRDB
import Testing
@testable import StudyCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func makeStore(clock: FixedClock = FixedClock(t0), url: URL? = nil) throws -> (StudyStore, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("studyquest-test-\(UUID().uuidString)")
    let url = url ?? dir.appendingPathComponent("test.sqlite")
    let store = try StudyStore(database: AppDatabase(url: url), clock: clock, notifier: NoopChangeNotifier())
    return (store, url)
}

private final class CountingNotifier: ChangeNotifier, @unchecked Sendable {
    var count = 0
    func post() { count += 1 }
}

@Suite struct CurriculumTests {
    @Test func seedCreatesTenStagesOnce() throws {
        let (store, url) = try makeStore()
        #expect(try store.stages().count == 10)
        let (again, _) = try makeStore(url: url)
        #expect(try again.stages().count == 10)
        #expect(try again.modules(stage: 0).count == 4)
    }

    @Test func seedValuesMatchSpec() throws {
        let (store, _) = try makeStore()
        let stages = try store.stages()
        #expect(stages.map(\.passLine) == [80, 80, 75, 80, 80, 80, 80, 75, 85, 80])
        #expect(stages[0].status == .inProgress)
        #expect(stages.dropFirst().allSatisfy { $0.status == .locked })
        #expect(stages.allSatisfy { $0.cooldownDays == 3 && $0.minSectionRatio == 0.6
            && $0.cumulativeMin == 0.2 && $0.cumulativeMax == 0.3 })
    }

    @Test func modulesMatchAppendixA() throws {
        let (store, _) = try makeStore()
        let mods = try store.modules(stage: 2)
        #expect(mods.count == 14)
        #expect(mods.first?.title == "复杂度分析")
        #expect(mods.last?.title == "动态规划入门")
        var keys = Set<String>()
        for stage in try store.stages() {
            for m in try store.modules(stage: stage.index) { keys.insert(m.key) }
        }
        let total = try store.stages().reduce(0) { $0 + (try store.modules(stage: $1.index).count) }
        #expect(keys.count == total)
        #expect(try store.module(key: "s2.hash")?.stageIndex == 2)
    }

    @Test func stageZeroHasSamples() throws {
        let clock = FixedClock(t0)
        let (store, _) = try makeStore(clock: clock)
        let (cards, problems) = try store.pool.read { db in
            (try Card.filter(Column("stageIndex") == 0).fetchAll(db), try Problem.filter(Column("stageIndex") == 0).fetchAll(db))
        }
        #expect(cards.count >= 5)
        #expect(problems.count >= 5)
        for kind in [ProblemKind.singleChoice, .shortAnswer, .coding] {
            #expect(problems.contains { $0.kind == kind })
        }
        #expect(problems.allSatisfy { $0.source == "seed" && $0.moduleId != nil })
        #expect(cards.allSatisfy { $0.step == nil && $0.dueDay == clock.today() && $0.moduleId != nil })
    }

    @Test func moduleStatusTransitions() throws {
        let clock = FixedClock(t0)
        let notifier = CountingNotifier()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("studyquest-test-\(UUID().uuidString)")
        let store = try StudyStore(database: AppDatabase(url: dir.appendingPathComponent("t.sqlite")), clock: clock, notifier: notifier)
        let id = try #require(try store.module(key: "s0.git")?.id)
        try store.setModuleStatus(id: id, .learning)
        #expect(try store.learningModules().map(\.id) == [id])
        #expect(try store.module(id: id).startedAt == t0)
        #expect(try store.modulesStudiedThisWeek().map(\.id) == [id])
        try store.setModuleStatus(id: id, .done)
        #expect(try store.learningModules().isEmpty)
        #expect(try store.module(id: id).completedAt == t0)
        #expect(notifier.count == 2)
        clock.current = t0.addingTimeInterval(8 * 24 * 3600)
        #expect(try store.modulesStudiedThisWeek().isEmpty)
        #expect(throws: StoreError.notFound("模块 9999")) { try store.module(id: 9999) }
    }

    @Test func stageSettingsUpdate() throws {
        let (store, _) = try makeStore()
        try store.updateStageSettings(index: 1, passLine: 90, cooldownDays: nil, reward: "吃顿好的")
        let s = try store.stage(1)
        #expect(s.passLine == 90 && s.cooldownDays == 3 && s.reward == "吃顿好的")
    }

    @Test func cooldownOutOfRangeRejected() throws {
        let (store, _) = try makeStore()
        #expect(throws: StoreError.invalid("冷却期必须在 3 到 7 天之间")) {
            try store.updateStageSettings(index: 0, passLine: nil, cooldownDays: 8, reward: nil)
        }
        #expect(try store.stage(0).cooldownDays == 3)
    }
}
