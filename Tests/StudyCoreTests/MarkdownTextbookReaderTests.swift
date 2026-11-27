import Foundation
import Testing
@testable import StudyCore

private func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mdreader-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

@Suite struct MarkdownTextbookReaderTests {
    @Test func splitsByTopTwoHeadingLevels() throws {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("book.md")
        try write("# 第一章\n引言\n## 1.1 变量\nA\n## 1.2 循环\nB", to: file)
        let book = try MarkdownTextbookReader.read(file: file)
        #expect(book.sourceKind == .markdownFile)
        #expect(book.sections.map(\.chapterTitle) == ["第一章", "第一章", "第一章"])
        #expect(book.sections.map(\.title) == ["第一章", "1.1 变量", "1.2 循环"])
        #expect(book.sections.map(\.text) == ["引言", "A", "B"])
        #expect(book.sections[1].matchKey == "book.md|第一章|1.1 变量#1")
    }

    @Test func codeFenceHashIsNotHeading() throws {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("b.md")
        try write("# 章\n## 节\n```python\n# 计算总价\nx = 1\n```\n", to: file)
        let book = try MarkdownTextbookReader.read(file: file)
        #expect(book.sections.count == 1)
        #expect(book.sections[0].text.contains("# 计算总价"))
    }

    @Test func fileWithoutHeadingsIsOneSection() throws {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("笔记.md")
        try write("只有正文\n没有标题", to: file)
        let book = try MarkdownTextbookReader.read(file: file)
        #expect(book.sections.count == 1)
        #expect(book.sections[0].chapterTitle == "笔记")
        #expect(book.sections[0].title == "笔记")
    }

    @Test func folderUsesNaturalOrderAndSkipsHidden() throws {
        let dir = try makeTempDir()
        try write("# t\nbody b", to: dir.appendingPathComponent("10.b.md"))
        try write("# t\nbody a", to: dir.appendingPathComponent("2.a.md"))
        try write("x", to: dir.appendingPathComponent(".obsidian/x.md"))
        try write("y", to: dir.appendingPathComponent("attachments/y.md"))
        let book = try MarkdownTextbookReader.read(folder: dir)
        #expect(book.sourceKind == .markdownFolder)
        #expect(book.sections.map(\.chapterTitle) == ["2.a", "10.b"])
    }

    @Test func duplicateTitlesGetOrdinalInMatchKey() throws {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("d.md")
        try write("# 章\n## 练习\n甲\n## 练习\n乙", to: file)
        let book = try MarkdownTextbookReader.read(file: file)
        #expect(book.sections.map(\.matchKey).filter { $0.contains("练习") }.map { String($0.suffix(2)) } == ["#1", "#2"])
    }

    @Test func resolvesBothImageSyntaxes() throws {
        let dir = try makeTempDir()
        try write("# 章\n![](img/a.png)\n![[b.png]]\n![[missing.png]]", to: dir.appendingPathComponent("m.md"))
        try Data([1]).write(to: { try FileManager.default.createDirectory(at: dir.appendingPathComponent("img"), withIntermediateDirectories: true); return dir.appendingPathComponent("img/a.png") }())
        try write("", to: dir.appendingPathComponent("attachments/keep.txt"))
        try Data([2]).write(to: dir.appendingPathComponent("attachments/b.png"))
        let book = try MarkdownTextbookReader.read(file: dir.appendingPathComponent("m.md"))
        #expect(book.assets["img/a.png"] == Data([1]))
        #expect(book.assets["attachments/b.png"] == Data([2]))
        #expect(book.warnings.contains { $0.contains("missing.png") })
        #expect(book.sections[0].text.contains("![](img/a.png)"))
    }

    @Test func gb18030FileIsDecoded() throws {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("g.md")
        let enc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        try #require("# 章\n变量与类型".data(using: enc)).write(to: file)
        let book = try MarkdownTextbookReader.read(file: file)
        #expect(book.sections.contains { $0.text.contains("变量与类型") })
    }

    @Test func emptySectionsAreDropped() throws {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("e.md")
        try write("# 章\n## 空节\n## 有内容\n正文", to: file)
        let book = try MarkdownTextbookReader.read(file: file)
        #expect(book.sections.map(\.title) == ["有内容"])

        let empty = try makeTempDir()
        try write("# 只有标题", to: empty.appendingPathComponent("a.md"))
        do {
            _ = try MarkdownTextbookReader.read(folder: empty)
            Issue.record("应当抛错")
        } catch let error as StoreError {
            #expect(error.localizedDescription == "没有可导入的内容")
        }
    }

    @Test func trailingHashOnlyStrippedAfterSpace() throws {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("h.md")
        try write("# 章\n## 学习 C#\n甲\n## 标题 ##\n乙", to: file)
        let book = try MarkdownTextbookReader.read(file: file)
        #expect(book.sections.map(\.title) == ["学习 C#", "标题"])
    }

    @Test func nestedAndMismatchedFencesDoNotSplit() throws {
        let dir = try makeTempDir()
        let a = dir.appendingPathComponent("a.md")
        try write("# 章\n## 节\n````md\n```python\n## 假标题\n```\n## 还是假的\n````\n后文", to: a)
        let bookA = try MarkdownTextbookReader.read(file: a)
        #expect(bookA.sections.map(\.title) == ["节"])
        #expect(bookA.sections[0].text.contains("## 还是假的") && bookA.sections[0].text.contains("后文"))

        let b = dir.appendingPathComponent("b.md")
        try write("# 章\n## 节\n~~~\n```\n# x\n~~~\n尾", to: b)
        let bookB = try MarkdownTextbookReader.read(file: b)
        #expect(bookB.sections.map(\.title) == ["节"])
        #expect(bookB.sections[0].text.contains("# x"))
    }

    @Test func unclosedFenceRunsToEndOfFile() throws {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("u.md")
        try write("# 章\n## 节\n```\ncode\n## 不是标题\n更多", to: file)
        let book = try MarkdownTextbookReader.read(file: file)
        #expect(book.sections.map(\.title) == ["节"])
        #expect(book.sections[0].text.contains("更多"))
    }
}
