import OctoKit
import SwiftUI

/// An icon that can light up with a soft glow: a wide faint halo and a tighter bright one behind
/// the sharp icon. The glow fades in and out as `lit` changes.
struct SoundGlowIcon: View {
    let systemName: String
    let tint: Color
    let lit: Bool

    var body: some View {
        ZStack {
            icon.blur(radius: 10 * 0.57735 + 0.5).opacity(lit ? 0.6 : 0)
            icon.blur(radius: 3 * 0.57735 + 0.5).opacity(lit ? 0.7 : 0)
            icon
        }
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.3), value: lit)
    }

    private var icon: some View {
        Image(systemName: systemName)
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
            .foregroundStyle(tint)
    }
}
