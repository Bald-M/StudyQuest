import Foundation
import Testing
@testable import StudyMCP

@Suite struct DatabaseFileIdentityTests {
    @Test func detectsReplacedOrMissingFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("studyquest-inode-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = dir.appendingPathComponent("studyquest.sqlite")
        try Data("old".utf8).write(to: db)

        let identity = DatabaseFileIdentity(path: db.path)
        #expect(identity.isUnchanged)
        try Data("appended".utf8).write(to: db)  // 原地写入不换 inode
        #expect(identity.isUnchanged)

        // 恢复备份：新文件挪到原路径，inode 变化
        let replacement = dir.appendingPathComponent("restore-pending.sqlite")
        try Data("new".utf8).write(to: replacement)
        try FileManager.default.removeItem(at: db)
        try FileManager.default.moveItem(at: replacement, to: db)
        #expect(!identity.isUnchanged)

        try FileManager.default.removeItem(at: db)
        #expect(!identity.isUnchanged)
        #expect(!DatabaseFileIdentity(path: db.path).isUnchanged)
    }
}
