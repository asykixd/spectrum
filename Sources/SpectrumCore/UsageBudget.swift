public struct UsageBudget: Equatable, Sendable {
    public let limit: Double

    public init(_ limit: Double) {
        self.limit = limit.isFinite ? max(0, limit) : 0
    }

    public func reached(by estimatedCost: Double) -> Bool {
        limit > 0 && estimatedCost >= limit
    }
}
