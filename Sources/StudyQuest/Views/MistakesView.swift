import StudyCore
import SwiftUI

struct MistakesView: View {
    let model: AppModel

    @State private var rows: [AppModel.MistakeRow] = []
    @State private var messages: [Int64: String] = [:]
    @State private var loadError: String?

    private var today: Day { model.store.clock.today() }
    private var due: [AppModel.MistakeRow] { rows.filter { $0.mistake.dueDay <= today } }
    private var upcoming: [AppModel.MistakeRow] { rows.filter { $0.mistake.dueDay > today } }

    var body: some View {
        Group {
            if rows.isEmpty {
                ContentUnavailableView(loadError ?? "错题本是空的", systemImage: "checkmark.circle")
            } else {
                List {
                    if !due.isEmpty {
                        Section("到期（\(due.count)）") { ForEach(due) { row($0) } }
                    }
                    if !upcoming.isEmpty {
                        Section("未到期（\(upcoming.count)）") { ForEach(upcoming) { row($0) } }
                    }
                }
            }
        }
        .navigationTitle("错题本")
        .onAppear(perform: reload)
        .onChange(of: model.revision) { reload() }
    }

    private func row(_ item: AppModel.MistakeRow) -> some View {
        let id = item.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(item.problem?.prompt ?? "（题目已不存在）").lineLimit(4)
                Spacer()
                Button("重做") { redo(id) }
                    .disabled(item.mistake.dueDay > today)
            }
            HStack(spacing: 12) {
                Text(item.lastPercent.map { "上次得分 \(NumberText.whole($0))%" } ?? "尚未重做")
                Text("下次 \(item.mistake.dueDay.rawValue)")
                Text("连续答对 \(item.mistake.streak) 次")
            }
            .font(.caption).foregroundStyle(.secondary)
            if let problem = item.problem { OriginLink(model: model, sectionId: problem.sectionId) }
            if let message = messages[id] {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private func redo(_ id: Int64) {
        do {
            try model.startMistakeRedo(mistakeId: id)
            messages[id] = nil
        } catch StoreError.blocked(let reason) {
            messages[id] = reason
        } catch {
            messages[id] = error.localizedDescription
        }
    }

    private func reload() {
        do {
            rows = try model.mistakeRows()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}
