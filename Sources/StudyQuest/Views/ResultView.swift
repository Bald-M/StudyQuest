import StudyCore
import SwiftUI

/// 交卷后的结果：总分与是否通过、各分区得分与最低线、逐题答案/得分/反馈/判卷模型、复判、
/// 未通过时的"回城修炼"与错因分析，以及阶段考试通过时的奖励弹窗。
/// 参考答案由 `attemptDetail` 在作答中隐藏，这里只显示它给出的内容。
struct ResultView: View {
    let model: AppModel
    let detail: AttemptDetail
    /// 还没有成绩的题数。
    let pending: Int
    let regrading: Bool
    let onRegrade: () -> Void
    /// 复判后通知上层重新读取。
    let onChanged: () -> Void

    @State private var context = AppModel.ResultContext()
    @State private var regradingProblem: Int64?
    @State private var regradeErrors: [Int64: String] = [:]
    @State private var reflection = ""
    @State private var reflectionLoaded = false
    @State private var reflectionNote: String?
    @State private var rewardShown = false
    @State private var showReward = false

    private var attempt: Attempt { detail.attempt }
    private var isExam: Bool { attempt.kind == .exam }
    private var busy: Bool { regrading || regradingProblem != nil }
    private var failed: Bool { pending == 0 && isExam && attempt.passed == false }
    private var rewardText: String {
        guard let stage = context.stage else { return "" }
        if let reward = stage.reward, !reward.isEmpty { return reward }
        return "恭喜通过阶段 \(stage.index)：\(stage.title)！"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            summary
            if isExam, pending == 0 { sectionsBox }
            if failed { retreatBox }
            ForEach(Array(detail.items.enumerated()), id: \.element.problem.id) { offset, item in
                itemView(number: offset + 1, item)
            }
        }
        .onAppear(perform: loadContext)
        .onChange(of: detail.attempt) { loadContext() }
        .alert("阶段通过", isPresented: $showReward) {
            Button("好的") {}
        } message: {
            Text(rewardText)
        }
    }

    private func loadContext() {
        context = (try? model.resultContext(attempt: attempt)) ?? AppModel.ResultContext()
        if !reflectionLoaded {
            reflection = attempt.reflection ?? ""
            reflectionLoaded = true
        }
        // 只有通过的阶段考试才弹；每次作答在本次界面会话中只弹一次
        if !rewardShown, pending == 0, attempt.passed == true, context.exam?.kind == .stageExam {
            rewardShown = true
            showReward = true
        }
    }

    // MARK: 总分

    @ViewBuilder private var summary: some View {
        GroupBox {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                if pending == 0, let percent = attempt.totalPercent {
                    Text("\(Int(percent.rounded())) 分").font(.largeTitle.bold())
                    if let passed = attempt.passed {
                        Label(passed ? "通过" : "未通过", systemImage: passed ? "checkmark.seal.fill" : "xmark.seal.fill")
                            .foregroundStyle(passed ? .green : .red)
                    }
                    if let stage = context.stage, let exam = context.exam {
                        Text("过关线 \(Int(exam.kind == .stageExam ? stage.passLine : 75)) 分").foregroundStyle(.secondary)
                    }
                } else {
                    Label("待判卷（还有 \(pending) 题没有成绩）", systemImage: "hourglass").font(.title3)
                    Button("重新判卷", action: onRegrade).disabled(busy)
                    if regrading { ProgressView().controlSize(.small) }
                }
                Spacer()
            }
            .padding(4)
        }
    }

    // MARK: 分区

    private var sectionsBox: some View {
        let floor = (context.stage?.minSectionRatio ?? 0.6) * 100
        return GroupBox("分区得分（每区不低于 \(Int(floor.rounded()))%）") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(detail.sections.enumerated()), id: \.offset) { _, section in
                    let ok = section.percent >= floor
                    HStack {
                        Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(ok ? .green : .red)
                        Text(section.title)
                        Spacer()
                        Text("\(format(section.earned)) / \(format(section.max)) · \(Int(section.percent.rounded()))%")
                            .monospacedDigit().foregroundStyle(ok ? Color.secondary : Color.red)
                    }
                }
            }
            .padding(4)
        }
    }

    // MARK: 回城修炼

    private var retreatBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("回城修炼", systemImage: "house.fill").font(.title3.bold()).foregroundStyle(.red)
                if case .coolingDown(let until)? = context.gate {
                    Text("冷却到 \(until.rawValue)，之后可以重考。先补弱项，再写下这次失分的原因。")
                } else {
                    Text("先补弱项，再写下这次失分的原因。")
                }
                Text("错因分析").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $reflection)
                    .font(.body).frame(minHeight: 100)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                HStack {
                    Button("保存") { saveReflection() }
                    if let reflectionNote { Text(reflectionNote).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .padding(4)
        }
    }

    private func saveReflection() {
        guard let id = attempt.id else { return }
        do {
            try model.saveReflection(attemptId: id, text: reflection)
            reflectionNote = "已保存"
        } catch {
            reflectionNote = userMessage(error)
        }
    }

    // MARK: 逐题

    private func itemView(number: Int, _ item: AttemptDetail.Item) -> some View {
        let grade = item.grades.last
        let problemId = item.problem.id ?? 0
        return GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("第 \(number) 题").font(.headline)
                    Spacer()
                    if let grade {
                        Text("\(format(grade.score)) / \(format(grade.maxScore))").font(.headline)
                    } else {
                        Text("待判卷").foregroundStyle(.orange)
                    }
                }
                Text(item.problem.prompt).textSelection(.enabled)
                labeled("你的答案", item.answer.flatMap { $0.isEmpty ? nil : $0 } ?? "（未作答）", mono: item.problem.kind == .coding)
                if let grade {
                    if !grade.feedback.isEmpty { labeled("反馈", grade.feedback) }
                    ForEach(grade.mistakes, id: \.self) { Text("• \($0)").font(.callout).foregroundStyle(.red) }
                    Text("判卷模型：\(grade.grader)").font(.caption).foregroundStyle(.secondary)
                    if !grade.raw.isEmpty {
                        DisclosureGroup("原始判卷返回") {
                            Text(grade.raw).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    HStack {
                        Button("申请复判") { Task { await regrade(problemId) } }.disabled(busy)
                        if regradingProblem == problemId { ProgressView().controlSize(.small) }
                    }
                    if let message = regradeErrors[problemId] { Text(message).font(.caption).foregroundStyle(.red) }
                }
                if !item.problem.referenceAnswer.isEmpty {
                    DisclosureGroup("参考答案") {
                        Text(item.problem.referenceAnswer).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(4)
        }
    }

    private func regrade(_ problemId: Int64) async {
        guard let id = attempt.id else { return }
        regradingProblem = problemId
        regradeErrors[problemId] = nil
        defer { regradingProblem = nil }
        do {
            try await model.regrade(attemptId: id, problemId: problemId)
        } catch {
            regradeErrors[problemId] = userMessage(error)
        }
        onChanged()
    }

    private func labeled(_ title: String, _ text: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(text).font(mono ? .system(.body, design: .monospaced) : .body).textSelection(.enabled)
        }
    }

    private func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
