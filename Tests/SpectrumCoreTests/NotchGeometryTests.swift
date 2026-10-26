import CoreGraphics
import Testing

@testable import SpectrumCore

@Test func panelSpansNotchPlusEars() {
    let screen = CGRect(x: 0, y: 0, width: 1280, height: 832)
    let left = CGRect(x: 0, y: 800, width: 547, height: 32)
    let right = CGRect(x: 733, y: 800, width: 547, height: 32)

    let geometry = NotchGeometry(screenFrame: screen, topLeftArea: left, topRightArea: right)

    #expect(geometry.notch == CGRect(x: 547, y: 800, width: 186, height: 32))
    #expect(geometry.panel == CGRect(x: 507, y: 800, width: 266, height: 32))
    #expect(geometry.hasHardwareNotch)
}

@Test func fallsBackToCenteredNotchWithoutHardwareNotch() {
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    let geometry = NotchGeometry(screenFrame: screen, topLeftArea: nil, topRightArea: nil)

    #expect(!geometry.hasHardwareNotch)
    #expect(geometry.notch.midX == screen.midX)
    #expect(geometry.notch.maxY == screen.maxY)
    #expect(geometry.panel.width == geometry.notch.width + 2 * NotchGeometry.earWidth)
}
