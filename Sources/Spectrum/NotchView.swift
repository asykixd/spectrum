import SwiftUI

struct NotchView: View {
    var body: some View {
        UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12)
            .fill(.black)
            .overlay(Text("Spectrum").font(.caption).foregroundStyle(.white))
    }
}
