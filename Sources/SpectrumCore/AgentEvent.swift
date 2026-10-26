import Foundation

/// A lifecycle event emitted by a Claude Code hook.
///
/// Field names mirror the JSON payload Claude Code writes to a hook's stdin.
public struct AgentEvent: Decodable, Equatable, Sendable {
    public enum Kind: String, Decodable, Sendable {
        case sessionStart = "SessionStart"
        case userPromptSubmit = "UserPromptSubmit"
        case preToolUse = "PreToolUse"
        case postToolUse = "PostToolUse"
        case notification = "Notification"
        case stop = "Stop"
        case subagentStop = "SubagentStop"
        case sessionEnd = "SessionEnd"
    }

    public let sessionID: String
    public let kind: Kind
    public let cwd: String?
    public let toolName: String?
    public let transcriptPath: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case kind = "hook_event_name"
        case cwd
        case toolName = "tool_name"
        case transcriptPath = "transcript_path"
    }

    public static func decode(_ data: Data) throws -> AgentEvent {
        try JSONDecoder().decode(AgentEvent.self, from: data)
    }
}
