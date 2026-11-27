import Foundation
import CoreGraphics
import CoreText
import PDFKit
import Testing
@testable import StudyCore

private func tempURL(_ name: String) -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pdfreader-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent(name)
}

/// 生成带文字层的 pdf；`texts[i]` 为 nil 时该页只画一个色块（模拟扫描页）。
private func makePDF(_ texts: [String?], title: String? = nil, to url: URL) {
    var box = CGRect(x: 0, y: 0, width: 400, height: 300)
    var info: [CFString: Any] = [:]
    if let title { info[kCGPDFContextTitle] = title }
    let ctx = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary)!
    for t in texts {
        ctx.beginPDFPage(nil)
        if let t {
            let font = CTFontCreateWithName("Helvetica" as CFString, 20, nil)
            let attr = NSAttributedString(string: t, attributes: [.font: font])
            let line = CTLineCreateWithAttributedString(attr)
            ctx.textPosition = CGPoint(x: 20, y: 150)
            CTLineDraw(line, ctx)
        } else {
            ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        }
        ctx.endPDFPage()
    }
    ctx.closePDF()
}

/// 给已有 pdf 加书签：(标题, 页码, 子书签)。
private func addOutline(_ entries: [(String, Int, [(String, Int)])], to url: URL) {
    let doc = PDFDocument(url: url)!
    let root = PDFOutline()
    for (i, e) in entries.enumerated() {
        let item = PDFOutline()
        item.label = e.0
        item.destination = PDFDestination(page: doc.page(at: e.1)!, at: .zero)
        for (j, c) in e.2.enumerated() {
            let child = PDFOutline()
            child.label = c.0
            child.destination = PDFDestination(page: doc.page(at: c.1)!, at: .zero)
            item.insertChild(child, at: j)
        }
        root.insertChild(item, at: i)
    }
    doc.outlineRoot = root
    doc.write(to: url)
}

@Suite struct PDFTextbookReaderTests {
    @Test func splitsByOutline() throws {
        let url = tempURL("book.pdf")
        makePDF((0..<8).map { "page\($0)" }, title: "线性代数", to: url)
        addOutline([("第一章", 0, [("1.1 向量", 0), ("1.2 矩阵", 2)]),
                    ("第二章", 4, [("2.1 行列式", 4), ("2.2 特征值", 6)])], to: url)
        let book = try PDFTextbookReader.read(file: url)
        #expect(book.title == "线性代数")
        #expect(book.sourceKind == .pdf)
        let raw = try Data(contentsOf: url)
        #expect(book.pdfData == raw)
        #expect(book.sections.map(\.chapterTitle) == ["第一章", "第一章", "第二章", "第二章"])
        #expect(book.sections.map(\.title) == ["1.1 向量", "1.2 矩阵", "2.1 行列式", "2.2 特征值"])
        #expect(book.sections.map { $0.pageStart! } == [0, 2, 4, 6])
        #expect(book.sections.map { $0.pageEnd! } == [1, 3, 5, 7])
        #expect(book.sections[0].matchKey == "第一章|1.1 向量#1")
        #expect(book.sections[1].text.contains("page2"))
        #expect(book.sections[1].text.contains("page3"))
        #expect(!book.sections[1].text.contains("page4"))
    }

    @Test func noOutlineSplitsEveryTenPages() throws {
        let url = tempURL("纸质书.pdf")
        makePDF((0..<23).map { "content page \($0)" }, to: url)
        let book = try PDFTextbookReader.read(file: url)
        #expect(book.title == "纸质书")
        #expect(book.sections.count == 3)
        #expect(book.sections.map(\.title) == ["第 1–10 页", "第 11–20 页", "第 21–23 页"])
        #expect(book.sections.allSatisfy { $0.chapterTitle == "纸质书" })
        #expect(book.sections.map { $0.pageStart! } == [0, 10, 20])
        #expect(book.sections.map { $0.pageEnd! } == [9, 19, 22])
        #expect(book.sections[2].matchKey == "|第 21–23 页#1")
    }

    @Test func noOutlineMatchKeyIgnoresTitleMetadata() throws {
        let a = tempURL("a.pdf"), b = tempURL("a.pdf")
        makePDF((0..<3).map { "content page \($0)" }, title: "旧标题", to: a)
        makePDF((0..<3).map { "content page \($0)" }, title: "新标题", to: b)
        let old = try PDFTextbookReader.read(file: a), new = try PDFTextbookReader.read(file: b)
        #expect(new.sections[0].chapterTitle == "新标题")
        #expect(new.sections.map(\.matchKey) == old.sections.map(\.matchKey))
    }

    @Test func singleLevelOutlineMakesChapterAndSection() throws {
        let url = tempURL("b.pdf")
        makePDF((0..<4).map { "some text page \($0)" }, to: url)
        addOutline([("甲", 0, []), ("乙", 2, [])], to: url)
        let book = try PDFTextbookReader.read(file: url)
        #expect(book.sections.map(\.chapterTitle) == ["甲", "乙"])
        #expect(book.sections.map(\.title) == ["甲", "乙"])
        #expect(book.sections.map { $0.pageEnd! } == [1, 3])
    }

    @Test func scannedPdfIsRejected() throws {
        let url = tempURL("scan.pdf")
        makePDF([nil, nil, nil], to: url)
        #expect(throws: StoreError.invalid("这像是扫描版 pdf，暂不支持")) {
            try PDFTextbookReader.read(file: url)
        }
    }

    @Test func unreadableFileIsRejected() throws {
        let url = tempURL("bad.pdf")
        try Data("not a pdf".utf8).write(to: url)
        #expect(throws: StoreError.invalid("无法打开这个 pdf")) {
            try PDFTextbookReader.read(file: url)
        }
    }
}
