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
        case .sessionStart, .postToolUse, .userPromptSubmit, .subagentStop:
            return .thinking
        case .preToolUse:
            return .usingTool(event.toolName ?? "tool")
        case .notification:
            return .waitingForUser
        case .stop:
            return .idle
        case .sessionEnd:
            return .finished
        }
    }
}
