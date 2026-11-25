import Foundation
import GRDB

public enum StoreError: Error, Equatable {
    case notFound(String)
    case invalid(String)
    case blocked(String)
}

/// 所有业务读写的入口。App 与 MCP 服务器共用；每次写入提交后通知其他进程。
public final class StudyStore: Sendable {
    let database: AppDatabase
    public let clock: Clock
    let notifier: ChangeNotifier

    var pool: DatabasePool { database.pool }

    public init(database: AppDatabase, clock: Clock, notifier: ChangeNotifier) throws {
        self.database = database
        self.clock = clock
        self.notifier = notifier
        let now = clock.now()
        let today = clock.today()
        try database.pool.write { try Seeder.seedIfEmpty($0, now: now, today: today) }
    }
}
