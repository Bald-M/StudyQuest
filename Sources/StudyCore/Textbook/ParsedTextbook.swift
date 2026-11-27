import Foundation
import CryptoKit

/// 解析出的一节，尚未入库。
public struct ParsedSection: Equatable, Sendable {
    public var matchKey: String
    public var chapterTitle: String
    public var title: String
    public var text: String
    public var pageStart: Int?
    public var pageEnd: Int?
    public init(matchKey: String, chapterTitle: String, title: String, text: String, pageStart: Int? = nil, pageEnd: Int? = nil) { self.matchKey = matchKey; self.chapterTitle = chapterTitle; self.title = title; self.text = text; self.pageStart = pageStart; self.pageEnd = pageEnd }
}

/// 教材解析结果（Markdown 与 PDF 共用），不含数据库信息。
public struct ParsedTextbook: Sendable {
    public var title: String
    public var sourceKind: TextbookSourceKind
    public var sections: [ParsedSection]
    /// 键为相对导入根目录的图片路径。
    public var assets: [String: Data]
    public var pdfData: Data?
    public var warnings: [String]
    public init(title: String, sourceKind: TextbookSourceKind, sections: [ParsedSection], assets: [String: Data] = [:], pdfData: Data? = nil, warnings: [String] = []) { self.title = title; self.sourceKind = sourceKind; self.sections = sections; self.assets = assets; self.pdfData = pdfData; self.warnings = warnings }
}

public enum SectionText {
    /// 送给 AI 的单节正文字数上限。
    public static let aiLimit = 30_000
    /// 正文的 SHA-256 十六进制，用来判断一节内容有没有变。
    public static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
