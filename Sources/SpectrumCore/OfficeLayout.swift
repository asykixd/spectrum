import CoreGraphics

/// Where everyone sits in the pixel office, in grid units (160 × 78), shared by drawing and
/// pointer hit-testing.
public struct OfficeLayout: Sendable {
    public enum Zone: Sendable {
        case desk
        case meeting
        case sofa
    }

    public struct Placement: Sendable {
        public let session: AgentSession
        public let zone: Zone
        /// Top-left of the slot: desk or meeting table origin, or sofa seat.
        public let origin: CGPoint
        /// Area that reacts to the pointer.
        public let hitArea: CGRect
    }

    public static let columns = 160.0
    public static let rows = 78.0
    public static let deskColumns = [4.0, 36.0, 68.0]
    public static let deskRows = [40.0, 63.0]
    public static let deskWidth = 28.0
    public static let meetingSlots = [106.0, 132.0]
    public static let meetingTop = 40.0
    public static let meetingWidth = 24.0
    public static let loungeY = 54.0
    public static let sofaSeats = [109.0, 121.0, 133.0]

    public static var deskSlots: [CGPoint] {
        deskRows.flatMap { top in deskColumns.map { CGPoint(x: $0, y: top) } }
    }

    public let placements: [Placement]
    public let hiddenCode: Int
    public let hiddenChats: Int
    public let hiddenAFK: Int

    public init(sessions: [AgentSession]) {
        let groups = SessionGroups(sessions)
        var placements: [Placement] = []

        for (session, slot) in zip(groups.code, Self.deskSlots) {
            placements.append(
                Placement(
                    session: session, zone: .desk, origin: slot,
                    hitArea: CGRect(x: slot.x, y: slot.y - 10, width: Self.deskWidth, height: 21)))
        }
        for (session, x) in zip(groups.chats, Self.meetingSlots) {
            let origin = CGPoint(x: x, y: Self.meetingTop)
            placements.append(
                Placement(
                    session: session, zone: .meeting, origin: origin,
                    hitArea: CGRect(
                        x: x, y: Self.meetingTop - 10, width: Self.meetingWidth, height: 21)))
        }
        for (session, x) in zip(groups.afk, Self.sofaSeats) {
            let origin = CGPoint(x: x, y: Self.loungeY)
            placements.append(
                Placement(
                    session: session, zone: .sofa, origin: origin,
                    hitArea: CGRect(x: x - 1, y: Self.loungeY + 2, width: 11, height: 21)))
        }

        self.placements = placements
        hiddenCode = max(groups.code.count - Self.deskSlots.count, 0)
        hiddenChats = max(groups.chats.count - Self.meetingSlots.count, 0)
        hiddenAFK = max(groups.afk.count - Self.sofaSeats.count, 0)
    }

    public func placement(at point: CGPoint) -> Placement? {
        placements.first { $0.hitArea.contains(point) }
    }

    /// Pixel size and origin that fit the grid centered in `size`, as the canvas draws it.
    public static func fit(in size: CGSize) -> (pixel: CGFloat, origin: CGPoint) {
        let pixel = min(size.width / columns, size.height / rows)
        let origin = CGPoint(
            x: (size.width - columns * pixel) / 2, y: (size.height - rows * pixel) / 2)
        return (pixel, origin)
    }

    /// Converts a point in the canvas to grid units.
    public static func gridPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let (pixel, origin) = fit(in: size)
        return CGPoint(x: (point.x - origin.x) / pixel, y: (point.y - origin.y) / pixel)
    }
}
