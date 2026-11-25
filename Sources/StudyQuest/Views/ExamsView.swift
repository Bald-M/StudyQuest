import StudyCore
import SwiftUI

/// 考试页：按阶段分组的试卷（状态、警告）、草稿的确认上线与丢弃、开考前确认、被门槛挡住时的原因，以及模拟面试入口。
struct ExamsView: View {
    let model: AppModel

    @State private var groups: [AppModel.ExamGroup] = []
    @State private var interviews: [MockInterview] = []
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var confirming: Confirmation?
    @State private var highlighted: Int64?
    @State private var interviewTarget: InterviewTarget?
    @State private var discarding: AppModel.StageExamRow?

    struct Confirmation: Identifiable {
        var group: AppModel.ExamGroup
        var row: AppModel.StageExamRow
        var id: Int64 { row.id }
    }

    struct InterviewTarget: Identifiable {
        /// nil 表示新面试。
        var id: Int64?
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                if let actionError { Text(actionError).foregroundStyle(.red) }
                if groups.isEmpty {
                    Section {
                        Text(loadError ?? "还没有试卷。在阶段详情里生成阶段考试，或让 Claude Code 录入。").foregroundStyle(.secondary)
                    }
                }
                ForEach(groups) { group in
                    Section("阶段 \(group.stage.index)：\(group.stage.title)") {
                        ForEach(group.rows) { row in
                            examRow(group, row)
                                .id(row.id)
                                .padding(4)
                                .background(highlighted == row.id ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                interviewSection
            }
            .formStyle(.grouped)
            .onAppear { reload(); focusSelected(proxy) }
            .onChange(of: model.revision) { reload() }
            .onChange(of: model.selectedExamId) { focusSelected(proxy) }
        }
        .navigationTitle("考试")
        .sheet(item: $confirming) { confirmation in
            StartConfirmation(group: confirmation.group, row: confirmation.row) { start(confirmation.row) }
        }
        .sheet(item: $interviewTarget) { target in
            InterviewView(model: model, interviewId: target.id)
        }
        .confirmationDialog("丢弃这份草稿试卷？",
                            isPresented: Binding(get: { discarding != nil }, set: { if !$0 { discarding = nil } }),
                            presenting: discarding) { row in
            Button("丢弃", role: .destructive) { perform { try model.discardExam(id: row.id) } }
            Button("取消", role: .cancel) {}
        } message: { row in
            Text("「\(row.exam.title)」会被删除，无法恢复。")
        }
    }

    // MARK: 试卷

    private func examRow(_ group: AppModel.ExamGroup, _ row: AppModel.StageExamRow) -> some View {
        let attempt = row.attempts.first
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.exam.title).font(.headline)
                if !row.exam.warnings.isEmpty { Text("⚠️").help(row.exam.warnings.joined(separator: "\n")) }
                Text(row.exam.kind == .stageExam ? "阶段考试" : "周测").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(statusText(row.exam, attempt)).foregroundStyle(.secondary)
                action(group, row, attempt)
            }
            Text("限时 \(row.exam.timeLimitMinutes) 分钟").font(.caption).foregroundStyle(.secondary)
            ForEach(row.exam.warnings, id: \.self) { Text("⚠️ \($0)").font(.caption).foregroundStyle(.orange) }
        }
    }

    @ViewBuilder private func action(_ group: AppModel.ExamGroup, _ row: AppModel.StageExamRow, _ attempt: Attempt?) -> some View {
        if let attempt {
            Button(attempt.status == .inProgress ? "继续作答" : "查看结果") { open(row) }
        } else if row.exam.status == .draft {
            Button("确认上线") { perform { try model.confirmExam(id: row.id) } }
            Button("丢弃", role: .destructive) { discarding = row }
        } else if row.exam.status == .ready {
            Button("开考…") { confirming = Confirmation(group: group, row: row) }
        }
    }

    private func statusText(_ exam: Exam, _ attempt: Attempt?) -> String {
        guard let attempt else { return exam.status == .ready ? "未开考" : "草稿" }
        switch attempt.status {
        case .inProgress: return "作答中"
        case .submitted: return "已交卷，待判卷"
        case .graded: return "\(NumberText.whole(attempt.totalPercent ?? 0)) 分 · \(attempt.passed == true ? "通过" : "未通过")"
        }
    }

    private func perform(_ body: () throws -> Void) {
        do {
            try body()
            actionError = nil
        } catch {
            actionError = userMessage(error)
        }
        reload()
    }

    private func start(_ row: AppModel.StageExamRow) {
        confirming = nil
        open(row)
    }

    private func open(_ row: AppModel.StageExamRow) {
        do {
            try model.openExam(id: row.id)
            actionError = nil
            highlighted = nil
            model.selectedExamId = nil
        } catch {
            actionError = userMessage(error)
        }
        reload()
    }

    // MARK: 模拟面试

    private var interviewSection: some View {
        Section("模拟面试") {
            let scored = interviews.compactMap(\.score).prefix(3)
            HStack {
                Button("开始新面试") { interviewTarget = InterviewTarget(id: nil) }
                Spacer()
                // 阶段 9 只认最近 3 场的平均分，不足 3 场记 0
                if scored.count < 3 {
                    Text("还需 \(3 - scored.count) 场模拟面试才计分").foregroundStyle(.secondary)
                } else {
                    Text("最近 \(scored.count) 场平均 \(NumberText.whole(scored.reduce(0, +) / Double(scored.count))) 分")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(interviews) { interview in
                Button {
                    interviewTarget = InterviewTarget(id: interview.id)
                } label: {
                    HStack {
                        Text(interview.createdAt.formatted(date: .abbreviated, time: .shortened))
                        Spacer()
                        Text(interview.score.map { "\(NumberText.whole($0)) 分" } ?? "未打分").foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 加载与定位

    private func reload() {
        do {
            groups = try model.examGroups()
            interviews = try model.mockInterviews()
            loadError = nil
        } catch {
            loadError = userMessage(error)
        }
    }

    /// 今日或阶段详情点进来的试卷：滚动到并高亮几秒。
    private func focusSelected(_ proxy: ScrollViewProxy) {
        guard let id = model.selectedExamId else { return }
        highlighted = id
        withAnimation { proxy.scrollTo(id, anchor: .center) }
        Task {
            try? await Task.sleep(for: .seconds(3))
            if highlighted == id { highlighted = nil }
            if model.selectedExamId == id { model.selectedExamId = nil }
        }
    }
}

/// 开考前确认：限时与规则；门槛没开时给出原因并禁用开考。
private struct StartConfirmation: View {
    let group: AppModel.ExamGroup
    let row: AppModel.StageExamRow
    let onStart: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var blockedReason: String? {
        row.exam.kind == .stageExam && group.gate != .open ? gateDescription(group.gate, modules: group.modules) : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(row.exam.title).font(.title2.bold())
            Label("限时 \(row.exam.timeLimitMinutes) 分钟，开考后立即计时，不能暂停", systemImage: "timer")
            Label(passRule, systemImage: "checkmark.seal")
            Label("考试中不提供提示；时间到会自动交卷", systemImage: "lightbulb.slash")
            Label("每张试卷只能作答一次", systemImage: "1.circle")
            if row.exam.kind == .stageExam {
                Label("未通过后冷却 \(group.stage.cooldownDays) 天才能重考", systemImage: "hourglass")
            }
            ForEach(row.exam.warnings, id: \.self) { Text("⚠️ \($0)").font(.callout).foregroundStyle(.orange) }
            if let blockedReason {
                Label(blockedReason, systemImage: "lock.fill").foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("开始考试", action: onStart)
                    .buttonStyle(.borderedProminent)
                    .disabled(blockedReason != nil)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private var passRule: String {
        guard row.exam.kind == .stageExam else { return "总分 ≥ 75 分才算通过" }
        let section = NumberText.whole(group.stage.minSectionRatio * 100)
        return "总分 ≥ \(NumberText.whole(group.stage.passLine)) 分且每个分区 ≥ \(section)% 才算通过"
    }
}
