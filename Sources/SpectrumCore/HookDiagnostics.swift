import Foundation

/// Bounded, shareable hook diagnostics. No session identifiers, paths, arguments or prompts.
public struct HookDiagnostics: Codable, Sendable {
    public struct Event: Codable, Equatable, Sendable {
        public let provider: String
        public let name: String
        public let receivedAt: Date
    }

    public static let request = Data("Spectrum diagnostics v1".utf8)
    public private(set) var events: [Event] = []
    public var accessibilityGranted: Bool?

    public init() {}

    public static func fetch(socketPath: String) throws -> Self? {
        let data = try AgentSocket.request(request, to: socketPath, timeout: 0.5)
        return data.isEmpty ? nil : try JSONDecoder().decode(Self.self, from: data)
    }

    public mutating func record(_ event: AgentEvent, at date: Date) {
        events.append(
            Event(provider: event.provider.name, name: event.kind.rawValue, receivedAt: date))
        if events.count > 20 { events.removeFirst(events.count - 20) }
    }
}
