import OctoKit
import SwiftUI

// Octo's rows and cards, the same sizes as the other apps'.

/// The mark on the artwork of something not in the library: a small glass disc with a plus,
/// at the bottom right.
struct NotInLibraryMark: View {
    let artSize: CGFloat
    var round = false

    var body: some View {
        let size = min(20, max(12, artSize * 0.125))
        let inset = max(3, artSize * 0.04)
        Circle()
            .fill(.black.opacity(0.42))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: size * 0.6, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .glassEffect(.regular, in: .circle)
            .padding(round ? artSize * 0.1 : inset)
            .accessibilityLabel("Not in your library")
    }
}

/// A cover with the not-in-library mark when the item is not in the library.
struct BadgedCover: View {
    let id: String?
    var size: CGFloat
    var radius: CGFloat = OctoRadius.artM
    var external = false

    var body: some View {
        Cover(id: id, size: size, radius: radius)
            .overlay(alignment: .bottomTrailing) {
                if external { NotInLibraryMark(artSize: size, round: radius >= size / 2) }
            }
    }
}

/// Three bars that dance while a song plays and rest when it is paused.
struct NowPlayingBars: View {
    let playing: Bool
    var size: CGFloat = 16
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: !playing || reduceMotion)) { time in
            let phase = time.date.timeIntervalSinceReferenceDate / 2.4
            HStack(alignment: .bottom, spacing: size / 7 / 3) {
                ForEach(0..<3, id: \.self) { i in
                    let rest = [0.45, 0.8, 0.6][i]
                    let speed = [2.0, 3.0, 4.0][i]
                    let offset = [0, 0.3, 0.65][i]
                    let height = playing && !reduceMotion ? 0.25 + 0.75 * abs(sin((phase * speed + offset) * .pi)) : rest
                    Capsule().frame(width: size / 4, height: size * height)
                }
            }
            .frame(width: size, height: size, alignment: .bottom)
            .foregroundStyle(playing ? .white : OctoColor.textMuted)
            .shadow(color: playing ? .white.opacity(0.7) : .clear, radius: 2)
        }
        .accessibilityHidden(true)
    }
}

/// What sits at the start of a song row.
enum SongLead: Equatable {
    case artwork
    case number(Int?)
    /// A place in a ranking, then the artwork.
    case ranked(Int)
}

/// One song in a list, from the library or found online. A tap plays (or picks it while the list
/// is picking); a long press opens its menu; a swipe right puts it next in the queue on lists
/// where a swipe does nothing else.
struct TrackRow: View {
    let track: LibraryTrack
    var lead: SongLead = .artwork
    /// Words under the title in place of "Artist • Album"; empty leaves the line out.
    var subtitle: String?
    var context = SongMenuContext()
    var selection: SongSelection?
    /// The row's key for picking: its id, or its playlist row on a playlist page.
    var selectKey: String?
    var swipe: SwipeKind = .playNext
    /// Whether this list offers add: a find ends with the add button, and a library song keeps
    /// the same space empty when `addSpace` so lengths line up.
    var offersAdd = false
    var addSpace = false
    /// A list mixing library songs with finds: a check or the add button after the number.
    var ownership = false
    /// An album's main song, starred.
    var highlighted = false
    var trailing: AnyView?
    let onTap: () -> Void

    /// What a swipe does on this row.
    enum SwipeKind {
        case none, playNext
        case remove(() -> Void)
    }

    @Environment(Player.self) private var player
    @Environment(LibraryActions.self) private var actions

    private var key: String { selectKey ?? track.id }
    private var song: Song { track.asSong }
    private var selecting: Bool { selection?.active == true }
    private var picked: Bool { selection?.isPicked(key) == true }
    private var isNow: Bool { player.current.map { $0.id == song.id && $0.isExternal == song.isExternal } ?? false }

