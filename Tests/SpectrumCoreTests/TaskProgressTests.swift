import Foundation
import Testing

@testable import SpectrumCore

private func post(_ tool: String, input: String, response: String = "null") throws -> AgentEvent {
    try AgentEvent.decode(
        Data(
            """
            {"session_id":"s","hook_event_name":"PostToolUse","tool_name":"\(tool)",
             "tool_input":\(input),"tool_response":\(response)}
            """.utf8))
}

@Test func todoWriteReplacesTheWholeList() throws {
    var store = SessionStore()
    let todos = """
        {"todos":[
          {"content":"Add model","status":"completed","activeForm":"Adding model"},
          {"content":"Write view","status":"in_progress","activeForm":"Writing view"},
          {"content":"Run tests","status":"pending","activeForm":"Running tests"}]}
        """
    try store.apply(post("TodoWrite", input: todos), at: .distantPast)

    let tasks = try #require(store.sessions["s"]?.tasks)
    #expect(tasks.completed == 1)
    #expect(tasks.total == 3)
    #expect(tasks.current == "Writing view")
}

@Test func taskToolsBuildTheListOneItemAtATime() throws {
    var store = SessionStore()
    try store.apply(
        post(
            "TaskCreate", input: #"{"subject":"Add model","description":"x"}"#,
            response: #"{"task":{"id":"1","subject":"Add model"}}"#), at: .distantPast)
    try store.apply(
        post(
            "TaskCreate", input: #"{"subject":"Run tests","description":"y"}"#,
            response: #"{"task":{"id":"2","subject":"Run tests"}}"#), at: .distantPast)
    try store.apply(
        post("TaskUpdate", input: #"{"taskId":"1","status":"completed"}"#), at: .distantPast)
    try store.apply(
        post("TaskUpdate", input: #"{"taskId":"2","status":"in_progress","activeForm":"Testing"}"#),
        at: .distantPast)

    var tasks = try #require(store.sessions["s"]?.tasks)
    #expect(tasks.completed == 1)
    #expect(tasks.total == 2)
    #expect(tasks.current == "Testing")

    try store.apply(
        post("TaskUpdate", input: #"{"taskId":"2","status":"deleted"}"#), at: .distantPast)
    tasks = try #require(store.sessions["s"]?.tasks)
    #expect(tasks.total == 1)
    #expect(tasks.current == nil)
}

@Test func otherToolsLeaveTheListAlone() throws {
    var store = SessionStore()
    try store.apply(
        post("TodoWrite", input: #"{"todos":[{"content":"A","status":"pending"}]}"#),
        at: .distantPast)
    try store.apply(post("Bash", input: #"{"command":"ls"}"#), at: .distantPast)

    #expect(store.sessions["s"]?.tasks.total == 1)
}
