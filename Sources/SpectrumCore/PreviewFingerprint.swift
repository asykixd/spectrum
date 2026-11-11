import Foundation

/// A small color thumbnail lets snapshot checks tolerate system font and renderer differences.
public struct PreviewFingerprint: Codable, Sendable {
    public let width: Int
    public let height: Int
    public let pixels: Data

    public init(width: Int, height: Int, pixels: Data) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public func difference(from reference: Self) -> Double? {
        guard width == reference.width, height == reference.height,
            pixels.count == reference.pixels.count, !pixels.isEmpty
        else { return nil }
        let error = zip(pixels, reference.pixels).reduce(0) { sum, pair in
            sum + abs(Int(pair.0) - Int(pair.1))
        }
        return Double(error) / (Double(pixels.count) * 255)
    }
}
