import Foundation

/// 阅读器显示 Markdown 时的图片链接：把正文里的本地图片引用改写成 `sqasset://<教材 id>/<编码后的 ref>`，
/// 再由界面的 scheme handler 按 ref 从库里取图片。ref 与导入时 `ParsedTextbook.assets` 的键一致。
public enum MarkdownAssetLinks {
    public static let scheme = "sqasset"

    /// `documentPath` 是该节所在 md 文件相对导入根目录的路径（matchKey 第一段）；
    /// 只改写能在 `assetRefs` 里找到的引用，其余原样保留。
    public static func rewrite(_ text: String, documentPath: String, assetRefs: Set<String>, textbookId: Int64) -> String {
        let ns = text as NSString
        let whole = NSRange(location: 0, length: ns.length)
        var replacements: [(NSRange, String)] = []
        for m in MarkdownTextbookReader.standardImageRegex.matches(in: text, range: whole) {
            var raw = ns.substring(with: m.range(at: 1))
            if raw.hasPrefix("<") && raw.hasSuffix(">") { raw = String(raw.dropFirst().dropLast()) }
            let ref = normalize(raw.removingPercentEncoding ?? raw, relativeTo: documentPath)
            guard let ref, assetRefs.contains(ref) else { continue }
            replacements.append((m.range(at: 1), url(textbookId: textbookId, ref: ref)))
        }
        for m in MarkdownTextbookReader.wikiImageRegex.matches(in: text, range: whole) {
            let name = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            guard let ref = wikiTarget(name, assetRefs: assetRefs) else { continue }
            replacements.append((m.range, "![\(name)](\(url(textbookId: textbookId, ref: ref)))"))
        }
        let result = NSMutableString(string: text)
        for (range, value) in replacements.sorted(by: { $0.0.location > $1.0.location }) {
            result.replaceCharacters(in: range, with: value)
        }
        return result as String
    }

    public static func url(textbookId: Int64, ref: String) -> String {
        "\(scheme)://\(textbookId)/\(ref.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ref)"
    }

    /// `url(textbookId:ref:)` 的反向；不是本 scheme 或格式不对返回 nil。
    public static func parse(_ url: URL) -> (textbookId: Int64, ref: String)? {
        guard url.scheme == scheme, let host = url.host, let id = Int64(host) else { return nil }
        let prefix = "\(scheme)://\(host)/"
        let string = url.absoluteString
        guard string.hasPrefix(prefix), let ref = String(string.dropFirst(prefix.count)).removingPercentEncoding, !ref.isEmpty else { return nil }
        return (id, ref)
    }

    /// 按扩展名推断图片类型，未知时为 `application/octet-stream`。
    public static func mimeType(ref: String) -> String {
        switch (ref as NSString).pathExtension.lowercased() {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "webp": "image/webp"
        case "svg": "image/svg+xml"
        case "bmp": "image/bmp"
        case "tif", "tiff": "image/tiff"
        case "heic": "image/heic"
        case "avif": "image/avif"
        default: "application/octet-stream"
        }
    }

    // MARK: - 内部

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// 相对 md 文件所在目录解析路径并去掉 `.`、`..`；外链、绝对路径或越出根目录返回 nil。
    private static func normalize(_ path: String, relativeTo documentPath: String) -> String? {
        let lower = path.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("data:") || path.hasPrefix("/") { return nil }
        var parts = documentPath.split(separator: "/").dropLast().map(String.init)
        for part in path.split(separator: "/") {
            switch part {
            case ".": continue
            case "..":
                guard !parts.isEmpty else { return nil }
                parts.removeLast()
            default: parts.append(String(part))
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "/")
    }

    /// 与导入时一致：先按完整 ref 找，再按文件名找，同名时取自然排序最前的一个。
    private static func wikiTarget(_ name: String, assetRefs: Set<String>) -> String? {
        if assetRefs.contains(name) { return name }
        return assetRefs.filter { ($0 as NSString).lastPathComponent == name }
            .min { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
