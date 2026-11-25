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
            ProviderEditor(config: config, isNew: !providers.contains { $0.id == config.id }) { saved, key in
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
            message = "备份已就绪，退出并重新打开 StudyQuest 后生效。重启前的改动会被备份覆盖。"
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

    private func run(_ body: () throws -> Void) {
        do {
            try body()
        } catch {
            message = "出错了：\(error.displayText)"
        }
    }
}

// MARK: - MCP 接入

private struct MCPSection: View {
    private let path = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("studyquest-mcp").path

    var body: some View {
        Section("MCP 接入") {
            LabeledContent("studyquest-mcp") {
                Text(path).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            }
            if !FileManager.default.fileExists(atPath: path) {
                Text("该路径下没有找到 studyquest-mcp，请用 scripts/bundle-app.sh 打包后再配置。")
                    .foregroundStyle(.secondary)
            }
            snippet("Claude Code", "claude mcp add studyquest -- \(shellQuoted(path))")
            snippet("Codex（~/.codex/config.toml）", "[mcp_servers.studyquest]\ncommand = \"\(path)\"")
        }
    }

    /// 单引号包住路径，内嵌的 ' 写成 '\''，路径含空格等字符时命令照样可用。
    private func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func snippet(_ title: String, _ text: String) -> some View {
        LabeledContent(title) {
            HStack(alignment: .top) {
                Text(text).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
        }
    }
}

// MARK: - 单个阶段

private struct StageSettingsRow: View {
    let stage: Stage
    let onSave: (_ passLine: Double?, _ cooldownDays: Int?, _ reward: String?) -> Void

    @State private var passLine: Double = 0
    @State private var reward = ""

    var body: some View {
        LabeledContent {
            HStack {
                TextField("过关线", value: $passLine, format: .number)
                    .frame(width: 50)
                    .onSubmit { onSave(passLine, nil, nil) }
                Text("%")
                Stepper("冷却 \(stage.cooldownDays) 天", value: Binding(
                    get: { stage.cooldownDays }, set: { onSave(nil, $0, nil) }), in: 3...7)
                TextField("奖励", text: $reward)
                    .frame(minWidth: 120)
                    .onSubmit { onSave(nil, nil, reward) }
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
    let onSave: (ProviderConfig, String?) -> Void

    @State private var apiKey = ""
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
            TextField("模型", text: $config.model)
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
    /// StudyCore 的错误枚举没有本地化描述，localizedDescription 只会给出"操作无法完成"，改用枚举本身的描述。
    /// HTTP 错误不显示响应体：有的服务商会在报错里回显部分 Key。
    var displayText: String {
        if case AIError.http(let status, _)? = self as? AIError {
            return "连接失败（HTTP \(status)），请检查 Base URL、模型名和 API Key"
        }
        let ns = self as NSError
        if self is LocalizedError || ns.userInfo[NSLocalizedDescriptionKey] != nil { return localizedDescription }
        return String(describing: self)
    }
}
