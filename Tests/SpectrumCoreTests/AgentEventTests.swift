import Foundation
import Testing

@testable import SpectrumCore

@Test func decodesPreToolUsePayload() throws {
    let json = Data(
        #"{"session_id":"abc","hook_event_name":"PreToolUse","cwd":"/tmp","tool_name":"Bash","tool_input":{}}"#
            .utf8)

    let event = try AgentEvent.decode(json)

    #expect(event.sessionID == "abc")
    #expect(event.kind == .preToolUse)
    #expect(event.toolName == "Bash")
}

@Test func rejectsUnknownEventKind() {
    let json = Data(#"{"session_id":"abc","hook_event_name":"Nope"}"#.utf8)

    #expect(throws: DecodingError.self) { try AgentEvent.decode(json) }
}

@Test func activityFollowsToolLifecycle() throws {
    let pre = try AgentEvent.decode(
        Data(#"{"session_id":"a","hook_event_name":"PreToolUse","tool_name":"Edit"}"#.utf8))
    let notify = try AgentEvent.decode(
        Data(#"{"session_id":"a","hook_event_name":"Notification"}"#.utf8))

    let working = AgentActivity.idle.applying(pre)

    #expect(working == .usingTool("Edit"))
    #expect(working.applying(notify) == .waitingForUser)
}
