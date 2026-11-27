import AppKit
import StudyCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let model: AppModel

    @State private var providers: [ProviderConfig] = []
    @State private var gradingId = ""
    @State private var generationId = ""
    @State private var newCardLimit = 20
    @State private var reviewCap = 100
    @State private var autoGenEnabled = true
    @State private var autoGenDailyMax = 3
    @State private var assignmentSize = 5
    @State private var stages: [Stage] = []
    @State private var editing: ProviderConfig?
    @State private var testResults: [String: String] = [:]
    @State private var message: String?

    var body: some View {
        Form {
            if let message {
                Section { Text(message).foregroundStyle(.secondary) }
            }
            providersSection
            MCPSection()
            reviewSection
            autoGenSection
            stagesSection
            dataSection
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
        .onAppear(perform: reload)
        .onChange(of: model.revision) { reload() }
        .sheet(item: $editing) { config in
            ProviderEditor(config: config, isNew: !providers.contains { $0.id == config.id }, registry: model.registry) { saved, key in
                save(saved, apiKey: key)
            }
        }
    }

    // MARK: AI 服务商

    private var providersSection: some View {
        Section("AI 服务商") {
            ForEach(providers) { config in
                LabeledContent {
                    HStack {
                        if let result = testResults[config.id] {
                            Text(result).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Button("测试连接") { test(config) }
                        Button("编辑") { editing = config }
                        Button("删除", role: .destructive) { delete(config) }
                    }
                } label: {
                    Text(config.name)
                    Text("\(config.kind == .anthropic ? "Anthropic" : "OpenAI 兼容") · \(config.model)")
                }
            }
            Button("添加服务商") {
                editing = ProviderConfig(id: UUID().uuidString, kind: .openAICompatible, name: "",
                                         baseURL: "https://api.openai.com/v1", model: "")
            }
            Picker("判卷用", selection: settingBinding($gradingId, .gradingProviderId)) {
                Text("未选择").tag("")
                ForEach(providers) { Text($0.name).tag($0.id) }
            }
            Picker("出题与助教用", selection: settingBinding($generationId, .generationProviderId)) {
                Text("未选择").tag("")
                ForEach(providers) { Text($0.name).tag($0.id) }
            }
        }
    }

    // MARK: 复习与自动生成

    private var reviewSection: some View {
        Section("复习") {
            Stepper("每日新卡上限：\(newCardLimit)", value: intBinding($newCardLimit, .dailyNewCardLimit), in: 0...200)
            Stepper("复习显示上限：\(reviewCap)", value: intBinding($reviewCap, .reviewDisplayCap), in: 10...1000, step: 10)
        }
    }

    private var autoGenSection: some View {
        Section("自动生成") {
            Toggle("每天自动出作业", isOn: Binding(
                get: { autoGenEnabled },
                set: { autoGenEnabled = $0; write(.autoGenEnabled, $0 ? "true" : "false") }))
            Stepper("每日最多份数：\(autoGenDailyMax)", value: intBinding($autoGenDailyMax, .autoGenDailyMax), in: 0...10)
            Stepper("每份题数：\(assignmentSize)", value: intBinding($assignmentSize, .assignmentSize), in: 1...20)
        }
    }

    // MARK: 阶段

    private var stagesSection: some View {
        Section("阶段过关线、冷却期与奖励") {
            ForEach(stages) { stage in
                StageSettingsRow(stage: stage) { passLine, cooldown, reward in
                    run { try model.store.updateStageSettings(index: stage.index, passLine: passLine, cooldownDays: cooldown, reward: reward) }
                }
            }
        }
    }

    // MARK: 数据

    private var dataSection: some View {
        Section("数据") {
            LabeledContent("数据库", value: model.dbURL.path)
            HStack {
                Button("导出全部数据…", action: exportData)
                Button("从备份恢复…", action: restoreData)
            }
        }
    }

    // MARK: 动作

    private func reload() {
        run {
            let store = model.store
            providers = try model.registry.configs()
            gradingId = try store.setting(.gradingProviderId)
            generationId = try store.setting(.generationProviderId)
            newCardLimit = Int(try store.setting(.dailyNewCardLimit)) ?? 20
            reviewCap = Int(try store.setting(.reviewDisplayCap)) ?? 100
            autoGenEnabled = try store.setting(.autoGenEnabled) == "true"
            autoGenDailyMax = Int(try store.setting(.autoGenDailyMax)) ?? 3
            assignmentSize = Int(try store.setting(.assignmentSize)) ?? 5
            stages = try store.stages()
        }
    }

    private func save(_ config: ProviderConfig, apiKey: String?) {
        run { try model.registry.save(config, apiKey: apiKey) }
        testResults[config.id] = nil
        reload()
    }

    private func delete(_ config: ProviderConfig) {
        run {
            try model.registry.delete(id: config.id)
            if gradingId == config.id { try model.store.setSetting(.gradingProviderId, "") }
            if generationId == config.id { try model.store.setSetting(.generationProviderId, "") }
        }
        reload()
    }

    private func test(_ config: ProviderConfig) {
        testResults[config.id] = "正在测试…"
        Task {
            do {
                try await model.registry.testConnection(id: config.id)
                testResults[config.id] = "连接成功"
            } catch {
                testResults[config.id] = "失败：\(error.displayText)"
            }
        }
    }

    private func exportData() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "StudyQuest-备份-\(model.store.clock.today().rawValue).sqlite"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run {
            try BackupService.export(database: model.database, to: url)
            message = "已导出到 \(url.path)"
        }
    }

    private func restoreData() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run {
            try BackupService.scheduleRestore(from: url, dbURL: model.dbURL)
            message = "备份已就绪，退出并重新打开 StudyQuest 后生效。重启前的改动会被备份覆盖。恢复前请先退出正在使用 StudyQuest MCP 的 AI 助手。"
        }
    }

    private func write(_ key: SettingKey, _ value: String) {
        run { try model.store.setSetting(key, value) }
    }

    private func settingBinding(_ state: Binding<String>, _ key: SettingKey) -> Binding<String> {
        Binding(get: { state.wrappedValue }, set: { state.wrappedValue = $0; write(key, $0) })
    }

    private func intBinding(_ state: Binding<Int>, _ key: SettingKey) -> Binding<Int> {
        Binding(get: { state.wrappedValue }, set: { state.wrappedValue = $0; write(key, String($0)) })
    }

    @discardableResult private func run(_ body: () throws -> Void) -> Bool {
        do {
            try body()
            return true
        } catch {
            message = "出错了：\(error.displayText)"
            return false
        }
    }
}

