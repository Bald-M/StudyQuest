import StudyCore
import SwiftUI

/// 解析完成后、写入前的确认：书名、节数与解析提示。`stages` 非 nil 时（资料库导入）可选择所属阶段。
struct ImportTextbookSheet: View {
    let parsed: ParsedTextbook
    let stages: [Stage]?
    let onCancel: () -> Void
    let onImport: (Int) async throws -> Void

    @State private var stage: Int
    @State private var working = false
    @State private var error: String?

    init(parsed: ParsedTextbook, stages: [Stage]?, defaultStage: Int, onCancel: @escaping () -> Void, onImport: @escaping (Int) async throws -> Void) {
        self.parsed = parsed
        self.stages = stages
        self.onCancel = onCancel
        self.onImport = onImport
        _stage = State(initialValue: defaultStage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("导入「\(parsed.title)」").font(.headline)
            Text("共 \(parsed.sections.count) 节").foregroundStyle(.secondary)
            if let stages {
                Picker("所属阶段", selection: $stage) {
                    ForEach(stages) { Text("阶段 \($0.index)：\($0.title)").tag($0.index) }
                }
                .disabled(working)
            }
            if !parsed.warnings.isEmpty {
                Text("解析提示").font(.subheadline.bold())
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(parsed.warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                if working {
                    ProgressView().controlSize(.small)
                    Text("正在写入…").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction).disabled(working)
                Button("导入") {
                    working = true
                    error = nil
                    Task {
                        do { try await onImport(stage) } catch { self.error = userMessage(error) }
                        working = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(working)
            }
        }
        .padding(20)
        .frame(width: 440)
        .interactiveDismissDisabled(working)
    }
}
