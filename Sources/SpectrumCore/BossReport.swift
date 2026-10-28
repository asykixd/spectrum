import Foundation

/// Token usage read from Claude Code transcripts.
public struct UsageLog: Sendable {
    public struct Tokens: Equatable, Sendable {
        public var input: Int
        public var output: Int
        public var cacheWrite5m: Int
        public var cacheWrite1h: Int
        public var cacheRead: Int

        public var total: Int { input + output + cacheWrite5m + cacheWrite1h + cacheRead }
    }

    public struct Entry: Sendable {
        public let messageID: String
        public let date: Date
        public let sessionID: String
        public let project: String
        public let model: String
        public let tokens: Tokens

        public var cost: Double {
            let price = ModelPrice.for(model)
            let dollars =
                Double(tokens.input) * price.input + Double(tokens.output) * price.output
                + Double(tokens.cacheWrite5m) * price.cacheWrite5m
                + Double(tokens.cacheWrite1h) * price.cacheWrite1h
                + Double(tokens.cacheRead) * price.cacheRead
            return dollars / 1_000_000
        }
    }

    /// Something the user asked for, to say what an agent worked on.
    public struct Prompt: Sendable {
        public let date: Date
        public let sessionID: String
        public let text: String
    }

    public private(set) var entries: [Entry] = []
    public private(set) var prompts: [Prompt] = []
    /// Every moment a session did something, for working out active time.
    public private(set) var activity: [(sessionID: String, project: String, date: Date)] = []

    public init() {}

    public mutating func append(_ other: UsageLog) {
        entries += other.entries
        prompts += other.prompts
        activity += other.activity
    }

    private struct Line: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                struct Creation: Decodable {
                    let ephemeral5mInputTokens: Int?
                    let ephemeral1hInputTokens: Int?

                    enum CodingKeys: String, CodingKey {
                        case ephemeral5mInputTokens = "ephemeral_5m_input_tokens"
                        case ephemeral1hInputTokens = "ephemeral_1h_input_tokens"
                    }
                }

                let inputTokens: Int?
                let outputTokens: Int?
                let cacheCreationInputTokens: Int?
                let cacheReadInputTokens: Int?
                let cacheCreation: Creation?

                enum CodingKeys: String, CodingKey {
                    case inputTokens = "input_tokens"
                    case outputTokens = "output_tokens"
                    case cacheCreationInputTokens = "cache_creation_input_tokens"
                    case cacheReadInputTokens = "cache_read_input_tokens"
                    case cacheCreation = "cache_creation"
                }
            }

            let id: String?
            let model: String?
            let usage: Usage?
            let content: LooseString?
        }

        let type: String?
        let timestamp: String?
        let sessionId: String?
        let cwd: String?
        let isMeta: Bool?
        let message: Message?
    }

    public static func parse(_ jsonl: String) -> UsageLog {
        let decoder = JSONDecoder()
        let dates = ISO8601DateFormatter()
        dates.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainDates = ISO8601DateFormatter()
        var log = UsageLog()
        var seen = Set<String>()
        for raw in jsonl.split(separator: "\n") {
            // Most lines are tool output; skip them before paying for a full decode.
            guard raw.contains("\"timestamp\"") else { continue }
            guard let line = try? decoder.decode(Line.self, from: Data(raw.utf8)),
                let stamp = line.timestamp,
                let date = dates.date(from: stamp) ?? plainDates.date(from: stamp),
                let sessionID = line.sessionId
            else { continue }
            let project = line.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "?"
            log.activity.append((sessionID, project, date))
            switch line.type {
            case "assistant":
                guard let message = line.message, let id = message.id, let usage = message.usage,
                    seen.insert(id).inserted
                else { continue }
                let write = usage.cacheCreationInputTokens ?? 0
                let write1h = usage.cacheCreation?.ephemeral1hInputTokens ?? 0
                let write5m = usage.cacheCreation?.ephemeral5mInputTokens ?? (write - write1h)
                log.entries.append(
                    Entry(
                        messageID: id, date: date, sessionID: sessionID, project: project,
                        model: message.model ?? "",
                        tokens: Tokens(
                            input: usage.inputTokens ?? 0, output: usage.outputTokens ?? 0,
                            cacheWrite5m: write5m, cacheWrite1h: write1h,
                            cacheRead: usage.cacheReadInputTokens ?? 0)))
            case "user":
                // Typed prompts are plain strings; tool results and injected turns are not.
                guard line.isMeta != true,
                    let text = line.message?.content?.value?.trimmingCharacters(
                        in: .whitespacesAndNewlines),
                    !text.isEmpty, !text.hasPrefix("<")
                else { continue }
                log.prompts.append(Prompt(date: date, sessionID: sessionID, text: text))
            default:
                continue
            }
        }
        return log
    }
}

