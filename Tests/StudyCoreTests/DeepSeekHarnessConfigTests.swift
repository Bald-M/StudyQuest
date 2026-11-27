import Foundation
import Testing
@testable import StudyCore

@Test func appendsBlockAfterOtherEntries() throws {
    let existing = "- insert:\n    - id: mcp-other\n"
    let result = try DeepSeekHarnessConfig.upsert(into: existing, command: "/a/studyquest-mcp")
    #expect(result.hasPrefix(existing))
    #expect(result.contains("serverName: studyquest"))
    #expect(result.contains("command: \"/a/studyquest-mcp\""))
    #expect(result.hasSuffix(DeepSeekHarnessConfig.endMarker + "\n"))
}

@Test func emptyFileGetsOnlyTheBlock() throws {
    #expect(try DeepSeekHarnessConfig.upsert(into: "", command: "/a") == DeepSeekHarnessConfig.block(command: "/a") + "\n")
}

@Test func reconnectReplacesOldBlockInPlace() throws {
    let before = "# head\n"
    let after = "- insert:\n    - id: mcp-other\n"
    let first = try DeepSeekHarnessConfig.upsert(into: before, command: "/old") + after
    let second = try DeepSeekHarnessConfig.upsert(into: first, command: "/new")
    #expect(!second.contains("/old"))
    #expect(second.contains("\"/new\""))
    #expect(second.hasPrefix(before))
    #expect(second.hasSuffix(after))
    #expect(second.components(separatedBy: DeepSeekHarnessConfig.beginMarker).count == 2)
}

@Test func quotesSpecialCharacters() {
    #expect(DeepSeekHarnessConfig.yamlQuoted(#"/My "App"\x"#) == #""/My \"App\"\\x""#)
}

@Test func refusesToWriteWithOrphanMarker() {
    let orphan = DeepSeekHarnessConfig.beginMarker + "\n- insert:\n    - id: mcp-other\n"
    #expect(throws: DeepSeekHarnessConfig.BrokenMarkers.self) { try DeepSeekHarnessConfig.upsert(into: orphan, command: "/a") }
    #expect(throws: DeepSeekHarnessConfig.BrokenMarkers.self) { try DeepSeekHarnessConfig.upsert(into: DeepSeekHarnessConfig.endMarker, command: "/a") }
}
