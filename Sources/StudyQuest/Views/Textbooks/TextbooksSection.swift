import AppKit
import StudyCore
import SwiftUI
import UniformTypeIdentifiers

/// 阶段详情里“教材”区的状态与动作：列表、导入、挂模块、从原文件更新、删除。
/// 由 StageDetailView 持有；表单行与弹出内容分开挂，弹出内容挂在 Form 之外，只出现一次。
@MainActor @Observable final class TextbooksController {
    enum ActiveSheet: Identifiable {
        case importing(ParsedTextbook, sourcePath: String)
        case mapping(textbookId: Int64, title: String)
        /// `sourcePath` 非 nil 表示用户重新选择了原文件位置，更新时一并保存。
        case sync(TextbookSummary, SyncPlan, ParsedTextbook, sourcePath: String?)

        var id: String {
            switch self {
            case .importing(_, let path): "import-\(path)"
            case .mapping(let id, _): "mapping-\(id)"
            case .sync(let book, _, _, _): "sync-\(book.id)"
            }
        }
    }

    let model: AppModel
    let stageIndex: Int

    var rows: [TextbookSummary] = []
    /// 正在解析或比对时的说明；非空时导入与更新按钮禁用。
    var busy: String?
    var error: String?
    var sheet: ActiveSheet?
    var deleteTarget: TextbookSummary?
    var missingSource: TextbookSummary?

    init(model: AppModel, stageIndex: Int) {
        self.model = model
        self.stageIndex = stageIndex
    }

    private static let markdownTypes = ["md", "markdown"].compactMap { UTType(filenameExtension: $0) }

    func chooseImport() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.pdf] + Self.markdownTypes
        panel.message = "选择 .md、.pdf 文件或 Markdown 文件夹"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run("正在解析…") {
            let parsed = try await self.model.parseTextbook(at: url)
            self.sheet = .importing(parsed, sourcePath: url.path)
        }
    }

    func preview(_ book: TextbookSummary, from url: URL?) {
        run("正在比对「\(book.title)」…") {
            do {
                let (plan, parsed) = try await self.model.syncPreview(textbook: book, from: url)
                self.sheet = .sync(book, plan, parsed, sourcePath: url?.path)
            } catch StoreError.notFound("原文件") {
                self.missingSource = book
            }
        }
    }

    /// 原路径丢失时按教材原来的类型重新选择位置，再预览一次。
    func relocate(_ book: TextbookSummary) {
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

    func delete(_ book: TextbookSummary) {
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

    func reload() {
        do {
            rows = try model.textbookRows(stage: stageIndex)
        } catch {
            self.error = userMessage(error)
        }
    }
}

/// 表单里的“教材”区，只放行内容；弹出内容见 `TextbooksPresentations`。
struct TextbooksSection: View {
    let controller: TextbooksController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Section("教材") {
            if controller.rows.isEmpty {
                Text("还没有教材。可以导入 .md、.pdf 文件或 Markdown 文件夹。").foregroundStyle(.secondary)
            }
            ForEach(controller.rows) { row($0) }
            HStack(spacing: 8) {
                Button("导入教材", action: controller.chooseImport).disabled(controller.busy != nil)
                if let busy = controller.busy {
                    ProgressView().controlSize(.small)
                    Text(busy).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error = controller.error { Text(error).font(.caption).foregroundStyle(.red) }
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
                Button("阅读") { openWindow(value: ReaderRoute(textbookId: book.id, sectionId: nil)) }
                Button("挂模块") { controller.sheet = .mapping(textbookId: book.id, title: book.title) }
                Button("从原文件更新") { controller.preview(book, from: nil) }.disabled(controller.busy != nil)
                Divider()
                Button("删除", role: .destructive) { controller.deleteTarget = book }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

/// 教材区的表单、确认框、提示与加载；挂在 Form 外层容器上，避免在列表式 Form 里重复出现。
struct TextbooksPresentations: ViewModifier {
    @Bindable var controller: TextbooksController

    func body(content: Content) -> some View {
        content
            .onAppear(perform: controller.reload)
            .onChange(of: controller.model.revision) { controller.reload() }
            .sheet(item: $controller.sheet) { sheetView($0) }
            .confirmationDialog("删除教材", isPresented: Binding(get: { controller.deleteTarget != nil }, set: { if !$0 { controller.deleteTarget = nil } }), presenting: controller.deleteTarget) { book in
                Button("删除「\(book.title)」", role: .destructive) { controller.delete(book) }
            } message: { _ in
                Text("删除后教材不再显示，题目、卡片和错题会保留；可以重新导入，但掌握进度从头开始。")
            }
            .alert("找不到原文件", isPresented: Binding(get: { controller.missingSource != nil }, set: { if !$0 { controller.missingSource = nil } }), presenting: controller.missingSource) { book in
                Button("重新选择…") { controller.relocate(book) }
                Button("取消", role: .cancel) {}
            } message: { book in
                Text("「\(book.title)」原来的位置 \(book.sourcePath) 已不存在，请选择它现在的位置。")
            }
    }

    @ViewBuilder private func sheetView(_ active: TextbooksController.ActiveSheet) -> some View {
        let model = controller.model, stageIndex = controller.stageIndex
        switch active {
        case .importing(let parsed, let path):
            ImportTextbookSheet(parsed: parsed, onCancel: { controller.sheet = nil }) {
                let id = try await model.importTextbook(parsed, stage: stageIndex, sourcePath: path)
                controller.sheet = .mapping(textbookId: id, title: parsed.title)
            }
        case .mapping(let id, let title):
            ModuleMappingSheet(model: model, textbookId: id, title: title, stageIndex: stageIndex) { controller.sheet = nil }
        case .sync(let book, let plan, let parsed, let sourcePath):
            SyncPreviewSheet(title: book.title, plan: plan, onCancel: { controller.sheet = nil }) {
                try await model.applySync(textbookId: book.id, parsed: parsed, sourcePath: sourcePath)
                controller.sheet = nil
            }
        }
    }
}
