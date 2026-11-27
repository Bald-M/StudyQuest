import StudyCore

/// 一个 MCP 工具的名字、说明和 JSON Schema 输入定义（与 SDK 无关，MCPServer 负责转换）。
public struct ToolSpec: Sendable {
    public var name: String
    public var description: String
    public var inputSchema: JSONValue
}

/// 设计文档 §10.1 的 15 个工具。参数键一律 snake_case。
public enum ToolCatalog {
    public static let tools: [ToolSpec] = [
        ToolSpec(name: "get_progress", description: "当前阶段、各阶段状态、经验/等级/连续天数、今日经验。", inputSchema: object([:])),
        ToolSpec(name: "get_today", description: "今日任务清单：到期卡片数、到期错题数、今日作业、待考试卷、待确认的草稿试卷数、待判卷作答数、自动生成状态。",
                 inputSchema: object([:])),
        ToolSpec(name: "list_stages", description: "全部 10 个阶段及过关线、冷却期、累积题比例、奖励。", inputSchema: object([:])),
        ToolSpec(name: "get_stage", description: "阶段详情：过关规则与模块（学习要点、资源、游戏任务、生活题）。",
                 inputSchema: object(["stage_index": integer("阶段序号 0–9")], required: ["stage_index"])),
        ToolSpec(name: "create_cards", description: "批量创建复习卡片。",
                 inputSchema: object(["cards": array(card)], required: ["cards"])),
        ToolSpec(name: "create_problems", description: "批量创建题目（加入题库，不组成作业）。",
                 inputSchema: object(["problems": array(problem)], required: ["problems"])),
        ToolSpec(name: "create_assignment", description: "用已有题目 id 或内联新题创建今日作业。",
                 inputSchema: object(["assignment": assignment], required: ["assignment"])),
        ToolSpec(name: "create_exam",
                 description: "创建周测或阶段考试（分区、权重之和 100、限时、题目可内联），创建后为就绪状态。返回 exam_id 与警告（累积题占比、重复题）。",
                 inputSchema: object(["exam": exam], required: ["exam"])),
        ToolSpec(name: "list_exams", description: "试卷列表，可按阶段过滤。",
                 inputSchema: object(["stage_index": integer("阶段序号 0–9")])),
        ToolSpec(name: "get_exam", description: "试卷详情。试卷判卷前（就绪、作答中）不返回参考答案和评分标准。",
                 inputSchema: object(["exam_id": integer("试卷 id")], required: ["exam_id"])),
        ToolSpec(name: "list_attempts", description: "作答列表，可按试卷和状态过滤。",
                 inputSchema: object(["exam_id": integer("试卷 id"),
                                      "status": enumeration(["inProgress", "submitted", "graded"], "作答状态")])),
        ToolSpec(name: "get_attempt", description: "作答详情：每题作答、判卷记录、分区得分。交卷后含参考答案与评分标准。",
                 inputSchema: object(["attempt_id": integer("作答 id")], required: ["attempt_id"])),
        ToolSpec(name: "submit_grading", description: "为已交卷的作答写入每题得分与反馈；全部题目有成绩后自动结算。",
                 inputSchema: object(["attempt_id": integer("作答 id"), "grades": array(grade)], required: ["attempt_id", "grades"])),
        ToolSpec(name: "list_mistakes", description: "错题列表（含题干）与复习状态。",
                 inputSchema: object(["include_graduated": boolean("是否包含已毕业错题，默认 false")])),
        ToolSpec(name: "update_stage_settings", description: "修改阶段过关线、冷却天数（3–7）、奖励描述。",
                 inputSchema: object(["stage_index": integer("阶段序号 0–9"), "pass_line": number("过关线（百分比）"),
                                      "cooldown_days": integer("冷却天数 3–7"), "reward": string("奖励描述")],
                                     required: ["stage_index"])),
    ]

    // MARK: 输入类型

    private static let card = object([
        "stage_index": integer("阶段序号 0–9"), "module_key": string("模块 key，可省略"),
        "front": string("正面"), "back": string("背面"), "tags": array(string("标签")),
    ], required: ["stage_index", "front", "back"])

    private static let problem = object([
        "stage_index": integer("阶段序号 0–9"), "module_key": string("模块 key，可省略"),
        "kind": enumeration(["singleChoice", "multipleChoice", "shortAnswer", "coding", "project"], "题型"),
        "prompt": string("题干"), "options": array(string("选项（选择题必填）")),
        "reference_answer": string("参考答案"), "rubric": string("评分标准"), "max_score": number("满分，必须大于 0"),
        "difficulty": enumeration(["easy", "medium", "hard"], "难度"), "tags": array(string("标签")),
    ], required: ["stage_index", "kind", "prompt", "reference_answer", "rubric", "max_score", "difficulty"])

    private static let assignment = object([
        "stage_index": integer("阶段序号 0–9"), "module_key": string("模块 key，可省略"), "title": string("作业标题"),
        "problem_ids": array(integer("已有题目 id")), "problems": array(problem),
    ], required: ["stage_index", "title"])

    private static let section = object([
        "title": string("分区标题"), "weight": number("权重，所有分区之和为 100"),
        "source": enumeration(["problems", "mockInterviewAverage"], "计分来源，默认 problems；模拟面试均分只用于阶段 9"),
        "problem_ids": array(integer("已有题目 id")), "problems": array(problem),
    ], required: ["title", "weight"])

    private static let exam = object([
        "stage_index": integer("阶段序号 0–9"), "kind": enumeration(["weeklyQuiz", "stageExam"], "试卷类型"),
        "title": string("试卷标题"), "time_limit_minutes": integer("限时（分钟）"), "sections": array(section),
    ], required: ["stage_index", "kind", "title", "time_limit_minutes", "sections"])

    private static let grade = object([
        "problem_id": integer("题目 id"), "score": number("得分"), "feedback": string("反馈"),
        "mistakes": array(string("错误点")),
    ], required: ["problem_id", "score", "feedback"])

    // MARK: Schema 片段

    private static func object(_ properties: [String: JSONValue], required: [String] = []) -> JSONValue {
        var schema: [String: JSONValue] = ["type": .string("object"), "properties": .object(properties)]
        if !required.isEmpty { schema["required"] = .array(required.map(JSONValue.string)) }
        return .object(schema)
    }

    private static func array(_ items: JSONValue) -> JSONValue {
        .object(["type": .string("array"), "items": items])
    }

    private static func typed(_ type: String, _ description: String) -> JSONValue {
        .object(["type": .string(type), "description": .string(description)])
    }

    private static func string(_ description: String) -> JSONValue { typed("string", description) }
    private static func integer(_ description: String) -> JSONValue { typed("integer", description) }
    private static func number(_ description: String) -> JSONValue { typed("number", description) }
    private static func boolean(_ description: String) -> JSONValue { typed("boolean", description) }

    private static func enumeration(_ values: [String], _ description: String) -> JSONValue {
        .object(["type": .string("string"), "enum": .array(values.map(JSONValue.string)), "description": .string(description)])
    }
}
