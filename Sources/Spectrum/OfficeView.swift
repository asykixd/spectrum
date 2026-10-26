import SpectrumCore
import SwiftUI

/// Pixel-art office in three zones: desks for Claude Code agents at work, a meeting room for
/// Claude app chats, and a lounge where idle agents doze off. Agents react to the pointer:
/// hovering highlights one, clicking opens its conversation.
struct OfficeView: View {
    let model: NotchModel

    var body: some View {
        let layout = OfficeLayout(sessions: model.sessions)
        TimelineView(.animation(minimumInterval: 1.0 / 12)) { timeline in
            Canvas { context, size in
                OfficeScene(
                    layout: layout, date: timeline.date, hoveredID: model.officeHoverID,
                    style: model.settings.characters
                ).draw(in: context, size: size)
            }
        }
        .overlay {
            GeometryReader { proxy in
                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        hover(phase, layout: layout, size: proxy.size)
                    }
                    .onTapGesture { location in
                        let point = OfficeLayout.gridPoint(location, in: proxy.size)
                        if let session = layout.placement(at: point)?.session {
                            model.open(session, fromOffice: true)
                        }
                    }
            }
        }
    }

    private func hover(_ phase: HoverPhase, layout: OfficeLayout, size: CGSize) {
        var id: String?
        if case .active(let location) = phase {
            id = layout.placement(at: OfficeLayout.gridPoint(location, in: size))?.session.id
        }
        guard id != model.officeHoverID else { return }
        model.officeHoverID = id
        if id == nil { NSCursor.arrow.set() } else { NSCursor.pointingHand.set() }
    }
}

struct OfficeScene {
    static let columns = OfficeLayout.columns
    static let rows = OfficeLayout.rows
    static let wallHeight = 24.0
    static let deskWidth = OfficeLayout.deskWidth
    /// Glass wall between the open space and the meeting room / lounge.
    static let partitionX = 101.0
    static let meetingWidth = OfficeLayout.meetingWidth
    static let loungeY = OfficeLayout.loungeY

    let layout: OfficeLayout
    let date: Date
    var hoveredID: String?
    var style: SpectrumSettings.CharacterStyle = .clawd

    private var time: Double { date.timeIntervalSinceReferenceDate }

    func draw(in context: GraphicsContext, size: CGSize) {
        let (pixel, origin) = OfficeLayout.fit(in: size)
        let canvas = PixelCanvas(context: context, pixel: pixel, origin: origin)

        drawWall(canvas)
        drawFloor(canvas)
        drawZones(canvas)

        let taken = layout.placements.filter { $0.zone == .desk }.map(\.origin)
        for slot in OfficeLayout.deskSlots where !taken.contains(slot) {
            drawEmptyDesk(canvas, x: slot.x, top: slot.y)
        }
        let busyTables = Set(layout.placements.filter { $0.zone == .meeting }.map(\.origin.x))
        for x in OfficeLayout.meetingSlots where !busyTables.contains(x) {
            drawMeetingTable(canvas, x: x, top: OfficeLayout.meetingTop)
        }
        drawSofaBack(canvas)

        if let hovered = layout.placements.first(where: { $0.session.id == hoveredID }) {
            drawHighlight(canvas, hovered.hitArea)
        }
        for placement in layout.placements {
            let origin = placement.origin
            switch placement.zone {
            case .desk:
                drawWorkstation(canvas, x: origin.x, top: origin.y, session: placement.session)
            case .meeting:
                drawMeeting(canvas, x: origin.x, top: origin.y, session: placement.session)
            case .sofa:
                drawLounger(canvas, x: origin.x, session: placement.session)
            }
        }
        drawSofaFront(canvas)
        for placement in layout.placements where placement.zone == .sofa {
            // Slow, sleepy swinging over the edge of the cushion.
            let swing = Int(time * 1.5 + Double(placement.session.appearanceSeed % 5))
                .isMultiple(of: 2)
            drawLegs(canvas, x: placement.origin.x, y: Self.loungeY + 14, swing: swing)
        }

        if layout.hiddenCode > 0 {
            label(canvas, "+\(layout.hiddenCode) at work", x: 50, y: 76, size: 2.2)
        }
        if layout.hiddenChats > 0 {
            label(canvas, "+\(layout.hiddenChats) chats", x: 150, y: 27, size: 2)
        }
        if layout.hiddenAFK > 0 {
            label(canvas, "+\(layout.hiddenAFK) AFK", x: 150, y: Self.loungeY + 1, size: 2)
        }
        if layout.placements.isEmpty {
            label(canvas, "No agents at work", x: 50, y: 34, size: 3, opacity: 0.75)
        }
    }

