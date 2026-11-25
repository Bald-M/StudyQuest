import Foundation

/// 每日自动生成需要的出题能力；`GenerationService` 是唯一的真实实现，测试用假实现。
public protocol ContentGenerating {
    func generateAssignment(moduleId: Int64, size: Int) async throws -> Int64
    func generateWeeklyQuiz() async throws -> Int64
}

extension GenerationService: ContentGenerating {}

public enum AutoGenStatus: Equatable, Sendable {
    case disabled, notConfigured, running, done
    case failed([String])
}

/// 每天第一次打开时自动出作业（和周日的周测）。靠数据库里的"当天记录"保证同一天只做一轮。
public final class AutoGenerator {
    private let store: StudyStore
    private let generation: ContentGenerating
    private let isConfigured: () -> Bool

    public init(store: StudyStore, generation: ContentGenerating, isConfigured: @escaping () -> Bool) {
        self.store = store
        self.generation = generation
        self.isConfigured = isConfigured
    }

    public func runIfNeeded() async -> AutoGenStatus {
        do {
            guard try store.setting(.autoGenEnabled) == "true" else { return .disabled }
            guard isConfigured() else { return .notConfigured }
            let today = store.clock.today()
            guard try store.claimAutoGenRun(day: today) else {
                return try store.autoGenRun(day: today).map(Self.status) ?? .running
            }
            return try await generateAndRecord(day: today, countExisting: false)
        } catch {
            return .failed([error.localizedDescription])
        }
    }

    /// 只补当天还缺的部分，不看当天记录，结果覆盖当天记录。
    public func retry() async -> AutoGenStatus {
        do {
            return try await generateAndRecord(day: store.clock.today(), countExisting: true)
        } catch {
            return .failed([error.localizedDescription])
        }
    }

    // MARK: 内部

    private func generateAndRecord(day: Day, countExisting: Bool) async throws -> AutoGenStatus {
        let errors = await generateMissing(day: day, countExisting: countExisting)
        try store.finishAutoGenRun(day: day, errors: errors)
        return errors.isEmpty ? .done : .failed(errors)
    }

    /// `countExisting`：重试时当天已有的作业占用每日上限，避免重试后总数超过上限。
    private func generateMissing(day: Day, countExisting: Bool) async -> [String] {
        var errors: [String] = []
        do {
            let size = Int(try store.setting(.assignmentSize)) ?? 5
            let existing = try store.assignments(day: day)
            let done = Set(existing.compactMap(\.moduleId))
            let cap = Int(try store.setting(.autoGenDailyMax)) ?? 3
            let budget = max(0, cap - (countExisting ? existing.count : 0))
            let pending = try store.learningModules().filter { !done.contains($0.id!) }.prefix(budget)
            for module in pending {
                do {
                    _ = try await generation.generateAssignment(moduleId: module.id!, size: size)
                } catch {
                    errors.append("作业「\(module.title)」：\(error.localizedDescription)")
                }
            }
            if day.isSunday(calendar: store.clock.calendar), try !hasWeeklyQuiz(since: day.startOfWeek(calendar: store.clock.calendar)) {
                do {
                    _ = try await generation.generateWeeklyQuiz()
                } catch {
                    errors.append("周测：\(error.localizedDescription)")
                }
            }
        } catch {
            errors.append(error.localizedDescription)
        }
        return errors
    }

    private func hasWeeklyQuiz(since weekStart: Day) throws -> Bool {
        let calendar = store.clock.calendar
        return try store.exams(stage: nil).contains {
            $0.kind == .weeklyQuiz && Day.of($0.createdAt, calendar: calendar) >= weekStart
        }
    }

    /// 当天记录对应的状态；MCP 的 get_today 也用它。
    public static func status(of run: AutoGenRun) -> AutoGenStatus {
        switch run.status {
        case "done": .done
        case "failed": .failed(run.errors)
        default: .running
        }
    }
}
