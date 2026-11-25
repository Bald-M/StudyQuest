import Foundation
import StudyCore
import StudyMCP

// stdout 只用于 MCP 协议；日志与错误一律写 stderr。
// STUDYQUEST_DB_PATH 可覆盖数据库路径（冒烟测试用，避免写入真实数据）。
do {
    let url = try ProcessInfo.processInfo.environment["STUDYQUEST_DB_PATH"].map { URL(fileURLWithPath: $0) }
        ?? AppDatabase.defaultURL()
    let store = try StudyStore(database: AppDatabase(url: url), clock: SystemClock(), notifier: DistributedChangeNotifier())
    try await MCPServer(store: store).run()
} catch {
    FileHandle.standardError.write(Data("studyquest-mcp: \(error)\n".utf8))
    exit(1)
}
