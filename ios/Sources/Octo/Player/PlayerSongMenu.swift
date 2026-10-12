import OctoKit
import SwiftUI

/// The song menu's pages from the player.
enum PlayerMenuPage: Equatable { case actions, rate }

/// The menu for the song playing, opened from the player's More button: a glass card beside it
/// with the song at its top, then its actions in groups. It always offers Go to album and Go to
/// artist, since it has no page of its own to come from.
struct PlayerSongMenu: View {
    let song: Song
    let facts: PlayerSongFacts
    let pages: PopupPages<PlayerMenuPage>
    let dismiss: () -> Void
    /// Closes the player, then opens a page.
    let leave: (Route) -> Void
    @Environment(Player.self) private var player
    @Environment(Router.self) private var router
    @Environment(LikeStore.self) private var likes
    @Environment(\.dataServices) private var data

    var body: some View {
        PopupPager(pages: pages) { page, _ in
            switch page {
            case .actions:
                GlassMenuPage {
                    header
                    GlassMenuSeparator()
                } content: {
                    GlassMenuGroups(groups: groups) { row in row }
                }
            case .rate:
                GlassMenuPage {
                    GlassMenuBack(title: "Rate") { pages.back() }
                    header
                } content: {
                    RateStars(rating: facts.rating) { rate($0) }
                        .padding(.bottom, 10)
                }
            }
        }
    }

    private var header: some View {
        GlassMenuHeader(title: song.title, subtitle: song.byline) {
            Cover(id: song.coverArt, size: 40, radius: 6)
        }
    }

    private var groups: [[AnyView]] {
        let queue: [AnyView] = [
            AnyView(GlassMenuAction(.playNext, "Play next") {
                player.playNext([song])
                dismiss()
            }),
            AnyView(GlassMenuAction(.addToQueue, "Add to queue") {
                player.append([song])
                dismiss()
            }),
            AnyView(GlassMenuAction(.radio, "Start radio") {
                dismiss()
                Task { await player.startRadio(from: song) }
            }),
        ]
        if song.isExternal {
            return [queue, [AnyView(AddToLibraryRow(song: song))]]
        }
        var keep: [AnyView] = []
        if let trackId = facts.trackId {
            let liked = likes.isLiked(trackId)
            keep.append(AnyView(GlassMenuAction(liked ? .liked : .like, liked ? "Remove from Liked songs" : "Add to Liked songs") {
                likes.toggle(trackId)
            }))
            keep.append(AnyView(GlassMenuAction(.star, "Rate", detail: ratingWords(facts.rating), opensPage: true) {
                pages.open(.rate)
            }))
        }
        var places: [AnyView] = []
        if let albumId = song.albumId, !albumId.isEmpty {
            places.append(AnyView(GlassMenuAction(.album, "Go to album") {
                dismiss()
                leave(.album(Album(id: albumId, name: song.album ?? "", artist: song.artist ?? "", coverArt: song.coverArt)))
            }))
        }
        if let artistId = song.artistId, !artistId.isEmpty {
            places.append(AnyView(GlassMenuAction(.artist, "Go to artist") {
                dismiss()
                leave(.artist(id: artistId, name: song.artist ?? ""))
            }))
        }
        return [queue, keep, places]
    }

    private func ratingWords(_ rating: Int) -> String? {
        rating <= 0 ? nil : rating == 1 ? "1 star" : "\(rating) stars"
    }

    /// Tapping the stars the song already has clears its rating.
    private func rate(_ stars: Int) {
        guard let trackId = facts.trackId else { return }
        let next = stars == facts.rating ? 0 : stars
        facts.showRating(next)
        data?.ratings.rate(trackId, next)
    }
}

/// Five stars to rate with, 48 points each: the song's stars lit and filled, the rest outlined
/// and muted.
private struct RateStars: View {
    let rating: Int
    let rate: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Button { rate(star) } label: {
                    IconView(star <= rating ? .starFilled : .star, size: 30, color: star <= rating ? .white : OctoColor.textMuted)
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(NoPress())
                .accessibilityLabel(star == 1 ? "1 star" : "\(star) stars")
                .accessibilityAddTraits(star == rating ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// "Add to your library" for a song found online, following its way into the library.
private struct AddToLibraryRow: View {
    let song: Song
    @Environment(Downloads.self) private var downloads

    var body: some View {
        let state = downloads.phase(song.id).state
        let added = state == .done
        let adding = state == .requested
        GlassMenuAction(added || adding ? .check : .addToLibrary,
                        added ? "In your library" : adding ? "Adding to your library" : "Add to your library",
                        enabled: !added && !adding) {
            Task { _ = await downloads.request(song) }
        }
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
