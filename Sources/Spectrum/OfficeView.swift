import SpectrumCore
import SwiftUI

/// Pixel-art office: every agent session works at its own desk.
struct OfficeView: View {
    let sessions: [AgentSession]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12)) { timeline in
            Canvas { context, size in
                OfficeScene(sessions: sessions, date: timeline.date).draw(in: context, size: size)
            }
        }
    }
}

struct OfficeScene {
    static let columns = 160.0
    static let rows = 78.0
    static let wallHeight = 24.0
    static let deskColumns = [14.0, 48.0, 82.0, 116.0]
    static let deskRows = [40.0, 63.0]
    static let deskWidth = 28.0

    let sessions: [AgentSession]
    let date: Date

    private var time: Double { date.timeIntervalSinceReferenceDate }

    func draw(in context: GraphicsContext, size: CGSize) {
        let pixel = min(size.width / Self.columns, size.height / Self.rows)
        let origin = CGPoint(
            x: (size.width - Self.columns * pixel) / 2, y: (size.height - Self.rows * pixel) / 2)
        let canvas = PixelCanvas(context: context, pixel: pixel, origin: origin)

        drawWall(canvas)
        drawFloor(canvas)
        drawDecor(canvas)

        let seated = sessions.prefix(Self.deskColumns.count * Self.deskRows.count)
        for (index, session) in seated.enumerated() {
            let x = Self.deskColumns[index % Self.deskColumns.count]
            let y = Self.deskRows[index / Self.deskColumns.count]
            drawWorkstation(canvas, x: x, top: y, session: session)
        }
        if sessions.count > seated.count {
            label(canvas, "+\(sessions.count - seated.count) more", x: 150, y: 74, size: 2.2)
        }
        if sessions.isEmpty {
            label(canvas, "No agents at work", x: 80, y: 46, size: 3, opacity: 0.75)
            label(canvas, "Start a Claude Code session", x: 80, y: 54, size: 2.2, opacity: 0.5)
        }
    }

    // MARK: Room

    private func drawWall(_ canvas: PixelCanvas) {
        canvas.fill(0, 0, Self.columns, Self.wallHeight, Color(hex: 0x2A3152))
        for x in stride(from: 4.0, to: Self.columns, by: 10) {
            canvas.fill(x, 0, 1, Self.wallHeight - 1, Color(hex: 0x313961))
        }
        canvas.fill(0, Self.wallHeight - 1, Self.columns, 1, Color(hex: 0x1B2038))

        drawWindow(canvas, x: 8)
        drawWindow(canvas, x: 126)
        drawClock(canvas, centerX: 80, centerY: 10)
        drawPoster(canvas, x: 50, art: .mountains)
        drawPoster(canvas, x: 98, art: .chart)
    }

    private func drawWindow(_ canvas: PixelCanvas, x: Double) {
        let y = 4.0
        let width = 26.0
        let height = 14.0
        let frame = Color(hex: 0x6B4F3A)
        let hour = Calendar.current.component(.hour, from: date)
        let isNight = hour < 6 || hour >= 21
        let isDusk = (18..<21).contains(hour) || (6..<8).contains(hour)
        let sky = Color(hex: isNight ? 0x16213E : isDusk ? 0xF2A65A : 0x7EC8F0)

        canvas.fill(x - 1, y - 1, width + 2, height + 2, frame)
        canvas.fill(x, y, width, height, sky)
        if isNight {
            for (index, star) in [(3.0, 2.0), (9, 5), (17, 3), (22, 8), (13, 10), (5, 9)]
                .enumerated()
            {
                let twinkle = sin(time * 2 + Double(index) * 1.3) > -0.3
                if twinkle { canvas.fill(x + star.0, y + star.1, 1, 1, Color(hex: 0xF5F3CE)) }
            }
        } else {
            // Clouds drift slowly and wrap around inside the window.
            for (offset, row, length) in [(0.0, 3.0, 6.0), (13, 8, 8)] {
                let start =
                    (time * 0.8 + offset * 3).truncatingRemainder(dividingBy: width + 10) - 8
                for column in 0..<Int(length) {
                    let cloudX = start + Double(column)
                    if cloudX >= 0, cloudX < width {
                        canvas.fill(x + cloudX.rounded(.down), y + row, 1, 1, .white.opacity(0.9))
                        if column > 1, column < Int(length) - 2 {
                            canvas.fill(
                                x + cloudX.rounded(.down), y + row - 1, 1, 1, .white.opacity(0.8))
                        }
                    }
                }
            }
        }
        canvas.fill(x + width / 2, y, 1, height, frame)
        canvas.fill(x, y + height / 2, width, 1, frame)
        canvas.fill(x - 2, y + height + 1, width + 4, 1, Color(hex: 0x8A6A50))
    }

