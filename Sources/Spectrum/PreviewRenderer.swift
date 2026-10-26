import AppKit
import SpectrumCore
import SwiftUI

/// `Spectrum preview <dir>`: renders every notch mode with sample data to PNGs, so the UI can
/// be reviewed without music playing or agents running.
@MainActor
enum PreviewRenderer {
    static func render(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let geometry = NotchGeometry(
            screenFrame: screen,
            topLeftArea: CGRect(x: 0, y: 950, width: 663, height: 32),
            topRightArea: CGRect(x: 849, y: 950, width: 663, height: 32))

        let scenes: [(String, NotchMode, AgentsTab)] = [
            ("compact", .compact, .sessions),
            ("expanded", .expanded, .sessions),
            ("agents-sessions", .agents, .sessions),
            ("agents-office", .agents, .office),
        ]
        for (name, mode, tab) in scenes {
            let model = sampleModel(geometry: geometry)
            model.tab = tab
            switch mode {
            case .agents: model.agentsOpen = true
            case .expanded: model.isHovering = true
            case .compact, .hidden: break
            }
            let frame = NotchLayout.panelFrame(for: geometry)
            let view = NotchRootView(model: model)
                .frame(width: frame.width, height: frame.height)
                .background(Color(hex: 0x3B4252))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else {
                throw CocoaError(.fileWriteUnknown)
            }
            let url = directory.appending(path: "\(name).png")
            try png.write(to: url)
            print(url.path)
        }
    }

    private static func sampleModel(geometry: NotchGeometry) -> NotchModel {
        let model = NotchModel(geometry: geometry)
        model.hooksInstalled = true
        model.accent = Color(hex: 0xF2A65A)
        model.nowPlaying = NowPlaying(
            title: "высокие вещи", artist: "Sqwore", duration: 96, elapsed: 28,
            sampledAt: Date(), isPlaying: true, bundleID: "com.spotify.client")
        let now = Date()
        let samples: [(String, String, AgentActivity)] = [
            ("a1", "/Users/me/code/spectrum", .usingTool("Bash")),
            ("b2", "/Users/me/code/api-server", .waitingForUser),
            ("c3", "/Users/me/code/landing", .thinking),
            ("d4", "/Users/me/code/dotfiles", .idle),
            ("e5", "/Users/me/code/ml-pipeline", .usingTool("Edit")),
        ]
        model.codeSessions = samples.enumerated().map { index, sample in
            AgentSession(
                id: sample.0, cwd: sample.1, activity: sample.2,
                startedAt: now.addingTimeInterval(Double(-600 + index * 60)),
                updatedAt: now.addingTimeInterval(Double(-index * 17)))
        }
        model.chatSessions = [
            AgentSession(
                id: "chat", kind: .chat, title: "Trip to Tbilisi", cwd: nil,
                activity: .responding, startedAt: now, updatedAt: now)
        ]
        // Mode only advances from compact to expanded, as it would with a real pointer.
        model.isHovering = false
        return model
    }
}