// MARK: - MCP 接入

private struct MCPSection: View {
    private let path = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("studyquest-mcp").path

    @State private var busy: String?
    @State private var results: [String: String] = [:]

    var body: some View {
        Section("MCP 接入") {
            if !FileManager.default.fileExists(atPath: path) {
                Text("该路径下没有找到 studyquest-mcp，请用 scripts/bundle-app.sh 打包后再配置。")
                    .foregroundStyle(.secondary)
            }
            connectRow("Claude Code") {
                try runShell("claude mcp remove -s user studyquest >/dev/null 2>&1; claude mcp add -s user studyquest -- \(shellQuoted(path))")
                return "已连接，新开的 Claude Code 会话可用。"
            }
            connectRow("Codex") {
                try runShell("codex mcp remove studyquest >/dev/null 2>&1; codex mcp add studyquest -- \(shellQuoted(path))")
                return "已连接，新开的 Codex 会话可用。"
            }
            connectRow("DeepSeek Harness") {
                try connectDeepSeekHarness()
                return "已写入配置，重启 DeepSeek Harness 后生效。"
            }
        }
    }

    private func connectRow(_ title: String, action: @escaping @Sendable () throws -> String) -> some View {
        LabeledContent {
            HStack {
                if let result = results[title] {
                    Text(result).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if busy == title { ProgressView().controlSize(.small) }
                Button("连接") {
                    busy = title
                    results[title] = nil
                    Task {
                        let outcome = await Task.detached {
                            do { return try action() } catch { return "连接失败：\(error.displayText)" }
                        }.value
                        results[title] = outcome
                        busy = nil
                    }
                }
                .disabled(busy != nil || !FileManager.default.fileExists(atPath: path))
            }
        } label: {
            Text(title)
        }
    }

    /// 用交互式登录 shell 执行（会读 ~/.zprofile 和 ~/.zshrc），GUI 应用才能拿到 Homebrew、nvm 等加进 PATH 的命令。
    nonisolated private func runShell(_ command: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-ilc", command]
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw ConnectError(text.isEmpty ? "命令退出码 \(process.terminationStatus)" : text)
        }
    }

    nonisolated private func connectDeepSeekHarness() throws {
        let env = ProcessInfo.processInfo.environment["DSH_HOME"]
        let home = env.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dsh")
        guard FileManager.default.fileExists(atPath: home.path) else {
            throw ConnectError("没有找到 \(home.path)，请先安装并运行一次 DeepSeek Harness。")
        }
        let file = home.appendingPathComponent("cordis.patch.yml")
        let existing = FileManager.default.fileExists(atPath: file.path) ? try String(contentsOf: file, encoding: .utf8) : ""
        try DeepSeekHarnessConfig.upsert(into: existing, command: path).write(to: file, atomically: true, encoding: .utf8)
    }

    /// 单引号包住路径，内嵌的 ' 写成 '\''，路径含空格等字符时命令照样可用。
    nonisolated private func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private struct ConnectError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

// MARK: - 单个阶段

private struct StageSettingsRow: View {
    let stage: Stage
    /// 返回是否保存成功；失败时（如过关线超出 1–100）输入框恢复为当前值，错误由 SettingsView 顶部显示。
    let onSave: (_ passLine: Double?, _ cooldownDays: Int?, _ reward: String?) -> Bool

