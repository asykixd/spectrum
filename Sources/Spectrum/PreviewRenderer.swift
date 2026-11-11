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
        var withoutNotch = false
        var hovering = false
        var agentsOpen = false
        var conversation = false
        var hour = 14
        var boss = false
        var newSession = false
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
            Scene(name: "compact-pill", music: true, withoutNotch: true),
            Scene(name: "expanded", music: true, hovering: true),
            Scene(
                name: "expanded-waiting",
                sessions: [
                    agent("b", "billing-api", .waitingForUser),
                    agent("w", "weather-app", .thinking),
                    agent("d", "docs-site", .waitingForUser),
                ],
                music: true, hovering: true),
            Scene(name: "attention", sessions: [agent("b", "billing-api", .waitingForUser)]),
            Scene(
                name: "compact-attention", sessions: [agent("b", "billing-api", .waitingForUser)],
                music: true),
            Scene(name: "permission", sessions: [askingAgent], hovering: true),
            Scene(
                name: "done", sessions: [agent("w", "weather-app", .idle)],
                before: [agent("w", "weather-app", .thinking)]),
            Scene(name: "agents-sessions", sessions: listSessions, agentsOpen: true),
            Scene(
                name: "agents-conversation", sessions: listSessions, agentsOpen: true,
                conversation: true),
            Scene(name: "agents-office", tab: .office, sessions: officeSessions, agentsOpen: true),
            Scene(name: "agents-new-session", agentsOpen: true, newSession: true),
            Scene(
                name: "agents-boss", tab: .boss, sessions: listSessions, agentsOpen: true,
                boss: true),
            Scene(
                name: "agents-office-night", tab: .office, sessions: officeSessions,
                agentsOpen: true, hour: 23),
        ]
        try write(
            AppIcon().frame(width: 512, height: 512), to: directory.appending(path: "AppIcon.png"))
        for scene in scenes {
            let sceneGeometry =
                scene.withoutNotch
                ? NotchGeometry(
                    screenFrame: screen, topLeftArea: nil, topRightArea: nil, visibleTop: 958)
                : geometry
            let model = NotchModel(geometry: sceneGeometry)
            model.renderingStill = true
            model.installedHooks = [.claude]
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
                if scene.hovering {
                    model.lyrics = Lyrics(lrc: "[01:05.00] Neon lights are fading into the rain")
                }
            }
            if let before = scene.before { model.codeSessions = before }
            model.chatSessions = scene.sessions.filter { $0.kind == .chat }
            model.codeSessions = scene.sessions.filter { $0.kind == .code }
            if scene.conversation {
                model.selectedSessionID = "a"
                model.transcript = sampleTranscript
            }
            if scene.boss { model.bossReport = sampleReport }
            if scene.newSession {
                model.newSessionOpen = true
                model.recentProjects = [
                    "~/code/weather-app", "~/code/billing-api", "~/code/landing-page",
                    "~/code/dotfiles", "~/code/ml-pipeline",
                ]
                model.newSessionDirectory = "~/code/weather-app"
            }
            if scene.hovering { model.isHovering = true }
            if scene.agentsOpen { model.agentsOpen = true }

            let frame = NotchLayout.panelFrame(for: sceneGeometry)
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

    private static var askingAgent: AgentSession {
        var session = agent("b", "billing-api", .waitingForUser)
        session.permission = PermissionPrompt(tool: "Bash", detail: "rm -rf .build && swift test")
        return session
    }

    private static var planningAgent: AgentSession {
        var session = agent("a", "weather-app", .usingTool("Bash"))
        session.tasks.apply(
            .replaceAll(
                [
                    .init(id: "0", title: "Add model", status: .completed),
                    .init(id: "1", title: "Fetch forecast", status: .completed),
                    .init(
                        id: "2", title: "Write view", activeForm: "Writing the view",
                        status: .inProgress),
                    .init(id: "3", title: "Run tests", status: .pending),
                ]))
        return session
    }

    private static var finishedAgent: AgentSession {
        var session = agent("d", "dotfiles", .idle, minutesAgo: 12)
        session.changes.record(FileChange(path: "~/.zshrc", added: 18, removed: 31))
        session.changes.record(FileChange(path: "~/.gitconfig", added: 4, removed: 2))
        return session
    }

    /// Small enough to fit the list without scrolling.
    private static let listSessions = [
        planningAgent,
        agent("b", "billing-api", .waitingForUser, minutesAgo: 1),
        agent("c", "Trip ideas", .responding, kind: .chat),
        finishedAgent,
    ]

    private static var delegatingAgent: AgentSession {
        var session = agent("f", "ml-pipeline", .usingTool("Agent"))
        session.subagents = 2
        return session
    }

    private static let officeSessions = [
        agent("a", "weather-app", .usingTool("Bash")),
        agent("b", "billing-api", .waitingForUser),
        agent("e", "landing-page", .usingTool("Read")),
        delegatingAgent,
        agent("h", "docs-site", .usingTool("WebSearch")),
        agent("c", "Trip ideas", .responding, kind: .chat),
        agent("d", "dotfiles", .idle),
        agent("g", "Recipes", .idle, kind: .chat),
    ]

    private static var sampleReport: BossReport {
        let now = Date()
        let hour = Calendar.current.dateInterval(of: .hour, for: now)?.start ?? now
        return BossReport(
            todayCost: 18.42, todayTokens: 21_400_000, activeTime: 5 * 3600 + 38 * 60,
            projects: [
                .init(
                    name: "weather-app", cost: 9.85, tokens: 11_200_000,
                    activeTime: 2 * 3600 + 50 * 60,
                    sessions: 2, lastPrompt: "Add a 7-day forecast screen"),
                .init(
                    name: "billing-api", cost: 5.10, tokens: 6_300_000,
                    activeTime: 1 * 3600 + 42 * 60,
                    sessions: 1, lastPrompt: "Retry failed webhooks with backoff"),
                .init(
                    name: "landing-page", cost: 2.31, tokens: 2_900_000, activeTime: 48 * 60,
                    sessions: 1, lastPrompt: "Make the hero section responsive"),
                .init(
                    name: "dotfiles", cost: 1.16, tokens: 1_000_000, activeTime: 18 * 60,
                    sessions: 1, lastPrompt: "Clean up zsh aliases"),
            ],
            window: .init(
                start: hour.addingTimeInterval(-3600), end: hour.addingTimeInterval(4 * 3600),
                cost: 6.70, tokens: 7_800_000))
    }

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
