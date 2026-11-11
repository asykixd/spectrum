import CoreGraphics
import Testing

@testable import SpectrumCore

@Test func pointerPollingSlowsAwayFromTheIslandAndUsesHysteresis() {
    let island = CGRect(x: 600, y: 940, width: 250, height: 30)
    let near = CGPoint(x: 640, y: 900)
    let boundary = CGPoint(x: 640, y: 840)
    let far = CGPoint(x: 640, y: 800)

    #expect(PointerPollRate.resolve(pointer: near, island: island, previous: .far) == .near)
    #expect(PointerPollRate.resolve(pointer: boundary, island: island, previous: .near) == .near)
    #expect(PointerPollRate.resolve(pointer: boundary, island: island, previous: .far) == .far)
    #expect(PointerPollRate.resolve(pointer: far, island: island, previous: .near) == .far)
    #expect(PointerPollRate.far.interval == 4 * PointerPollRate.near.interval)
}
