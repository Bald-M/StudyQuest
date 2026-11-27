import Foundation

/// 把 Markdown 文件或文件夹切成章节，不碰数据库。
public enum MarkdownTextbookReader {
    private static let skippedDirectories: Set<String> = ["attachments", "images", "assets"]

    public static func read(file: URL) throws -> ParsedTextbook {
        let file = file.resolvingSymlinksInPath()
        let root = file.deletingLastPathComponent()
        var warnings: [String] = []
        guard let text = decode(file) else {
            throw StoreError.invalid("没有可导入的内容")
        }
        // 单文件的 matchKey 不含文件名，改名后更新仍能对上
        let sections = split(text, relativePath: "", fileTitle: file.deletingPathExtension().lastPathComponent, chapterFromFile: false)
        return try finish(title: file.deletingPathExtension().lastPathComponent, kind: .markdownFile, sections: sections.map { ($0, file) }, root: root, warnings: &warnings)
    }

    public static func read(folder: URL) throws -> ParsedTextbook {
        let root = folder.resolvingSymlinksInPath()
        var warnings: [String] = []
        var sections: [(ParsedSection, URL)] = []
        for (rel, url) in markdownFiles(in: root) {
            guard let text = decode(url) else {
                warnings.append("无法解码，已跳过：\(rel)")
                continue
            }
            let base = url.deletingPathExtension().lastPathComponent
            sections += split(text, relativePath: rel, fileTitle: base, chapterFromFile: true).map { ($0, url) }
        }
        return try finish(title: root.lastPathComponent, kind: .markdownFolder, sections: sections, root: root, warnings: &warnings)
    }

    /// 取出正文里的图片引用串：`![alt](路径)` 的路径，以及 `![[文件名]]` 的文件名。
    public static func imageRefs(in text: String) -> [String] {
        references(in: text).map(\.ref)
    }

    // MARK: - 内部

    private struct ImageRef { var ref: String; var isWiki: Bool }

    /// `![alt](路径)`：第 1 组是路径（可带尖括号）。阅读器改写图片链接时共用。
    static let standardImageRegex = try! NSRegularExpression(pattern: #"!\[[^\]]*\]\(\s*(<[^>]+>|[^)\s]+)(?:\s+"[^"]*")?\s*\)"#)
    /// `![[文件名|尺寸]]`：第 1 组是文件名。
    static let wikiImageRegex = try! NSRegularExpression(pattern: #"!\[\[([^\]\|]+)(?:\|[^\]]*)?\]\]"#)

    private static func references(in text: String) -> [ImageRef] {
        let ns = text as NSString
        let whole = NSRange(location: 0, length: ns.length)
        let std = standardImageRegex, wiki = wikiImageRegex
        var found: [(Int, ImageRef)] = []
        for m in std.matches(in: text, range: whole) {
            var raw = ns.substring(with: m.range(at: 1))
            if raw.hasPrefix("<") && raw.hasSuffix(">") { raw = String(raw.dropFirst().dropLast()) }
            let lower = raw.lowercased()
            if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("data:") { continue }
            found.append((m.range.location, ImageRef(ref: raw.removingPercentEncoding ?? raw, isWiki: false)))
        }
        for m in wiki.matches(in: text, range: whole) {
            found.append((m.range.location, ImageRef(ref: ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces), isWiki: true)))
        }
        return found.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// 依次尝试 UTF-8、GB18030；都不行返回 nil。
    private static func decode(_ url: URL) -> String? {
        guard var data = try? Data(contentsOf: url) else { return nil }
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data.removeFirst(3) }
        if let s = String(data: data, encoding: .utf8) { return s }
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        return String(data: data, encoding: gb)
    }

    /// 返回 (相对路径, URL)，按相对路径自然排序。
    private static func markdownFiles(in root: URL) -> [(String, URL)] {
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        var files: [(String, URL)] = []
        for case let url as URL in en {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                if skippedDirectories.contains(url.lastPathComponent) { en.skipDescendants() }
                continue
            }
            let ext = url.pathExtension.lowercased()
            guard ext == "md" || ext == "markdown" else { continue }
            files.append((relativePath(of: url.resolvingSymlinksInPath(), to: root), url.resolvingSymlinksInPath()))
        }
        return files.sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
    }

    private static func relativePath(of url: URL, to root: URL) -> String {
        let r = root.standardizedFileURL.path, p = url.standardizedFileURL.path
        if p.hasPrefix(r + "/") { return String(p.dropFirst(r.count + 1)) }
        return url.lastPathComponent
    }

    /// 返回 (级数, 标题)；围栏内、非 ATX 的行返回 nil。
    private static func heading(_ line: Substring) -> (Int, String)? {
        var level = 0
        for c in line { if c == "#" { level += 1 } else { break } }
        guard (1...6).contains(level) else { return nil }
        let rest = line.dropFirst(level)
        guard rest.first == " " else { return nil }
        var title = rest.trimmingCharacters(in: .whitespaces)
        // 结尾的 # 只有前面是空格（或整个标题都是 #）时才算关闭序列，C#、F# 不动
        var stripped = title
        while stripped.hasSuffix("#") { stripped.removeLast() }
        if stripped.isEmpty || stripped.hasSuffix(" ") || stripped.hasSuffix("\t") {
            title = stripped.trimmingCharacters(in: .whitespaces)
        }
        return title.isEmpty ? nil : (level, title)
    }

