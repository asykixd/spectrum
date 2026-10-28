/// Claude API list prices in dollars per million tokens, to put a number on what agents spent.
/// From Anthropic's pricing table as of 2026-10; with a subscription this is what the same work
/// would cost on the API, not what was billed.
public struct ModelPrice: Equatable, Sendable {
    public let input: Double
    public let output: Double
    public let cacheRead: Double

    /// Cache writes cost a multiple of the input price.
    public var cacheWrite5m: Double { input * 1.25 }
    public var cacheWrite1h: Double { input * 2 }

    init(input: Double, output: Double, cacheRead: Double? = nil) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead ?? input * 0.1
    }

    /// Exact matches first, then the family, so dated or unknown versions still get a price.
    public static func `for`(_ model: String) -> ModelPrice {
        let exact: [(String, ModelPrice)] = [
            ("claude-fable-5-1", .init(input: 10, output: 50, cacheRead: 0.25)),
            ("claude-mythos-5-1", .init(input: 10, output: 50, cacheRead: 0.25)),
            ("claude-opus-5-5", .init(input: 4, output: 20, cacheRead: 0.2)),
            ("claude-sonnet-5-5", .init(input: 2, output: 10, cacheRead: 0.2)),
            ("claude-sonnet-5", .init(input: 2, output: 10)),
            ("claude-haiku-5-5", .init(input: 0.1, output: 0.5, cacheRead: 0.01)),
        ]
        if let match = exact.first(where: { model.hasPrefix($0.0) }) { return match.1 }
        if model.contains("fable") || model.contains("mythos") {
            return .init(input: 10, output: 50)
        }
        if model.contains("opus") { return .init(input: 5, output: 25) }
        if model.contains("haiku") { return .init(input: 1, output: 5) }
        return .init(input: 3, output: 15)
    }
}