    var body: some View {
        Button {
            if selecting { selection?.toggle(key) } else { onTap() }
        } label: {
            face
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
                .opacity(outOfReach ? 0.4 : 1)
        }
        .buttonStyle(PressSqueeze())
        .background {
            if picked {
                RoundedRectangle(cornerRadius: OctoRadius.row)
                    .fill(LibraryLook.accentSelected)
                    .overlay {
                        RoundedRectangle(cornerRadius: OctoRadius.row)
                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.12), .black.opacity(0.25)], startPoint: .top, endPoint: .bottom),
                                          lineWidth: 1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
            }
        }
        .contextMenu {
            SongActions(track: track, context: context, selection: selection)
        } preview: {
            MenuHeader(artwork: track.artwork, title: track.title, line: track.artist)
        }
        .rowSwipe(rowSwipe, enabled: !selecting)
        .accessibilityAddTraits(selecting && picked ? .isSelected : [])
        .accessibilityAction(named: "Play next") { actions.playNextUndoable(song) }
        .accessibilityAction(named: "Add to queue") { player.append([song]) }
    }

    private var rowSwipe: RowSwipe {
        switch swipe {
        case .none: .none
        case .playNext: .playNext { actions.playNextUndoable(song) }
        case .remove(let run): .remove(run)
        }
    }

    /// With no connection, a song that cannot play is drawn faint.
    private var outOfReach: Bool {
        !actions.state.online && !track.onPhone && actions.state.kept.status(track.id)?.status != .done
    }

    private var shownSubtitle: String {
        subtitle ?? songSubtitle(title: track.title, artist: track.artist, album: track.album, find: track.isFound)
    }

    private var face: some View {
        HStack(spacing: 12) {
            leadView
            if ownership { ownershipMark }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    if highlighted {
                        Image(systemName: MenuIcon.starFilled)
                            .font(.system(size: 11))
                            .foregroundStyle(OctoColor.accent)
                            .frame(width: 14, height: 14)
                            .padding(.trailing, 6)
                            .accessibilityLabel("Most popular")
                    }
                    Text(track.title)
                        .font(.octoBodySmall)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if track.explicit == true {
                        ExplicitMark().padding(.leading, 6).layoutPriority(1)
                    }
                }
                if !shownSubtitle.isEmpty {
                    Text(shownSubtitle)
                        .font(.octoCaption)
                        .foregroundStyle(OctoColor.textMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                sourceMark
                lengthSlot
            }
            end
        }
    }

    @ViewBuilder
    private var leadView: some View {
        switch lead {
        case .artwork:
            artwork
        case .ranked(let rank):
            HStack(spacing: 10) {
                Text("\(rank)")
                    .font(.octoCaption)
                    .foregroundStyle(OctoColor.textMuted)
                    .frame(width: 20, alignment: .trailing)
                artwork
            }
        case .number(let number):
            ZStack(alignment: .trailing) {
                if picked {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 19)).foregroundStyle(.white)
                } else if isNow {
                    NowPlayingBars(playing: player.isPlaying, size: 14)
                } else {
                    Text(number.map(String.init) ?? "")
                        .font(.octoCaption.monospacedDigit())
                        .foregroundStyle(OctoColor.textMuted)
                }
            }
            .frame(width: 28, alignment: .trailing)
        }
    }

    private var artwork: some View {
        ArtCover(artwork: track.artwork, size: 44, radius: OctoRadius.artS)
            .overlay(alignment: .bottomTrailing) {
                if track.isFound && !offersAdd { NotInLibraryMark(artSize: 44) }
            }
            .overlay {
                if picked || isNow {
                    RoundedRectangle(cornerRadius: OctoRadius.artS).fill(.black.opacity(0.5))
                    if picked {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 19)).foregroundStyle(.white)
                    } else {
                        NowPlayingBars(playing: player.isPlaying)
                    }
                }
            }
            .accessibilityLabel(track.isFound ? "Not in your library" : "")
    }

    @ViewBuilder
    private var ownershipMark: some View {
        ZStack {
            if track.isFound {
                AddToLibraryButton(song: song, size: 32, iconSize: 20)
            } else {
                Image(systemName: MenuIcon.check)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OctoColor.accent)
                    .accessibilityLabel("In your library")
            }
        }
        .frame(width: 32)
    }

    @ViewBuilder
    private var sourceMark: some View {
        if !track.isFound {
            if actions.state.kept.status(track.id)?.status == .done {
                Image(systemName: MenuIcon.downloaded)
                    .font(.system(size: 11))
                    .foregroundStyle(OctoColor.textMuted)
                    .frame(width: 14, height: 14)
                    .accessibilityLabel("Downloaded")
            } else if !track.onPhone {
                Image(systemName: MenuIcon.cloud)
                    .font(.system(size: 11))
                    .foregroundStyle(OctoColor.textMuted)
                    .frame(width: 14, height: 14)
                    .accessibilityLabel("Streams from your server")
            }
        }
    }

    /// The length in a column at least as wide as "00:00", so lengths line up.
    private var lengthSlot: some View {
        ZStack(alignment: .trailing) {
            Text(lengthSlotSample).hidden()
            Text(rowLength(track.durationMs) ?? "")
        }
        .font(.octoCaption.monospacedDigit())
        .foregroundStyle(OctoColor.textMuted)
        .lineLimit(1)
    }

    @ViewBuilder
    private var end: some View {
        if offersAdd && track.isFound && !ownership {
            AddToLibraryButton(song: song, size: 40, iconSize: 22)
        } else if let trailing {
            trailing
        } else if offersAdd && addSpace {
            Color.clear.frame(width: 40, height: 40)
        }
    }
}

