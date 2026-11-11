import Foundation

/// Reads and controls top-level HTML media using the browser's opt-in AppleScript support.
public enum BrowserMedia: CaseIterable, Sendable {
    case safari
    case chrome

    public var bundleID: String {
        switch self {
        case .safari: "com.apple.Safari"
        case .chrome: "com.google.Chrome"
        }
    }

    public func sampleScript(applicationURL: URL) -> String {
        script(
            javascript: """
                (() => {
                    if (!["https:", "http:"].includes(location.protocol)) return "";
                    const media = [...document.querySelectorAll("audio, video")].filter(
                        item => item.currentSrc && !item.ended && !item.muted && item.volume > 0
                    );
                    const item = media.find(item => !item.paused) ||
                        media.find(item => item.currentTime > 0);
                    if (!item) return "";
                    const key = Symbol.for("dev.spectrum.browser-media");
                    if (window[key]?.media !== item) {
                        const token = [...crypto.getRandomValues(new Uint8Array(16))]
                            .map(byte => byte.toString(16).padStart(2, "0")).join("");
                        window[key] = { media: item, token };
                    }
                    const metadata = navigator.mediaSession?.metadata;
                    return (item.paused ? "-" : "+") + JSON.stringify({
                        token: window[key].token,
                        title: metadata?.title || document.title,
                        artist: metadata?.artist || "",
                        album: metadata?.album || "",
                        elapsed: item.currentTime,
                        duration: Number.isFinite(item.duration) ? item.duration : 0,
                        isPlaying: !item.paused
                    });
                })()
                """,
            applicationURL: applicationURL, sampling: true)
    }

    public func toggleScript(token: String, applicationURL: URL) -> String? {
        guard Self.valid(token) else { return nil }
        return script(
            javascript: """
                (() => {
                    const target = window[Symbol.for("dev.spectrum.browser-media")];
                    if (target?.token !== "\(token)" || !target.media.isConnected) return "";
                    if (target.media.paused) void target.media.play().catch(() => {});
                    else target.media.pause();
                    return "+";
                })()
                """,
            applicationURL: applicationURL, sampling: false)
    }

    public func parse(_ output: String, sampledAt: Date) -> NowPlaying? {
        guard output.first == "+" || output.first == "-",
            let sample = try? JSONDecoder().decode(
                Sample.self, from: Data(output.dropFirst().utf8)),
            Self.valid(sample.token), (0...Double(Int32.max)).contains(sample.elapsed),
            (0...Double(Int32.max)).contains(sample.duration),
            !sample.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return NowPlaying(
            title: sample.title, artist: sample.artist, album: sample.album,
            duration: max(0, sample.duration), elapsed: max(0, sample.elapsed),
            sampledAt: sampledAt, isPlaying: sample.isPlaying, bundleID: bundleID,
            browserToken: sample.token)
    }

    private struct Sample: Decodable {
        let token: String
        let title: String
        let artist: String
        let album: String
        let elapsed: TimeInterval
        let duration: TimeInterval
        let isPlaying: Bool
    }

    private static func valid(_ token: String) -> Bool {
        let digits = "0123456789abcdef".utf8
        return token.utf8.count == 32 && token.utf8.allSatisfy { digits.contains($0) }
    }

    private func script(javascript: String, applicationURL: URL, sampling: Bool) -> String {
        let escaped = Self.escape(javascript)
        let path = Self.escape(applicationURL.path)
        let execute =
            self == .safari
            ? "do JavaScript \"\(escaped)\" in browserTab"
            : "execute browserTab javascript \"\(escaped)\""
        let privateWindow =
            self == .chrome ? "if mode of browserWindow is not \"incognito\" then" : ""
        let endWindow = self == .chrome ? "end if" : ""
        let remember = sampling ? "if fallback is \"\" then set fallback to sampleResult" : ""
        return """
            with timeout of 2 seconds
                tell application "\(path)"
                    set fallback to ""
                    repeat with browserWindow in windows
                        \(privateWindow)
                        repeat with browserTab in tabs of browserWindow
                            try
                                set sampleResult to \(execute)
                                if sampleResult is not missing value and sampleResult is not "" then
                                    if character 1 of sampleResult is "+" then return sampleResult
                                    \(remember)
                                end if
                            on error number errorNumber
                                if errorNumber is -1743 or errorNumber is -1712 then return ""
                            end try
                        end repeat
                        \(endWindow)
                    end repeat
                    return fallback
                end tell
            end timeout
            """
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
