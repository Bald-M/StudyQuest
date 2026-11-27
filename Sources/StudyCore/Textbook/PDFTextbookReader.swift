import Foundation
import PDFKit

/// 把带文字层的 pdf 切成章节，不碰数据库。
public enum PDFTextbookReader {
    /// 没有书签时每节的页数。
    public static let pagesPerSection = 10

    /// `keyChapter` 是 matchKey 里的章名：没有书签时为空串，改 pdf 标题元数据后更新仍能对上。
    private struct Entry {
        var chapter: String; var title: String; var start: Int; var keyChapter: String
        init(chapter: String, title: String, start: Int, keyChapter: String? = nil) {
            self.chapter = chapter; self.title = title; self.start = start; self.keyChapter = keyChapter ?? chapter
        }
    }

    public static func read(file: URL) throws -> ParsedTextbook {
        guard let data = try? Data(contentsOf: file), let doc = PDFDocument(data: data), doc.pageCount > 0 else {
            throw StoreError.invalid("无法打开这个 pdf")
        }
        if looksScanned(doc) { throw StoreError.invalid("这像是扫描版 pdf，暂不支持") }

        let fileName = file.deletingPathExtension().lastPathComponent
        let attrTitle = (doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = attrTitle.isEmpty ? fileName : attrTitle

        var entries = outlineEntries(doc)
        if entries.isEmpty {
            entries = stride(from: 0, to: doc.pageCount, by: pagesPerSection).map { start in
                let end = min(start + pagesPerSection, doc.pageCount) - 1
                return Entry(chapter: title, title: "第 \(start + 1)–\(end + 1) 页", start: start, keyChapter: "")
            }
        }

        var counts: [String: Int] = [:]
        var sections: [ParsedSection] = []
        for (i, e) in entries.enumerated() {
            // 下一节与本节同页（或顺序倒置）时，本节只取自己那一页。
            let end = i + 1 < entries.count ? max(e.start, entries[i + 1].start - 1) : doc.pageCount - 1
            let text = (e.start...end).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
            let key = "\(e.keyChapter)|\(e.title)"
            counts[key, default: 0] += 1
            sections.append(ParsedSection(matchKey: "\(key)#\(counts[key]!)", chapterTitle: e.chapter, title: e.title, text: text, pageStart: e.start, pageEnd: end))
        }
        return ParsedTextbook(title: title, sourceKind: .pdf, sections: sections, pdfData: data)
    }

    // MARK: - 内部

    /// 抽样最多 5 页，去掉空白后字符总数少于 20 就当作扫描版。
    private static func looksScanned(_ doc: PDFDocument) -> Bool {
        let n = doc.pageCount
        var picks: Set<Int> = [0, n - 1]
        for k in 1..<4 { picks.insert(k * (n - 1) / 4) }
        let count = picks.reduce(0) { sum, i in
            sum + (doc.page(at: i)?.string ?? "").filter { !$0.isWhitespace }.count
        }
        return count < 20
    }

    /// 书签展开成按文档顺序排列的节；第一层是章，第二层是节。
    private static func outlineEntries(_ doc: PDFDocument) -> [Entry] {
        guard let root = doc.outlineRoot else { return [] }
        func page(_ o: PDFOutline) -> Int? {
            guard let p = o.destination?.page else { return nil }
            let i = doc.index(for: p)
            return i == NSNotFound ? nil : i
        }
        func label(_ o: PDFOutline) -> String? {
            let s = (o.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : s
        }
        var result: [Entry] = []
        for i in 0..<root.numberOfChildren {
            guard let top = root.child(at: i), let chapter = label(top) else { continue }
            let topPage = page(top)
            var kids: [Entry] = []
            for j in 0..<top.numberOfChildren {
                guard let c = top.child(at: j), let t = label(c), let p = page(c) else { continue }
                kids.append(Entry(chapter: chapter, title: t, start: p))
            }
            if kids.isEmpty {
                if let p = topPage { result.append(Entry(chapter: chapter, title: chapter, start: p)) }
            } else {
                // 章首到第一个子书签之前的页并入第一节。
                if let p = topPage, p < kids[0].start { kids[0].start = p }
                result += kids
            }
        }
        return result
    }
}
