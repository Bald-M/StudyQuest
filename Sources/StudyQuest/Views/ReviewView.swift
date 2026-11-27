import StudyCore
import SwiftUI

struct ReviewView: View {
    let model: AppModel

    @State private var cards: [Card] = []
    @State private var deferred = 0
    @State private var cleared = false
    @State private var flipped = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            if let card = cards.first {
                Text("还剩 \(cards.count) 张").foregroundStyle(.secondary)
                cardFace(card)
                HStack(spacing: 16) {
                    Button("忘了 (1)") { answer(card, remembered: false) }
                        .keyboardShortcut("1", modifiers: [])
                    Button("记得 (2)") { answer(card, remembered: true) }
                        .keyboardShortcut("2", modifiers: [])
                        .buttonStyle(.borderedProminent)
                }
                .disabled(!flipped)
                .controlSize(.large)
            } else {
                ContentUnavailableView(
                    cleared ? "今日复习完成 +20" : "暂无待复习卡片",
                    systemImage: cleared ? "checkmark.seal.fill" : "tray")
            }
            if deferred > 0 {
                Text("另有 \(deferred) 张已顺延到之后").font(.callout).foregroundStyle(.secondary)
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("复习")
        .onAppear(perform: reload)
        .onChange(of: model.revision) { reload() }
    }

    private func cardFace(_ card: Card) -> some View {
        VStack(spacing: 8) {
            flipButton(card)
            if flipped { OriginLink(model: model, sectionId: card.sectionId) }
        }
    }

    private func flipButton(_ card: Card) -> some View {
        Button { flipped.toggle() } label: {
            VStack(spacing: 12) {
                Text(flipped ? "答案" : "问题").font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    Text(flipped ? card.back : card.front).font(.title2).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                Text(flipped ? "" : "点击或按空格翻面").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(24)
            .frame(maxWidth: 560, minHeight: 220, maxHeight: 320)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])
    }

    private func answer(_ card: Card, remembered: Bool) {
        guard let id = card.id else { return }
        do {
            try model.recordReview(cardId: id, remembered: remembered)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        reload()
    }

    /// 以数据库为准重读队列。
    private func reload() {
        do {
            let queue = try model.reviewQueue()
            if queue.cards.first?.id != cards.first?.id { flipped = false }
            cards = queue.cards
            deferred = queue.deferred
            cleared = try model.reviewClearedToday()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
