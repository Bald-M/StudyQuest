import Foundation

/// 数据变更后通知其他进程（App 与 MCP 服务器共用同一个数据库）。
public protocol ChangeNotifier: Sendable {
    func post()
}

public struct DistributedChangeNotifier: ChangeNotifier {
    public static let name = Notification.Name("local.studyquest.dataChanged")

    public init() {}

    public func post() {
        DistributedNotificationCenter.default().postNotificationName(
            Self.name, object: nil, userInfo: nil, deliverImmediately: true)
    }
}

public struct NoopChangeNotifier: ChangeNotifier {
    public init() {}
    public func post() {}
}
