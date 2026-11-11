import Foundation

/// A reproducible workload that uses synthetic transcripts and never opens the user's logs.
public enum UsageBenchmark {
    public enum Failure: Error { case invalidRecordCount }

    public struct Sample: Sendable {
        public let duration: Duration
        public let entries: Int

        public var milliseconds: Double {
            let time = duration.components
            return Double(time.seconds) * 1_000 + Double(time.attoseconds) / 1e15
        }
    }

    public struct Result: Sendable {
        public let cold: Sample
        public let unchanged: Sample
        public let append: Sample
    }

    public static func run(records: Int) throws -> Result {
        guard (1...500_000).contains(records) else { throw Failure.invalidRecordCount }
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appending(path: "spectrum-usage-\(UUID())")
        try manager.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: directory) }
        let file = directory.appending(path: "session.jsonl")
        do {
            var data = Data()
            for index in 0..<records { data.append(contentsOf: line(index).utf8) }
            try data.write(to: file)
        }

        var scanner = UsageScanner(root: directory)
        let cold = sample(&scanner)
        let unchanged = sample(&scanner)
        let writer = try FileHandle(forWritingTo: file)
        defer { try? writer.close() }
        try writer.seekToEnd()
        try writer.write(contentsOf: Data(line(records * 3).utf8))
        return Result(cold: cold, unchanged: unchanged, append: sample(&scanner))
    }

    private static func sample(_ scanner: inout UsageScanner) -> Sample {
        let clock = ContinuousClock()
        let start = clock.now
        let entries = scanner.scan(since: .distantPast).entries.count
        return Sample(duration: start.duration(to: clock.now), entries: entries)
    }

    private static func line(_ index: Int) -> String {
        let fields =
            #""timestamp":"2026-10-28T10:00:00Z","sessionId":"benchmark","cwd":"/benchmark""#
        switch index % 3 {
        case 0:
            return
                "{\(fields),\"type\":\"assistant\",\"message\":{\"id\":\"m\(index)\",\"model\":\"claude-sonnet-4-6\",\"usage\":{\"input_tokens\":500,\"output_tokens\":50}}}\n"
        case 1:
            return "{\(fields),\"type\":\"user\",\"message\":{\"content\":\"Check the parser\"}}\n"
        default:
            return
                "{\(fields),\"type\":\"system\",\"message\":{\"content\":[{\"type\":\"tool_result\",\"content\":\"Build complete\"}]}}\n"
        }
    }
}
