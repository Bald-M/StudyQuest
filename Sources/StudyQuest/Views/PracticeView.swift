import StudyCore
import SwiftUI

/// 练习与作业：未完成的在前（新的在上），已完成的显示成绩。点击按作答状态继续、看结果或新开一次。
struct PracticeView: View {
    let model: AppModel

    @State private var open: [AppModel.AssignmentRow] = []
    @State private var completed: [AppModel.AssignmentRow] = []
    @State private var message: String?

    var body: some View {
        Group {
            if open.isEmpty && completed.isEmpty {
                ContentUnavailableView(message ?? "还没有作业", systemImage: "square.and.pencil",
                                       description: Text("在地图的阶段详情里生成作业，或让 AI 助手通过 MCP 出题"))
            } else {
                List {
                    if let message { Text(message).foregroundStyle(.red) }
                    if !open.isEmpty { Section("未完成（\(open.count)）") { ForEach(open) { row($0) } } }
                    if !completed.isEmpty { Section("已完成（\(completed.count)）") { ForEach(completed) { row($0) } } }
                }
            }
        }
        .navigationTitle("练习与作业")
        .onAppear {
            reload()
            // 今日页点进来时带着要打开的作业
            if let id = model.selectedAssignmentId {
                model.selectedAssignmentId = nil
                openAssignment(id)
            }
        }
        .onChange(of: model.revision) { reload() }
    }

    private func row(_ item: AppModel.AssignmentRow) -> some View {
        Button { openAssignment(item.id) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.assignment.title)
                    Text("\(item.assignment.day.rawValue) · 阶段 \(item.assignment.stageIndex) · \(item.assignment.problemIds.count) 题")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let percent = item.lastPercent {
                    Text("\(Int(percent.rounded())) 分").foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openAssignment(_ id: Int64) {
        do {
            try model.openAssignment(id: id)
            message = nil
        } catch {
            message = userMessage(error)
        }
    }

    private func reload() {
        do {
            (open, completed) = try model.assignmentRows()
        } catch {
            message = userMessage(error)
        }
    }
}
