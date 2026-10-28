import Foundation

/// An agent's own plan, from `TodoWrite` or the newer `TaskCreate` / `TaskUpdate` tools.
public struct TaskList: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public enum Status: String, Decodable, Sendable {
            case pending
            case inProgress = "in_progress"
            case completed
        }

        public var id: String
        public var title: String
        public var activeForm: String?
        public var status: Status

        public init(id: String, title: String, activeForm: String? = nil, status: Status) {
            self.id = id
            self.title = title
            self.activeForm = activeForm
            self.status = status
        }
    }

    /// One tool call's effect on the list.
    public enum Change: Equatable, Sendable {
        case replaceAll([Item])
        case create(Item)
        case update(id: String, status: Item.Status?, title: String?, activeForm: String?)
        case delete(id: String)
    }

    public private(set) var items: [Item] = []

    public init() {}

    public var total: Int { items.count }
    public var completed: Int { items.filter { $0.status == .completed }.count }
    public var isEmpty: Bool { items.isEmpty }
    public var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }

    /// What the agent says it is doing now, in its own "-ing" words when it gave them.
    public var current: String? {
        items.first { $0.status == .inProgress }.map { $0.activeForm ?? $0.title }
    }

    public mutating func apply(_ change: Change) {
        switch change {
        case .replaceAll(let all):
            items = all
        case .create(let item):
            items.removeAll { $0.id == item.id }
            items.append(item)
        case .update(let id, let status, let title, let activeForm):
            guard let index = items.firstIndex(where: { $0.id == id }) else { return }
            if let status { items[index].status = status }
            if let title { items[index].title = title }
            if let activeForm { items[index].activeForm = activeForm }
        case .delete(let id):
            items.removeAll { $0.id == id }
        }
    }
}

/// The parts of `tool_input` and `tool_response` the task tools use.
struct TaskToolPayload: Decodable {
    struct Todo: Decodable {
        let content: String
        let status: TaskList.Item.Status
        let activeForm: String?
    }

    struct Created: Decodable {
        struct Task: Decodable {
            let id: String
            let subject: String
        }

        let task: Task
    }

    let todos: [Todo]?
    let taskId: String?
    let status: String?
    let subject: String?
    let activeForm: String?

    /// Only settled calls count, so a denied update never shows as progress.
    static func change(tool: String?, input: TaskToolPayload?, response: Created?)
        -> TaskList.Change?
    {
        switch tool {
        case "TodoWrite":
            guard let todos = input?.todos else { return nil }
            return .replaceAll(
                todos.enumerated().map { index, todo in
                    TaskList.Item(
                        id: String(index), title: todo.content, activeForm: todo.activeForm,
                        status: todo.status)
                })
        case "TaskCreate":
            guard let task = response?.task else { return nil }
            return .create(
                TaskList.Item(
                    id: task.id, title: task.subject, activeForm: input?.activeForm,
                    status: .pending))
        case "TaskUpdate":
            guard let input, let id = input.taskId else { return nil }
            if input.status == "deleted" { return .delete(id: id) }
            return .update(
                id: id, status: input.status.flatMap(TaskList.Item.Status.init(rawValue:)),
                title: input.subject, activeForm: input.activeForm)
        default:
            return nil
        }
    }
}
