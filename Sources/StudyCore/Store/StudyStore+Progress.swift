import Foundation
import GRDB

public struct ProgressSummary: Codable, Sendable {
    public var currentStage: Int
    public var stageStatuses: [Int: StageStatus]
    public var xp: Int
    public var level: Int
    public var nextLevelXP: Int
    public var streak: Int
    public var xpToday: Int
}

extension StudyStore {
    /// 重复的 dedupKey 返回 false，不抛错，也不发通知。
    @discardableResult
    public func awardXP(dedupKey: String, amount: Int, reason: XPReason, day: Day) throws -> Bool {
        let now = clock.now()
        let inserted = try pool.write { try Self.insertXP($0, dedupKey: dedupKey, amount: amount, reason: reason, day: day, now: now) }
        if inserted { notifier.post() }
        return inserted
    }

    @discardableResult
    static func insertXP(_ db: Database, dedupKey: String, amount: Int, reason: XPReason, day: Day, now: Date) throws -> Bool {
        try db.execute(
            sql: """
                INSERT INTO xpEvent (dedupKey, amount, reason, day, createdAt)
                VALUES (?, ?, ?, ?, ?) ON CONFLICT(dedupKey) DO NOTHING
                """,
            arguments: [dedupKey, amount, reason.rawValue, day.rawValue, now])
        return db.changesCount > 0
    }

    public func totalXP() throws -> Int {
        try pool.read { try Int.fetchOne($0, sql: "SELECT COALESCE(SUM(amount), 0) FROM xpEvent") ?? 0 }
    }

    public func xp(on day: Day) throws -> Int {
        try pool.read {
            try Int.fetchOne($0, sql: "SELECT COALESCE(SUM(amount), 0) FROM xpEvent WHERE day = ?", arguments: [day.rawValue]) ?? 0
        }
    }

    /// 有"复习清零"或"作业完成"经验记录的日期。
    public func studyDays() throws -> Set<Day> {
        let raws = try pool.read {
            try String.fetchAll(
                $0, sql: "SELECT DISTINCT day FROM xpEvent WHERE reason IN (?, ?)",
                arguments: [XPReason.reviewCleared.rawValue, XPReason.assignmentCompleted.rawValue])
        }
        return Set(raws.compactMap { Day(rawValue: $0) })
    }

    public func progressSummary() throws -> ProgressSummary {
        let stages = try self.stages()
        let statuses = Dictionary(uniqueKeysWithValues: stages.map { ($0.index, $0.status) })
        let current: Int
        if let inProgress = stages.filter({ $0.status == .inProgress }).map(\.index).min() {
            current = inProgress
        } else if let passed = stages.filter({ $0.status == .passed }).map(\.index).max() {
            current = Swift.min(passed + 1, 9)
        } else {
            current = 0
        }
        let total = try totalXP()
        let today = clock.today()
        let level = XPRules.level(forXP: total)
        return ProgressSummary(
            currentStage: current,
            stageStatuses: statuses,
            xp: total,
            level: level,
            nextLevelXP: XPRules.xpForNextLevel(level),
            streak: XPRules.streak(studyDays: try studyDays(), today: today, calendar: clock.calendar),
            xpToday: try xp(on: today))
    }

    public func dailyNote(day: Day) throws -> DailyNote? {
        try pool.read { try DailyNote.fetchOne($0, key: day.rawValue) }
    }

    /// 同日覆盖保存；首次保存奖励 +5 经验（dedupKey `note:<day>`）。
    public func saveDailyNote(_ text: String) throws {
        let today = clock.today()
        let now = clock.now()
        try pool.write { db in
            try DailyNote(day: today, text: text).save(db)
            try Self.insertXP(db, dedupKey: "note:\(today.rawValue)", amount: XPRules.dailyNote, reason: .dailyNote, day: today, now: now)
        }
        notifier.post()
    }
}

// MARK: 每日自动生成记录

extension StudyStore {
    public func autoGenRun(day: Day) throws -> AutoGenRun? {
        try pool.read { try AutoGenRun.fetchOne($0, key: day.rawValue) }
    }

    /// 当天第一个调用者插入 "running" 记录并返回 true；已有记录返回 false。
    public func claimAutoGenRun(day: Day) throws -> Bool {
        let now = clock.now()
        let claimed = try pool.write { db -> Bool in
            try db.execute(
                sql: "INSERT INTO autoGenRun (day, status, errors, createdAt) VALUES (?, 'running', '[]', ?) ON CONFLICT(day) DO NOTHING",
                arguments: [day.rawValue, now])
            return db.changesCount > 0
        }
        if claimed { notifier.post() }
        return claimed
    }

    /// 无错误记为 "done"，否则 "failed"。记录不存在时插入（重试路径）。
    public func finishAutoGenRun(day: Day, errors: [String]) throws {
        let now = clock.now()
        try pool.write { db in
            var run = try AutoGenRun.fetchOne(db, key: day.rawValue)
                ?? AutoGenRun(day: day, status: "running", errors: [], createdAt: now)
            run.status = errors.isEmpty ? "done" : "failed"
            run.errors = errors
            try run.save(db)
        }
        notifier.post()
    }
}

// MARK: 服务商配置（API Key 不在这里，见 SecretStore）

extension StudyStore {
    public func providerConfigs() throws -> [ProviderConfig] {
        try pool.read { try ProviderConfig.order(Column("name"), Column("id")).fetchAll($0) }
    }

    public func saveProviderConfig(_ config: ProviderConfig) throws {
        try pool.write { try config.save($0) }
        notifier.post()
    }

    /// 同时清掉指向它的角色设置。
    public func deleteProviderConfig(id: String) throws {
        try pool.write { db in
            _ = try ProviderConfig.deleteOne(db, key: id)
            for key in [SettingKey.gradingProviderId, .generationProviderId] {
                try db.execute(
                    sql: "UPDATE appSetting SET value = ? WHERE key = ? AND value = ?",
                    arguments: [key.defaultValue, key.rawValue, id])
            }
        }
        notifier.post()
    }
}
