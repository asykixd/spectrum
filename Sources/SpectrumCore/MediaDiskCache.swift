import CryptoKit
import Foundation

/// A bounded cache of fetched artwork and lyrics. Cache failures never affect playback.
public actor MediaDiskCache {
    private let directory: URL
    private let maximumBytes: Int
    private let maximumEntryBytes: Int
    private let manager = FileManager.default

    public init(
        directory: URL, maximumBytes: Int = 32 * 1024 * 1024,
        maximumEntryBytes: Int = 4 * 1024 * 1024
    ) {
        self.directory = directory
        self.maximumBytes = max(0, maximumBytes)
        self.maximumEntryBytes = max(0, min(maximumEntryBytes, maximumBytes))
    }

    public func data(for key: String) -> Data? {
        let url = location(for: key)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            size > 0, size <= maximumEntryBytes,
            let data = try? Data(contentsOf: url)
        else { return nil }
        try? manager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    public func insert(_ data: Data, for key: String) {
        guard !data.isEmpty, data.count <= maximumEntryBytes else { return }
        do {
            try manager.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try data.write(to: location(for: key), options: .atomic)
            evict()
        } catch {
            // The downloaded item can still be shown without a cache.
            return
        }
    }

    private func location(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let filename = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: filename + ".cache")
    }

    private func evict() {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard
            let urls = try? manager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: Array(keys))
        else { return }
        let entries = urls.filter { $0.pathExtension == "cache" }.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys), let size = values.fileSize
            else { return nil as (URL, Int, Date)? }
            return (url, size, values.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.1 }
        for (url, size, _) in entries.sorted(by: { $0.2 < $1.2 }) {
            if total <= maximumBytes { break }
            if (try? manager.removeItem(at: url)) != nil { total -= size }
        }
    }
}
