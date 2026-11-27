import StudyCore
import SwiftUI

/// 题目或卡片的教材出处：可用时点击在阅读器里打开对应的节，教材或章节被删后只显示灰字。
struct OriginLink: View {
    let model: AppModel
    let sectionId: Int64?

    @Environment(\.openWindow) private var openWindow
    @State private var origin: SectionOrigin?

    var body: some View {
        Group {
            if let origin {
                switch origin.availability {
                case .available:
                    Button("出自《\(origin.textbookTitle)》\(origin.sectionTitle)") {
                        // 该教材的窗口已打开时只会被提到前面，由它读 pendingReaderSection 跳到这一节
                        model.pendingReaderSection[origin.textbookId] = origin.sectionId
                        openWindow(value: ReaderRoute(textbookId: origin.textbookId))
                    }
                    .buttonStyle(.link)
                case .sectionRemoved:
                    Text("原章节已删除").foregroundStyle(.secondary)
                case .textbookDeleted:
                    Text("原教材已删除").foregroundStyle(.secondary)
                }
            }
        }
        .font(.caption)
        .task(id: "\(sectionId ?? -1)-\(model.revision)") {
            origin = model.origin(sectionId: sectionId)
        }
    }
}
