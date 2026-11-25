/// 内置 10 阶段路线（设计文档第 9 节与附录 A）。写成字符串常量，避免 SwiftPM 资源包在 .app 中定位不可靠。
/// 模块以 [key, 标题, 要点] 表示；游戏任务、生活题、推荐资源为阶段级，播种时复制到每个模块。
enum CurriculumData {
    static let json = #"""
    {
      "stages": [
        {
          "index": 0, "title": "工具与学习系统", "estimatedWeeks": "1–2 周", "passLine": 80,
          "summary": "终端、Git、Markdown、Anki。考试：上机。在新仓库里制造一次合并冲突并解决；用命令完成一组文件操作。",
          "resources": ["Pro Git（中文版）", "The Missing Semester"],
          "gameTasks": ["Learn Git Branching", "OverTheWire Bandit 第 0–10 关"],
          "lifeProblems": ["用 Git 管理自己的笔记仓库"],
          "modules": [
            ["s0.terminal", "终端基础", "目录与文件操作、管道与重定向、查看帮助"],
            ["s0.git", "Git（提交、分支、合并、冲突）", "提交历史、分支、合并、解决冲突"],
            ["s0.vscode-markdown", "VS Code 与 Markdown", "编辑器基本操作与 Markdown 语法"],
            ["s0.anki-app", "Anki 与本应用的用法", "间隔复习、卡片制作、本应用的作业与考试流程"]
          ]
        },
        {
          "index": 1, "title": "编程基础（Python）", "estimatedWeeks": "5–6 周", "passLine": 80,
          "summary": "Python 编程基础。考试：90 分钟。理论占 30%，上机占 70%（5 道题，至少做对 4 道）。",
          "resources": ["Python 官方教程", "Codewars"],
          "gameTasks": ["文字冒险游戏 → 猜词游戏（Wordle 玩法）→ 用 pygame 写贪吃蛇", "Codewars 从 8kyu 做到 6kyu"],
          "lifeProblems": ["命令行记账本（含月度统计）", "外卖满减与红包叠加的最优凑单", "课程表冲突检测"],
          "modules": [
            ["s1.variables", "变量与类型", "基本类型、类型转换、输入输出"],
            ["s1.control-flow", "分支和循环", "if、for、while、break/continue"],
            ["s1.functions", "函数", "参数、返回值、作用域"],
            ["s1.list-dict", "列表和字典", "增删改查、推导式、遍历"],
            ["s1.file-io", "文件读写", "open、with、文本与 CSV"],
            ["s1.exceptions", "异常处理", "try/except、自定义异常"],
            ["s1.oop-intro", "面向对象入门", "类、对象、继承"],
            ["s1.unittest-intro", "单元测试入门", "unittest/pytest 基本用法"]
          ]
        },
        {
          "index": 2, "title": "数据结构与算法", "estimatedWeeks": "8–10 周", "passLine": 75,
          "summary": "数据结构与算法。考试：2 小时。4 道题（2 道简单、2 道中等），外加复杂度口述分析。",
          "resources": ["代码随想录", "LeetCode"],
          "gameTasks": ["迷宫生成与自动寻路可视化", "数独求解器（回溯）", "每周参加 LeetCode 周赛"],
          "lifeProblems": ["深圳地铁最少换乘（BFS / Dijkstra）", "外卖派单（堆）", "撤销与重做（栈）", "通讯录快速查找（哈希表）"],
          "modules": [
            ["s2.complexity", "复杂度分析", "大 O、时间与空间复杂度"],
            ["s2.array-string", "数组与字符串", "遍历、前缀和、字符串处理"],
            ["s2.hash", "哈希表", "哈希冲突、计数与查找"],
            ["s2.two-pointers", "双指针", "快慢指针、对撞指针、滑动窗口"],
            ["s2.stack-queue", "栈与队列", "单调栈、队列模拟"],
            ["s2.linked-list", "链表", "反转、环检测、合并"],
            ["s2.recursion", "递归", "递归三要素、分治、回溯入口"],
            ["s2.sorting", "排序", "常见排序的原理与复杂度"],
            ["s2.binary-search", "二分查找", "边界处理、答案二分"],
            ["s2.tree", "树", "遍历、二叉搜索树、递归解法"],
            ["s2.bfs-dfs", "BFS 与 DFS", "层序遍历、连通块、回溯"],
            ["s2.heap", "堆", "优先队列、Top K"],
            ["s2.graph", "图", "邻接表、拓扑排序、最短路径"],
            ["s2.dp-intro", "动态规划入门", "状态定义、转移方程、经典背包与路径题"]
          ]
        },
        {
          "index": 3, "title": "计算机基础（网络 / 操作系统 / 数据库）", "estimatedWeeks": "6–8 周", "passLine": 80,
          "summary": "网络、操作系统、数据库。考试：选择题、简答题、SQL 上机。每天保留 1–2 道算法题作为长期练习。",
          "resources": ["《图解 HTTP》", "CS:APP", "SQLBolt"],
          "gameTasks": ["SQL Murder Mystery", "SQL Island", "可选 Turing Complete"],
          "lifeProblems": ["用 Wireshark 抓包，画出“打开 B 站时发生了什么”", "12306 抢票为什么会超卖，用锁解决", "银行转账为什么需要事务"],
          "modules": [
            ["s3.http", "HTTP 与 HTTPS", "请求与响应、状态码、TLS 握手"],
            ["s3.tcpip-dns", "TCP/IP 与 DNS", "三次握手、四次挥手、域名解析"],
            ["s3.process-thread", "进程与线程", "调度、上下文切换"],
            ["s3.memory", "内存管理", "虚拟内存、分页、垃圾回收概念"],
            ["s3.concurrency-lock", "并发与锁", "竞态、互斥锁、死锁"],
            ["s3.sql", "SQL", "增删改查、连接、分组聚合"],
            ["s3.index", "索引", "B+ 树、最左前缀、执行计划"],
            ["s3.transaction", "事务与隔离级别", "ACID、隔离级别、MVCC 概念"]
          ]
        },
        {
          "index": 4, "title": "前端（HTML/CSS/JS/TS + Vue 3，末尾 React 迁移）", "estimatedWeeks": "7–8 周", "passLine": 80,
          "summary": "HTML、CSS、JavaScript、TypeScript、Vue 3，末尾 React 迁移。考试：3 小时上机。按需求文档和模拟接口实现一个页面，按评分表打分。",
          "resources": ["MDN Web Docs", "Vue 3 官方文档"],
          "gameTasks": ["Flexbox Froggy", "Grid Garden", "网页版 2048"],
          "lifeProblems": ["天气查询页（调用真实 API）", "网页版记账本"],
          "modules": [
            ["s4.html", "HTML 语义化", "语义标签、表单、可访问性"],
            ["s4.css-layout", "CSS 布局（Flexbox、Grid）", "盒模型、Flexbox、Grid、响应式"],
            ["s4.js-core", "JavaScript 核心（闭包、Promise、async/await、事件循环）", "闭包、Promise、事件循环"],
            ["s4.dom", "DOM", "选择、修改、事件委托"],
            ["s4.typescript", "TypeScript", "类型标注、接口、泛型"],
            ["s4.vue3", "Vue 3", "组合式 API、响应式、路由与状态"],
            ["s4.react-migration", "React 迁移", "把 Vue 项目的核心页面迁移到 React"]
          ]
        },
        {
          "index": 5, "title": "后端（Java + Spring Boot + MySQL/Redis）", "estimatedWeeks": "10–12 周", "passLine": 80,
          "summary": "Java、Spring Boot、MySQL、Redis。考试：4 小时。按接口文档实现一组 API（AI 对照接口文档和测试用例判分），另加一场后端常见知识点笔试。",
          "resources": ["Spring 官方指南", "《Java 核心技术》"],
          "gameTasks": ["用 WebSocket 做联机五子棋"],
          "lifeProblems": ["校园二手交易平台后端", "优惠券秒杀（Redis 防超卖）", "短链接服务"],
          "modules": [
            ["s5.java-syntax", "Java 语法", "类型、控制流、面向对象"],
            ["s5.collections", "集合", "List、Map、Set 与泛型"],
            ["s5.threads", "多线程基础", "线程池、synchronized、并发工具"],
            ["s5.jvm", "JVM 入门", "内存模型、垃圾回收、类加载"],
            ["s5.spring-rest", "Spring Boot 与 REST", "控制器、依赖注入、参数校验"],
            ["s5.mybatis", "MyBatis", "映射、动态 SQL"],
            ["s5.mysql-design", "MySQL 表设计", "范式、索引设计、慢查询"],
            ["s5.redis", "Redis 缓存", "数据结构、缓存穿透与击穿、分布式锁"],
            ["s5.jwt", "JWT 鉴权", "登录态、令牌签发与校验"],
            ["s5.unit-test", "单元测试", "JUnit、Mockito、接口测试"],
            ["s5.mq-intro", "消息队列入门", "削峰、解耦、可靠投递"]
          ]
        },
        {
          "index": 6, "title": "工程化与部署（Linux/Docker/CI）", "estimatedWeeks": "3–4 周", "passLine": 80,
          "summary": "Linux、Docker、Nginx、CI。考试：2 小时内从空服务器完成部署，再修好 4 个预先埋好的故障（至少修好 3 个）。",
          "resources": ["Docker 官方文档", "GitHub Actions 文档"],
          "gameTasks": ["OverTheWire Bandit 打到第 20 关"],
          "lifeProblems": ["把阶段 5 的项目部署上线，让同学真正用起来"],
          "modules": [
            ["s6.linux", "Linux 常用操作", "权限、进程、服务管理"],
            ["s6.docker", "Docker", "镜像、容器、Compose"],
            ["s6.nginx", "Nginx", "反向代理、静态资源、HTTPS"],
            ["s6.github-actions", "GitHub Actions 持续集成", "工作流、缓存、部署"],
            ["s6.logs-debug", "日志与排障", "日志分析、常见故障定位"]
          ]
        },
        {
          "index": 7, "title": "AI 应用开发（LLM/RAG/Agent）", "estimatedWeeks": "6–8 周", "passLine": 75,
          "summary": "LLM、RAG、Agent。考试：给定一份文档集，搭一个 RAG 系统，用 20 道题测准确率（至少 70%），外加代码答辩。",
          "resources": ["Anthropic 官方文档", "LangGraph 文档"],
          "gameTasks": ["AI 狼人杀，或有大模型 NPC 的文字冒险"],
          "lifeProblems": ["课程资料问答助手", "简历与 JD 匹配助手", "一句话记账"],
          "modules": [
            ["s7.llm-basics", "大模型基础（token、上下文、temperature）", "token、上下文窗口、采样参数"],
            ["s7.prompting", "提示词工程", "角色、示例、约束与迭代"],
            ["s7.structured-output", "结构化输出", "JSON Schema、校验与重试"],
            ["s7.function-calling", "函数调用", "工具定义、调用循环"],
            ["s7.rag", "RAG（分块、向量化、pgvector）", "分块、嵌入、检索与重排"],
            ["s7.agent", "Agent（ReAct、LangGraph）", "ReAct 循环、状态图"],
            ["s7.mcp-intro", "MCP 入门", "工具、资源、提示模板"],
            ["s7.evaluation", "效果评测", "测试集、指标、回归"],
            ["s7.fastapi", "FastAPI", "接口、异步、流式响应"]
          ]
        },
        {
          "index": 8, "title": "毕业大项目", "estimatedWeeks": "6–8 周", "passLine": 85,
          "summary": "毕业大项目。考试：模拟答辩，按评分表打分（至少 85 分）。重点考能否讲清个人负责的功能、技术取舍和验证方法。",
          "resources": ["自选"],
          "gameTasks": [],
          "lifeProblems": ["项目本身就是解决一个真实问题"],
          "modules": [
            ["s8.requirements", "需求与设计", "需求文档、原型、接口设计"],
            ["s8.frontend", "前端", "页面与交互实现"],
            ["s8.backend", "后端（Spring Boot）", "接口、鉴权、数据层"],
            ["s8.ai-service", "AI 服务（FastAPI）", "模型调用与检索服务"],
            ["s8.storage", "数据存储（MySQL、Redis）", "表设计与缓存策略"],
            ["s8.docker-deploy", "Docker 部署", "镜像构建、编排、上线"],
            ["s8.ci-testing", "持续集成与测试", "自动化测试与流水线"],
            ["s8.readme-demo", "README 与演示视频", "文档与演示材料"]
          ]
        },
        {
          "index": 9, "title": "求职冲刺", "estimatedWeeks": "4–6 周", "passLine": 80,
          "summary": "求职冲刺。考试规则见设计文档 7.2。",
          "resources": ["LeetCode Hot 100", "牛客面经"],
          "gameTasks": [],
          "lifeProblems": ["用真实 JD 做简历匹配与面试准备"],
          "modules": [
            ["s9.interview-knowledge", "常见面试知识点", "按阶段 1–7 的高频题复盘"],
            ["s9.hot100", "LeetCode Hot 100 二刷", "按题型分组刷题"],
            ["s9.resume", "简历打磨", "项目描述、量化成果"],
            ["s9.mock-interview", "模拟面试", "完整的模拟面试与复盘"]
          ]
        }
      ],
      "stageZeroCards": [
        {"module": "s0.terminal", "front": "终端里 `pwd` 命令的作用是什么？", "back": "打印当前所在目录的绝对路径。", "tags": ["terminal"]},
        {"module": "s0.terminal", "front": "`ls -la` 比 `ls` 多显示什么？", "back": "显示隐藏文件（以 . 开头）以及权限、所有者、大小、时间等详细信息。", "tags": ["terminal"]},
        {"module": "s0.git", "front": "`git add` 与 `git commit` 分别做什么？", "back": "add 把改动放入暂存区；commit 把暂存区内容记录成一次提交。", "tags": ["git"]},
        {"module": "s0.git", "front": "合并出现冲突时，文件里的 <<<<<<< ======= >>>>>>> 标记表示什么？", "back": "两个分支对同一处的不同改动：上半是当前分支，下半是被合并分支。手动保留想要的内容并删除标记，再 add 和 commit。", "tags": ["git"]},
        {"module": "s0.vscode-markdown", "front": "Markdown 里如何写一个二级标题和一个行内代码？", "back": "二级标题用 `## 标题`；行内代码用反引号包住，如 `code`。", "tags": ["markdown"]}
      ],
      "stageZeroProblems": [
        {"module": "s0.terminal", "kind": "singleChoice", "difficulty": "easy", "prompt": "想把命令 `ls` 的输出保存到文件 out.txt（覆盖原内容），应该用哪个写法？",
         "options": ["ls | out.txt", "ls > out.txt", "ls < out.txt", "ls >> out.txt"], "referenceAnswer": "B",
         "rubric": "选 B 得满分；D 是追加而非覆盖。", "maxScore": 10, "tags": ["terminal"]},
        {"module": "s0.git", "kind": "shortAnswer", "difficulty": "medium", "prompt": "简述 git merge 出现冲突后的处理步骤。",
         "options": [], "referenceAnswer": "git status 找出冲突文件；打开文件，按需保留内容并删除冲突标记；git add 标记已解决；git commit 完成合并。",
         "rubric": "要点：定位冲突文件、编辑并删除标记、add、commit。每点 25%。", "maxScore": 10, "tags": ["git"]},
        {"module": "s0.terminal", "kind": "coding", "difficulty": "medium", "prompt": "写出一条命令：在当前目录递归查找所有扩展名为 .md 的文件并列出路径。",
         "options": [], "referenceAnswer": "find . -name \"*.md\"",
         "rubric": "使用 find（或等价的 fd/ls 递归写法）且匹配 .md 文件，得满分；缺少递归得一半。", "maxScore": 10, "tags": ["terminal"]},
        {"module": "s0.git", "kind": "singleChoice", "difficulty": "easy", "prompt": "想基于当前提交新建并切换到名为 feature 的分支，应该用哪条命令？",
         "options": ["git branch feature", "git checkout -b feature", "git merge feature", "git push feature"], "referenceAnswer": "B",
         "rubric": "选 B 得满分（git switch -c 同效）；A 只创建不切换。", "maxScore": 10, "tags": ["git"]},
        {"module": "s0.vscode-markdown", "kind": "shortAnswer", "difficulty": "easy", "prompt": "写出一段 Markdown：一个一级标题“笔记”，下面一个包含两项的无序列表。",
         "options": [], "referenceAnswer": "# 笔记\n\n- 第一项\n- 第二项",
         "rubric": "一级标题用 #；列表用 - 或 *，共两项。各占 50%。", "maxScore": 10, "tags": ["markdown"]}
      ]
    }
    """#
}
