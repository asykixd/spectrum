/// What a tool call looks like at the agent's desk in the office.
public enum ToolKind: Equatable, Sendable {
    case reading
    case writing
    case terminal
    case browsing
    /// Handing work to a subagent.
    case delegating

    public init(_ toolName: String) {
        switch toolName {
        case "Read", "Grep", "Glob", "LS", "NotebookRead", "TaskList", "TaskGet": self = .reading
        case "Bash", "BashOutput", "KillShell", "KillBash", "Monitor": self = .terminal
        case "WebSearch", "WebFetch": self = .browsing
        case "Task", "Agent": self = .delegating
        // Edits and everything else, MCP tools included, read as typing code.
        default: self = .writing
        }
    }
}
