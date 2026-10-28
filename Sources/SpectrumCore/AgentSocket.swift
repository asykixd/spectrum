import Darwin
import Foundation

public enum AgentSocketError: Error, Equatable {
    case pathTooLong
    case system(String, Int32)
}

/// Unix-domain socket transport between the `Spectrum hook` command and the running app.
/// One connection carries one hook payload. A plain send closes it right away; a request
/// half-closes it and waits for the app's answer.
public enum AgentSocket {
    /// Delivers `payload` to the app. Fails fast when the app isn't running.
    public static func send(_ payload: Data, to path: String, timeout: TimeInterval = 1) throws {
        let fd = try connected(to: path, timeout: timeout)
        defer { close(fd) }
        try write(payload, to: fd)
    }

    /// Delivers `payload` and returns the app's answer, empty when the app has none or doesn't
    /// answer within `timeout`.
    public static func request(_ payload: Data, to path: String, timeout: TimeInterval) throws
        -> Data
    {
        let fd = try connected(to: path, timeout: 1)
        defer { close(fd) }
        try write(payload, to: fd)
        shutdown(fd, SHUT_WR)
        try setTimeout(fd, option: SO_RCVTIMEO, seconds: timeout)
        var answer = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &buffer, buffer.count)
            guard count > 0 else { break }
            answer.append(buffer, count: count)
        }
        return answer
    }

    private static func connected(to path: String, timeout: TimeInterval) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AgentSocketError.system("socket", errno) }
        do {
            preventSigPipe(fd)
            try setTimeout(fd, option: SO_SNDTIMEO, seconds: timeout)
            var address = try makeAddress(path)
            let connected = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard connected == 0 else { throw AgentSocketError.system("connect", errno) }
            return fd
        } catch {
            close(fd)
            throw error
        }
    }

    static func preventSigPipe(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    static func write(_ payload: Data, to fd: Int32) throws {
        try payload.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(fd, base + offset, buffer.count - offset)
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

/// The open connection of one hook payload. Answering closes it; so does dropping it.
public final class AgentSocketReply: @unchecked Sendable {
    private let lock = NSLock()
    private var fd: Int32?

    init(fd: Int32) {
        self.fd = fd
    }

    deinit {
        if let fd { close(fd) }
    }

    /// Sends `answer` (or nothing) and closes the connection. Later calls do nothing.
    public func send(_ answer: Data?) {
        guard
            let fd = lock.withLock({ () -> Int32? in
                defer { self.fd = nil }
                return self.fd
            })
        else { return }
        // The hook may have given up already; then there is nobody left to tell.
        if let answer { try? AgentSocket.write(answer, to: fd) }
        close(fd)
    }
}

/// Accepts hook payloads on a Unix socket and hands each one to `handler` with its reply.
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

    public func start(handler: @escaping @Sendable (Data, AgentSocketReply) -> Void) throws {
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
            AgentSocket.preventSigPipe(client)
            let reply = AgentSocketReply(fd: client)
            guard let payload = Self.readAll(client), !payload.isEmpty else {
                reply.send(nil)
                return
            }
            handler(payload, reply)
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
