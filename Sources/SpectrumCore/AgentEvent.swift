import Foundation

/// A lifecycle event emitted by a coding agent's hook.
public struct AgentEvent: Decodable, Equatable, Sendable {
    public enum Kind: String, Decodable, Sendable {
        case sessionStart = "SessionStart"
        case userPromptSubmit = "UserPromptSubmit"
        case preToolUse = "PreToolUse"
        case postToolUse = "PostToolUse"
        case notification = "Notification"
        case permissionRequest = "PermissionRequest"
        case stop = "Stop"
        case interrupt = "Interrupt"
        case subagentStop = "SubagentStop"
        case sessionEnd = "SessionEnd"
    }

    public let provider: AgentProvider
    public let sessionID: String
    public var sessionKey: String { provider == .codex ? "codex:\(sessionID)" : sessionID }
    public let kind: Kind
    public let cwd: String?
    public let toolName: String?
    public let transcriptPath: String?
    public let terminalTab: TerminalTab?
    /// Text of a `Notification` event, e.g. "Claude needs your permission to use Bash".
    public let message: String?
    /// String fields of the tool's input; other value types are dropped.
    public let toolInput: [String: LooseString]?
    /// How a settled task tool call changed the agent's plan.
    public let taskChange: TaskList.Change?
    /// Lines a settled edit or write changed.
    public let fileChange: FileChange?
    private let permissionSuggestions: [PermissionSuggestion]?

    enum CodingKeys: String, CodingKey {
        case provider = "spectrum_provider"
        case sessionID = "session_id"
        case kind = "hook_event_name"
        case cwd
        case toolName = "tool_name"
        case transcriptPath = "transcript_path"
        case terminalTTY = "spectrum_terminal_tty"
        case terminalLeader = "spectrum_terminal_leader"
        case message
        case toolInput = "tool_input"
        case toolResponse = "tool_response"
        case permissionSuggestions = "permission_suggestions"
    }

    private struct PermissionSuggestion: Decodable, Equatable, Sendable {
        struct Rule: Decodable, Equatable, Sendable {
            let toolName: String?
            let ruleContent: String?
        }

        let type: String?
        let behavior: String?
        let destination: String?
        let rules: [Rule]?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decodeIfPresent(AgentProvider.self, forKey: .provider) ?? .claude
        sessionID = try container.decode(String.self, forKey: .sessionID)
        kind = try container.decode(Kind.self, forKey: .kind)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        transcriptPath = try container.decodeIfPresent(String.self, forKey: .transcriptPath)
        if let tty = try? container.decode(String.self, forKey: .terminalTTY),
            let leader = try? container.decode(Int32.self, forKey: .terminalLeader)
        {
            terminalTab = TerminalTab(tty: tty, sessionLeader: leader)
        } else {
            terminalTab = nil
        }
        message = try container.decodeIfPresent(String.self, forKey: .message)
        toolInput = try? container.decodeIfPresent([String: LooseString].self, forKey: .toolInput)
        permissionSuggestions =
            kind == .permissionRequest
            ? try? container.decode([PermissionSuggestion].self, forKey: .permissionSuggestions)
            : nil
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
        let fields = ["command", "file_path", "url", "pattern", "path", "query", "description"]
        let detail = fields.lazy.compactMap { self.toolInput?[$0]?.value }.first
        return PermissionPrompt(tool: toolName ?? "tool", detail: detail, projectRule: projectRule)
    }

    private var projectRule: ProjectPermissionRule? {
        guard provider == .claude, toolName == "Bash", let command = toolInput?["command"]?.value,
            permissionSuggestions?.contains(where: { suggestion in
                suggestion.type == "addRules" && suggestion.behavior == "allow"
                    && suggestion.destination == "localSettings" && suggestion.rules?.count == 1
                    && suggestion.rules?.first?.toolName == "Bash"
                    && suggestion.rules?.first?.ruleContent == command
            }) == true
        else { return nil }
        return ProjectPermissionRule(tool: "Bash", command: command)
    }

    /// Adds the provider and any local Terminal target before sending the hook to the app.
    public static func forwardedPayload(
        _ data: Data, from provider: AgentProvider, terminalTab: TerminalTab? = nil
    ) throws -> Data {
        guard provider == .codex || terminalTab != nil else { return data }
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return data
        }
        object[CodingKeys.provider.rawValue] = provider.rawValue
        object[CodingKeys.terminalTTY.rawValue] = terminalTab?.tty
        object[CodingKeys.terminalLeader.rawValue] = terminalTab?.sessionLeader
        return try JSONSerialization.data(withJSONObject: object)
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
