import Foundation
import Testing

@testable import SpectrumCore

private let sample = """
    {"type":"user","uuid":"u1","message":{"role":"user","content":"make the notch blue"}}
    {"type":"user","uuid":"m1","isMeta":true,"message":{"role":"user","content":"meta"}}
    {"type":"user","uuid":"c1","message":{"role":"user","content":"<command-name>/clear</command-name>"}}
    {"type":"assistant","uuid":"a1","message":{"role":"assistant","content":[{"type":"text","text":"On it."},{"type":"tool_use","name":"Bash","input":{"command":"swift build\\nswift test","description":"Build"}}]}}
    {"type":"user","uuid":"r1","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}
    {"type":"summary","summary":"Notch color"}
    not json
    {"type":"assistant","uuid":"a2","message":{"role":"assistant","content":[{"type":"tool_use","name":"TodoWrite","input":{"todos":[]}}]}}
    """

@Test func parsesConversationAndSkipsNoise() {
    let messages = Transcript.parse(sample)

    #expect(messages.map(\.role) == [.user, .assistant, .tool, .tool])
    #expect(
        messages.map(\.text) == ["make the notch blue", "On it.", "Bash: swift build", "TodoWrite"])
}

@Test func loadsOnlyTheTail() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: url) }
    let filler = String(repeating: "x", count: Transcript.tailBytes)
    try Data(
        (#"{"type":"user","uuid":"old","message":{"content":"\#(filler)"}}"# + "\n" + sample).utf8
    )
    .write(to: url)

    let messages = try Transcript.load(from: url, limit: 2)

    #expect(messages.map(\.text) == ["Bash: swift build", "TodoWrite"])
}

@Test func openTranscriptReadsAppendsAndRetainsMessageIDs() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let first =
        #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"first"}]}}"#
    let second =
        #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"second"}]}}"#
    let split = second.index(second.startIndex, offsetBy: 23)
    try Data((first + "\n" + second[..<split]).utf8).write(to: url)

    var tail = Transcript.Tail()
    try tail.read(from: url, provider: .codex)
    let original = try #require(tail.messages.first)
    #expect(tail.messages.map(\.text) == ["first"])

    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data((second[split...] + "\n").utf8))
    try tail.read(from: url, provider: .codex)
    #expect(tail.messages.map(\.text) == ["first", "second"])
    #expect(tail.messages.first == original)
    #expect(Set(tail.messages.map(\.id)).count == 2)

    try tail.read(from: url, provider: .codex)
    #expect(tail.messages.count == 2)
}

@Test func openTranscriptReloadsAReplacementAtTheSamePath() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let first = #"{"type":"user","message":{"content":"first"}}"# + "\n"
    let replacement = #"{"type":"user","message":{"content":"newer"}}"# + "\n"
    try Data(first.utf8).write(to: url)
    var tail = Transcript.Tail()
    try tail.read(from: url, provider: .claude)

    try Data(replacement.utf8).write(to: url, options: .atomic)
    try tail.read(from: url, provider: .claude)
    #expect(tail.messages.map(\.text) == ["newer"])
}
