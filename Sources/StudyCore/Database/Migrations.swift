import GRDB

enum Migrations {
    static func make() -> DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "stage") { t in
                t.primaryKey("index", .integer)
                t.column("title", .text).notNull()
                t.column("summary", .text).notNull()
                t.column("estimatedWeeks", .text).notNull()
                t.column("passLine", .double).notNull()
                t.column("minSectionRatio", .double).notNull()
                t.column("cumulativeMin", .double).notNull()
                t.column("cumulativeMax", .double).notNull()
                t.column("cooldownDays", .integer).notNull()
                t.column("reward", .text)
                t.column("status", .text).notNull()
                t.column("passedAt", .datetime)
            }
            try db.create(table: "module") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("stageIndex", .integer).notNull().indexed()
                t.column("key", .text).notNull().unique()
                t.column("title", .text).notNull()
                t.column("points", .text).notNull()
                t.column("resources", .text).notNull()
                t.column("gameTasks", .text).notNull()
                t.column("lifeProblems", .text).notNull()
                t.column("order", .integer).notNull()
                t.column("status", .text).notNull()
                t.column("startedAt", .datetime)
                t.column("completedAt", .datetime)
                t.column("needsRelearn", .boolean).notNull()
            }
            try db.create(table: "card") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("stageIndex", .integer).notNull()
                t.column("moduleId", .integer)
                t.column("front", .text).notNull()
                t.column("back", .text).notNull()
                t.column("tags", .text).notNull()
                t.column("step", .integer)
                t.column("dueDay", .text).notNull().indexed()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "cardReview") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("cardId", .integer).notNull().indexed().references("card", onDelete: .cascade)
                t.column("day", .text).notNull()
                t.column("remembered", .boolean).notNull()
            }
            try db.create(table: "problem") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("stageIndex", .integer).notNull().indexed()
                t.column("moduleId", .integer)
                t.column("kind", .text).notNull()
                t.column("prompt", .text).notNull()
                t.column("options", .text).notNull()
                t.column("referenceAnswer", .text).notNull()
                t.column("rubric", .text).notNull()
                t.column("maxScore", .double).notNull()
                t.column("difficulty", .text).notNull()
                t.column("tags", .text).notNull()
                t.column("source", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "assignment") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("stageIndex", .integer).notNull()
                t.column("moduleId", .integer)
                t.column("day", .text).notNull().indexed()
                t.column("title", .text).notNull()
                t.column("problemIds", .text).notNull()
                t.column("status", .text).notNull()
                t.column("source", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "exam") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("stageIndex", .integer).notNull()
                t.column("kind", .text).notNull()
                t.column("title", .text).notNull()
                t.column("timeLimitMinutes", .integer).notNull()
                t.column("status", .text).notNull()
                t.column("warnings", .text).notNull()
                t.column("source", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "examSection") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("examId", .integer).notNull().indexed().references("exam", onDelete: .cascade)
                t.column("order", .integer).notNull()
                t.column("title", .text).notNull()
                t.column("weight", .double).notNull()
                t.column("sourceKind", .text).notNull()
                t.column("problemIds", .text).notNull()
            }
            try db.create(table: "attempt") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("kind", .text).notNull()
                t.column("assignmentId", .integer).indexed()
                t.column("examId", .integer).indexed()
                t.column("mistakeId", .integer)
                t.column("status", .text).notNull()
                t.column("startedAt", .datetime).notNull()
                t.column("deadline", .datetime)
                t.column("submittedAt", .datetime)
                t.column("gradedAt", .datetime)
                t.column("totalPercent", .double)
                t.column("passed", .boolean)
                t.column("reflection", .text)
            }
            try db.create(table: "attemptAnswer") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("attemptId", .integer).notNull().references("attempt", onDelete: .cascade)
                t.column("problemId", .integer).notNull()
                t.column("answer", .text).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.uniqueKey(["attemptId", "problemId"])
            }
            try db.create(table: "questionGrade") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("attemptId", .integer).notNull().references("attempt", onDelete: .cascade)
                t.column("problemId", .integer).notNull()
                t.column("score", .double).notNull()
                t.column("maxScore", .double).notNull()
                t.column("feedback", .text).notNull()
                t.column("mistakes", .text).notNull()
                t.column("grader", .text).notNull()
                t.column("raw", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "questionGrade_attempt_problem", on: "questionGrade", columns: ["attemptId", "problemId"])
            try db.create(table: "mistake") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("problemId", .integer).notNull()
                t.column("sourceAttemptId", .integer).notNull()
                t.column("step", .integer).notNull()
                t.column("streak", .integer).notNull()
                t.column("dueDay", .text).notNull()
                t.column("graduated", .boolean).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            // 同一道题同时只能有一条未毕业的错题。
            try db.create(index: "mistake_open_problem", on: "mistake", columns: ["problemId"],
                          options: .unique, condition: Column("graduated") == false)
            try db.create(table: "mockInterview") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("transcript", .text).notNull()
                t.column("score", .double)
                t.column("feedback", .text)
                t.column("grader", .text)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "xpEvent") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("dedupKey", .text).notNull().unique()
                t.column("amount", .integer).notNull()
                t.column("reason", .text).notNull()
                t.column("day", .text).notNull().indexed()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "dailyNote") { t in
                t.primaryKey("day", .text)
                t.column("text", .text).notNull()
            }
            try db.create(table: "autoGenRun") { t in
                t.primaryKey("day", .text)
                t.column("status", .text).notNull()
                t.column("errors", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "appSetting") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
            try db.create(table: "providerConfig") { t in
                t.primaryKey("id", .text)
                t.column("kind", .text).notNull()
                t.column("name", .text).notNull()
                t.column("baseURL", .text).notNull()
                t.column("model", .text).notNull()
                t.column("effort", .text)
            }
        }
        m.registerMigration("v2") { db in
            try db.create(table: "textbook") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("stageIndex", .integer).notNull()
                t.column("title", .text).notNull()
                t.column("sourceKind", .text).notNull()
                t.column("sourcePath", .text).notNull()
                t.column("pdfData", .blob)
                t.column("language", .text)
                t.column("lastSectionId", .integer)
                t.column("importedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
            }
            try db.create(table: "textbookSection") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("textbookId", .integer).notNull().indexed().references("textbook", onDelete: .cascade)
                t.column("matchKey", .text).notNull()
                t.column("chapterTitle", .text).notNull()
                t.column("title", .text).notNull()
                t.column("order", .integer).notNull()
                t.column("moduleId", .integer)
                t.column("text", .text).notNull()
                t.column("textHash", .text).notNull()
                t.column("pageStart", .integer)
                t.column("pageEnd", .integer)
                t.column("masteredAt", .datetime)
                t.column("removedAt", .datetime)
                t.column("codeLevelsEnabled", .boolean).notNull().defaults(to: true)
            }
            try db.create(table: "textbookAsset") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("textbookId", .integer).notNull().references("textbook", onDelete: .cascade)
                t.column("ref", .text).notNull()
                t.column("data", .blob).notNull()
                t.uniqueKey(["textbookId", "ref"])
            }
            try db.create(table: "sectionChallenge") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("sectionId", .integer).notNull().indexed().references("textbookSection", onDelete: .cascade)
                t.column("problemIds", .text).notNull()
                t.column("stale", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.column("source", .text).notNull()
            }
            try db.alter(table: "problem") { $0.add(column: "sectionId", .integer) }
            try db.alter(table: "card") { $0.add(column: "sectionId", .integer) }
            try db.alter(table: "attempt") { $0.add(column: "sectionChallengeId", .integer) }
        }
        return m
    }
}
