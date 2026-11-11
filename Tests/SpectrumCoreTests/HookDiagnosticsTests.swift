import Foundation
import Testing

@testable import SpectrumCore

@Test func diagnosticsAreBoundedAndDoNotIncludeSessionContent() throws {
    let input = Data(
        #"{"session_id":"private-session","hook_event_name":"PreToolUse","cwd":"/private/work","tool_name":"Bash","tool_input":{"command":"private command"}}"#
            .utf8)
    let event = try AgentEvent.decode(input)
    var diagnostics = HookDiagnostics()
    for index in 0..<25 {
        diagnostics.record(event, at: Date(timeIntervalSince1970: Double(index)))
    }
    #expect(diagnostics.events.count == 20)
    #expect(diagnostics.events.first?.receivedAt == Date(timeIntervalSince1970: 5))
    let data = try JSONEncoder().encode(diagnostics)
    #expect(!String(decoding: data, as: UTF8.self).contains("private"))
    #expect(try JSONDecoder().decode(HookDiagnostics.self, from: data).events == diagnostics.events)
}

@Test func diagnosticsCanBeQueriedOverTheAgentSocket() throws {
    let path = "/tmp/spectrum-diag-\(UUID().uuidString.prefix(8)).sock"
    let server = AgentSocketServer(path: path)
    var diagnostics = HookDiagnostics()
    diagnostics.accessibilityGranted = true
    let payload = try JSONEncoder().encode(diagnostics)
    try server.start { request, reply in
        reply.send(request == HookDiagnostics.request ? payload : nil)
    }
    defer { server.stop() }

    #expect(try HookDiagnostics.fetch(socketPath: path)?.accessibilityGranted == true)
}
