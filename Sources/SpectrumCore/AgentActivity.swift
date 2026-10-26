/// What an agent is doing right now, as shown at its desk in the office.
public enum AgentActivity: Equatable, Sendable {
    case idle
    case thinking
    case usingTool(String)
    case waitingForUser
    case finished

    /// Folds the next hook event into the current activity.
    public func applying(_ event: AgentEvent) -> AgentActivity {
        switch event.kind {
        case .sessionStart, .stop:
            return .idle
        case .postToolUse, .userPromptSubmit, .subagentStop:
            return .thinking
        case .preToolUse:
            return .usingTool(event.toolName ?? "tool")
        case .notification:
            return .waitingForUser
        case .sessionEnd:
            return .finished
        }
    }

    public var summary: String {
        switch self {
        case .idle: "Idle"
        case .thinking: "Thinking…"
        case .usingTool(let tool): "Running \(tool)"
        case .waitingForUser: "Waiting for you"
        case .finished: "Done"
        }
    }

    public var isWorking: Bool {
        switch self {
        case .thinking, .usingTool: true
        case .idle, .waitingForUser, .finished: false
        }
    }
}
