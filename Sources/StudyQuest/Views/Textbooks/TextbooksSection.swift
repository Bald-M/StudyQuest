import AppKit
import StudyCore
import SwiftUI
import UniformTypeIdentifiers

/// 阶段详情里的“教材”区：列表、导入、从原文件更新、删除。
struct TextbooksSection: View {
    let model: AppModel
    let stageIndex: Int

    enum ActiveSheet: Identifiable {
        case importing(ParsedTextbook, sourcePath: String)
        case mapping(textbookId: Int64, title: String)
        case sync(TextbookSummary, SyncPlan, ParsedTextbook)

        var id: String {
            switch self {
            case .importing(_, let path): "import-\(path)"
            case .mapping(let id, _): "mapping-\(id)"
            case .sync(let book, _, _): "sync-\(book.id)"
            }
        }
    }

    @State private var rows: [TextbookSummary] = []
    /// 正在解析或比对时的说明；非空时导入与更新按钮禁用。
    @State private var busy: String?
    @State private var error: String?
    @State private var sheet: ActiveSheet?
    @State private var deleteTarget: TextbookSummary?
    @State private var missingSource: TextbookSummary?

    var body: some View {
        Section("教材") {
            if rows.isEmpty {
                Text("还没有教材。可以导入 .md、.pdf 文件或 Markdown 文件夹。").foregroundStyle(.secondary)
            }
            ForEach(rows) { row($0) }
            HStack(spacing: 8) {
                Button("导入教材", action: chooseImport).disabled(busy != nil)
                if let busy {
                    ProgressView().controlSize(.small)
                    Text(busy).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .onAppear(perform: reload)
        .onChange(of: model.revision) { reload() }
        .sheet(item: $sheet) { sheetView($0) }
        .confirmationDialog("删除教材", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), presenting: deleteTarget) { book in
            Button("删除「\(book.title)」", role: .destructive) { delete(book) }
        } message: { _ in
            Text("删除后教材不再显示，题目、卡片和错题会保留；可以重新导入，但掌握进度从头开始。")
        }
        .alert("找不到原文件", isPresented: Binding(get: { missingSource != nil }, set: { if !$0 { missingSource = nil } }), presenting: missingSource) { book in
            Button("重新选择…") { relocate(book) }
            Button("取消", role: .cancel) {}
        } message: { book in
            Text("「\(book.title)」原来的位置 \(book.sourcePath) 已不存在，请选择它现在的位置。")
        }
    }

    private func row(_ book: TextbookSummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                Text("已掌握 \(book.mastered) / \(book.total) 节").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("阅读") {}.disabled(true)  // Task 9 接入阅读器
                Button("从原文件更新") { preview(book, from: nil) }.disabled(busy != nil)
                Divider()
                Button("删除", role: .destructive) { deleteTarget = book }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    @ViewBuilder private func sheetView(_ active: ActiveSheet) -> some View {
        switch active {
        case .importing(let parsed, let path):
            ImportTextbookSheet(parsed: parsed, onCancel: { sheet = nil }) {
                let id = try await model.importTextbook(parsed, stage: stageIndex, sourcePath: path)
                sheet = .mapping(textbookId: id, title: parsed.title)
            }
        case .mapping(let id, let title):
            ModuleMappingSheet(model: model, textbookId: id, title: title, stageIndex: stageIndex) { sheet = nil }
        case .sync(let book, let plan, let parsed):
            SyncPreviewSheet(title: book.title, plan: plan, onCancel: { sheet = nil }) {
                try await model.applySync(textbookId: book.id, parsed: parsed)
                sheet = nil
            }
        }
    }

    // MARK: 动作

    private static let markdownTypes = ["md", "markdown"].compactMap { UTType(filenameExtension: $0) }

    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.pdf] + Self.markdownTypes
        panel.message = "选择 .md、.pdf 文件或 Markdown 文件夹"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run("正在解析…") {
            let parsed = try await model.parseTextbook(at: url)
            sheet = .importing(parsed, sourcePath: url.path)
        }
    }

    private func preview(_ book: TextbookSummary, from url: URL?) {
        run("正在比对「\(book.title)」…") {
            do {
                let (plan, parsed) = try await model.syncPreview(textbook: book, from: url)
                sheet = .sync(book, plan, parsed)
            } catch StoreError.notFound("原文件") {
                missingSource = book
            }
        }
    }

    /// 原路径丢失时按教材原来的类型重新选择位置，再预览一次。
    private func relocate(_ book: TextbookSummary) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        switch book.sourceKind {
        case .markdownFolder:
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
        case .markdownFile:
            panel.allowedContentTypes = Self.markdownTypes
        case .pdf:
            panel.allowedContentTypes = [.pdf]
        }
        panel.message = "选择「\(book.title)」现在的位置"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        preview(book, from: url)
    }

    private func delete(_ book: TextbookSummary) {
        do {
            try model.deleteTextbook(id: book.id)
            error = nil
        } catch {
            self.error = userMessage(error)
        }
    }

    private func run(_ label: String, _ work: @escaping () async throws -> Void) {
        busy = label
        error = nil
        Task {
            do { try await work() } catch { self.error = userMessage(error) }
            busy = nil
        }
    }

    private func reload() {
        do {
            rows = try model.textbookRows(stage: stageIndex)
        } catch {
            self.error = userMessage(error)
        }
    }
}
