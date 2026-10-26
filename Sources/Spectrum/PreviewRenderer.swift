import AppKit
import SpectrumCore
import SwiftUI

/// `Spectrum preview <dir>`: renders every notch state with made-up sample data to PNGs, for
/// reviewing the UI and for the README. Nothing from the user's own sessions is used.
@MainActor
enum PreviewRenderer {
    private struct Scene {
        let name: String
        var tab: AgentsTab = .sessions
        var sessions: [AgentSession] = []
        var music = false
        var hovering = false
        var agentsOpen = false
        var conversation = false
        var hour = 14
        /// Activities the sessions had a moment ago, to trigger the done checkmark.
        var before: [AgentSession]?
    }

    static func render(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let geometry = NotchGeometry(
            screenFrame: screen,
            topLeftArea: CGRect(x: 0, y: 950, width: 663, height: 32),
            topRightArea: CGRect(x: 849, y: 950, width: 663, height: 32))

        let scenes = [
            Scene(name: "compact", music: true),
            Scene(name: "expanded", music: true, hovering: true),
            Scene(name: "attention", sessions: [agent("b", "billing-api", .waitingForUser)]),
            Scene(
                name: "done", sessions: [agent("w", "weather-app", .idle)],
                before: [agent("w", "weather-app", .thinking)]),
            Scene(name: "agents-sessions", sessions: listSessions, agentsOpen: true),
            Scene(
                name: "agents-conversation", sessions: listSessions, agentsOpen: true,
                conversation: true),
            Scene(name: "agents-office", tab: .office, sessions: officeSessions, agentsOpen: true),
            Scene(
                name: "agents-office-night", tab: .office, sessions: officeSessions,
                agentsOpen: true, hour: 23),
        ]
        for scene in scenes {
            let model = NotchModel(geometry: geometry)
            model.renderingStill = true
            model.hooksInstalled = true
            model.tab = scene.tab
            model.clockOverride = Calendar.current.date(
                bySettingHour: scene.hour, minute: 10, second: 0, of: Date())
            if scene.music {
                model.artwork = sampleArtwork
                model.accent = Color(hex: 0xF2A65A)
                model.nowPlaying = NowPlaying(
                    title: "Midnight Drive", artist: "Neon Coast, Lumen", duration: 214,
                    elapsed: 71, sampledAt: Date(), isPlaying: true,
                    bundleID: "com.spotify.client")
            }
            if let before = scene.before { model.codeSessions = before }
            model.chatSessions = scene.sessions.filter { $0.kind == .chat }
            model.codeSessions = scene.sessions.filter { $0.kind == .code }
            if scene.conversation {
                model.selectedSessionID = "a"
                model.transcript = sampleTranscript
            }
            if scene.hovering { model.isHovering = true }
            if scene.agentsOpen { model.agentsOpen = true }

            let frame = NotchLayout.panelFrame(for: geometry)
            let view = NotchRootView(model: model)
                .frame(width: frame.width, height: frame.height)
                .background(
                    LinearGradient(
                        colors: [Color(hex: 0x3A2E6E), Color(hex: 0x1F4E79), Color(hex: 0x0F2A3F)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
            try write(view, to: directory.appending(path: "\(scene.name).png"))
        }
    }

    /// Made-up cover art: a synthwave sunset.
    private static var sampleArtwork: NSImage? {
        let cover = ZStack {
            LinearGradient(
                colors: [Color(hex: 0x2B1055), Color(hex: 0xD53A9D), Color(hex: 0xF9A03F)],
                startPoint: .top, endPoint: .bottom)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xFFE29A), Color(hex: 0xFF6B6B)], startPoint: .top,
                        endPoint: .bottom)
                )
                .frame(width: 120, height: 120)
                .offset(y: 30)
            VStack(spacing: 6) {
                ForEach(0..<5) { row in
                    Rectangle().fill(Color(hex: 0x2B1055)).frame(height: CGFloat(2 + row))
                }
            }
            .offset(y: 70)
        }
        .frame(width: 240, height: 240)
        .clipped()
        let renderer = ImageRenderer(content: cover)
        renderer.scale = 2
        return renderer.nsImage
    }

    private static func write(_ view: some View, to url: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let tiff = renderer.nsImage?.tiffRepresentation,
            let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
        print(url.path)
    }

    private static func agent(
        _ id: String, _ project: String, _ activity: AgentActivity,
        kind: AgentSession.Kind = .code, minutesAgo: Double = 3
    ) -> AgentSession {
        let now = Date()
        return AgentSession(
            id: id, kind: kind, title: kind == .chat ? project : nil,
            cwd: kind == .code ? "~/code/\(project)" : nil, transcriptPath: "/dev/null",
            activity: activity, startedAt: now.addingTimeInterval(-minutesAgo * 60),
            updatedAt: now.addingTimeInterval(-minutesAgo * 20))
    }

    /// Small enough to fit the list without scrolling.
    private static let listSessions = [
        agent("a", "weather-app", .usingTool("Bash")),
        agent("b", "billing-api", .waitingForUser, minutesAgo: 1),
        agent("c", "Trip ideas", .responding, kind: .chat),
        agent("d", "dotfiles", .idle, minutesAgo: 12),
    ]

    private static let officeSessions = [
        agent("a", "weather-app", .usingTool("Bash")),
        agent("b", "billing-api", .waitingForUser),
        agent("e", "landing-page", .thinking),
        agent("f", "ml-pipeline", .usingTool("Edit")),
        agent("c", "Trip ideas", .responding, kind: .chat),
        agent("d", "dotfiles", .idle),
        agent("g", "Recipes", .idle, kind: .chat),
    ]

    private static let sampleTranscript: [TranscriptMessage] = [
        .init(id: "1", role: .user, text: "Add a 7-day forecast screen"),
        .init(
            id: "2", role: .assistant, text: "I'll add a ForecastView fed by the daily endpoint."),
        .init(id: "3", role: .tool, text: "Read: Sources/Weather/API.swift"),
        .init(id: "4", role: .tool, text: "Write: Sources/Weather/ForecastView.swift"),
        .init(id: "5", role: .tool, text: "Bash: swift test"),
        .init(
            id: "6", role: .assistant,
            text: "Done: the forecast screen shows 7 days with highs, lows and icons. Tests pass."),
    ]
}
