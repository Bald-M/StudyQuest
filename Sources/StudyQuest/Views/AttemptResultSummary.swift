import StudyCore
import SwiftUI

/// 交卷后的简单结果：总分、是否通过、逐题得分与反馈。Task 17 的 ResultView 可替换或扩展它。
struct AttemptResultSummary: View {
    let detail: AttemptDetail
    /// 还没有成绩的题数。
    let pending: Int
    let regrading: Bool
    let onRegrade: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            summary
            ForEach(Array(detail.items.enumerated()), id: \.element.problem.id) { offset, item in
                itemView(number: offset + 1, item)
            }
        }
    }

    @ViewBuilder private var summary: some View {
        GroupBox {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                if pending == 0, let percent = detail.attempt.totalPercent {
                    Text("\(Int(percent.rounded())) 分").font(.largeTitle.bold())
                    if let passed = detail.attempt.passed {
                        Label(passed ? "通过" : "未通过", systemImage: passed ? "checkmark.seal.fill" : "xmark.seal.fill")
                            .foregroundStyle(passed ? .green : .red)
                    }
                } else {
                    Label("待判卷（还有 \(pending) 题没有成绩）", systemImage: "hourglass").font(.title3)
                    Button("重新判卷", action: onRegrade).disabled(regrading)
                    if regrading { ProgressView().controlSize(.small) }
                }
                Spacer()
            }
            .padding(4)
        }
    }

    private func itemView(number: Int, _ item: AttemptDetail.Item) -> some View {
        let grade = item.grades.last
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