    /// A soft spotlight under the agent the pointer is on.
    private func drawHighlight(_ canvas: PixelCanvas, _ area: CGRect) {
        let rect = CGRect(
            x: canvas.origin.x + area.minX * canvas.pixel,
            y: canvas.origin.y + area.minY * canvas.pixel,
            width: area.width * canvas.pixel, height: area.height * canvas.pixel)
        let shape = RoundedRectangle(cornerRadius: canvas.pixel * 2).path(in: rect)
        canvas.context.fill(shape, with: .color(.white.opacity(0.1)))
        canvas.context.stroke(
            shape, with: .color(.white.opacity(0.55)), lineWidth: canvas.pixel * 0.5)
    }

    private func drawSofaBack(_ canvas: PixelCanvas) {
        let y = Self.loungeY
        canvas.fill(106, y + 4, 40, 7, Color(hex: 0x4E3F7A))
        canvas.fill(106, y + 4, 40, 1, Color(hex: 0x6650A0))
    }

    private func drawLounger(_ canvas: PixelCanvas, x: Double, session: AgentSession) {
        let y = Self.loungeY
        // Heads loll at different moments so the lounge doesn't move in lockstep.
        let nod = sin(time * 0.8 + Double(session.appearanceSeed % 7)) > 0.6 ? 1.0 : 0.0
        let headTop = drawCharacter(
            canvas, session: session, x: x, bottom: y + 12, sleeping: true, lift: nod)
        drawBubble(
            canvas, x: x + 6, headTop: headTop, activity: .idle,
            seed: Double(session.appearanceSeed % 1000))
        label(canvas, String(session.projectName.prefix(8)), x: x + 4.5, y: y + 21, size: 1.9)
    }

    /// Draws an agent whose lowest visible row ends at `bottom` and returns the top of its
    /// head, where bubbles attach.
    @discardableResult
    private func drawCharacter(
        _ canvas: PixelCanvas, session: AgentSession, x: Double, bottom: Double,
        sleeping: Bool, lift: Double, typing: Bool = false
    ) -> Double {
        let look = AgentLook(seed: session.appearanceSeed)
        switch (style, session.kind) {
        case (.clawd, _):
            let palette = ClawdLook.palette(accent: look.shirt)
            let frame = sleeping ? ClawdLook.sleeping : typing ? ClawdLook.typing : ClawdLook.awake
            let top = bottom - Double(frame.count) + lift
            canvas.sprite(frame, x: x, y: top, palette: palette)
            // Chats in the lounge are Claude itself, so no accessory.
            let accessory = session.kind == .chat ? 0 : ClawdLook.accessoryIndex(session)
            let rows = ClawdLook.accessories[accessory]
            canvas.sprite(rows, x: x, y: top - Double(rows.count), palette: palette)
            if ClawdLook.hasEarCups(accessory) {
                canvas.fill(x - 0.5, top + 1, 1, 2, look.shirt)
                canvas.fill(x + 8.5, top + 1, 1, 2, look.shirt)
            }
            return top - Double(rows.count)
        case (.people, .chat):
            let top = bottom - 9 + lift
            canvas.sprite(ClaudeLook.head, x: x, y: top, palette: ClaudeLook.palette)
            canvas.sprite(AgentLook.body, x: x, y: bottom - 3, palette: ClaudeLook.palette)
            return top
        case (.people, .code):
            let top = bottom - 9 + lift
            let head = sleeping ? AgentLook.sleepingHead : AgentLook.head
            canvas.sprite(head, x: x, y: top, palette: look.palette())
            canvas.sprite(AgentLook.body, x: x, y: bottom - 3, palette: look.palette())
            return top
        }
    }

    /// Clawd's legs, drawn after whatever they hang in front of. People keep theirs hidden.
    private func drawLegs(_ canvas: PixelCanvas, x: Double, y: Double, swing: Bool) {
        guard style == .clawd else { return }
        canvas.sprite(
            swing ? ClawdLook.legsSwinging : ClawdLook.legs, x: x, y: y,
            palette: ClawdLook.palette(accent: .clear))
    }

