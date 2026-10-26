import Foundation
import Testing

@testable import SpectrumCore

private final class Inbox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Data] = []
    let arrived = DispatchSemaphore(value: 0)

    func add(_ data: Data) {
        lock.withLock { items.append(data) }
        arrived.signal()
    }

    var received: [Data] { lock.withLock { items } }
}

@Test func serverReceivesPayloads() throws {
    let path = "/tmp/spectrum-test-\(UUID().uuidString.prefix(8)).sock"
    let server = AgentSocketServer(path: path)
    let inbox = Inbox()
    try server.start { inbox.add($0) }
    defer { server.stop() }

    try AgentSocket.send(Data("one".utf8), to: path)
    try AgentSocket.send(Data("two".utf8), to: path)

    #expect(inbox.arrived.wait(timeout: .now() + 2) == .success)
    #expect(inbox.arrived.wait(timeout: .now() + 2) == .success)
    #expect(Set(inbox.received) == [Data("one".utf8), Data("two".utf8)])
}

@Test func sendFailsFastWhenAppIsNotRunning() {
    #expect(throws: AgentSocketError.self) {
        try AgentSocket.send(Data("x".utf8), to: "/tmp/spectrum-missing-\(UUID().uuidString).sock")
    }
}

@Test func rejectsOverlongSocketPath() {
    #expect(throws: AgentSocketError.pathTooLong) {
        try AgentSocket.send(Data(), to: "/" + String(repeating: "a", count: 200))
    }
}