    private func drawClock(_ canvas: PixelCanvas, centerX: Double, centerY: Double) {
        let radius = 6.0 * canvas.pixel
        let center = canvas.point(centerX, centerY)
        let face = Path(
            ellipseIn: CGRect(
                x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        canvas.context.fill(face, with: .color(Color(hex: 0xE8E4D8)))
        canvas.context.stroke(face, with: .color(Color(hex: 0x14182B)), lineWidth: canvas.pixel)

        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minute = Double(components.minute ?? 0)
        let hour = Double((components.hour ?? 0) % 12) + minute / 60
        for (fraction, length, width) in [(hour / 12, 0.5, 1.2), (minute / 60, 0.8, 0.8)] {
            let angle = fraction * 2 * .pi - .pi / 2
            var hand = Path()
            hand.move(to: center)
            hand.addLine(
                to: CGPoint(
                    x: center.x + cos(angle) * radius * length,
                    y: center.y + sin(angle) * radius * length))
            canvas.context.stroke(
                hand, with: .color(Color(hex: 0x14182B)),
                style: StrokeStyle(lineWidth: canvas.pixel * width, lineCap: .round))
        }
    }

    private enum PosterArt { case mountains, chart }

    private func drawPoster(_ canvas: PixelCanvas, x: Double, art: PosterArt) {
        let y = 5.0
        canvas.fill(x, y, 12, 11, Color(hex: 0xE8E4D8))
        switch art {
        case .mountains:
            canvas.fill(x + 1, y + 1, 10, 9, Color(hex: 0x3E63DD))
            canvas.fill(x + 8, y + 2, 2, 2, Color(hex: 0xFFE08A))
            canvas.sprite(
                ["....g.....", "...ggg..g.", "..ggggggg.", ".gggggggggg"],
                x: x + 1, y: y + 6, palette: ["g": Color(hex: 0x30A46C)])
        case .chart:
            canvas.fill(x + 1, y + 1, 10, 9, Color(hex: 0x1F2433))
            for (index, height) in [3.0, 5, 4, 7].enumerated() {
                canvas.fill(
                    x + 2 + Double(index) * 2.3, y + 9 - height, 1.5, height, Color(hex: 0x4ADE80))
            }
        }
    }

    private func drawFloor(_ canvas: PixelCanvas) {
        let top = Self.wallHeight
        canvas.fill(0, top, Self.columns, Self.rows - top, Color(hex: 0x8B5E3C))
        var band = 0.0
        while top + band * 4 < Self.rows {
            let y = top + band * 4
            let tone = Int(band).isMultiple(of: 2) ? 0x93653F : 0x865A39
            canvas.fill(0, y, Self.columns, 4, Color(hex: UInt32(tone)))
            canvas.fill(0, y, Self.columns, 0.5, Color(hex: 0x6E4A2F, opacity: 0.6))
            let shift = (band * 37).truncatingRemainder(dividingBy: 32)
            for x in stride(from: shift, to: Self.columns, by: 32) {
                canvas.fill(x, y + 0.5, 0.5, 3.5, Color(hex: 0x6E4A2F, opacity: 0.6))
            }
            band += 1
        }
    }

    private func drawDecor(_ canvas: PixelCanvas) {
        // Potted plant, gently swaying.
        let sway = sin(time * 1.2) > 0 ? 0.0 : 0.5
        canvas.sprite(
            ["..l.l...", ".lllll.l", "llllllll", ".llDlll.", "..lDll..", "...D...."],
            x: 1 + sway, y: 60, palette: ["l": Color(hex: 0x3FA34D), "D": Color(hex: 0x2E7D3A)])
        canvas.fill(1, 66, 8, 1, Color(hex: 0xD9804F))
        canvas.fill(2, 67, 6, 5, Color(hex: 0xC46A3F))
        canvas.fill(2, 72, 6, 0.6, .black.opacity(0.25))

        // Water cooler with a bubble now and then.
        canvas.fill(150, 44, 6, 8, Color(hex: 0x7CC4F5, opacity: 0.85))
        canvas.fill(151, 43, 4, 1, Color(hex: 0x5AA8DD))
        canvas.fill(149, 52, 8, 14, Color(hex: 0xD9DEE8))
        canvas.fill(150, 55, 2, 1, Color(hex: 0x4A90E2))
        canvas.fill(154, 55, 2, 1, Color(hex: 0xE5484D))
        canvas.fill(149, 66, 8, 0.6, .black.opacity(0.25))
        let bubble = (time * 0.7).truncatingRemainder(dividingBy: 4)
        if bubble < 1.6 {
            canvas.fill(152, 50 - bubble * 4, 1, 1, .white.opacity(0.7))
        }
    }

    // MARK: Agents

    private func drawWorkstation(
        _ canvas: PixelCanvas, x: Double, top: Double, session: AgentSession
    ) {
        let look = AgentLook(seed: session.appearanceSeed)
        let activity = session.activity
        let seed = Double(session.appearanceSeed % 1000)
        let beat = Int(time * 4 + seed).isMultiple(of: 2)

        // Chair back peeks out behind the agent.
        canvas.fill(x + 15, top - 6, 11, 6, Color(hex: 0x3A3F55))

        let characterX = x + 16
        let bob = activity.isWorking && beat ? 1.0 : 0.0
        let slouch = activity == .idle ? 1.0 : 0.0
        let headTop = top - 9 + bob + slouch
        let head = activity == .idle ? AgentLook.sleepingHead : AgentLook.head
        canvas.sprite(head, x: characterX, y: headTop, palette: look.palette())
        canvas.sprite(AgentLook.body, x: characterX, y: top - 3, palette: look.palette())

        drawMonitor(canvas, x: x + 2, top: top - 8, activity: activity, seed: seed)
        drawDesk(canvas, x: x, top: top)

        if activity.isWorking {
            let left = beat ? 1.0 : 0.0
            canvas.fill(characterX + 1, top - left, 1, 1, look.skin)
            canvas.fill(characterX + 7, top - (1 - left), 1, 1, look.skin)
        }
        if session.appearanceSeed.isMultiple(of: 3) {
            canvas.fill(x + 24, top - 2, 2, 2, Color(hex: 0xF4F1EA))
            canvas.fill(x + 26, top - 1.5, 0.6, 1, Color(hex: 0xF4F1EA))
        }

        drawBubble(canvas, x: characterX + 6, headTop: headTop, activity: activity, seed: seed)
        label(
            canvas, String(session.projectName.prefix(14)), x: x + Self.deskWidth / 2, y: top + 12)
    }

    private func drawDesk(_ canvas: PixelCanvas, x: Double, top: Double) {
        let width = Self.deskWidth
        canvas.fill(x, top, width, 1, Color(hex: 0xD29A63))
        canvas.fill(x, top + 1, width, 2, Color(hex: 0xB07A4A))
        canvas.fill(x + 1, top + 3, width - 2, 5, Color(hex: 0x7A4E30))
        canvas.fill(x + 19, top + 5, 4, 1, Color(hex: 0xC9A06A))
        canvas.fill(x + 1, top + 8, 2, 2, Color(hex: 0x5C3A22))
        canvas.fill(x + width - 3, top + 8, 2, 2, Color(hex: 0x5C3A22))
        canvas.fill(x, top + 10, width, 0.7, .black.opacity(0.25))
    }

    private func drawMonitor(
        _ canvas: PixelCanvas, x: Double, top: Double, activity: AgentActivity, seed: Double
    ) {
        canvas.fill(x, top, 12, 7, Color(hex: 0x20222B))
        canvas.fill(x + 5, top + 7, 2, 1, Color(hex: 0x20222B))
        let screenX = x + 1
        let screenY = top + 1
        let step = Int(time * 6)

        switch activity {
        case .usingTool:
            canvas.fill(screenX, screenY, 10, 5, Color(hex: 0x0B1F14))
            for row in 0..<5 {
                let hash = (step + row * 7 + Int(seed)) &* 2_654_435_761
                let length = Double(2 + abs(hash >> 7) % 7)
                let indent = Double(abs(hash >> 3) % 3)
                canvas.fill(
                    screenX + indent, screenY + Double(row), min(length, 10 - indent), 0.6,
                    Color(hex: 0x4ADE80, opacity: row == 4 ? 1 : 0.7))
            }
        case .thinking:
            canvas.fill(screenX, screenY, 10, 5, Color(hex: 0x0E1630))
            for dot in 0..<3 {
                let lit = (step / 2) % 3 == dot
                canvas.fill(
                    screenX + 2 + Double(dot) * 2.5, screenY + 2, 1, 1,
                    Color(hex: 0x60A5FA, opacity: lit ? 1 : 0.35))
            }
        case .waitingForUser:
            let flash = Int(time * 2).isMultiple(of: 2)
            canvas.fill(screenX, screenY, 10, 5, Color(hex: flash ? 0xF59E0B : 0x3A2405))
            canvas.fill(screenX + 4.5, screenY + 1, 1, 2, Color(hex: flash ? 0x3A2405 : 0xF59E0B))
            canvas.fill(
                screenX + 4.5, screenY + 3.5, 1, 0.8, Color(hex: flash ? 0x3A2405 : 0xF59E0B))
        case .idle, .finished:
            canvas.fill(screenX, screenY, 10, 5, Color(hex: 0x0A0A12))
            let drift = (time * 0.6 + seed).truncatingRemainder(dividingBy: 16)
            let dotX = drift < 8 ? drift : 16 - drift
            canvas.fill(screenX + 1 + dotX, screenY + 2, 1, 1, Color(hex: 0x8E4EC6, opacity: 0.8))
        }
        // Screen glow on the desk.
        canvas.fill(x, top + 8, 12, 0.6, glow(for: activity).opacity(0.35))
    }

    private func glow(for activity: AgentActivity) -> Color {
        switch activity {
        case .usingTool: Color(hex: 0x4ADE80)
        case .thinking: Color(hex: 0x60A5FA)
        case .waitingForUser: Color(hex: 0xF59E0B)
        case .idle, .finished: .clear
        }
    }

    private func drawBubble(
        _ canvas: PixelCanvas, x: Double, headTop: Double, activity: AgentActivity, seed: Double
    ) {
        switch activity {
        case .waitingForUser:
            let bounce = sin(time * 5) > 0 ? 0.0 : 1.0
            let top = headTop - 8 + bounce
            canvas.fill(x, top, 5, 6, .white)
            canvas.fill(x + 1, top + 6, 1, 1, .white)
            canvas.fill(x + 2, top + 1, 1, 2.5, Color(hex: 0xF59E0B))
            canvas.fill(x + 2, top + 4, 1, 1, Color(hex: 0xF59E0B))
        case .thinking:
            let top = headTop - 6
            canvas.fill(x, top, 7, 4, .white.opacity(0.95))
            canvas.fill(x, top + 4, 1, 1, .white.opacity(0.95))
            let active = Int(time * 3 + seed) % 3
            for dot in 0..<3 {
                canvas.fill(
                    x + 1 + Double(dot) * 2, top + 1.5, 1, 1,
                    Color(hex: 0x3A3F55, opacity: dot == active ? 1 : 0.35))
            }
        case .idle:
            let rise = (time * 0.8 + seed).truncatingRemainder(dividingBy: 3)
            let opacity = 1 - rise / 3
            canvas.sprite(
                ["zzz", "..z", ".z.", "zzz"], x: x + 1, y: headTop - 3 - rise * 2,
                palette: ["z": .white.opacity(opacity * 0.8)])
        case .usingTool, .finished:
            break
        }
    }

    private func label(
        _ canvas: PixelCanvas, _ text: String, x: Double, y: Double, size: Double = 2.4,
        opacity: Double = 0.85
    ) {
        canvas.context.draw(
            Text(text)
                .font(.system(size: size * canvas.pixel, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(opacity)),
            at: canvas.point(x, y))
    }
}
