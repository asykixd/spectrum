import CoreGraphics

/// Placement of the panel around the hardware notch, in screen coordinates (origin bottom-left).
public struct NotchGeometry: Equatable, Sendable {
    /// Width of each visible "ear" to the left and right of the notch.
    public static let earWidth: CGFloat = 80
    /// Fallback for screens without a notch, roughly the size of a MacBook notch.
    static let fallbackNotchSize = CGSize(width: 185, height: 32)

    public let notch: CGRect
    public let panel: CGRect

    /// - Parameters:
    ///   - screenFrame: `NSScreen.frame`.
    ///   - topLeftArea: `NSScreen.auxiliaryTopLeftArea`, nil on screens without a notch.
    ///   - topRightArea: `NSScreen.auxiliaryTopRightArea`, nil on screens without a notch.
    public init(screenFrame: CGRect, topLeftArea: CGRect?, topRightArea: CGRect?) {
        let notch: CGRect
        if let left = topLeftArea, let right = topRightArea, right.minX > left.maxX {
            let height = max(left.height, right.height)
            notch = CGRect(
                x: left.maxX, y: screenFrame.maxY - height,
                width: right.minX - left.maxX, height: height)
        } else {
            let size = Self.fallbackNotchSize
            notch = CGRect(
                x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - size.height,
                width: size.width, height: size.height)
        }
        self.notch = notch
        panel = notch.insetBy(dx: -Self.earWidth, dy: 0)
    }
}
