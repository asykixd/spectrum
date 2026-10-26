import SwiftUI

/// The app icon: Clawd under a glowing notch on a night-sky squircle. Rendered to PNG by the
/// preview command and turned into `Resources/AppIcon.icns` by `scripts/make-icon.sh`.
struct AppIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size.width
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x241B4D), Color(hex: 0x10162E)],
                            startPoint: .top, endPoint: .bottom))
                Capsule()
                    .fill(.black)
                    .frame(width: size * 0.42, height: size * 0.12)
                    .offset(y: -size * 0.3)
                    .shadow(color: ClawdLook.body.opacity(0.6), radius: size * 0.05)
                Canvas { context, canvasSize in
                    let pixel = canvasSize.width / 11
                    let canvas = PixelCanvas(
                        context: context, pixel: pixel, origin: CGPoint(x: pixel, y: pixel * 2))
                    let palette = ClawdLook.palette(accent: .clear)
                    canvas.sprite(ClawdLook.awake, x: 0, y: 0, palette: palette)
                    canvas.sprite(ClawdLook.legs, x: 0, y: 5, palette: palette)
                }
                .frame(width: size * 0.62, height: size * 0.62)
                .offset(y: size * 0.1)
                .shadow(color: ClawdLook.body.opacity(0.45), radius: size * 0.06)
            }
            .padding(size * 0.08)
        }
    }
}
