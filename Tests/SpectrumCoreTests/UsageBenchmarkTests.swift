import Testing

@testable import SpectrumCore

@Test func benchmarkSeparatesColdUnchangedAndAppendedScans() throws {
    let result = try UsageBenchmark.run(records: 12)
    #expect(result.cold.entries == 4)
    #expect(result.unchanged.entries == 4)
    #expect(result.append.entries == 5)
    #expect(result.cold.milliseconds >= 0)
}
