import StudyCore
import SwiftUI

/// 给教材每一节挂一个本阶段的模块，或不挂。
struct ModuleMappingSheet: View {
    let model: AppModel
    let textbookId: Int64
    let title: String
    let stageIndex: Int
    let onDone: () -> Void

    @State private var sections: [TextbookSection] = []
    @State private var modules: [Module] = []
    @State private var selection: [Int64: Int64?] = [:]
    @State private var loading = true
    @State private var suggesting = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("给「\(title)」挂模块").font(.headline)
                Spacer()
                if suggesting { ProgressView().controlSize(.small) }
                Button("AI 建议", action: suggest).disabled(loading || suggesting || sections.isEmpty)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            if loading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            } else {
                List(sections) { section in
                    let id = section.id ?? 0
                    Picker(selection: binding(id)) {
                        Text("不挂模块").tag(Int64?.none)
                        ForEach(modules) { Text($0.title).tag($0.id) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.title)
                            Text(section.chapterTitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(minHeight: 320)
            }
            HStack {
                Spacer()
                Button("稍后再说", action: onDone).keyboardShortcut(.cancelAction)
                Button("保存", action: save).keyboardShortcut(.defaultAction).disabled(loading)
            }
        }
        .padding(20)
        .frame(width: 560)
        .task { await load() }
    }

    private func binding(_ sectionId: Int64) -> Binding<Int64?> {
        Binding(get: { selection[sectionId] ?? nil }, set: { selection[sectionId] = $0 })
    }

    private func load() async {
        do {
            modules = try model.modules(stage: stageIndex)
            sections = try await model.sectionRows(textbookId: textbookId).map(\.section)
            selection = Dictionary(uniqueKeysWithValues: sections.compactMap { s in s.id.map { ($0, s.moduleId) } })
        } catch {
            self.error = userMessage(error)
        }
        loading = false
    }

    private func suggest() {
        suggesting = true
        error = nil
        Task {
            do {
                let suggestions = try await model.suggestModules(textbookId: textbookId)
                let idByKey = Dictionary(modules.compactMap { m in m.id.map { (m.key, $0) } }, uniquingKeysWith: { a, _ in a })
                for (sectionId, key) in suggestions {
                    selection[sectionId] = key.flatMap { idByKey[$0] }
                }
            } catch {
                self.error = userMessage(error)
            }
            suggesting = false
        }
    }

    private func save() {
        do {
            try model.saveModuleMapping(selection)
            onDone()
        } catch {
            self.error = userMessage(error)
        }
    }
}
