import SwiftUI

/// 考试作答页顶部的倒计时条：每秒按注入的时间来源对一次截止时间；剩 5 分钟及以下变橙，1 分钟及以下变红。
/// 剩 2 秒时触发一次 `onNearExpiry`（AnswerView 借此把未保存的答案先写入）；
/// 到点后只触发一次 `onExpire`，由 AnswerView 走与"交卷"按钮相同的路径（先保存、再交卷、再判卷）。
struct ExamSessionView: View {
    let deadline: Date
    let now: () -> Date
    let onExpire: () -> Void
    /// 自动交卷失败时为 true：显示「重新交卷」。
    var failed = false
    var onRetry: () -> Void = {}
    var onNearExpiry: () -> Void = {}

    @State private var remaining: TimeInterval
    @State private var expired = false
    @State private var nearExpiryFired = false

    init(deadline: Date, now: @escaping () -> Date, failed: Bool = false, onRetry: @escaping () -> Void = {},
         onNearExpiry: @escaping () -> Void = {}, onExpire: @escaping () -> Void) {
        self.deadline = deadline
        self.now = now
        self.failed = failed
        self.onRetry = onRetry
        self.onNearExpiry = onNearExpiry
        self.onExpire = onExpire
        _remaining = State(initialValue: max(0, deadline.timeIntervalSince(now())))
    }

    var body: some View {
        HStack {
            Image(systemName: "timer")
            Text(expired ? (failed ? "时间已到，交卷失败" : "时间已到，正在交卷…") : "剩余 \(Self.format(remaining))")
                .font(.title3.monospacedDigit().bold())
            Spacer()
            if failed { Button("重新交卷", action: onRetry) }
            Text("考试中不提供提示").font(.caption).foregroundStyle(.secondary)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(color.opacity(0.1))
        .task {
            while !Task.isCancelled {
                tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var color: Color {
        if expired || remaining <= 60 { return .red }
        return remaining <= 300 ? .orange : .primary
    }

    private func tick() {
        remaining = max(0, deadline.timeIntervalSince(now()))
        if remaining > 0, remaining <= 2, !nearExpiryFired {
            nearExpiryFired = true
            onNearExpiry()
        }
        if remaining <= 0, !expired {
            expired = true
            onExpire()
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