    @State private var passLine: Double = 0
    @State private var reward = ""

    var body: some View {
        LabeledContent {
            HStack {
                TextField("过关线", value: $passLine, format: .number)
                    .frame(width: 50)
                    .onSubmit { if !onSave(passLine, nil, nil) { sync() } }
                Text("%")
                Stepper("冷却 \(stage.cooldownDays) 天", value: Binding(
                    get: { stage.cooldownDays }, set: { _ = onSave(nil, $0, nil) }), in: 3...7)
                TextField("奖励", text: $reward)
                    .frame(minWidth: 120)
                    .onSubmit { if !onSave(nil, nil, reward) { sync() } }
            }
            .labelsHidden()
        } label: {
            Text("阶段 \(stage.index) \(stage.title)")
        }
        .onAppear(perform: sync)
        .onChange(of: stage) { sync() }
    }

    private func sync() {
        passLine = stage.passLine
        reward = stage.reward ?? ""
    }
}

// MARK: - 编辑服务商

private struct ProviderEditor: View {
    @State var config: ProviderConfig
    let isNew: Bool
    let registry: ProviderRegistry
    let onSave: (ProviderConfig, String?) -> Void

    @State private var apiKey = ""
    @State private var models: [String] = []
    @State private var modelsStatus: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Picker("类型", selection: $config.kind) {
                Text("OpenAI 兼容").tag(ProviderKind.openAICompatible)
                Text("Anthropic").tag(ProviderKind.anthropic)
            }
            .onChange(of: config.kind) { applyDefaults() }
            TextField("名称", text: $config.name)
            TextField("Base URL", text: $config.baseURL)
            LabeledContent("模型") {
                HStack {
                    TextField("模型", text: $config.model, prompt: Text(modelsStatus ?? ""))
                        .labelsHidden()
                    Menu {
                        ForEach(models, id: \.self) { id in
                            Button(id) { config.model = id }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .disabled(models.isEmpty)
                    .help(modelsStatus ?? "从服务商的模型列表中选择")
                }
            }
            .task(id: ModelQuery(kind: config.kind, baseURL: config.baseURL, apiKey: apiKey)) { await loadModels() }
            if config.kind == .anthropic {
                TextField("effort", text: Binding(get: { config.effort ?? "medium" }, set: { config.effort = $0 }))
            }
            SecureField("API Key", text: $apiKey, prompt: Text(isNew ? "必填" : "留空则保留原 Key"))
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    onSave(config, apiKey.isEmpty ? nil : apiKey)
                    dismiss()
                }
                .disabled(config.name.isEmpty || config.baseURL.isEmpty || config.model.isEmpty || (isNew && apiKey.isEmpty))
            }
        }
    }

    private struct ModelQuery: Equatable { let kind: ProviderKind; let baseURL: String; let apiKey: String }

    /// 地址、类型或 Key 变化后稍等再查，避免逐字输入时连发请求。新建且没填 Key 时不查。
    private func loadModels() async {
        models = []
        guard !(isNew && apiKey.isEmpty), !config.baseURL.isEmpty else {
            modelsStatus = isNew ? "填写 API Key 后可从列表选择" : nil
            return
        }
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        modelsStatus = "正在获取模型列表…"
        do {
            let ids = try await registry.availableModels(for: config, apiKey: apiKey)
            guard !Task.isCancelled else { return }
            models = ids
            modelsStatus = ids.isEmpty ? "服务商没有返回模型，请手动填写" : nil
        } catch {
            guard !Task.isCancelled else { return }
            modelsStatus = "获取模型列表失败，请手动填写"
        }
    }

    /// 只在新建时按类型填默认地址与模型，编辑已有服务商不改用户填的值。
    private func applyDefaults() {
        guard isNew else { return }
        switch config.kind {
        case .openAICompatible:
            config.baseURL = "https://api.openai.com/v1"
            config.model = ""
            config.effort = nil
        case .anthropic:
            config.baseURL = "https://api.anthropic.com"
            config.model = "claude-opus-5-5"
            config.effort = "medium"
        }
    }
}

private extension Error {
    /// 没有本地化描述的错误（localizedDescription 只会给出"操作无法完成"）改用枚举本身的描述。
    /// HTTP 错误不显示响应体（有的服务商会在报错里回显部分 Key），并提示检查哪些配置。
    var displayText: String {
        if case AIError.http(let status, _)? = self as? AIError {
            return "连接失败（HTTP \(status)），请检查 Base URL、模型名和 API Key"
        }
        let ns = self as NSError
        if self is LocalizedError || ns.userInfo[NSLocalizedDescriptionKey] != nil { return localizedDescription }
        return String(describing: self)
    }
}
