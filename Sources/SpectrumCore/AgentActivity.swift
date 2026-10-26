/// What an agent is doing right now, as shown at its desk in the office.
public enum AgentActivity: Equatable, Sendable {
    case idle
    case thinking
    case usingTool(String)
    /// Writing the answer: streamed text in a Claude chat.
    case responding
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
            // Claude Code also notifies after a minute of idling; that one isn't a request.
            let idleReminder = event.message?.lowercased().contains("waiting for your input")
            return idleReminder == true ? self : .waitingForUser
        case .sessionEnd:
            return .finished
        }
    }

    public var summary: String {
        switch self {
        case .idle: "Idle"
        case .thinking: "Thinking…"
        case .usingTool(let tool): "Running \(tool)"
        case .responding: "Answering…"
        case .waitingForUser: "Waiting for you"
        case .finished: "Done"
        }
    }

    public var isWorking: Bool {
        switch self {
        case .thinking, .usingTool, .responding: true
        case .idle, .waitingForUser, .finished: false
        }
    }
}