    /// Seat cushions drawn over the loungers' laps, then the arms and the plant.
    private func drawSofaFront(_ canvas: PixelCanvas) {
        let y = Self.loungeY
        canvas.fill(105, y + 11, 42, 4, Color(hex: 0x6E5BA6))
        canvas.fill(105, y + 11, 42, 1, Color(hex: 0x8470C0))
        canvas.fill(103, y + 7, 3, 8, Color(hex: 0x5A4890))
        canvas.fill(146, y + 7, 3, 8, Color(hex: 0x5A4890))
        canvas.fill(106, y + 15, 2, 2, Color(hex: 0x2E2440))
        canvas.fill(144, y + 15, 2, 2, Color(hex: 0x2E2440))
        canvas.fill(104, y + 17, 46, 0.7, .black.opacity(0.25))

        let sway = sin(time * 1.2) > 0 ? 0.0 : 0.5
        canvas.sprite(
            ["..l.l...", ".lllll.l", "llllllll", ".llDlll.", "..lDll..", "...D...."],
            x: 151 + sway, y: y + 4,
            palette: ["l": Color(hex: 0x3FA34D), "D": Color(hex: 0x2E7D3A)])
        canvas.fill(151, y + 10, 8, 1, Color(hex: 0xD9804F))
        canvas.fill(152, y + 11, 6, 5, Color(hex: 0xC46A3F))
        canvas.fill(152, y + 16, 6, 0.6, .black.opacity(0.25))
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

    private func drawZones(_ canvas: PixelCanvas) {
        let top = Self.wallHeight
        let x = Self.partitionX
        // Carpet in the meeting room, a rug in the lounge.
        canvas.fill(x + 2, top, Self.columns - x - 2, 28, Color(hex: 0x3E4A6E))
        for row in stride(from: top, to: top + 28, by: 2) {
            canvas.fill(x + 2, row, Self.columns - x - 2, 0.5, Color(hex: 0x46537A))
        }
        canvas.fill(x + 4, Self.loungeY + 16, 54, 7, Color(hex: 0x8C4B5E))
        canvas.fill(x + 5, Self.loungeY + 17, 52, 5, Color(hex: 0xA65B70))

        // Glass partition with a door gap at the bottom.
        canvas.fill(x, top, 2, 44, Color(hex: 0xBFE3F5, opacity: 0.35))
        canvas.fill(x, top, 0.6, 44, Color(hex: 0xDDEFF8, opacity: 0.6))
        canvas.fill(x, top + 27, 2, 1, Color(hex: 0x8A9BB0))
        canvas.fill(x + 2, top + 28, Self.columns - x - 2, 1, Color(hex: 0xBFE3F5, opacity: 0.35))

        // Door sign for the meeting room, under the window.
        canvas.fill(x + 26, top - 4, 22, 3, Color(hex: 0xE8E4D8))
        label(canvas, "MEETING", x: x + 37, y: top - 2.5, size: 1.8, opacity: 1, color: .black)
    }

    private func drawEmptyDesk(_ canvas: PixelCanvas, x: Double, top: Double) {
        canvas.fill(x + 15, top - 6, 11, 6, Color(hex: 0x3A3F55, opacity: 0.7))
        canvas.fill(x + 2, top - 8, 12, 7, Color(hex: 0x20222B))
        canvas.fill(x + 3, top - 7, 10, 5, Color(hex: 0x0A0A12))
        canvas.fill(x + 7, top - 1, 2, 1, Color(hex: 0x20222B))
        drawDesk(canvas, x: x, top: top)
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
        let headTop = drawCharacter(
            canvas, session: session, x: characterX, bottom: top,
            sleeping: activity == .idle, lift: bob + slouch, typing: activity.isWorking && beat)

        drawMonitor(canvas, x: x + 2, top: top - 8, activity: activity, seed: seed)
        drawDesk(canvas, x: x, top: top)
        // Legs dangle in the gap under the desk, kicking while the agent works.
        drawLegs(canvas, x: characterX, y: top + 8, swing: activity.isWorking && beat)

        if activity.isWorking, style == .people {
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
        case .usingTool, .responding:
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
        case .responding: ClaudeLook.orange
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
                ["zzz", "..z", ".z.", "zzz"], x: x + 1, y: headTop - 4 - rise,
                palette: ["z": .white.opacity(opacity * 0.8)])
        case .usingTool, .responding, .finished:
            break
        }
    }

