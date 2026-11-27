import StudyCore
import SwiftUI

/// 阅读器窗口的值：每本教材一个窗口。`sectionId` 非 nil 时打开后定位到该节。
struct ReaderRoute: Hashable, Codable {
    var textbookId: Int64
    var sectionId: Int64?
}

/// 教材阅读器：左侧目录（✓ 已掌握、▶ 可读、🔒 未解锁），右侧正文，底部开始闯关。
/// 作答页以 sheet 出现在本窗口里。
struct ReaderView: View {
    let model: AppModel
    let route: ReaderRoute

    private enum Content {
        case markdown(String)
        /// 没有 marked.min.js 时的纯文本。
        case plain(String)
        case pdf(PDFBox)
        case unavailable(String)
    }

    private struct ActiveAttempt: Identifiable { var id: Int64 }

    @State private var snapshot: AppModel.ReaderSnapshot?
    @State private var loadError: String?
    @State private var selectedId: Int64?
    @State private var content: Content?
    @State private var truncated = false
    @State private var pdfSource: PDFSource?
    @State private var preparing = false
    @State private var challengeError: String?
    @State private var activeAttempt: ActiveAttempt?

    private var selectedRow: SectionRow? { snapshot?.rows.first { $0.section.id == selectedId } }

    var body: some View {
        Group {
            if let snapshot {
                if let book = snapshot.textbook {
                    NavigationSplitView {
                        sidebar(snapshot.rows)
                            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
                    } detail: {
                        detail(book: book, stageLocked: snapshot.stageLocked)
                    }
                } else {
                    ContentUnavailableView("教材已删除", systemImage: "trash")
                }
            } else {
                ContentUnavailableView(loadError ?? "加载中…", systemImage: "book")
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .navigationTitle(snapshot?.textbook?.title ?? "教材")
        .task { await reload(initial: true) }
        .onChange(of: model.revision) { Task { await reload(initial: false) } }
        .onChange(of: selectedId) {
            if let selectedId { model.setLastRead(textbookId: route.textbookId, sectionId: selectedId) }
        }
        // 节换了或正文更新了才重新加载
        .task(id: "\(selectedId ?? 0)-\(selectedRow?.section.textHash ?? "")") { await loadContent() }
        .sheet(item: $activeAttempt) { active in
            AnswerView(model: model, attemptId: active.id, showHints: true) {
                activeAttempt = nil
                model.refresh()
            }
            .id(active.id)
        }
    }

    // MARK: 目录

    private func sidebar(_ rows: [SectionRow]) -> some View {
        List(selection: $selectedId) {
            ForEach(chapters(rows), id: \.offset) { _, chapter in
                Section(chapter.title) {
                    ForEach(chapter.rows, id: \.section.id) { row in
                        HStack(spacing: 6) {
                            Text(icon(row.state)).frame(width: 18)
                            Text(row.section.title).lineLimit(2)
                        }
                        .foregroundStyle(row.state == .locked ? .secondary : .primary)
                        .tag(row.section.id)
                        .selectionDisabled(row.state == .locked)
                    }
                }
            }
        }
    }

    /// 相邻且章名相同的节归为一组。
    private func chapters(_ rows: [SectionRow]) -> [(offset: Int, element: (title: String, rows: [SectionRow]))] {
        var groups: [(title: String, rows: [SectionRow])] = []
        for row in rows {
            if groups.last?.title == row.section.chapterTitle {
                groups[groups.count - 1].rows.append(row)
            } else {
                groups.append((row.section.chapterTitle, [row]))
            }
        }
        return Array(groups.enumerated())
    }

    private func icon(_ state: SectionState) -> String {
        switch state {
        case .mastered: "✓"
        case .unlocked: "▶"
        case .locked: "🔒"
        }
    }

    // MARK: 正文与闯关

    @ViewBuilder private func detail(book: Textbook, stageLocked: Bool) -> some View {
        if let row = selectedRow {
            VStack(spacing: 0) {
                contentView.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                footer(row, stageLocked: stageLocked)
            }
            .navigationTitle("\(book.title) · \(row.section.title)")
        } else {
            ContentUnavailableView("这本教材没有可读的章节", systemImage: "book")
        }
    }

    @ViewBuilder private var contentView: some View {
        switch content {
        case .markdown(let text):
            MarkdownWebView(store: model.store, markdown: text)
        case .plain(let text):
            VStack(alignment: .leading, spacing: 0) {
                Label("未找到渲染资源，请用 bundle-app.sh 打包后运行", systemImage: "exclamationmark.triangle.fill")
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.yellow.opacity(0.2))
                ScrollView {
                    Text(text).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                }
            }
        case .pdf(let box):
            PDFSectionView(box: box)
        case .unavailable(let message):
            ContentUnavailableView(message, systemImage: "exclamationmark.triangle")
        case nil:
            ProgressView()
        }
    }

    private func footer(_ row: SectionRow, stageLocked: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button("读完了，开始闯关") { start(row) }
                .buttonStyle(.borderedProminent)
                .disabled(stageLocked || preparing || row.state == .locked)
            if preparing {
                ProgressView().controlSize(.small)
                Text("正在按本节出题…").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                if stageLocked { Text(AppModel.stageLockedMessage).foregroundStyle(.secondary) }
                if truncated { Text("本节较长，题目只覆盖前半部分").foregroundStyle(.orange) }
                if let challengeError { Text(challengeError).foregroundStyle(.red) }
            }
            .font(.callout)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private func start(_ row: SectionRow) {
        guard let id = row.section.id else { return }
        preparing = true
        challengeError = nil
        Task {
            defer { preparing = false }
            do {
                activeAttempt = ActiveAttempt(id: try await model.prepareSectionChallenge(sectionId: id).attemptId)
            } catch {
                challengeError = userMessage(error)
            }
        }
    }

    // MARK: 加载

    private func reload(initial: Bool) async {
        do {
            let next = try await model.readerSnapshot(textbookId: route.textbookId)
            snapshot = next
            loadError = nil
            let open = next.rows.filter { $0.state != .locked }.compactMap(\.section.id)
            if let selectedId, open.contains(selectedId) { return }
            if initial, let id = route.sectionId, open.contains(id) {
                selectedId = id
            } else if let last = next.textbook?.lastSectionId, open.contains(last) {
                selectedId = last
            } else {
                selectedId = (next.rows.first { $0.state == .unlocked } ?? next.rows.first)?.section.id
            }
        } catch {
            loadError = userMessage(error)
        }
    }

    private func loadContent() async {
        guard let book = snapshot?.textbook, let row = selectedRow else {
            content = nil
            return
        }
        content = nil
        challengeError = nil
        truncated = row.section.text.count > SectionText.aiLimit
        switch book.sourceKind {
        case .pdf:
            guard let start = row.section.pageStart, let end = row.section.pageEnd, start <= end else {
                content = .unavailable("这一节没有页码范围")
                return
            }
            do {
                if pdfSource == nil {
                    guard let data = try await model.pdfData(textbookId: route.textbookId) else {
                        content = .unavailable("找不到 pdf 原文件")
                        return
                    }
                    if pdfSource == nil { pdfSource = PDFSource(data: data) }
                }
                guard let box = await pdfSource?.subdocument(pages: start...end) else {
                    content = .unavailable("无法打开这个 pdf")
                    return
                }
                if !Task.isCancelled { content = .pdf(box) }
            } catch {
                content = .unavailable(userMessage(error))
            }
        case .markdownFile, .markdownFolder:
            guard MarkdownWebView.marked != nil else {
                content = .plain(row.section.text)
                return
            }
            let text = row.section.text, refs = snapshot?.assetRefs ?? [], bookId = route.textbookId
            let path = row.section.matchKey.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? ""
            let rewritten = await Task.detached {
                MarkdownAssetLinks.rewrite(text, documentPath: path, assetRefs: refs, textbookId: bookId)
            }.value
            if !Task.isCancelled { content = .markdown(rewritten) }
        }
    }
}