    /// 切一个文件。chapterFromFile 为真时整个文件是一章，节按最高级标题切。
    /// 单文件模式（chapterFromFile 为假）下，借用文件名的章名、节名在 matchKey 里记为空串。
    private static func split(_ text: String, relativePath: String, fileTitle: String, chapterFromFile: Bool) -> [ParsedSection] {
        let keyFileTitle = chapterFromFile ? fileTitle : ""
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        // 第一遍：找最高级标题
        // 围栏按 CommonMark 匹配：记下开栏字符和长度，只有同字符且不短于开栏的纯围栏行才关闭
        var fence: (char: Character, length: Int)?
        var marks: [(index: Int, level: Int, title: String)] = []
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if let open = fence {
                if t.count >= open.length, t.allSatisfy({ $0 == open.char }) { fence = nil }
                continue
            }
            if let c = t.first, c == "`" || c == "~" {
                let run = t.prefix { $0 == c }.count
                if run >= 3 { fence = (c, run); continue }
            }
            if let h = heading(line) { marks.append((i, h.0, h.1)) }
        }
        guard let top = marks.map(\.level).min() else {
            return [ParsedSection(matchKey: "\(relativePath)|\(keyFileTitle)|\(keyFileTitle)#1", chapterTitle: fileTitle, title: fileTitle, text: text.trimmingCharacters(in: .whitespacesAndNewlines))]
                .filter { !$0.text.isEmpty }
        }
        // 节级别：文件夹模式是最高级；单文件模式是最高级 + 1
        let sectionLevel = chapterFromFile ? top : top + 1
        var chapter = fileTitle, keyChapter = keyFileTitle
        var title = fileTitle, keyTitle = keyFileTitle
        var body: [Substring] = []
        var raw: [(chapter: String, title: String, key: String, text: String)] = []
        func flush() {
            raw.append((chapter, title, "\(keyChapter)|\(keyTitle)", body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
            body = []
        }
        let boundary = Dictionary(uniqueKeysWithValues: marks.filter { $0.level == top || $0.level == sectionLevel }.map { ($0.index, $0) })
        for (i, line) in lines.enumerated() {
            if let m = boundary[i] {
                flush()
                if !chapterFromFile && m.level == top {
                    chapter = m.title
                    keyChapter = m.title
                }
                title = m.title
                keyTitle = m.title
            } else {
                body.append(line)
            }
        }
        flush()
        // 序号按（章, 节）计，且在丢弃空节之前计，这样以后补内容不会让后面的 key 变动
        var counts: [String: Int] = [:]
        var result: [ParsedSection] = []
        for item in raw {
            let n = (counts[item.key] ?? 0) + 1
            counts[item.key] = n
            guard !item.text.isEmpty else { continue }
            result.append(ParsedSection(matchKey: "\(relativePath)|\(item.key)#\(n)", chapterTitle: item.chapter, title: item.title, text: item.text))
        }
        return result
    }

    private static func finish(title: String, kind: TextbookSourceKind, sections: [(ParsedSection, URL)], root: URL, warnings: inout [String]) throws -> ParsedTextbook {
        guard !sections.isEmpty else { throw StoreError.invalid("没有可导入的内容") }
        var assets: [String: Data] = [:]
        var byName: [String: String]?
        func nameIndex() -> [String: String] {
            if let byName { return byName }
            var map: [String: String] = [:]
            if let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for case let url as URL in en {
                    let rel = relativePath(of: url.resolvingSymlinksInPath(), to: root)
                    let name = url.lastPathComponent
                    if map[name] == nil || rel.localizedStandardCompare(map[name]!) == .orderedAscending { map[name] = rel }
                }
            }
            byName = map
            return map
        }
        var missing = Set<String>()
        for (section, mdURL) in sections {
            for ref in references(in: section.text) {
                var rel: String?
                if ref.isWiki {
                    rel = nameIndex()[ref.ref]
                } else {
                    let url = URL(fileURLWithPath: ref.ref, relativeTo: mdURL.deletingLastPathComponent()).resolvingSymlinksInPath()
                    let candidate = relativePath(of: url, to: root)
                    if FileManager.default.fileExists(atPath: url.path), url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") { rel = candidate }
                }
                if let rel, assets[rel] == nil {
                    if let data = try? Data(contentsOf: root.appendingPathComponent(rel)) { assets[rel] = data } else { warnings.append("无法读取图片：\(ref.ref)") }
                } else if rel == nil {
                    let from = relativePath(of: mdURL, to: root)
                    if missing.insert("\(ref.ref)|\(from)").inserted {
                        warnings.append("找不到图片：\(ref.ref)（来自 \(from)）")
                    }
                }
            }
        }
        return ParsedTextbook(title: title, sourceKind: kind, sections: sections.map(\.0), assets: assets, warnings: warnings)
    }
}
