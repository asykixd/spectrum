import SpectrumCore
import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity)
    }
}

/// Draws on a coarse grid so shapes stay crisp at any panel size.
struct PixelCanvas {
    var context: GraphicsContext
    let pixel: CGFloat
    let origin: CGPoint

    func fill(_ x: Double, _ y: Double, _ width: Double, _ height: Double, _ color: Color) {
        // Edges snapped to the Retina half-point grid, so neighbouring pixels share an edge
        // exactly and anti-aliasing doesn't draw seams between them.
        func snap(_ value: CGFloat) -> CGFloat { (value * 2).rounded() / 2 }
        let minX = snap(origin.x + x * pixel)
        let minY = snap(origin.y + y * pixel)
        let rect = CGRect(
            x: minX, y: minY, width: snap(origin.x + (x + width) * pixel) - minX,
            height: snap(origin.y + (y + height) * pixel) - minY)
        context.fill(Path(rect), with: .color(color))
    }

    func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: origin.x + x * pixel, y: origin.y + y * pixel)
    }

    /// Draws `rows` of characters, looking each one up in `palette`; unknown ones are clear.
    func sprite(_ rows: [String], x: Double, y: Double, palette: [Character: Color]) {
        for (row, line) in rows.enumerated() {
            for (column, character) in line.enumerated() {
                if let color = palette[character] {
                    fill(x + Double(column), y + Double(row), 1, 1, color)
                }
            }
        }
    }
}

/// Per-agent look, derived from the session id so it survives restarts.
struct AgentLook {
    let shirt: Color
    let hair: Color
    let skin: Color

    private static let shirts: [UInt32] = [
        0xE5484D, 0x3E63DD, 0x30A46C, 0xF76B15, 0x8E4EC6, 0x12A594, 0xD6409F, 0xFFC53D,
    ]
    private static let hairs: [UInt32] = [0x2B1B12, 0x5A3A1E, 0xC9A063, 0x1A1A1A, 0x8B3A1E]
    private static let skins: [UInt32] = [0xF1C7A1, 0xD9A47A, 0xA86F4C, 0x7A4B2E]

    init(seed: UInt64) {
        shirt = Color(hex: Self.shirts[Int(seed % UInt64(Self.shirts.count))])
        hair = Color(hex: Self.hairs[Int((seed >> 8) % UInt64(Self.hairs.count))])
        skin = Color(hex: Self.skins[Int((seed >> 16) % UInt64(Self.skins.count))])
    }

    static let head = [
        "..hhhhh..",
        ".hhhhhhh.",
        ".hsssssh.",
        ".sessses.",
        ".sssssss.",
        "..sssss..",
    ]
    static let sleepingHead = [
        "..hhhhh..",
        ".hhhhhhh.",
        ".hsssssh.",
        ".sccsccs.",
        ".sssssss.",
        "..sssss..",
    ]
    static let body = [
        ".ttttttt.",
        "ttttttttt",
        "ttttttttt",
    ]

    func palette() -> [Character: Color] {
        [
            "h": hair, "s": skin, "e": Color(hex: 0x1B1B24), "t": shirt,
            "c": Color(hex: 0x6B4A3A),
        ]
    }
}

/// Claude as an office character: a terracotta head with a starburst crown.
enum ClaudeLook {
    static let orange = Color(hex: 0xD97757)
    static let ink = Color(hex: 0x3D3929)

    static let head = [
        "..o.o.o..",
        ".ooooooo.",
        "ooooooooo",
        "ooeoooeoo",
        "ooooooooo",
        ".ooooooo.",
    ]

    static let palette: [Character: Color] = [
        "o": orange, "e": ink, "t": Color(hex: 0xF0E6D8),
    ]
}

/// Clawd, the Claude Code mascot: a terracotta block with two eyes and stubby arms.
enum ClawdLook {
    static let body = Color(hex: 0xD97757)

    static let awake: [String] = [
        ".ooooooo.",
        ".okoooko.",
        ".okoooko.",
        "ooooooooo",
        ".ooooooo.",
    ]
    /// Arms up: alternated with `awake` while the agent types.
    static let typing: [String] = [
        ".ooooooo.",
        ".okoooko.",
        "ookoookoo",
        ".ooooooo.",
        ".ooooooo.",
    ]
    static let sleeping: [String] = [
        ".ooooooo.",
        ".ooooooo.",
        ".ocoooco.",
        "ooooooooo",
        ".ooooooo.",
    ]

    /// Small accessories so several Clawds in one office can be told apart.
    static let accessories: [[String]] = [
        [],
        ["..ttttt.."],
        [".kkkkkkk."],
        ["...t.t...", "....t...."],
        ["....g....", "...g.g..."],
    ]

    static func palette(accent: Color) -> [Character: Color] {
        [
            "o": body, "k": Color(hex: 0x1B1B24), "c": Color(hex: 0x8A3F28), "t": accent,
            "g": Color(hex: 0x3FA34D),
        ]
    }

    /// Headphone cups sit beside the head rather than above it.
    static func hasEarCups(_ accessory: Int) -> Bool { accessory == 2 }
}

/// The agent's face, used as an avatar in the sessions list.
struct AgentAvatar: View {
    let session: AgentSession
    var style: SpectrumSettings.CharacterStyle = .clawd

    var body: some View {
        Canvas { context, size in
            let pixel = size.width / 11
            let canvas = PixelCanvas(
                context: context, pixel: pixel, origin: CGPoint(x: pixel, y: pixel * 1.5))
            switch (style, session.kind) {
            case (.clawd, _):
                let accent = AgentLook(seed: session.appearanceSeed).shirt
                let accessory = session.kind == .chat ? 0 : ClawdLook.accessoryIndex(session)
                canvas.sprite(
                    session.activity == .idle ? ClawdLook.sleeping : ClawdLook.awake, x: 0, y: 2,
                    palette: ClawdLook.palette(accent: accent))
                canvas.sprite(
                    ClawdLook.accessories[accessory], x: 0,
                    y: 2 - Double(ClawdLook.accessories[accessory].count),
                    palette: ClawdLook.palette(accent: accent))
            case (.people, .chat):
                canvas.sprite(ClaudeLook.head, x: 0, y: 0, palette: ClaudeLook.palette)
                canvas.sprite(
                    Array(AgentLook.body.prefix(2)), x: 0, y: 6, palette: ClaudeLook.palette)
            case (.people, .code):
                let palette = AgentLook(seed: session.appearanceSeed).palette()
                let head = session.activity == .idle ? AgentLook.sleepingHead : AgentLook.head
                canvas.sprite(head, x: 0, y: 0, palette: palette)
                canvas.sprite(Array(AgentLook.body.prefix(2)), x: 0, y: 6, palette: palette)
            }
        }
        .frame(width: 30, height: 30)
        .background(Circle().fill(.white.opacity(0.08)))
        .clipShape(Circle())
    }
}

extension ClawdLook {
    static func accessoryIndex(_ session: AgentSession) -> Int {
        Int((session.appearanceSeed >> 24) % UInt64(accessories.count))
    }
}