/// One song as the server lists it, in a list. Tapping plays `list` from this song; holding opens
/// its menu; swiping right puts it next in the queue.
struct SongRow: View {
    let song: Song
    let list: [Song]
    let position: Int
    var showsCover = true
    var number: Int?
    /// Words under the title in place of "Artist • Album".
    var subtitle: String?
    /// Whether this list offers add: a find ends with the add button, and a library song keeps
    /// the same space empty when `addSpace` so lengths line up.
    var offersAdd = false
    var addSpace = false
    var lead: SongLead?
    var context = SongMenuContext()
    @Environment(Player.self) private var player
    @Environment(LibraryActions.self) private var actions

    var body: some View {
        TrackRow(track: actions.state.provisional(song), lead: lead ?? (showsCover ? .artwork : .number(number)), subtitle: subtitle,
                 context: context, offersAdd: offersAdd, addSpace: addSpace) {
            player.play(list, from: position)
        }
    }
}

/// Pressed rows and cards squeeze slightly.
struct PressSqueeze: ButtonStyle {
    var amount: CGFloat = 0.985

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? amount : 1)
            .animation(.easeInOut(duration: 0.17), value: configuration.isPressed)
    }
}

/// An album as a card: square cover, title and artist. A library album opens its menu on a long
/// press; one found online carries the not-in-library mark and how much of it the library has.
struct AlbumCard: View {
    let album: Album
    var width: CGFloat = 150
    /// The library's album, for its menu.
    var library: LibraryAlbum?
    @Environment(LibraryActions.self) private var actions

