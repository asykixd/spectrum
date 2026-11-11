import Darwin
import Foundation

/// A cursor for an append-only JSONL file. An unfinished record stays in memory until its newline.
struct JSONLReader: Sendable {
    private struct FileStamp: Equatable, Sendable {
        let device: dev_t
        let inode: ino_t
        let seconds: Int
        let nanoseconds: Int

        init(_ info: stat) {
            device = info.st_dev
            inode = info.st_ino
            seconds = info.st_mtimespec.tv_sec
            nanoseconds = info.st_mtimespec.tv_nsec
        }

        func matches(_ other: Self) -> Bool { device == other.device && inode == other.inode }
    }

    private var stamp: FileStamp?
    private var offset: UInt64 = 0
    private var lineStart: UInt64 = 0
    private var pending = Data()
    private var discarding = false

    mutating func read(
        _ url: URL, tailBytes: Int? = nil, maxRecordBytes: Int? = nil,
        onReset: () -> Void, onLine: (Data, UInt64) -> Void
    ) throws {
        let fd = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard info.st_mode & S_IFMT == S_IFREG else { throw POSIXError(.EINVAL) }
        let size = UInt64(info.st_size)
        let current = FileStamp(info)
        if stamp?.matches(current) != true || size < offset || (size == offset && stamp != current)
        {
            let start = tailBytes.map { size > UInt64($0) ? size - UInt64($0) : 0 } ?? 0
            discarding = false
            if start > 0 {
                try handle.seek(toOffset: start - 1)
                discarding = try handle.read(upToCount: 1)?.first != UInt8(ascii: "\n")
            }
            offset = start
            lineStart = start
            pending.removeAll()
            onReset()
        }
        stamp = current
        try handle.seek(toOffset: offset)
        while offset < size,
            let chunk = try handle.read(upToCount: Int(min(64 * 1024, size - offset))),
            !chunk.isEmpty
        {
            var start = chunk.startIndex
            for end in chunk.indices where chunk[end] == UInt8(ascii: "\n") {
                add(chunk[start..<end], limit: maxRecordBytes)
                if !discarding { onLine(pending, lineStart) }
                pending.removeAll(keepingCapacity: true)
                discarding = false
                lineStart = offset + UInt64(end + 1 - chunk.startIndex)
                start = end + 1
            }
            add(chunk[start...], limit: maxRecordBytes)
            offset += UInt64(chunk.count)
        }
    }

    private mutating func add(_ bytes: Data, limit: Int?) {
        guard !discarding else { return }
        if let limit, bytes.count > limit - pending.count {
            discarding = true
            pending.removeAll()
        } else {
            pending.append(bytes)
        }
    }
}
