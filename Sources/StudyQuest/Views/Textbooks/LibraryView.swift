import StudyCore
import SwiftUI

/// 资料库：按阶段分组集中查看与管理全部教材。导入、阅读、挂模块、更新、删除与阶段详情共用 `TextbooksController`。
struct LibraryView: View {
    @State private var controller: TextbooksController
    @State private var query = ""
    @State private var stageTitles: [Int: String] = [:]

    init(model: AppModel) {
        _controller = State(initialValue: TextbooksController(model: model, stageIndex: nil))
    }

    private var visible: [TextbookSummary] { controller.rows.filter { $0.matches(query) } }

    /// 只列出有教材的阶段，按阶段号排列。
    private var groups: [(stage: Int, books: [TextbookSummary])] {
        Dictionary(grouping: visible, by: \.stageIndex).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    var body: some View {
        Group {
            if controller.rows.isEmpty {
                ContentUnavailableView {
                    Label("还没有教材", systemImage: "books.vertical")
                } description: {
                    Text("可以导入 .md、.pdf 文件或 Markdown 文件夹。")
                } actions: {
                    importButton
                }
            } else if visible.isEmpty {
                ContentUnavailableView("没有找到相关教材", systemImage: "magnifyingglass")
            } else {
                List {
                    ForEach(groups, id: \.stage) { group in
                        Section(sectionTitle(group.stage)) {
                            ForEach(group.books) { TextbookRowView(controller: controller, book: $0) }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { status }
        .navigationTitle("资料库")
        .searchable(text: $query, placement: .toolbar, prompt: "搜索书名")
        .toolbar { ToolbarItem { importButton } }
        .onAppear(perform: loadStageTitles)
        .modifier(TextbooksPresentations(controller: controller))
    }

    private var importButton: some View {
        Button("导入教材", systemImage: "plus", action: controller.chooseImport)
            .disabled(controller.busy != nil)
    }

    @ViewBuilder private var status: some View {
        if controller.busy != nil || controller.error != nil {
            HStack(spacing: 8) {
                if let busy = controller.busy {
                    ProgressView().controlSize(.small)
                    Text(busy).foregroundStyle(.secondary)
                }
                if let error = controller.error { Text(error).foregroundStyle(.red) }
                Spacer()
            }
            .font(.caption)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(.bar)
        }
    }

    private func sectionTitle(_ stage: Int) -> String {
        stageTitles[stage].map { "阶段 \(stage)：\($0)" } ?? "阶段 \(stage)"
    }

    private func loadStageTitles() {
        let stages = (try? controller.model.stages()) ?? []
        stageTitles = Dictionary(uniqueKeysWithValues: stages.map { ($0.index, $0.title) })
    }
}
