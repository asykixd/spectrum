import Foundation
import Testing

@testable import SpectrumCore

private struct Mutations {
    private var state: UInt64 = 0x44f1_7a90_229e

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return state >> 32
    }

    mutating func mutate(_ text: String) -> String {
        var bytes = Array(text.utf8)
        for _ in 0..<Int(next() % 6) {
            let offset = Int(next() % UInt64(bytes.count + 1))
            switch next() % 3 {
            case 0 where offset < bytes.count: bytes.remove(at: offset)
            case 1 where offset < bytes.count: bytes[offset] = UInt8(truncatingIfNeeded: next())
            default: bytes.insert(UInt8(truncatingIfNeeded: next()), at: offset)
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

@Test func parsersTolerateDeterministicallyMutatedInputs() {
    let claude = #"{"type":"user","message":{"content":"Help with a build"}}"#
    let codex =
        #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Help with a build"}]}}"#
    let usage =
        #"{"type":"assistant","timestamp":"2026-10-28T10:00:00Z","sessionId":"s","message":{"id":"m","usage":{"input_tokens":100}}}"#
    let player = "playing\tTrack\tArtist\tAlbum\t212,5\t12\thttps://example.org/cover"
    let now = Date(timeIntervalSince1970: 1000)
    var mutations = Mutations()

    for _ in 0..<256 {
        for (input, provider) in [(claude, AgentProvider.claude), (codex, .codex)] {
            #expect(Transcript.parse(mutations.mutate(input), provider: provider).count <= 1)
        }
        let log = UsageLog.parse(mutations.mutate(usage))
        #expect(log.entries.allSatisfy { $0.tokens.total >= 0 })
        if let track = NowPlaying.parse(
            scriptOutput: mutations.mutate(player), bundleID: "player", sampledAt: now)
        {
            #expect(track.position(at: now).isFinite)
        }
        let chat = ClaudeChatSnapshot(
            pageTitle: mutations.mutate("Chat - Claude"),
            url: URL(string: mutations.mutate("https://claude.ai/chat/example")),
            buttonLabels: [mutations.mutate("Stop response")],
            texts: [mutations.mutate("Thinking")])
        #expect(!chat.isThinking || chat.isGenerating)
    }
}

@Test func extremeNumbersCannotOverflowPlaybackOrUsageTotals() throws {
    let track = try #require(
        NowPlaying.parse(
            scriptOutput: "playing\tTrack\tArtist\t\tNaN\t1e200",
            bundleID: "player", sampledAt: .distantPast))
    #expect(track.duration == 0)
    #expect(track.elapsed == 0)

    let invalid =
        #"{"type":"assistant","timestamp":"2026-10-28T10:00:00Z","sessionId":"s","message":{"id":"m","usage":{"input_tokens":9223372036854775807,"output_tokens":9223372036854775807}}}"#
    let log = UsageLog.parse(invalid)
    #expect(log.entries.isEmpty)
    #expect(log.activity.count == 1)
}
