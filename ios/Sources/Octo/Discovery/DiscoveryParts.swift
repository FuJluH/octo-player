import OctoKit
import SwiftUI

/// Type and colors the discovery pages use beyond the shared palette.
enum DiscoveryStyle {
    /// Octo's label style: small buttons, chips and choices.
    static let label = Font.system(size: 13.5, weight: .semibold)
    /// The darker pill a chosen chip sits in.
    static var accentSelected: Color { Color.black.mix(with: OctoColor.accent, by: 0.40) }
    static let orange = Color(hex: 0xFF9500)
    static let green = Color(hex: 0x28CD41)
    static let red = Color(hex: 0xFF3B30)
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
            if let action { QuietButton(action, action: perform) }
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

/// A cover with the not-in-library mark when the thing is not in the library.
struct OutsideCover: View {
    let id: String?
    let size: CGFloat
    var radius: CGFloat = OctoRadius.artM
    var outside = false

    var body: some View {
        BadgedCover(id: id, size: size, radius: radius, external: outside)
            .accessibilityElement()
            .accessibilityLabel(artworkDescription(nil, outside: outside) ?? "")
            .accessibilityHidden(!outside)
    }
}

/// An album on the server, not in the library: the album card with the not-in-library mark on
/// its cover and, when the library holds some of its songs, how many. No menu; a tap opens the
/// album's page from the server.
struct OnlineAlbumCard: View {
    let album: OnlineAlbum
    var width: CGFloat = 150
    var opened: () -> Void = {}

    var body: some View {
        NavigationLink(value: Route.onlineAlbum(id: album.id, name: album.title)) {
            VStack(alignment: .leading, spacing: 0) {
                OutsideCover(id: coverId(of: album.artwork), size: width, outside: true)
                Spacer().frame(height: 8)
                Text(album.title)
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
        .buttonStyle(PressScale(scale: 0.97))
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
        .buttonStyle(PressScale(scale: 0.97))
        .simultaneousGesture(TapGesture().onEnded(opened))
    }
}

/// An artist line: round picture, name, album count. A library artist opens its menu on a long
/// press.
struct ArtistListRow: View {
    let id: String
    let name: String
    let coverArt: String?
    let albumCount: Int
    var library: LibraryArtist?
    /// An artist the server found online, not in the library: its page is the server's, its picture
    /// has the not-in-library mark, and its album count shows only when known.
    var outside = false
    var opened: () -> Void = {}
    @Environment(Router.self) private var router

    // A button that opens the page, so a list shows it as a plain row.
    var body: some View {
        Button {
            opened()
            router.go(outside ? .onlineArtist(id: id, name: name) : .artist(id: id, name: name))
        } label: {
            HStack(spacing: 12) {
                OutsideCover(id: coverArt, size: 48, radius: 24, outside: outside)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.octoBodySmall).foregroundStyle(.white).lineLimit(1)
                    if !outside || albumCount > 0 {
                        Text(albumCount == 1 ? "1 album" : "\(albumCount) albums")
                            .font(.octoCaption)
                            .foregroundStyle(OctoColor.textMuted)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(SqueezeStyle())
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: OctoRadius.row))
        .contextMenu { if let library { CollectionMenuItems(subject: .artist(library)) } }
    }
}

/// A playlist line: its picture (the designed cover or the mosaic, with the phone's footer and an
/// Octo list's glyph), name, song count, and the cloud mark for one on the server.
struct PlaylistListRow: View {
    let summary: PlaylistSummary
    let playlist: Playlist
    var opened: () -> Void = {}
    @Environment(Router.self) private var router

    // A button that opens the page, so a list shows it as a plain row.
    var body: some View {
        Button {
            opened()
            router.go(.playlist(playlist))
        } label: {
            HStack(spacing: 12) {
                PlaylistCover(playlist: summary, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.name).font(.octoBodySmall).foregroundStyle(.white).lineLimit(1)
                    HStack(spacing: 4) {
                        Text(summary.songCount == 1 ? "1 song" : "\(summary.songCount) songs")
                            .font(.octoCaption)
                            .foregroundStyle(OctoColor.textMuted)
                        if summary.onServer {
                            Image(systemName: "cloud")
                                .font(.system(size: 11))
                                .foregroundStyle(OctoColor.textMuted)
                                .accessibilityLabel("On your server")
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(SqueezeStyle())
    }
}

