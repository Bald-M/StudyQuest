import SwiftUI
import AppKit

@main
struct StudyQuestApp: App {
    @State private var model: AppModel?
    @State private var startupError: String?

    init() {
        // 未打包（swift run）时也要让窗口出现
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        do {
            _model = State(initialValue: try AppModel.open())
        } catch {
            _startupError = State(initialValue: "\(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let model {
                    RootView(model: model)
                } else {
                    ContentUnavailableView("无法打开数据库", systemImage: "exclamationmark.triangle",
                                           description: Text(startupError ?? ""))
                }
            }
            .frame(minWidth: 820, minHeight: 560)
        }
    }
}

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $model.selection) { item in
                Label(item.title, systemImage: item.icon).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            Group {
                switch model.selection {
                case .today: TodayView(model: model)
                case .review: ReviewView(model: model)
                case .mistakes: MistakesView(model: model)
                case .settings: SettingsView(model: model)
                default: PlaceholderView(item: model.selection)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top) {
                if let restoreError = model.restoreError {
                    HStack {
                        Label(restoreError, systemImage: "exclamationmark.triangle.fill").lineLimit(3)
                        Spacer()
                        Button("关闭") { model.restoreError = nil }
                    }
                    .padding(10)
                    .background(.yellow.opacity(0.2))
                }
            }
        }
        .task { await model.onLaunchOrForeground() }
    }
}

/// 尚未实现的页面；后续任务逐个替换。
struct PlaceholderView: View {
    let item: SidebarItem

    var body: some View {
        ContentUnavailableView(item.title, systemImage: item.icon, description: Text("即将推出"))
            .navigationTitle(item.title)
    }
}
