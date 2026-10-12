import OctoKit
import SwiftUI

/// Type and colors the discovery pages use beyond the shared palette.
enum DiscoveryStyle {
    /// Octo's label style: small buttons, chips and choices.
    static let label = Font.system(size: 13.5, weight: .semibold)
    /// The darker pill a chosen chip sits in.
    static let accentSelected = Color.black.mix(with: OctoColor.accent, by: 0.40)
    static let orange = Color(hex: 0xFF9500)
    static let green = Color(hex: 0x28CD41)
    static let red = Color(hex: 0xFF3B30)
}

/// Whether Octo's own Reduce motion is on; the phone's setting counts too.
let reduceMotionKey = "motion.reduce"

/// The app-wide "Library songs only" switch.
let libraryOnlyKey = "library.only"

/// A small text button for a lesser action beside a title, like "See all" or "Clear all": no
/// border and no fill.
struct QuietAction: View {
    let text: String
    let action: () -> Void

    init(_ text: String, action: @escaping () -> Void) {
        self.text = text
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(DiscoveryStyle.label)
                .foregroundStyle(OctoColor.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A section's title with a quiet button at its end.
struct TitleRow: View {
    let title: String
    var action: String?
    var top: CGFloat = 0
    var perform: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.octoSection)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .accessibilityAddTraits(.isHeader)
            if let action { QuietAction(action, action: perform) }
        }
        .padding(.trailing, 10)
        .padding(.top, top)
    }
}

/// A muted line in place of a list: nothing found, or what to type.
struct SearchHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.octoBodySmall)
            .foregroundStyle(OctoColor.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
    }
}

/// A one-line note in a list, quieter than its rows.
struct QuietNote: View {
    let text: String
    var color: Color = OctoColor.textMuted

    var body: some View {
        Text(text)
            .font(.octoBodySmall)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
    }
}

/// Names each kind of find, quieter than a section title.
struct FindsSubtitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.octoBodySmall)
            .foregroundStyle(OctoColor.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 8)
    }
}

/// One filter as a filled chip: the darker pill with white words while on, a faint fill with
/// quieter words while off.
struct OnOffChip: View {
    let text: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(DiscoveryStyle.label)
                .foregroundStyle(on ? Color.white : OctoColor.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(minHeight: 36)
                .background(on ? DiscoveryStyle.accentSelected : Color.white.opacity(0.07), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
        .sensoryFeedback(.selection, trigger: on)
    }
}

/// A row of cards that scrolls sideways, 20 in from the sides and 14 apart. Its height is its
/// cards' own, never more.
struct SideScroller<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) { content }
                .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The mark on the artwork of something not in the library: a small glass disc with a black film
/// and a thin plus, at the bottom right. Only a sign, not a button.
struct OutsideMark: View {
    let art: CGFloat
    var round = false

    var body: some View {
        let size = notInLibraryMarkSize(Double(art))
        let inset = notInLibraryMarkInset(Double(art), mark: size, round: round)
        Circle()
            .fill(.black.opacity(0.42))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: size * 0.68 * 0.8, weight: .regular))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .glassEffect(.regular, in: .circle)
            .padding(.trailing, inset)
            .padding(.bottom, inset)
            .accessibilityHidden(true)
    }
}

/// A cover with the not-in-library mark when the thing is not in the library.
struct OutsideCover: View {
    let id: String?
    let size: CGFloat
    var radius: CGFloat = OctoRadius.artM
    var outside = false

    var body: some View {
        Cover(id: id, size: size, radius: radius)
            .overlay(alignment: .bottomTrailing) {
                if outside { OutsideMark(art: size, round: radius >= size / 2) }
            }
            .accessibilityElement()
            .accessibilityLabel(artworkDescription(nil, outside: outside) ?? "")
            .accessibilityHidden(!outside)
    }
}

/// An album on the server, not in the library: the album card with the not-in-library mark on
/// its cover and, when the library holds some of its songs, how many. No menu; a tap opens the
/// album's page from the server.
struct OnlineAlbumCard: View {
    let album: Album
    var width: CGFloat = 150
    var opened: () -> Void = {}

    var body: some View {
        NavigationLink(value: Route.onlineAlbum(id: album.id, name: album.name)) {
            VStack(alignment: .leading, spacing: 0) {
                OutsideCover(id: album.coverArt, size: width, outside: true)
                Spacer().frame(height: 8)
                Text(album.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(album.artist)
                    .font(.octoCaption)
                    .foregroundStyle(OctoColor.textMuted)
                    .lineLimit(1)
                if let note = albumShareLine(owned: album.ownedCount, songs: album.songCount) {
                    Text(note)
                        .font(.octoCaption)
                        .foregroundStyle(OctoColor.textMuted)
                        .lineLimit(1)
                }
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressSqueeze(amount: 0.97))
        .simultaneousGesture(TapGesture().onEnded(opened))
    }
}

/// An artist on the server, as a round picture with the name under it and the not-in-library
/// mark. No menu; a tap opens the artist's page from the server.
struct OnlineArtistCircle: View {
    let id: String
    let name: String
    let coverArt: String?
    var outside = true
    var opened: () -> Void = {}

    var body: some View {
        NavigationLink(value: Route.onlineArtist(id: id, name: name)) {
            VStack(spacing: 8) {
                OutsideCover(id: coverArt, size: 96, radius: 48, outside: outside)
                Text(name)
                    .font(.octoCaption)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .frame(width: 96)
            }
            .frame(width: 96)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressSqueeze(amount: 0.97))
        .simultaneousGesture(TapGesture().onEnded(opened))
    }
}

/// An artist line: round picture, name, album count.
struct ArtistListRow: View {
    let artist: Artist
    var opened: () -> Void = {}

    var body: some View {
        NavigationLink(value: Route.artist(id: artist.id, name: artist.name)) {
            HStack(spacing: 12) {
                Cover(id: artist.coverArt, size: 48, radius: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(artist.name).font(.octoBodySmall).foregroundStyle(.white).lineLimit(1)
                    Text(artist.albumCount == 1 ? "1 album" : "\(artist.albumCount) albums")
                        .font(.octoCaption)
                        .foregroundStyle(OctoColor.textMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressSqueeze())
        .simultaneousGesture(TapGesture().onEnded(opened))
    }
}

/// A playlist line: its artwork, name, song count, and the cloud mark for one on the server.
struct PlaylistListRow: View {
    let playlist: Playlist
    var opened: () -> Void = {}

    var body: some View {
        NavigationLink(value: Route.playlist(playlist)) {
            HStack(spacing: 12) {
                Cover(id: playlist.coverArt ?? playlist.id, size: 56, radius: OctoRadius.artS)
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.name).font(.octoBodySmall).foregroundStyle(.white).lineLimit(1)
                    HStack(spacing: 4) {
                        Text(playlist.songCount == 1 ? "1 song" : "\(playlist.songCount) songs")
                            .font(.octoCaption)
                            .foregroundStyle(OctoColor.textMuted)
                        Image(systemName: "cloud")
                            .font(.system(size: 11))
                            .foregroundStyle(OctoColor.textMuted)
                            .accessibilityLabel("On your server")
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressSqueeze())
        .simultaneousGesture(TapGesture().onEnded(opened))
    }
}

/// A spinner in the accent, while a page loads.
struct AccentSpinner: View {
    var size: CGFloat = 28

    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .tint(OctoColor.accent)
            .controlSize(size >= 28 ? .large : .regular)
            .frame(width: size, height: size)
    }
}
