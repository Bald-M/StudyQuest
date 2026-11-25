import StudyCore
import SwiftUI

struct TodayView: View {
    let model: AppModel

    @State private var note = ""
    @State private var noteSavedXP = false
    @State private var noteError: String?

    var body: some View {
        Form {
            if let today = model.today {
                header(today.progress)
                autoGenSection(today.autoGen)
                reviewSection(today)
                Section("错题") {
                    row("exclamationmark.bubble", today.dueMistakes > 0 ? "到期 \(today.dueMistakes) 道" : "没有到期错题") {
                        model.selection = .mistakes
                    }
                }
                assignmentsSection(today.assignments)
                examsSection(today)
                noteSection(today)
            } else if let error = model.loadError {
                Text(error).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("今日")
        .onAppear { note = (try? model.dailyNoteText()) ?? "" }
    }

    // MARK: 顶部：经验、连续天数、等级

    private func header(_ progress: ProgressSummary) -> some View {
        let base = XPRules.xpForNextLevel(progress.level - 1)
        let span = max(1, progress.nextLevelXP - base)
        return Section {
            HStack(spacing: 24) {
                Label("今日经验 \(progress.xpToday)", systemImage: "star.fill").foregroundStyle(.orange)
                Label("连续 \(progress.streak) 天", systemImage: "flame.fill").foregroundStyle(.red)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(progress.xp - base), total: Double(span))
                Text("Lv.\(progress.level) · \(progress.xp - base) / \(span) 经验升级")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 自动生成

    @ViewBuilder private func autoGenSection(_ status: AutoGenStatus) -> some View {
        switch status {
        case .disabled, .done:
            EmptyView()
        case .notConfigured:
            Section("自动出题") {
                Label("去设置配置 AI，或让 AI 助手通过 MCP 出题", systemImage: "info.circle").foregroundStyle(.secondary)
            }
        case .running:
            Section("自动出题") {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("正在生成今日作业…")
                    Spacer()
                    retryButton
                }
            }
        case .failed(let errors):
            Section("自动出题失败") {
                ForEach(errors, id: \.self) { Text($0).foregroundStyle(.red) }
                retryButton
            }
        }
    }

    private var retryButton: some View {
        Button("重试") { Task { await model.retryAutoGen() } }
            .disabled(model.retryingAutoGen)
    }

    // MARK: 复习、作业、考试

    private func reviewSection(_ today: TodaySummary) -> some View {
        Section("复习") {
            row("rectangle.on.rectangle", today.dueCards > 0 ? "到期 \(today.dueCards) 张" : "今日没有待复习卡片") {
                model.selection = .review
            }
            if today.deferredCards > 0 {
                Text("另有 \(today.deferredCards) 张已顺延到之后").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func assignmentsSection(_ assignments: [Assignment]) -> some View {
        Section("作业") {
            if assignments.isEmpty { Text("今天还没有作业").foregroundStyle(.secondary) }
            ForEach(assignments) { assignment in
                row(assignment.status == .completed ? "checkmark.circle.fill" : "square.and.pencil", assignment.title) {
                    model.selectedAssignmentId = assignment.id
                    model.selection = .practice
                }
            }
        }
    }

    private func examsSection(_ today: TodaySummary) -> some View {
        Section("考试") {
            if today.readyExams.isEmpty { Text("没有可参加的考试").foregroundStyle(.secondary) }
            ForEach(today.readyExams) { exam in
                row("doc.text", "\(exam.title) · \(exam.timeLimitMinutes) 分钟") {
                    model.selectedExamId = exam.id
                    model.selection = .exams
                }
            }
            if today.pendingGradingAttempts > 0 {
                Text("\(today.pendingGradingAttempts) 份试卷等待判卷").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 今日总结

    private func noteSection(_ today: TodaySummary) -> some View {
        Section("今日总结") {
            TextEditor(text: $note)
                .frame(height: 3 * 20 + 12)
                .font(.body)
            HStack {
                Button("保存") { saveNote(firstTime: !today.noteWritten) }
                if noteSavedXP { Text("+5").foregroundStyle(.orange) }
                if let noteError { Text(noteError).foregroundStyle(.red) }
            }
        }
    }

    private func saveNote(firstTime: Bool) {
        do {
            try model.saveDailyNote(note)
            noteSavedXP = firstTime
            noteError = nil
        } catch {
            noteError = error.localizedDescription
        }
    }

    // MARK: 通用行

    private func row(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
