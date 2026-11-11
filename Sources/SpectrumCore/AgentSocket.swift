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
    private static let maximumReply = 64 * 1024
    fileprivate static let maximumPayload = 4 * 1024 * 1024

    /// Delivers one event within a single deadline, even when a peer stops reading.
    public static func send(_ payload: Data, to path: String, timeout: TimeInterval = 1) throws {
        let deadline = Deadline(seconds: timeout)
        let fd = try connected(to: path, deadline: deadline)
        defer { close(fd) }
        try write(payload, to: fd, deadline: deadline, maximum: maximumPayload)
    }

    /// Delivers a request and returns a complete reply, or empty data on a reply timeout.
    public static func request(_ payload: Data, to path: String, timeout: TimeInterval) throws
        -> Data
    {
        let sendDeadline = Deadline(seconds: 1)
        let fd = try connected(to: path, deadline: sendDeadline)
        defer { close(fd) }
        try write(payload, to: fd, deadline: sendDeadline, maximum: maximumPayload)
        shutdown(fd, SHUT_WR)
        do {
            return try readAll(fd, deadline: Deadline(seconds: timeout), maximum: maximumReply)
        } catch AgentSocketError.system(_, ETIMEDOUT) {
            return Data()
        }
    }

    private static func connected(to path: String, deadline: Deadline) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AgentSocketError.system("socket", errno) }
        do {
            try prepare(fd)
            var address = try makeAddress(path)
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            if result != 0 {
                guard errno == EINPROGRESS else { throw AgentSocketError.system("connect", errno) }
                try deadline.wait(for: Int16(POLLOUT), fd: fd)
                var error: Int32 = 0
                var length = socklen_t(MemoryLayout<Int32>.size)
                guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0 else {
                    throw AgentSocketError.system("getsockopt", errno)
                }
                guard error == 0 else { throw AgentSocketError.system("connect", error) }
            }
            return fd
        } catch {
            close(fd)
            throw error
        }
    }

    fileprivate static func prepare(_ fd: Int32) throws {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        guard fcntl(fd, F_SETFL, O_NONBLOCK) >= 0 else {
            throw AgentSocketError.system("fcntl", errno)
        }
    }

    fileprivate static func write(
        _ payload: Data, to fd: Int32, deadline: Deadline, maximum: Int = maximumReply
    ) throws {
        guard payload.count <= maximum else { throw AgentSocketError.system("write", EMSGSIZE) }
        try payload.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                try deadline.wait(for: Int16(POLLOUT), fd: fd)
                let written = Darwin.write(fd, base + offset, buffer.count - offset)
                if written < 0, errno == EAGAIN || errno == EINTR { continue }
                guard written > 0 else { throw AgentSocketError.system("write", errno) }
                offset += written
            }
        }
    }

    fileprivate static func readAll(_ fd: Int32, deadline: Deadline, maximum: Int) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            try deadline.wait(for: Int16(POLLIN), fd: fd)
            let count = read(fd, &buffer, buffer.count)
            if count == 0 { return data }
            if count < 0, errno == EAGAIN || errno == EINTR { continue }
            guard count > 0 else { throw AgentSocketError.system("read", errno) }
            guard count <= maximum - data.count else {
                throw AgentSocketError.system("read", EMSGSIZE)
            }
            data.append(buffer, count: count)
        }
    }

    fileprivate struct Deadline {
        private let end: UInt64

        init(seconds: TimeInterval) {
            let finite = seconds.isFinite ? min(max(seconds, 0), 3_600) : 0
            end = DispatchTime.now().uptimeNanoseconds + UInt64(finite * 1_000_000_000)
        }

        func wait(for events: Int16, fd: Int32) throws {
            var event = pollfd(fd: fd, events: events, revents: 0)
            while true {
                let now = DispatchTime.now().uptimeNanoseconds
                guard end > now else { throw AgentSocketError.system("poll", ETIMEDOUT) }
                let remaining = Int32((end - now + 999_999) / 1_000_000)
                let result = poll(&event, 1, remaining)
                if result > 0 { return }
                if result == 0 { throw AgentSocketError.system("poll", ETIMEDOUT) }
                if errno != EINTR { throw AgentSocketError.system("poll", errno) }
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
        if let answer { try? AgentSocket.write(answer, to: fd, deadline: .init(seconds: 0.25)) }
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
        var address = try AgentSocket.makeAddress(path)
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        // A stale socket file from a previous run would make bind fail.
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AgentSocketError.system("socket", errno) }
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
            let failure = errno
            close(fd)
            unlink(path)
            throw AgentSocketError.system("listen", failure)
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            let reply = AgentSocketReply(fd: client)
            guard (try? AgentSocket.prepare(client)) != nil,
                let payload = try? AgentSocket.readAll(
                    client, deadline: .init(seconds: 1), maximum: AgentSocket.maximumPayload),
                !payload.isEmpty
            else {
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
        guard let source else { return }
        source.cancel()
        self.source = nil
        unlink(path)
    }

}
