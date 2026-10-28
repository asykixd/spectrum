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
        case permissionRequest = "PermissionRequest"
        case stop = "Stop"
        case subagentStop = "SubagentStop"
        case sessionEnd = "SessionEnd"
    }

    public let sessionID: String
    public let kind: Kind
    public let cwd: String?
    public let toolName: String?
    public let transcriptPath: String?
    /// Text of a `Notification` event, e.g. "Claude needs your permission to use Bash".
    public let message: String?
    /// String fields of the tool's input; other value types are dropped.
    public let toolInput: [String: LooseString]?
    /// How a settled task tool call changed the agent's plan.
    public let taskChange: TaskList.Change?
    /// Lines a settled edit or write changed.
    public let fileChange: FileChange?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case kind = "hook_event_name"
        case cwd
        case toolName = "tool_name"
        case transcriptPath = "transcript_path"
        case message
        case toolInput = "tool_input"
        case toolResponse = "tool_response"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        kind = try container.decode(Kind.self, forKey: .kind)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        transcriptPath = try container.decodeIfPresent(String.self, forKey: .transcriptPath)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        toolInput = try? container.decodeIfPresent([String: LooseString].self, forKey: .toolInput)
        // Tool payloads vary by tool and version; a shape we don't know just means no change.
        taskChange =
            kind == .postToolUse
            ? TaskToolPayload.change(
                tool: toolName,
                input: try? container.decodeIfPresent(TaskToolPayload.self, forKey: .toolInput),
                response: try? container.decodeIfPresent(
                    TaskToolPayload.Created.self, forKey: .toolResponse))
            : nil
        fileChange =
            kind == .postToolUse
            ? EditToolPayload.change(
                tool: toolName,
                input: try? container.decodeIfPresent(EditToolPayload.self, forKey: .toolInput))
            : nil
    }

    /// What a `PermissionRequest` asks to do, in a form short enough for the island.
    public var permissionPrompt: PermissionPrompt? {
        guard kind == .permissionRequest else { return nil }
        let fields = ["command", "file_path", "url", "pattern", "path", "query"]
        let detail = fields.lazy.compactMap { self.toolInput?[$0]?.value }.first
        return PermissionPrompt(tool: toolName ?? "tool", detail: detail)
    }

    public static func decode(_ data: Data) throws -> AgentEvent {
        try JSONDecoder().decode(AgentEvent.self, from: data)
    }
}

/// Decodes a string and quietly ignores any other JSON value.
public struct LooseString: Decodable, Equatable, Sendable {
    public let value: String?

    public init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(String.self)
    }
}