    var body: some View {
        let card = NavigationLink(value: Route.album(album)) {
            VStack(alignment: .leading, spacing: 8) {
                BadgedCover(id: album.coverArt, size: width, external: album.isExternal)
                VStack(alignment: .leading, spacing: 1) {
                    Text(album.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(album.byline)
                        .font(.octoCaption)
                        .foregroundStyle(OctoColor.textMuted)
                        .lineLimit(1)
                    if album.isExternal, let owned = album.ownedCount, owned > 0, owned < album.songCount {
                        Text("\(owned) of \(album.songCount) in your library")
                            .font(.octoCaption)
                            .foregroundStyle(OctoColor.textMuted)
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: width, alignment: .leading)
        }
        .buttonStyle(PressSqueeze(amount: 0.97))
        if album.isExternal {
            card
        } else {
            let shown = library ?? actions.state.provisionalAlbum(album)
            card.contextMenu {
                CollectionActions(target: .album(shown.id), album: shown)
            } preview: {
                MenuHeader(artwork: shown.artwork, title: shown.title, line: shown.artist)
            }
        }
    }
}

/// An album card that fills its grid cell.
struct GridAlbumCard: View {
    let album: LibraryAlbum

    var body: some View {
        GeometryReader { box in AlbumCard(album: album.asAlbum, width: box.size.width, library: album) }
            .aspectRatio(0.78, contentMode: .fit)
    }
}

/// A song as a card, for shelves of songs: tap plays, long press opens its menu.
struct SongCard: View {
    let song: Song
    let list: [Song]
    let position: Int
    var width: CGFloat = 150
    @Environment(Player.self) private var player
    @Environment(LibraryActions.self) private var actions

    var body: some View {
        let track = actions.state.provisional(song)
        Button { player.play(list, from: position) } label: {
            VStack(alignment: .leading, spacing: 8) {
                BadgedCover(id: song.coverArt, size: width, external: song.isExternal)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(song.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        if song.explicitStatus == "explicit" { ExplicitMark(size: 12) }
                    }
                    HStack(spacing: 4) {
                        Text(song.byline).font(.octoCaption).foregroundStyle(OctoColor.textMuted).lineLimit(1)
                        if !song.isExternal {
                            Image(systemName: MenuIcon.cloud).font(.system(size: 10)).foregroundStyle(OctoColor.textMuted)
                                .accessibilityLabel("Streams from your server")
                        }
                    }
                }
            }
            .frame(width: width, alignment: .leading)
            .opacity(!actions.state.online && !song.isExternal ? 0.4 : 1)
        }
        .buttonStyle(PressSqueeze(amount: 0.97))
        .contextMenu {
            SongActions(track: track)
        } preview: {
            MenuHeader(artwork: track.artwork, title: track.title, line: track.artist)
        }
    }
}

/// A station or a Made for you list: tapping plays it.
struct StationCard: View {
    let name: String
    let coverArt: String?
    var songCount: Int?
    var loading = false
    let play: () -> Void

    var body: some View {
        Button(action: play) {
            VStack(alignment: .leading, spacing: 8) {
                Cover(id: coverArt, size: 150)
                Text(name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                if let songCount {
                    Text(songCount == 1 ? "1 song" : "\(songCount) songs")
                        .font(.octoBodySmall)
                        .foregroundStyle(OctoColor.textSecondary)
                }
            }
            .frame(width: 150, alignment: .leading)
            .opacity(loading ? 0.5 : 1)
        }
        .buttonStyle(PressSqueeze(amount: 0.97))
    }
}

/// An artist as a circle with the name under it. A library artist opens its menu on a long
/// press; one only on the server carries the not-in-library mark.
struct ArtistCircle: View {
    let id: String
    let name: String
    let coverArt: String?
    var size: CGFloat = 96
    var external = false
    var library: LibraryArtist?

    var body: some View {
        let circle = NavigationLink(value: Route.artist(id: id, name: name)) {
            VStack(spacing: 8) {
                BadgedCover(id: coverArt, size: size, radius: size / 2, external: external)
                Text(name).font(.octoCaption).foregroundStyle(.white).lineLimit(1).frame(width: size)
            }
        }
        .buttonStyle(PressSqueeze(amount: 0.97))
        if let library {
            circle.contextMenu {
                CollectionActions(target: .artist(library.id), artist: library)
            } preview: {
                MenuHeader(artwork: library.artwork, title: library.name, line: albumsCount(library.albumCount), round: true)
            }
        } else {
            circle
        }
    }
}

/// An artist line: round picture, name, album count. A long press opens the artist's menu.
struct ArtistRow: View {
    let artist: LibraryArtist

    var body: some View {
        NavigationLink(value: Route.artist(id: artist.id, name: artist.name)) {
            HStack(spacing: 12) {
                ArtCover(artwork: artist.artwork, size: 48, radius: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(artist.name).font(.octoBodySmall).foregroundStyle(.white).lineLimit(1)
                    Text(albumsCount(artist.albumCount)).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressSqueeze())
        .contextMenu {
            CollectionActions(target: .artist(artist.id), artist: artist)
        } preview: {
            MenuHeader(artwork: artist.artwork, title: artist.name, line: albumsCount(artist.albumCount), round: true)
        }
    }
}

/// A playlist's picture: its first cover, or with four, a 2 by 2 grid of quarter-size covers.
struct PlaylistCover: View {
    let covers: [String]
    var size: CGFloat
    var radius: CGFloat = OctoRadius.artS
    var notice: String?

    var body: some View {
        ZStack {
            if covers.count >= 4 {
                VStack(spacing: 0) {
                    HStack(spacing: 0) { quarter(0); quarter(1) }
                    HStack(spacing: 0) { quarter(2); quarter(3) }
                }
            } else {
                ArtCover(artwork: covers.first, size: size, radius: 0)
            }
            if let glyph = noticeGlyph {
                Rectangle().fill(.black.opacity(0.35))
                Image(systemName: glyph).font(.system(size: size * 0.32, weight: .semibold)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .background(OctoColor.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            if size >= 96 || covers.count >= 4 {
                RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 1)
            }
        }
    }

    /// Octo's own lists draw their kind: the review list a magnifier, the duplicates list two
    /// squares, a liked list a heart.
    private var noticeGlyph: String? {
        switch notice {
        case "review": "magnifyingglass"
        case "duplicates": "square.on.square"
        case "liked": "heart.fill"
        default: nil
        }
    }

    private func quarter(_ index: Int) -> some View {
        ArtCover(artwork: covers[index], size: size / 2, radius: 0)
    }
}

/// A playlist line: its picture, the name, and a line under it with a cloud for one kept with
/// the server. A long press opens its menu.
struct PlaylistLine<Picture: View>: View {
    let name: String
    var subtitle: String?
    var onServer = false
    @ViewBuilder var picture: Picture

    var body: some View {
        HStack(spacing: 14) {
            picture.frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.octoBodySmall).foregroundStyle(.white).lineLimit(1)
                if subtitle != nil || onServer {
                    HStack(spacing: 4) {
                        if let subtitle { Text(subtitle).font(.octoCaption).foregroundStyle(OctoColor.textMuted).lineLimit(1) }
                        if onServer {
                            Image(systemName: MenuIcon.cloud).font(.system(size: 11)).foregroundStyle(OctoColor.textMuted)
                                .frame(width: 14, height: 14)
                                .accessibilityLabel("On your server")
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .frame(minHeight: 72)
        .contentShape(Rectangle())
    }
}

/// A titled row of cards that scrolls sideways. A title that leads to its own page carries a
/// chevron.
struct Shelf<Content: View>: View {
    let title: String
    var destination: Route?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let destination {
                    NavigationLink(value: destination) {
                        HStack(spacing: 2) {
                            Text(title).font(.octoSection)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(OctoColor.textMuted)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(title)")
                } else {
                    Text(title).font(.octoSection)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 10)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) { content }
                    .scrollTargetLayout()
                    .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

/// Play and Shuffle side by side, as glass capsules of equal width.
struct PlayButtons: View {
    let songs: [Song]
    @Environment(Player.self) private var player

    var body: some View {
        PlayShuffle(enabled: !songs.isEmpty) { player.play(songs) } shuffle: { player.shuffle(songs) }
    }
}

/// A message in place of a page that could not load, with Try again.
struct LoadFailed: View {
    let message: String
    let retry: () async -> Void

    var body: some View {
        LibraryFailure(message: message, retry: retry)
    }
}

extension Int {
    /// "1 hr 12 min" or "48 min", for an album's or playlist's length.
    var spokenLength: String { asLength(self) }
}

extension LibraryState {
    /// A library album as a plain server album shows it, before the library is asked.
    func provisionalAlbum(_ album: Album) -> LibraryAlbum {
        let source = library.serverInUse ?? ""
        let prefixed: (String?) -> String = { id in
            guard let id, !id.isEmpty else { return "" }
            return id.hasPrefix(source + ":") ? id : "\(source):\(id)"
        }
        let art = album.coverArt.flatMap { $0.isEmpty ? nil : ArtworkRef.server(sourceId: source, coverId: $0).encode() }
        let isLibraryId = album.id.hasPrefix(source + ":") || source.isEmpty
        return LibraryAlbum(
            id: isLibraryId ? album.id : prefixed(album.id), sourceId: source,
            nativeId: isLibraryId ? String(album.id.dropFirst(source.isEmpty ? 0 : source.count + 1)) : album.id,
            title: album.name, searchKey: searchKey(album.name), sortKey: sortKey(album.name), artist: album.byline,
            artistId: prefixed(album.artistId), year: album.year, songCount: album.songCount,
            durationMs: Int64(album.duration) * 1_000, addedAt: 0, artwork: art)
    }
}
