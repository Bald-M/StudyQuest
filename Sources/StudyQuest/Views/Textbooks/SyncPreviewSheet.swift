import StudyCore
import SwiftUI

/// 从原文件更新前的预览；确认后才写入。
struct SyncPreviewSheet: View {
    let title: String
    let plan: SyncPlan
    let onCancel: () -> Void
    let onApply: () async throws -> Void

    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("更新「\(title)」").font(.headline)
            Text("改了 \(plan.changed.count) 节、新增 \(plan.added.count) 节、删除 \(plan.removed.count) 节")
            if !plan.changed.isEmpty {
                Text("改过的节下次闯关会重新出题").font(.caption).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                if working {
                    ProgressView().controlSize(.small)
                    Text("正在更新…").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction).disabled(working)
                Button("更新") {
                    working = true
                    error = nil
                    Task {
                        do { try await onApply() } catch { self.error = userMessage(error) }
                        working = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(working)
            }
        }
        .padding(20)
        .frame(width: 400)
        .interactiveDismissDisabled(working)
    }
}
