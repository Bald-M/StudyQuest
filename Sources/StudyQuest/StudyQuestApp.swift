import SwiftUI
import AppKit

@main
struct StudyQuestApp: App {
    init() {
        // 未打包（swift run）时也要让窗口出现
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            Text("StudyQuest")
                .font(.largeTitle)
                .frame(minWidth: 480, minHeight: 320)
        }
    }
}
