import Darwin
import Foundation

public enum AgentSocketError: Error, Equatable {
    case pathTooLong
    case system(String, Int32)
}

/// Unix-domain socket transport between the `Spectrum hook` command and the running app.
/// One connection carries one hook payload and is closed by the sender.
public enum AgentSocket {
    /// Delivers `payload` to the app. Fails fast when the app isn't running.
    public static func send(_ payload: Data, to path: String, timeout: TimeInterval = 1) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AgentSocketError.system("socket", errno) }
        defer { close(fd) }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        try setTimeout(fd, option: SO_SNDTIMEO, seconds: timeout)

        var address = try makeAddress(path)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw AgentSocketError.system("connect", errno) }

        try payload.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = write(fd, base + offset, buffer.count - offset)
                guard written > 0 else { throw AgentSocketError.system("write", errno) }
                offset += written
            }
        }
    }

    static func makeAddress(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { throw AgentSocketError.pathTooLong }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
        }
        return address
    }

    static func setTimeout(_ fd: Int32, option: Int32, seconds: TimeInterval) throws {
        var value = timeval(
            tv_sec: Int(seconds), tv_usec: Int32((seconds - Double(Int(seconds))) * 1_000_000))
        guard setsockopt(fd, SOL_SOCKET, option, &value, socklen_t(MemoryLayout<timeval>.size)) == 0
        else { throw AgentSocketError.system("setsockopt", errno) }
    }
}

/// Accepts hook payloads on a Unix socket and hands each one to `handler`.
public final class AgentSocketServer: @unchecked Sendable {
    private let path: String
    private let queue = DispatchQueue(label: "spectrum.agent-socket")
    // Only touched on `queue` after `start`.
    private var source: DispatchSourceRead?

    public init(path: String) {
        self.path = path
    }

    deinit {
        source?.cancel()
    }

    public func start(handler: @escaping @Sendable (Data) -> Void) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        // A stale socket file from a previous run would make bind fail.
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AgentSocketError.system("socket", errno) }
        var address = try AgentSocket.makeAddress(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            close(fd)
            throw AgentSocketError.system("bind", errno)
        }
        guard listen(fd, 64) == 0 else {
            close(fd)
            throw AgentSocketError.system("listen", errno)
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            if let payload = Self.readAll(client), !payload.isEmpty {
                handler(payload)
            }
            close(client)
        }
        source.setCancelHandler { close(fd) }
        self.source = source
        source.resume()
    }

    public func stop() {
        source?.cancel()
        source = nil
        unlink(path)
    }

    private static func readAll(_ fd: Int32) -> Data? {
        // A stuck sender must not block the accept loop. macOS rejects the option with EINVAL
        // once the peer has already closed, which is fine: reads then hit EOF immediately.
        try? AgentSocket.setTimeout(fd, option: SO_RCVTIMEO, seconds: 1)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                return count == 0 ? data : nil
            }
        }
    }
}
