import AppKit
import ApplicationServices
import IOKit.ps
import SpectrumCore

private enum ChatReplyFailure: String, Sendable {
    case closed = "Open this chat in Claude first."
    case busy = "Wait for Claude to finish its current reply."
    case draftExists = "This chat already has a draft in Claude."
    case unavailable = "Spectrum couldn't find the chat's editable composer."
    case draftPlaced = "Check the draft in Claude and send it there."
}

/// Reads the Claude desktop app's accessibility tree, off the main thread: a long chat has
/// thousands of nodes.
private final class ClaudeAppReader: @unchecked Sendable {
    static let bundleID = "com.anthropic.claudefordesktop"
    private static let nodeLimit = 6000

    private let queue = DispatchQueue(label: "spectrum.claude-app", qos: .utility)
    // Only touched on `queue`.
    private var enabledPID: pid_t?

    func snapshot() async -> ClaudeChatSnapshot? {
        guard
            let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
                .first
        else { return nil }
        let pid = app.processIdentifier
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.read(pid: pid))
            }
        }
    }

    func reply(_ text: String, to sessionID: String) async -> ChatReplyFailure? {
        guard AXIsProcessTrusted() else { return .unavailable }
        guard
            let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
                .first
        else { return .closed }
        let pid = app.processIdentifier
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.send(text, to: sessionID, pid: pid))
            }
        }
    }

    private func send(_ text: String, to sessionID: String, pid: pid_t) -> ChatReplyFailure? {
        let app = AXUIElementCreateApplication(pid)
        guard let window = focusedWindow(of: app),
            let page = chatPage(in: window, sessionID: sessionID)
        else { return .closed }

        let before = elements(in: page)
        let buttons = before.filter { $0.1.role == kAXButtonRole }
            .flatMap { [$0.1.title, $0.1.description].compactMap { $0 } }
        if ClaudeChatSnapshot(pageTitle: nil, url: nil, buttonLabels: buttons, texts: [])
            .isGenerating
        {
            return .busy
        }
        let fields = before.filter { element, node in
            guard node.role == kAXTextAreaRole else { return false }
            var editable = DarwinBoolean(false)
            return AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &editable)
                == .success && editable.boolValue
        }
        guard fields.count == 1, let composer = fields.first?.0,
            let draft = composerText(composer)
        else { return .unavailable }
        guard draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .draftExists
        }
        guard focusedWindow(of: app).map({ CFEqual($0, window) }) == true,
            ClaudeChatReply.matches(sessionID: sessionID, url: value(page, "AXURL") as? URL)
        else { return .closed }
        guard
            AXUIElementSetAttributeValue(composer, kAXValueAttribute as CFString, text as CFString)
                == .success
        else { return .unavailable }

        // Let Electron update the enabled state of its Send button after the accessibility edit.
        Thread.sleep(forTimeInterval: 0.12)
        guard composerText(composer) == text,
            focusedWindow(of: app).map({ CFEqual($0, window) }) == true,
            ClaudeChatReply.matches(sessionID: sessionID, url: value(page, "AXURL") as? URL)
        else { return .draftPlaced }
        let sendButtons = elements(in: page).filter { element, node in
            node.role == kAXButtonRole
                && [node.title, node.description].compactMap { $0 }.contains(
                    where: ClaudeChatReply.isSendButton)
                && (value(element, kAXEnabledAttribute) as? Bool) == true
        }
        guard sendButtons.count == 1, let button = sendButtons.first?.0,
            focusedWindow(of: app).map({ CFEqual($0, window) }) == true,
            ClaudeChatReply.matches(sessionID: sessionID, url: value(page, "AXURL") as? URL),
            composerText(composer) == text,
            AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
        else { return .draftPlaced }
        return nil
    }

    private func focusedWindow(of app: AXUIElement) -> AXUIElement? {
        let window = value(app, kAXFocusedWindowAttribute) ?? value(app, kAXMainWindowAttribute)
        guard let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(window, to: AXUIElement.self)
    }

    private func chatPage(in window: AXUIElement, sessionID: String) -> AXUIElement? {
        var stack = [window]
        for _ in 0..<Self.nodeLimit {
            guard let element = stack.popLast() else { return nil }
            let node = attributes(of: element)
            if node.role == "AXWebArea",
                ClaudeChatReply.matches(sessionID: sessionID, url: node.url)
            {
                return element
            }
            stack.append(contentsOf: node.children.reversed())
        }
        return nil
    }

    private func composerText(_ element: AXUIElement) -> String? {
        let raw = value(element, kAXValueAttribute)
        return (raw as? String) ?? (raw as? NSAttributedString)?.string
    }

    private func elements(in root: AXUIElement) -> [(AXUIElement, Node)] {
        var stack = [root]
        var result: [(AXUIElement, Node)] = []
        while result.count < Self.nodeLimit, let element = stack.popLast() {
            let node = attributes(of: element)
            result.append((element, node))
            stack.append(contentsOf: node.children.reversed())
        }
        return result
    }

    private func read(pid: pid_t) -> ClaudeChatSnapshot? {
        let root = AXUIElementCreateApplication(pid)
        if enabledPID != pid {
            // Electron only builds its accessibility tree once a client asks for it.
            AXUIElementSetAttributeValue(
                root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            enabledPID = pid
        }
        var pageTitle: String?
        var url: URL?
        var buttons: [String] = []
        var texts: [String] = []
        var visited = 0

        func walk(_ element: AXUIElement) {
            visited += 1
            guard visited < Self.nodeLimit else { return }
            // One IPC round trip per node instead of one per attribute: this walk is the
            // most expensive thing Spectrum does.
            let node = attributes(of: element)
            switch node.role {
            case "AXWebArea":
                if let found = node.url, found.host() == "claude.ai" {
                    url = found
                    pageTitle = node.title
                }
            case kAXButtonRole:
                buttons += [node.description, node.title].compactMap { $0 }.filter { !$0.isEmpty }
            case kAXStaticTextRole:
                if let text = node.value, !text.isEmpty { texts.append(text) }
            default:
                break
            }
            node.children.forEach(walk)
        }

        let windows = value(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
        windows.forEach(walk)
        guard url != nil else { return nil }
        return ClaudeChatSnapshot(
            pageTitle: pageTitle, url: url, buttonLabels: buttons, texts: texts)
    }

    private struct Node {
        var role: String?
        var title: String?
        var description: String?
        var value: String?
        var url: URL?
        var children: [AXUIElement] = []
    }

    private static let nodeAttributes = [
        kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, "AXURL",
        kAXChildrenAttribute,
    ]

    private func attributes(of element: AXUIElement) -> Node {
        var result: CFArray?
        guard
            AXUIElementCopyMultipleAttributeValues(
                element, Self.nodeAttributes as CFArray, [], &result)
                == .success,
            let values = result as? [AnyObject], values.count == 6
        else { return Node() }
        // Missing attributes come back as AXValue error placeholders, which the casts reject.
        return Node(
            role: values[0] as? String, title: values[1] as? String,
            description: values[2] as? String, value: values[3] as? String,
            url: values[4] as? URL, children: values[5] as? [AXUIElement] ?? [])
    }

    private func value(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var result: AnyObject?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
        return status == .success ? result : nil
    }

}

/// Shows chats from the Claude desktop app as conversations in the office.
///
/// The app has no hooks, so Spectrum watches its UI through Accessibility: a Stop button means
/// Claude is answering, and the page title names the chat.
@MainActor
final class ClaudeChatMonitor {
    private let model: NotchModel
    private let reader = ClaudeAppReader()
    private var tracker = ClaudeChatTracker()
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var reading = false
    private var lastRead = Date.distantPast

    init(model: NotchModel) {
        self.model = model
    }

    func reply(_ text: String, to sessionID: String) {
        guard !model.chatReplySending, !model.settings.privacyMode else { return }
        model.chatReplySending = true
        model.chatReplyError = nil
        Task {
            let failure = await reader.reply(text, to: sessionID)
            model.chatReplySending = false
            guard model.selectedSessionID == sessionID else { return }
            if let failure {
                model.chatReplyError = failure.rawValue
            } else {
                model.chatReplyDraft = ""
                model.selectedSessionID = nil
                tick()
            }
        }
    }

    func start() {
        // Claude coming to the front speeds reads up right away rather than at the next tick.
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    /// Ticks only as often as the current read interval, so a closed panel costs one wakeup
    /// every few seconds instead of one a second.
    func tick() {
        if model.settings.privacyMode {
            timer?.invalidate()
            timer = nil
            return
        }
        let frontmost =
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == ClaudeAppReader.bundleID
        let interval = ChatPollPolicy.interval(
            panelOpen: model.agentsOpen, claudeFrontmost: frontmost,
            onBattery: Self.onBattery, pauseOnBattery: model.settings.pauseChatsOnBattery)
        let period = ChatPollPolicy.period(reading: interval)
        if timer?.timeInterval != period {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: period, repeats: true) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer?.tolerance = period / 5
        }
        guard let interval else { return }
        refresh(every: interval)
    }

    private static var onBattery: Bool {
        let source = IOPSGetProvidingPowerSourceType(nil)?.takeRetainedValue() as String?
        return source == kIOPMBatteryPowerKey
    }

    private func refresh(every interval: TimeInterval) {
        // Tolerance can fire the timer slightly early; that still counts as on time.
        guard !reading, model.settings.showClaudeChats,
            Date().timeIntervalSince(lastRead) >= interval * 0.8, AXIsProcessTrusted()
        else { return }
        lastRead = Date()
        tracker.retention = TimeInterval(model.settings.chatRetentionMinutes * 60)
        reading = true
        Task {
            defer { reading = false }
            let snapshot = await reader.snapshot()
            guard !model.settings.privacyMode else { return }
            let chats = tracker.update(snapshot, at: Date())
            if model.chatSessions != chats { model.chatSessions = chats }
        }
    }
}
