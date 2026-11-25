import Foundation
import StudyCore
import StudyMCP

// stdout 只用于 MCP 协议；日志与错误一律写 stderr。
// STUDYQUEST_DB_PATH：设置后改用该路径的数据库文件，不碰 ~/Library/Application Support 下的真实数据（defaultURL 不认 HOME，冒烟测试必须用它）。
do {
    let url = try ProcessInfo.processInfo.environment["STUDYQUEST_DB_PATH"].map { URL(fileURLWithPath: $0) }
        ?? AppDatabase.defaultURL()
    let store = try StudyStore(database: AppDatabase(url: url), clock: SystemClock(), notifier: DistributedChangeNotifier())
    try await MCPServer(store: store, databaseURL: url).run()
} catch {
    FileHandle.standardError.write(Data("studyquest-mcp: \(error)\n".utf8))
    exit(1)
}
