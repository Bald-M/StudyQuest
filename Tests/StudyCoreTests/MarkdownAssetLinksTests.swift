import Foundation
import Testing
@testable import StudyCore

@Suite struct MarkdownAssetLinksTests {
    private let refs: Set<String> = ["ch1/img/a b.png", "img/图.jpg", "x/z/pic.png", "y/pic.png"]

    @Test func rewritesRelativeLinksAgainstDocumentFolder() {
        let text = "前文 ![甲](img/a%20b.png \"t\") 和 ![乙](<./img/a b.png>) 以及 ![丙](../img/图.jpg)"
        let out = MarkdownAssetLinks.rewrite(text, documentPath: "ch1/intro.md", assetRefs: refs, textbookId: 7)
        #expect(out == "前文 ![甲](sqasset://7/ch1%2Fimg%2Fa%20b.png \"t\") 和 ![乙](sqasset://7/ch1%2Fimg%2Fa%20b.png) 以及 ![丙](sqasset://7/img%2F%E5%9B%BE.jpg)")
    }

    @Test func rewritesBackslashAndSpacedPaths() {
        let text = "![](img\\a b.png) ![x](img/a b.png \"t\")"
        let out = MarkdownAssetLinks.rewrite(text, documentPath: "ch1/intro.md", assetRefs: refs, textbookId: 7)
        #expect(out == "![](sqasset://7/ch1%2Fimg%2Fa%20b.png) ![x](sqasset://7/ch1%2Fimg%2Fa%20b.png \"t\")")
    }

    @Test func rewritesWikiEmbedsByFileName() {
        let text = "![[pic.png|300]]\n![[img/图.jpg]]"
        let out = MarkdownAssetLinks.rewrite(text, documentPath: "book.md", assetRefs: refs, textbookId: 2)
        #expect(out == "![pic.png](sqasset://2/x%2Fz%2Fpic.png)\n![img/图.jpg](sqasset://2/img%2F%E5%9B%BE.jpg)")
    }

    @Test func leavesUnknownAndExternalLinksAlone() {
        let text = "![a](https://e.com/a.png) ![b](missing.png) ![[nope.png]] ![c](../../out.png) [普通链接](img/图.jpg)"
        #expect(MarkdownAssetLinks.rewrite(text, documentPath: "book.md", assetRefs: refs, textbookId: 1) == text)
    }

    @Test func parseRoundTripsAndRejectsOthers() throws {
        let string = MarkdownAssetLinks.url(textbookId: 12, ref: "ch1/img/a b.png")
        let url = try #require(URL(string: string))
        let parsed = try #require(MarkdownAssetLinks.parse(url))
        #expect(parsed.textbookId == 12 && parsed.ref == "ch1/img/a b.png")
        #expect(MarkdownAssetLinks.parse(URL(string: "https://12/a.png")!) == nil)
        #expect(MarkdownAssetLinks.parse(URL(string: "sqasset://abc/a.png")!) == nil)
        #expect(MarkdownAssetLinks.parse(URL(string: "sqasset://3/")!) == nil)
    }

    @Test func mimeTypeFromExtension() {
        #expect(MarkdownAssetLinks.mimeType(ref: "a/B.PNG") == "image/png")
        #expect(MarkdownAssetLinks.mimeType(ref: "x.jpeg") == "image/jpeg")
        #expect(MarkdownAssetLinks.mimeType(ref: "x.svg") == "image/svg+xml")
        #expect(MarkdownAssetLinks.mimeType(ref: "x") == "application/octet-stream")
    }
}
