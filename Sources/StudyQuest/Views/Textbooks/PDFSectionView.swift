import PDFKit
import SwiftUI

/// 一本 pdf 教材的原文件：每个阅读器窗口只读一次，解析与复制页面都在 actor 上做，不占主线程。
actor PDFSource {
    private let data: Data
    private var document: PDFDocument?

    init(data: Data) { self.data = data }

    /// 把第 `pages`（从 0 开始，含两端）页复制成一个新文档；超出页数的部分忽略。
    func subdocument(pages: ClosedRange<Int>) -> PDFBox? {
        if document == nil { document = PDFDocument(data: data) }
        guard let document else { return nil }
        let result = PDFDocument()
        for index in pages where index < document.pageCount {
            if let page = document.page(at: index)?.copy() as? PDFPage { result.insert(page, at: result.pageCount) }
        }
        return PDFBox(document: result)
    }
}

/// 在 actor 与界面之间传递 PDFDocument；建好后只在主线程使用。
final class PDFBox: @unchecked Sendable {
    let document: PDFDocument
    init(document: PDFDocument) { self.document = document }
}

/// 显示一节的页面。
struct PDFSectionView: NSViewRepresentable {
    let box: PDFBox

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = box.document
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== box.document { view.document = box.document }
    }
}
