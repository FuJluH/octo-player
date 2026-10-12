import AVKit
import OctoKit
import SwiftUI
import UIKit

/// What the player's More menu adds to the song's own menu: where the music plays (AirPlay) and
/// how it sounds, each with its state under it.
struct PlayerMenuExtras: View {
    let airPlay: AirPlayTrigger
    /// Closes the player, then opens a page.
    let leave: (Route) -> Void
    @Environment(SoundStore.self) private var sound
    @State private var route = AudioRoute()

    var body: some View {
        Button { airPlay.open() } label: {
            Label {
                Text("AirPlay")
                Text(route.elsewhere.map { "Playing on \($0)" } ?? "Playing on this iPhone")
            } icon: { Image(systemName: OctoIcon.cast.symbol) }
        }
        Button { leave(.sound) } label: {
            Label {
                Text("Sound")
                Text(sound.current.eqEnabled ? "Equalizer on" : "Equalizer off")
            } icon: { Image(systemName: OctoIcon.sound.symbol) }
        }
    }
}

/// Opens the system's list of AirPlay speakers, TVs and headphones from anywhere, through a
/// route picker kept out of sight in the player.
@MainActor
final class AirPlayTrigger {
    fileprivate weak var picker: AVRoutePickerView?

    func open() {
        picker?.subviews.compactMap { $0 as? UIButton }.first?.sendActions(for: .touchUpInside)
    }
}

/// The route picker `AirPlayTrigger` opens, drawn invisibly.
struct HiddenRoutePicker: UIViewRepresentable {
    let trigger: AirPlayTrigger

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.delegate = RouteChoice.shared
        view.alpha = 0.011
        view.isUserInteractionEnabled = false
        trigger.picker = view
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        trigger.picker = view
    }
}

/// The rating under the song's title: one small star a point, nothing when unrated.
struct RatingStars: View {
    let rating: Int

    var body: some View {
        if rating > 0 {
            HStack(spacing: 2) {
                ForEach(0..<min(rating, 5), id: \.self) { _ in
                    IconView(.starFilled, size: 12, color: OctoColor.textMuted)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(rating == 1 ? "Rated 1 star" : "Rated \(rating) stars")
        }
    }
}
