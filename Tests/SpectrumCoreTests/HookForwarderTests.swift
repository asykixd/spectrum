import Darwin
import Foundation
import Testing

@testable import SpectrumCore

@Test func hookForwarderIsSilentAndFastWhenSpectrumIsDown() {
    let clock = ContinuousClock()
    let start = clock.now
    let input = Data(#"{"session_id":"s","hook_event_name":"SessionStart"}"#.utf8)
    let path = "/tmp/spectrum-absent-\(UUID().uuidString.prefix(8)).sock"
    #expect(HookForwarder.run(input, from: .claude, socketPath: path).isEmpty)
    #expect(start.duration(to: clock.now) < .seconds(1))
}

@Test func hookForwarderReturnsWhenSpectrumAcceptsNoData() throws {
    let path = "/tmp/spectrum-stuck-\(UUID().uuidString.prefix(8)).sock"
    let listener = socket(AF_UNIX, SOCK_STREAM, 0)
    try #require(listener >= 0)
    defer {
        close(listener)
        unlink(path)
    }
    var address = try AgentSocket.makeAddress(path)
    let result = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    try #require(result == 0)
    try #require(listen(listener, 1) == 0)

    let input = Data(
        ("{\"session_id\":\"s\",\"hook_event_name\":\"PostToolUse\",\"tool_response\":\""
            + String(repeating: "x", count: 2_000_000) + "\"}").utf8)
    let clock = ContinuousClock()
    let start = clock.now
    #expect(HookForwarder.run(input, from: .claude, socketPath: path).isEmpty)
    #expect(start.duration(to: clock.now) < .seconds(2))
}
