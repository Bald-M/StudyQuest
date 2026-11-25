import Foundation

/// 启动时记下数据库文件的 inode。App 从备份恢复会把另一个文件挪到原路径：已打开的连接仍指向旧文件，
/// 之后的写入都会落进被挪走的旧库。每次请求前比对一次，文件不见了或换了 inode 就该退出重启。
public struct DatabaseFileIdentity: Sendable {
    public let path: String
    private let fileNumber: UInt64?

    public init(path: String) {
        self.path = path
        fileNumber = Self.fileNumber(atPath: path)
    }

    /// 文件仍在、且还是启动时那一个。
    public var isUnchanged: Bool {
        fileNumber != nil && Self.fileNumber(atPath: path) == fileNumber
    }

    private static func fileNumber(atPath path: String) -> UInt64? {
        ((try? FileManager.default.attributesOfItem(atPath: path))?[.systemFileNumber] as? NSNumber)?.uint64Value
    }
}
