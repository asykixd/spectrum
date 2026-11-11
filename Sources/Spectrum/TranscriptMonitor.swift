import Darwin
import Foundation
import SpectrumCore

/// Watches just the transcript visible in the sessions tab.
@MainActor
final class TranscriptMonitor {
    private struct Target: Equatable, Sendable {
        let id: String
        let url: URL
        let provider: AgentProvider
    }

    private let model: NotchModel
    private var target: Target?
    private var generation = 0
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var directoryWatcher: DispatchSourceFileSystemObject?
    private var tail = Transcript.Tail()
    private var reading = false
    private var needsRead = false

    init(model: NotchModel) {
        self.model = model
    }

    func update() {
        var visible: Target?
        if model.agentsOpen, model.tab == .sessions, let session = model.selectedSession,
            let path = session.transcriptPath
        {
            visible = Target(
                id: session.id, url: URL(fileURLWithPath: path), provider: session.provider)
        }
        if visible != target {
            generation += 1
            fileWatcher?.cancel()
            fileWatcher = nil
            directoryWatcher?.cancel()
            directoryWatcher = nil
            target = visible
            tail = Transcript.Tail()
            needsRead = false
        }
        guard let target else { return }
        watch(target)
        reload()
    }

    func receivedHook(for sessionID: String) {
        guard model.selectedSessionID == sessionID else { return }
        update()
    }

    private func watch(_ target: Target) {
        let generation = self.generation
        if directoryWatcher == nil {
            // A writer may create or replace the file after the hook is sent.
            directoryWatcher = watcher(for: target.url.deletingLastPathComponent()) { [weak self] in
                guard let self, self.generation == generation else { return }
                if Self.wasRemoved(self.directoryWatcher?.data) {
                    self.directoryWatcher?.cancel()
                    self.directoryWatcher = nil
                }
                self.update()
            }
        }
        if fileWatcher == nil {
            fileWatcher = watcher(for: target.url) { [weak self] in
                guard let self, self.generation == generation else { return }
                if Self.wasRemoved(self.fileWatcher?.data) {
                    self.fileWatcher?.cancel()
                    self.fileWatcher = nil
                }
                self.update()
            }
        }
    }

    private func watcher(for url: URL, event: @escaping @MainActor () -> Void)
        -> DispatchSourceFileSystemObject?
    {
        let fd = open(url.path, O_EVTONLY | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .rename, .delete, .revoke],
            queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { event() } }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private static func wasRemoved(_ event: DispatchSource.FileSystemEvent?) -> Bool {
        !(event ?? []).intersection([.rename, .delete, .revoke]).isEmpty
    }

    private func reload() {
        guard let target else { return }
        needsRead = true
        guard !reading else { return }
        reading = true
        needsRead = false
        let cursor = tail
        let generation = self.generation
        Task {
            let next = await Task.detached(priority: .utility) {
                var cursor = cursor
                do {
                    try cursor.read(from: target.url, provider: target.provider)
                } catch let error as POSIXError where error.code == .ENOENT {
                    // The directory watcher will retry when the file is created.
                } catch {
                    log.error("reading transcript failed: \(error)")
                }
                return cursor
            }.value
            if self.generation == generation {
                tail = next
                if model.transcript != next.messages { model.transcript = next.messages }
            }
            reading = false
            if needsRead { reload() }
        }
    }
}
