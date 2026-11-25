import StudyCore
import Testing

@Suite struct RecordInitTests {
    @Test func recordsConstructibleFromOtherTargets() {
        let config = ProviderConfig(id: "abc", kind: .anthropic, name: "A", baseURL: "https://x", model: "m")
        #expect(config.id == "abc")
        #expect(config.effort == nil)
        let turn = ChatTurn(role: "user", content: "hi")
        #expect(turn.role == "user" && turn.content == "hi")
        let note = DailyNote(day: Day(rawValue: "2026-11-25")!, text: "t")
        #expect(note.text == "t")
    }
}
