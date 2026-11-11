import Foundation

/// One line of a conversation as shown in the sessions panel.
public struct TranscriptMessage: Identifiable, Equatable, Sendable {
    public enum Role: Equatable, Sendable {
        case user
        case assistant
        /// A tool call the assistant made, e.g. "Bash: swift test".
        case tool
    }

    public let id: String
    public let role: Role
    public let text: String

    public init(id: String, role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

/// Reads the supported coding agents' JSONL transcripts.
public enum Transcript {
    /// Tail of the file that is read; transcripts grow to many megabytes.
    static let tailBytes = 512 * 1024

    /// An open conversation keeps its last messages and parses each new record once.
    public struct Tail: Sendable {
        private var reader = JSONLReader()
        public private(set) var messages: [TranscriptMessage] = []

        public init() {}

        public mutating func read(from url: URL, provider: AgentProvider) throws {
            var updated = messages
            // Keep cursor and published messages in sync if a read fails after some records.
            defer { messages = updated }
            try reader.read(
                url, tailBytes: Transcript.tailBytes, maxRecordBytes: Transcript.tailBytes,
                onReset: { updated.removeAll() },
                onLine: { line, offset in
                    let parsed = Transcript.parse(
                        String(decoding: line, as: UTF8.self), provider: provider,
                        startingAt: offset)
                    guard !parsed.isEmpty else { return }
                    updated.append(contentsOf: parsed)
                    if updated.count > 40 { updated.removeFirst(updated.count - 40) }
                })
        }
    }

    private struct Line: Decodable {
        let type: String?
        let uuid: String?
        let isMeta: Bool?
        let message: Message?
    }

    private struct Message: Decodable {
        let content: Content?
    }

    private enum Content: Decodable {
        case text(String)
        case blocks([Block])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .text(text)
            } else {
                self = .blocks(try container.decode([Block].self))
            }
        }
    }

    private struct Block: Decodable {
        let type: String
        let text: String?
        let name: String?
        let input: [String: JSONValue]?
    }

    /// Only the scalar inputs worth showing next to a tool name.
    private enum JSONValue: Decodable {
        case string(String)
        case other

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self = (try? container.decode(String.self)).map(JSONValue.string) ?? .other
        }
    }

    private struct CodexLine: Decodable {
        let type: String
        let payload: Item

        struct Item: Decodable {
            let type: String
            let role: String?
            let content: [TextBlock]?
            let name: String?
            let arguments: String?

            struct TextBlock: Decodable {
                let type: String
                let text: String?
            }
        }
    }

    /// The last `limit` messages of the transcript at `url`.
    public static func load(
        from url: URL, limit: Int = 40, provider: AgentProvider = .claude
    ) throws -> [TranscriptMessage] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try handle.seek(toOffset: start)
        var text = String(decoding: try handle.readToEnd() ?? Data(), as: UTF8.self)
        if start > 0, let newline = text.firstIndex(of: "\n") {
            // The first line was cut in the middle.
            text = String(text[text.index(after: newline)...])
        }
        return Array(parse(text, provider: provider).suffix(limit))
    }

    public static func parse(
        _ jsonl: String, provider: AgentProvider = .claude
    ) -> [TranscriptMessage] {
        parse(jsonl, provider: provider, startingAt: 0)
    }

    private static func parse(
        _ jsonl: String, provider: AgentProvider, startingAt: UInt64
    ) -> [TranscriptMessage] {
        if provider == .codex { return parseCodex(jsonl, startingAt: startingAt) }
        let decoder = JSONDecoder()
        var messages: [TranscriptMessage] = []
        for (index, raw) in jsonl.split(separator: "\n").enumerated() {
            guard let line = try? decoder.decode(Line.self, from: Data(raw.utf8)),
                line.isMeta != true, let content = line.message?.content
            else { continue }
            let id = line.uuid ?? "line-\(startingAt + UInt64(index))"
            switch (line.type, content) {
            case ("user", .text(let text)):
                if isUserText(text) { messages.append(.init(id: id, role: .user, text: text)) }
            case ("user", .blocks(let blocks)):
                for (offset, block) in blocks.enumerated()
                where block.type == "text" && isUserText(block.text ?? "") {
                    messages.append(
                        .init(id: "\(id)-\(offset)", role: .user, text: block.text ?? ""))
                }
            case ("assistant", .blocks(let blocks)):
                for (offset, block) in blocks.enumerated() {
                    let blockID = "\(id)-\(offset)"
                    if block.type == "text", let text = block.text, !text.isEmpty {
                        messages.append(.init(id: blockID, role: .assistant, text: text))
                    } else if block.type == "tool_use", let name = block.name {
                        messages.append(
                            .init(id: blockID, role: .tool, text: toolSummary(name, block.input)))
                    }
                }
            default:
                continue
            }
        }
        return messages
    }

    private static func parseCodex(_ jsonl: String, startingAt: UInt64) -> [TranscriptMessage] {
        let decoder = JSONDecoder()
        return jsonl.split(separator: "\n").enumerated().compactMap { index, raw in
            guard let line = try? decoder.decode(CodexLine.self, from: Data(raw.utf8)),
                line.type == "response_item"
            else { return nil }
            let item = line.payload
            let id = "line-\(startingAt + UInt64(index))"
            switch item.type {
            case "message":
                let role: TranscriptMessage.Role
                let blockType: String
                switch item.role {
                case "user": (role, blockType) = (.user, "input_text")
                case "assistant": (role, blockType) = (.assistant, "output_text")
                default: return nil
                }
                let text = (item.content ?? []).filter { $0.type == blockType }
                    .compactMap(\.text).joined(separator: "\n")
                guard !text.isEmpty else { return nil }
                if role == .user, !isUserText(text) || text.hasPrefix("# AGENTS.md instructions") {
                    return nil
                }
                return .init(id: id, role: role, text: text)
            case "function_call", "custom_tool_call":
                guard let name = item.name else { return nil }
                let input = item.arguments.flatMap {
                    try? decoder.decode([String: JSONValue].self, from: Data($0.utf8))
                }
                return .init(id: id, role: .tool, text: toolSummary(name, input))
            default:
                return nil
            }
        }
    }

    /// Skips the system-injected user turns: slash-command wrappers, reminders, hook output.
    private static func isUserText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.hasPrefix("<")
    }

    private static func toolSummary(_ name: String, _ input: [String: JSONValue]?) -> String {
        let keys = ["command", "file_path", "pattern", "description", "url", "query", "prompt"]
        for key in keys {
            if case .string(let value) = input?[key] {
                let firstLine = value.split(separator: "\n").first.map(String.init) ?? value
                return "\(name): \(firstLine)"
            }
        }
        return name
    }
}
