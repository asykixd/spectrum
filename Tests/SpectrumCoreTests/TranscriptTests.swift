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
