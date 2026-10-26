import SwiftUI

struct NotchView: View {
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "waveform")
                .frame(maxWidth: .infinity)
            // Content under the hardware notch is hidden by the camera housing.
            Spacer().frame(width: notchWidth)
            Text("Spectrum")
                .frame(maxWidth: .infinity)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12)
                .fill(.black)
        )
    }
}
