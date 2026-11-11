import Darwin

/// A Terminal tab's device and the shell session that owns it. Device names can be reused.
public struct TerminalTab: Equatable, Sendable {
    public let tty: String
    public let sessionLeader: Int32

    public init?(tty: String, sessionLeader: Int32) {
        let prefix = "/dev/ttys"
        guard tty.hasPrefix(prefix), sessionLeader > 1 else { return nil }
        let suffix = tty.utf8.dropFirst(prefix.utf8.count)
        guard !suffix.isEmpty,
            suffix.allSatisfy({ (48...57).contains($0) || (97...122).contains($0) })
        else { return nil }
        self.tty = tty
        self.sessionLeader = sessionLeader
    }

    public static func capture(environment: [String: String]) -> TerminalTab? {
        // Hook stdin and stdout are pipes, even when the agent has a controlling terminal.
        guard environment["TERM_PROGRAM"] == "Apple_Terminal", environment["TMUX"] == nil,
            environment["STY"] == nil, environment["SSH_TTY"] == nil,
            let tty = controllingTTY(of: getpid())
        else { return nil }
        return TerminalTab(tty: tty, sessionLeader: getsid(0))
    }

    public var isLive: Bool { Self.controllingTTY(of: sessionLeader) == tty }

    public var focusScript: String {
        """
        with timeout of 3 seconds
            tell application "Terminal"
                repeat with candidateWindow in windows
                    repeat with candidateTab in tabs of candidateWindow
                        if tty of candidateTab is "\(tty)" then
                            set miniaturized of candidateWindow to false
                            set selected of candidateTab to true
                            set frontmost of candidateWindow to true
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end tell
        end timeout
        return false
        """
    }

    private static func controllingTTY(of pid: Int32) -> String? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
            info.e_tdev != UInt32.max,
            let name = devname(dev_t(bitPattern: info.e_tdev), mode_t(S_IFCHR))
        else { return nil }
        return "/dev/" + String(cString: name)
    }
}
