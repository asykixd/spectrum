import Foundation
import Testing

@testable import SpectrumCore

@Test func previewFingerprintsCheckGeometryAndColorChanges() {
    let original = PreviewFingerprint(width: 20, height: 10, pixels: Data([0, 0, 255, 255]))
    let changed = PreviewFingerprint(width: 20, height: 10, pixels: Data([0, 255, 0, 255]))
    let resized = PreviewFingerprint(width: 21, height: 10, pixels: original.pixels)
    #expect(original.difference(from: original) == 0)
    #expect(changed.difference(from: original) == 0.5)
    #expect(resized.difference(from: original) == nil)
}
