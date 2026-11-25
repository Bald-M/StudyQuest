import StudyCore
import SwiftUI

/// 把服务层错误转成给人看的一句话；不回显服务商响应体。
func userMessage(_ error: Error) -> String {
    switch error {
    case AIError.notConfigured: return "先在设置中配置 AI 服务商"
    case AIError.http(let status, _): return "AI 服务商返回错误（HTTP \(status)）"
    case AIError.refusal: return "AI 拒绝了这次请求"
    case AIError.truncated: return "AI 的回复被截断，请重试"
    case AIError.emptyResponse: return "AI 没有返回内容，请重试"
    case AIError.invalidJSON: return "AI 的回复格式不对，请重试"
    case StoreError.notFound(let what): return "找不到\(what)"
    case StoreError.invalid(let reason), StoreError.blocked(let reason): return reason
    default: return error.localizedDescription
    }
}

struct StageDetailView: View {
    let model: AppModel
    let stageIndex: Int

    @State private var detail: AppModel.StageDetail?
    @State private var loadError: String?
    /// 正在生成的任务：`assignment-<moduleId>`、`cards-<moduleId>` 或 `exam`。
    @State private var generating: String?
    @State private var errors: [String: String] = [:]
    @State private var moduleError: String?

    var body: some View {
        Group {
            if let detail {
                Form {
                    overview(detail.stage)
                    modulesSection(detail)
                    materialsSection(detail.modules)
                    examSection(detail)
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView(loadError ?? "加载中…", systemImage: "map")
            }
        }
        .navigationTitle(detail.map { "阶段 \($0.stage.index)：\($0.stage.title)" } ?? "阶段")
        .onAppear(perform: reload)
        .onChange(of: model.revision) { reload() }
    }

    // MARK: 简介与过关规则

    private func overview(_ stage: Stage) -> some View {
        Section {
            Text(stage.summary)
            LabeledContent("预计时间", value: stage.estimatedWeeks)
            LabeledContent("过关规则") {
                Text("总分 ≥ \(Int(stage.passLine))，每个分区 ≥ \(percent(stage.minSectionRatio))%，累积题占 \(percent(stage.cumulativeMin))%–\(percent(stage.cumulativeMax))%")
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("未通过后冷却", value: "\(stage.cooldownDays) 天")
            if let reward = stage.reward, !reward.isEmpty {
                LabeledContent("过关奖励", value: reward)
            }
        }
    }

    private func percent(_ ratio: Double) -> Int { Int((ratio * 100).rounded()) }

    // MARK: 模块

    private func modulesSection(_ detail: AppModel.StageDetail) -> some View {
        Section("模块") {
            ForEach(detail.modules) { module in
                moduleRow(module)
            }
            if let moduleError { Text(moduleError).font(.caption).foregroundStyle(.red) }
        }
    }

    private func moduleRow(_ module: Module) -> some View {
        let id = module.id ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(module.title).font(.headline)
                if module.needsRelearn {
                    Text("需重学").font(.caption.bold()).foregroundStyle(.red)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.red.opacity(0.12), in: Capsule())
                }
                Spacer()
                statusControl(module)
            }
            if !module.points.isEmpty {
                Text(module.points).font(.callout).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                generateButton("生成作业", key: "assignment-\(id)") { try await model.generateAssignment(moduleId: id) }
                generateButton("生成卡片", key: "cards-\(id)") { try await model.generateCards(moduleId: id) }
                if let message = errors["assignment-\(id)"] ?? errors["cards-\(id)"] {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private func statusControl(_ module: Module) -> some View {
        switch module.status {
        case .notStarted: Button("开始学习") { setStatus(module, .learning) }
        case .learning: Button("完成") { setStatus(module, .done) }
        case .done: Label("已完成", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }

    private func setStatus(_ module: Module, _ status: ModuleStatus) {
        guard let id = module.id else { return }
        do {
            try model.setModuleStatus(id: id, status)
            moduleError = nil
        } catch {
            moduleError = userMessage(error)
        }
    }

    // MARK: 资源、游戏任务、生活题（阶段级，各模块相同）

    @ViewBuilder private func materialsSection(_ modules: [Module]) -> some View {
        if let first = modules.first {
            if !first.resources.isEmpty { listSection("推荐资源", first.resources, icon: "book") }
            if !first.gameTasks.isEmpty { listSection("游戏任务", first.gameTasks, icon: "gamecontroller") }
            if !first.lifeProblems.isEmpty { listSection("生活题", first.lifeProblems, icon: "house") }
        }
    }

    private func listSection(_ title: String, _ items: [String], icon: String) -> some View {
        Section(title) {
            ForEach(items, id: \.self) { Label($0, systemImage: icon) }
        }
    }

    // MARK: 阶段考试

    private func gateText(_ detail: AppModel.StageDetail) -> String {
        switch detail.gate {
        case .open: "可以开考"
        case .coolingDown(let until): "冷却中，\(until.rawValue) 可再考"
        case .needsRelearn(let moduleId):
            "需先完成「\(detail.modules.first { $0.id == moduleId }?.title ?? "弱项模块")」的作业"
        case .locked: "未解锁：需先通过上一阶段的考试"
        case .alreadyPassed: "本阶段已通过"
        }
    }

    private func examSection(_ detail: AppModel.StageDetail) -> some View {
        Section("阶段考试（Boss）") {
            Label(gateText(detail), systemImage: detail.gate == .open ? "flame.fill" : "hourglass")
                .foregroundStyle(detail.gate == .open ? .red : .secondary)
            HStack {
                generateButton("生成阶段考试", key: "exam") { try await model.generateStageExam(stage: detail.stage.index) }
                if let message = errors["exam"] { Text(message).font(.caption).foregroundStyle(.red) }
            }
            ForEach(detail.exams) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(row.exam.title)
                        Spacer()
                        if row.attempts.isEmpty, row.exam.status == .ready {
                            Button("去考试") {
                                model.selectedExamId = row.exam.id
                                model.selection = .exams
                            }
                        }
                    }
                    ForEach(row.attempts) { attempt in
                        Text(attemptText(attempt)).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(row.exam.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                }
            }
        }
    }

    private func attemptText(_ attempt: Attempt) -> String {
        switch attempt.status {
        case .inProgress: "作答中"
        case .submitted: "已交卷，待判卷"
        case .graded:
            "\(Int((attempt.totalPercent ?? 0).rounded())) 分 · \(attempt.passed == true ? "通过" : "未通过")"
        }
    }

    // MARK: 生成按钮

    private func generateButton(_ title: String, key: String, work: @escaping () async throws -> Void) -> some View {
        HStack(spacing: 6) {
            Button(title) {
                generating = key
                errors[key] = nil
                Task {
                    do { try await work() } catch { errors[key] = userMessage(error) }
                    generating = nil
                }
            }
            .disabled(generating != nil)
            if generating == key { ProgressView().controlSize(.small) }
        }
    }

    private func reload() {
        do {
            detail = try model.stageDetail(stageIndex)
            loadError = nil
        } catch {
            loadError = userMessage(error)
        }
    }
}
