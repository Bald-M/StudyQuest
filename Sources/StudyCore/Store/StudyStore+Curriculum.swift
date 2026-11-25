import Foundation
import GRDB

extension StudyStore {
    public func stages() throws -> [Stage] {
        try pool.read { try Stage.order(Column("index")).fetchAll($0) }
    }

    public func stage(_ index: Int) throws -> Stage {
        guard let stage = try pool.read({ try Stage.fetchOne($0, key: index) }) else {
            throw StoreError.notFound("阶段 \(index)")
        }
        return stage
    }

    public func modules(stage: Int) throws -> [Module] {
        try pool.read { try Module.filter(Column("stageIndex") == stage).order(Column("order")).fetchAll($0) }
    }

    public func module(key: String) throws -> Module? {
        try pool.read { try Module.filter(Column("key") == key).fetchOne($0) }
    }

    public func module(id: Int64) throws -> Module {
        guard let module = try pool.read({ try Module.fetchOne($0, key: id) }) else {
            throw StoreError.notFound("模块 \(id)")
        }
        return module
    }

    public func setModuleStatus(id: Int64, _ status: ModuleStatus) throws {
        let now = clock.now()
        try pool.write { db in
            guard var module = try Module.fetchOne(db, key: id) else { throw StoreError.notFound("模块 \(id)") }
            module.status = status
            switch status {
            case .learning: module.startedAt = now
            case .done: module.completedAt = now
            case .notStarted: break
            }
            try module.update(db)
        }
        notifier.post()
    }

    public func learningModules() throws -> [Module] {
        try pool.read {
            try Module.filter(Column("status") == ModuleStatus.learning.rawValue)
                .order(Column("startedAt"), Column("id")).fetchAll($0)
        }
    }

    public func modulesStudiedThisWeek() throws -> [Module] {
        // 最近 7 天开始或完成的模块，以及最近 7 天有题目被判卷的模块。
        let cutoff = clock.now().addingTimeInterval(-7 * 24 * 3600)
        return try pool.read {
            try Module.filter(
                sql: """
                    startedAt >= :cutoff OR completedAt >= :cutoff OR id IN (
                        SELECT problem.moduleId FROM questionGrade JOIN problem ON problem.id = questionGrade.problemId
                        WHERE questionGrade.createdAt >= :cutoff AND problem.moduleId IS NOT NULL)
                    """,
                arguments: ["cutoff": cutoff])
                .order(Column("stageIndex"), Column("order")).fetchAll($0)
        }
    }

    public func updateStageSettings(index: Int, passLine: Double?, cooldownDays: Int?, reward: String?) throws {
        if let cooldownDays, !(3...7).contains(cooldownDays) {
            throw StoreError.invalid("冷却期必须在 3 到 7 天之间")
        }
        try pool.write { db in
            guard var stage = try Stage.fetchOne(db, key: index) else { throw StoreError.notFound("阶段 \(index)") }
            if let passLine { stage.passLine = passLine }
            if let cooldownDays { stage.cooldownDays = cooldownDays }
            if let reward { stage.reward = reward }
            try stage.update(db)
        }
        notifier.post()
    }
}
