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
        WindowGroup("教材", for: ReaderRoute.self) { $route in
            if let model, let route {
                ReaderView(model: model, route: route)
            }
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
                case .map: MapView(model: model)
                case .mistakes: MistakesView(model: model)
                case .practice: PracticeView(model: model)
                case .exams: ExamsView(model: model)
                case .growth: GrowthView(model: model)
                case .settings: SettingsView(model: model)
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
        .sheet(isPresented: Binding(get: { model.activeAttemptId != nil }, set: { if !$0 { model.activeAttemptId = nil } })) {
            if let id = model.activeAttemptId {
                AnswerView(model: model, attemptId: id, showHints: true) {
                    model.activeAttemptId = nil
                    model.refresh()
                }
                .id(id)
            }
        }
        .task { await model.onLaunchOrForeground() }
    }
}