    /// A Claude chat: the user and Claude talking across a small round table.
    private func drawMeeting(_ canvas: PixelCanvas, x: Double, top: Double, session: AgentSession) {
        let user = AgentLook(seed: 0)
        let activity = session.activity
        let talking = activity == .responding
        let beat = Int(time * 5).isMultiple(of: 2)
        let headTop = top - 9

        // You are always a person at the table; Claude matches the office's character style.
        canvas.fill(x, top - 6, 10, 6, Color(hex: 0x3A3F55))
        canvas.fill(x + 14, top - 6, 10, 6, Color(hex: 0x3A3F55))
        canvas.sprite(AgentLook.head, x: x, y: headTop, palette: user.palette())
        canvas.sprite(AgentLook.body, x: x, y: top - 3, palette: user.palette())
        let claudeBob = talking && beat ? 1.0 : 0.0
        switch style {
        case .clawd:
            canvas.sprite(
                talking && beat ? ClawdLook.typing : ClawdLook.awake, x: x + 15,
                y: top - 5 + claudeBob, palette: ClawdLook.palette(accent: .clear))
        case .people:
            canvas.sprite(
                ClaudeLook.head, x: x + 15, y: headTop + claudeBob, palette: ClaudeLook.palette)
            canvas.sprite(AgentLook.body, x: x + 15, y: top - 3, palette: ClaudeLook.palette)
        }
        drawMeetingTable(canvas, x: x, top: top)
        drawLegs(canvas, x: x + 15, y: top, swing: talking && beat)
        canvas.fill(x + 8, top - 2, 2, 2, Color(hex: 0xF4F1EA))
        canvas.fill(x + 14, top - 2, 2, 2, ClaudeLook.orange)

        switch activity {
        case .responding:
            drawSpeech(canvas, x: x + 7, top: headTop - 8, tailX: x + 16)
        case .thinking:
            drawBubble(canvas, x: x + 17, headTop: headTop, activity: .thinking, seed: 0)
        case .waitingForUser:
            drawTyping(canvas, x: x + 1, top: headTop - 6)
        case .idle, .usingTool, .finished:
            break
        }
        label(
            canvas, String(session.projectName.prefix(12)), x: x + Self.meetingWidth / 2,
            y: top + 12)
    }

    private func drawMeetingTable(_ canvas: PixelCanvas, x: Double, top: Double) {
        canvas.fill(x + 8, top, 8, 1, Color(hex: 0xD29A63))
        canvas.fill(x + 7, top + 1, 10, 2, Color(hex: 0xB07A4A))
        canvas.fill(x + 11, top + 3, 2, 6, Color(hex: 0x5C3A22))
        canvas.fill(x + 9, top + 9, 6, 1, Color(hex: 0x5C3A22))
        canvas.fill(x + 7, top + 10, 10, 0.7, .black.opacity(0.25))
    }

    /// Claude's speech bubble with lines of text appearing as it answers.
    private func drawSpeech(_ canvas: PixelCanvas, x: Double, top: Double, tailX: Double) {
        canvas.fill(x, top, 12, 6, .white)
        canvas.fill(tailX, top + 6, 1, 1, .white)
        let progress = (time * 1.5).truncatingRemainder(dividingBy: 3)
        for row in 0..<3 {
            let filled = min(max(progress - Double(row), 0), 1)
            if filled > 0 {
                canvas.fill(x + 1, top + 1 + Double(row) * 1.5, 10 * filled, 0.8, ClaudeLook.ink)
            }
        }
    }

    /// The user's turn: a typing indicator above their head.
    private func drawTyping(_ canvas: PixelCanvas, x: Double, top: Double) {
        let bounce = sin(time * 3) > 0 ? 0.0 : 0.5
        canvas.fill(x, top + bounce, 8, 4, .white)
        canvas.fill(x + 6, top + 4 + bounce, 1, 1, .white)
        let active = Int(time * 3) % 3
        for dot in 0..<3 {
            canvas.fill(
                x + 1.5 + Double(dot) * 2, top + 1.5 + bounce, 1, 1,
                Color(hex: 0xF59E0B, opacity: dot == active ? 1 : 0.35))
        }
    }

    private func label(
        _ canvas: PixelCanvas, _ text: String, x: Double, y: Double, size: Double = 2.4,
        opacity: Double = 0.85, color: Color = .white
    ) {
        canvas.context.draw(
            Text(text)
                .font(.system(size: size * canvas.pixel, weight: .medium, design: .monospaced))
                .foregroundStyle(color.opacity(opacity)),
            at: canvas.point(x, y))
    }
}
