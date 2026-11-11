import Foundation

/// Runs the transport used by the hook CLI. Only permission decisions produce output.
public enum HookForwarder {
    public static func run(
        _ input: Data, from provider: AgentProvider, terminalTab: TerminalTab? = nil,
        socketPath: String
    ) -> Data {
        guard
            let payload = try? AgentEvent.forwardedPayload(
                input, from: provider, terminalTab: terminalTab),
            let event = try? AgentEvent.decode(payload)
        else { return Data() }
        if event.kind == .permissionRequest && provider.supportsPermissionHooks {
            return
                (try? AgentSocket.request(
                    payload, to: socketPath, timeout: TimeInterval(HookInstaller.permissionWait)))
                ?? Data()
        }
        try? AgentSocket.send(payload, to: socketPath)
        return Data()
    }
}
