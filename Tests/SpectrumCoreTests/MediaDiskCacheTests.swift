import Foundation
import Testing

@testable import SpectrumCore

@Test func mediaCacheSurvivesRelaunchAndRejectsOversizedEntries() async {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = MediaDiskCache(directory: directory, maximumBytes: 8, maximumEntryBytes: 4)
    await first.insert(Data([1, 2, 3]), for: "lyrics/../track")
    await first.insert(Data(repeating: 0, count: 5), for: "oversized")
    let reopened = MediaDiskCache(directory: directory, maximumBytes: 8, maximumEntryBytes: 4)
    #expect(await reopened.data(for: "lyrics/../track") == Data([1, 2, 3]))
    #expect(await reopened.data(for: "oversized") == nil)
}

@Test func mediaCacheEvictsTheLeastRecentlyUsedEntry() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = MediaDiskCache(directory: directory, maximumBytes: 6)
    await cache.insert(Data([1, 2, 3]), for: "old")
    let entry = try #require(
        FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .first)
    try FileManager.default.setAttributes(
        [.modificationDate: Date.distantPast], ofItemAtPath: entry.path)
    await cache.insert(Data([4, 5, 6]), for: "recent")
    await cache.insert(Data([7, 8, 9]), for: "new")
    #expect(await cache.data(for: "old") == nil)
    #expect(await cache.data(for: "recent") == Data([4, 5, 6]))
    #expect(await cache.data(for: "new") == Data([7, 8, 9]))
}
