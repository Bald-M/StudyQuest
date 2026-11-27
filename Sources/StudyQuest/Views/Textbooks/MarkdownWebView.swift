import AppKit
import StudyCore
import SwiftUI
import WebKit

/// 用 WKWebView 显示一节 Markdown：页面内联 marked.min.js 渲染，图片走 `sqasset:` 由库里取，样式跟随浅色或深色模式。
/// `markdown` 应已经过 `MarkdownAssetLinks.rewrite` 改写。
struct MarkdownWebView: NSViewRepresentable {
    let store: StudyStore
    let markdown: String

    /// 打包后的 `Contents/Resources/Web/marked.min.js`；直接 `swift run` 时找不到，为 nil。
    static let marked: (url: URL, source: String)? = {
        guard let url = Bundle.main.url(forResource: "marked.min", withExtension: "js", subdirectory: "Web"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return (url, source)
    }()

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(context.coordinator, forURLScheme: MarkdownAssetLinks.scheme)
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        load(view, context: context)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        if context.coordinator.loaded != markdown { load(view, context: context) }
    }

    private func load(_ view: WKWebView, context: Context) {
        context.coordinator.loaded = markdown
        guard let marked = Self.marked else { return }
        view.loadHTMLString(Self.page(markdown: markdown, marked: marked), baseURL: nil)
    }

    /// marked 内联进页面：WKWebView 不允许 loadHTMLString 的页面读取本地文件，CSP 里的文件 URL 也匹配不上。
    static func page(markdown: String, marked: (url: URL, source: String)) -> String {
        // JSONEncoder 默认把 "/" 转成 "\/"，正文里的 </script> 不会提前结束脚本
        let json = (try? JSONEncoder().encode([markdown])).flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return """
            <!doctype html>
            <html><head><meta charset="utf-8">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src sqasset:; script-src 'unsafe-inline' \(marked.url.absoluteString); style-src 'unsafe-inline'">
            <style>\(css)</style>
            <script>\(marked.source)</script>
            </head><body><article id="content"></article>
            <script>document.getElementById("content").innerHTML = marked.parse(\(json)[0]);</script>
            </body></html>
            """
    }

    private static let css = """
        :root { color-scheme: light dark; }
        body { margin: 0; padding: 24px 32px 48px; font: 15px/1.7 -apple-system, "PingFang SC", sans-serif; color: #1d1d1f; background: #ffffff; }
        article { max-width: 760px; margin: 0 auto; }
        h1, h2, h3, h4 { line-height: 1.3; }
        pre, code { font-family: ui-monospace, Menlo, monospace; font-size: 13px; }
        pre { background: #f5f5f7; padding: 12px 14px; border-radius: 6px; overflow-x: auto; }
        :not(pre) > code { background: #f0f0f2; padding: 1px 4px; border-radius: 4px; }
        table { border-collapse: collapse; margin: 12px 0; }
        th, td { border: 1px solid #d2d2d7; padding: 6px 10px; }
        th { background: #f5f5f7; }
        img { max-width: 100%; }
        blockquote { margin: 12px 0; padding-left: 12px; border-left: 3px solid #d2d2d7; color: #6e6e73; }
        a { color: #0066cc; }
        @media (prefers-color-scheme: dark) {
            body { color: #e8e8ed; background: #1e1e1e; }
            pre, th { background: #2a2a2c; }
            :not(pre) > code { background: #333336; }
            th, td { border-color: #48484a; }
            blockquote { border-color: #48484a; color: #a1a1a6; }
            a { color: #4da3ff; }
        }
        """

    final class Coordinator: NSObject, WKURLSchemeHandler, WKNavigationDelegate {
        let store: StudyStore
        var loaded: String?

        init(store: StudyStore) { self.store = store }

        func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
            let url = task.request.url ?? URL(string: "\(MarkdownAssetLinks.scheme)://0/")!
            guard let (id, ref) = MarkdownAssetLinks.parse(url), let data = try? store.asset(textbookId: id, ref: ref) else {
                task.didReceive(HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
                task.didFinish()
                return
            }
            let headers = ["Content-Type": MarkdownAssetLinks.mimeType(ref: ref), "Content-Length": "\(data.count)"]
            task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)!)
            task.didReceive(data)
            task.didFinish()
        }

        func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

        /// 正文里的链接不在阅读器里跳转：网页链接交给默认浏览器，页内锚点照常。
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard action.navigationType == .linkActivated, let url = action.request.url, url.scheme != "about" else {
                decisionHandler(.allow)
                return
            }
            if url.scheme == "http" || url.scheme == "https" { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
        }
    }
}