/// The boss's view of the day: who worked how long, on what, and what it cost.
public struct BossReport: Sendable {
    public struct Project: Identifiable, Sendable {
        public var id: String { name }
        public let name: String
        public let cost: Double
        public let tokens: Int
        /// Seconds with the agent busy, leaving out breaks of five minutes or more.
        public let activeTime: TimeInterval
        public let sessions: Int
        public let lastPrompt: String?

        public init(
            name: String, cost: Double, tokens: Int, activeTime: TimeInterval, sessions: Int,
            lastPrompt: String?
        ) {
            self.name = name
            self.cost = cost
            self.tokens = tokens
            self.activeTime = activeTime
            self.sessions = sessions
            self.lastPrompt = lastPrompt
        }
    }

    /// Claude's usage limits reset in five-hour windows that start on the hour.
    public struct Window: Equatable, Sendable {
        public let start: Date
        public let end: Date
        public let cost: Double
        public let tokens: Int

        public init(start: Date, end: Date, cost: Double, tokens: Int) {
            self.start = start
            self.end = end
            self.cost = cost
            self.tokens = tokens
        }
    }

    public static let windowLength: TimeInterval = 5 * 3600
    static let breakLength: TimeInterval = 5 * 60

    public let todayCost: Double
    public let todayTokens: Int
    public let activeTime: TimeInterval
    public let projects: [Project]
    public let window: Window?

    /// Fixed numbers, for previews.
    public init(
        todayCost: Double, todayTokens: Int, activeTime: TimeInterval, projects: [Project],
        window: Window?
    ) {
        self.todayCost = todayCost
        self.todayTokens = todayTokens
        self.activeTime = activeTime
        self.projects = projects
        self.window = window
    }

    public init(log: UsageLog, now: Date, calendar: Calendar = .current) {
        let dayStart = calendar.startOfDay(for: now)
        // Lines of one message can be read in separate scans; count each message once.
        var seen = Set<String>()
        let entries = log.entries.filter { seen.insert($0.messageID).inserted }
        let today = entries.filter { $0.date >= dayStart && $0.date <= now }
        todayCost = today.reduce(0) { $0 + $1.cost }
        todayTokens = today.reduce(0) { $0 + $1.tokens.total }

        let moments = log.activity.filter { $0.date >= dayStart && $0.date <= now }
        var busy: [String: TimeInterval] = [:]
        var projectOfSession: [String: String] = [:]
        for (sessionID, points) in Dictionary(grouping: moments, by: \.sessionID) {
            let times = points.map(\.date).sorted()
            let gaps = zip(times, times.dropFirst()).map { $1.timeIntervalSince($0) }
            busy[sessionID] = gaps.filter { $0 < Self.breakLength }.reduce(0, +)
            projectOfSession[sessionID] = points.last?.project
        }
        activeTime = busy.values.reduce(0, +)

        let promptsToday = log.prompts.filter { $0.date >= dayStart && $0.date <= now }
        var projects: [Project] = []
        let sessionsByProject = Dictionary(grouping: projectOfSession.keys) {
            projectOfSession[$0] ?? "?"
        }
        for (name, sessionIDs) in sessionsByProject {
            let ids = Set(sessionIDs)
            let spent = today.filter { ids.contains($0.sessionID) }
            let last = promptsToday.filter { ids.contains($0.sessionID) }.max { $0.date < $1.date }
            projects.append(
                Project(
                    name: name, cost: spent.reduce(0) { $0 + $1.cost },
                    tokens: spent.reduce(0) { $0 + $1.tokens.total },
                    activeTime: sessionIDs.reduce(0) { $0 + (busy[$1] ?? 0) },
                    sessions: ids.count, lastPrompt: last?.text))
        }
        self.projects = projects.sorted {
            $0.cost != $1.cost ? $0.cost > $1.cost : $0.name < $1.name
        }
        window = Self.currentWindow(entries, now: now, calendar: calendar)
    }

    private static func currentWindow(_ entries: [UsageLog.Entry], now: Date, calendar: Calendar)
        -> Window?
    {
        var start: Date?
        for entry in entries.sorted(by: { $0.date < $1.date }) where entry.date <= now {
            if let current = start, entry.date < current.addingTimeInterval(windowLength) {
                continue
            }
            start = calendar.dateInterval(of: .hour, for: entry.date)?.start ?? entry.date
        }
        guard let start, now < start.addingTimeInterval(windowLength) else { return nil }
        let end = start.addingTimeInterval(windowLength)
        let inside = entries.filter { $0.date >= start && $0.date < end }
        return Window(
            start: start, end: end, cost: inside.reduce(0) { $0 + $1.cost },
            tokens: inside.reduce(0) { $0 + $1.tokens.total })
    }
}
