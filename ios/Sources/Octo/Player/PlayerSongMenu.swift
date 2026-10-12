import AVKit
import OctoKit
import SwiftUI
import UIKit

/// The menu for the song playing, opened from the player's More button as the system's own
/// menu: its queue actions, keeping it, where it is from, and then where and how it sounds. It
/// always offers Go to album and Go to artist, since it has no page of its own to come from.
struct PlayerSongMenu: View {
    let song: Song
    let facts: PlayerSongFacts
    let airPlay: AirPlayTrigger
    /// Closes the player, then opens a page.
    let leave: (Route) -> Void
    @Environment(Player.self) private var player
    @Environment(LikeStore.self) private var likes
    @Environment(Downloads.self) private var downloads
    @Environment(SoundStore.self) private var sound
    @Environment(\.dataServices) private var data
    @State private var route = AudioRoute()

    var body: some View {
        Section {
            Button("Play next", systemImage: OctoIcon.playNext.symbol) { player.playNext([song]) }
            Button("Add to queue", systemImage: OctoIcon.addToQueue.symbol) { player.append([song]) }
            Button("Start radio", systemImage: OctoIcon.radio.symbol) { Task { await player.startRadio(from: song) } }
        }
        Section { keeping }
        Section {
            if let albumId = song.albumId, !albumId.isEmpty, !song.isExternal {
                Button("Go to album", systemImage: OctoIcon.album.symbol) {
                    leave(.album(Album(id: albumId, name: song.album ?? "", artist: song.artist ?? "", coverArt: song.coverArt)))
                }
            }
            if let artistId = song.artistId, !artistId.isEmpty, !song.isExternal {
                Button("Go to artist", systemImage: OctoIcon.artist.symbol) {
                    leave(.artist(id: artistId, name: song.artist ?? ""))
                }
            }
        }
        Section {
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

    @ViewBuilder
    private var keeping: some View {
        if song.isExternal {
            let state = downloads.phase(song.id).state
            switch state {
            case .none:
                Button("Add to your library", systemImage: OctoIcon.addToLibrary.symbol) { Task { _ = await downloads.request(song) } }
            case .requested:
                Button("Adding to your library", systemImage: OctoIcon.check.symbol) {}.disabled(true)
            case .done:
                Button("In your library", systemImage: OctoIcon.check.symbol) {}.disabled(true)
            }
        } else if let trackId = facts.trackId {
            let liked = likes.isLiked(trackId)
            Button(liked ? "Remove from Liked songs" : "Add to Liked songs", systemImage: (liked ? OctoIcon.liked : OctoIcon.like).symbol) {
                likes.toggle(trackId)
            }
            Menu {
                ForEach(1...5, id: \.self) { stars in
                    Button {
                        rate(stars)
                    } label: {
                        if stars == facts.rating {
                            Label(starsWords(stars), systemImage: "checkmark")
                        } else {
                            Text(starsWords(stars))
                        }
                    }
                }
                if facts.rating > 0 {
                    Button("Clear rating", systemImage: "xmark", role: .destructive) { rate(facts.rating) }
                }
            } label: {
                Label {
                    Text("Rate")
                    if facts.rating > 0 { Text(starsWords(facts.rating)) }
                } icon: { Image(systemName: OctoIcon.star.symbol) }
            }
        }
    }

    private func starsWords(_ stars: Int) -> String { stars == 1 ? "1 star" : "\(stars) stars" }

    /// Picking the stars the song already has clears its rating.
    private func rate(_ stars: Int) {
        guard let trackId = facts.trackId else { return }
        let next = stars == facts.rating ? 0 : stars
        facts.showRating(next)
        data?.ratings.rate(trackId, next)
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
