import Foundation
@testable import StudyCore

/// 按队列依次返回文本或抛错；记录每次请求。
final class FakeModel: ChatModel, @unchecked Sendable {
    enum Reply { case text(String), error(Error) }
    private let lock = NSLock()
    private var queue: [Reply]
    private var recorded: [ChatRequest] = []
    init(_ replies: [Reply]) { queue = replies }
    var label: String { "fake:test" }
    var calls: Int { lock.withLock { recorded.count } }
    var requests: [ChatRequest] { lock.withLock { recorded } }
    func complete(_ request: ChatRequest) async throws -> String {
        let reply: Reply = lock.withLock {
            recorded.append(request)
            return queue.isEmpty ? .error(AIError.emptyResponse) : queue.removeFirst()
        }
        switch reply {
        case .text(let s): return s
        case .error(let e): throw e
        }
    }
}
