import OctoKit
import SwiftUI

// Octo's rows and cards, the same sizes as the other apps'.

/// The mark on the artwork of something not in the library: a small glass disc with a thin
/// plus at the bottom right, an eighth of the artwork's side (12 to 20 points). On a round
/// picture it sits along the diagonal, far enough in that the whole disc stays inside.
struct NotInLibraryMark: View {
    let artSize: CGFloat
    var round = false

    var body: some View {
        let size = CGFloat(notInLibraryMarkSize(Double(artSize)))
        let inset = CGFloat(notInLibraryMarkInset(Double(artSize), mark: Double(size), round: round))
        IconView(.notInLibrary, size: size * 0.68, color: .white.opacity(0.9))
            .frame(width: size, height: size)
            .octoGlass(Circle(), film: .black.opacity(0.42))
            .padding(.trailing, inset)
            .padding(.bottom, inset)
            .accessibilityLabel(notInLibraryText)
    }
}

/// A cover with the not-in-library mark when the item is not in the library.
struct BadgedCover: View {
    let id: String?
    var size: CGFloat
    var radius: CGFloat = OctoRadius.artM
    var external = false

    var body: some View {
        Cover(id: id, size: size, radius: radius, online: external)
            .overlay(alignment: .bottomTrailing) {
                if external { NotInLibraryMark(artSize: size, round: radius >= size / 2) }
            }
    }
}

/// Three small bars that mark the song playing now: moving and softly lit while it plays,
/// still and quiet while it is paused. With Reduce motion a playing song's bars rest, still lit.
struct NowPlayingBars: View {
    let playing: Bool
    var size: CGFloat = 16
    @Environment(\.motionScale) private var motion

    private static let rest: [Double] = [0.45, 0.8, 0.6]
    private static let speeds: [Double] = [2, 3, 4]
    private static let offsets: [Double] = [0, 0.3, 0.65]

    var body: some View {
        Group {
            if playing && !motion.still {
                TimelineView(.animation) { time in
                    let phase = time.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
                    ZStack {
                        bars(phase: phase, color: .white).blur(radius: 4).opacity(0.7)
                        bars(phase: phase, color: .white)
                    }
                }
            } else {
                bars(phase: nil, color: playing ? .white : OctoColor.textMuted)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func bars(phase: Double?, color: Color) -> some View {
        Canvas { context, canvas in
            let gap = canvas.width / 7
            let width = (canvas.width - gap * 2) / 3
            for i in 0..<3 {
                let share = phase.map { 0.25 + 0.75 * abs(sin(($0 * Self.speeds[i] + Self.offsets[i]) * .pi)) } ?? Self.rest[i]
                let height = canvas.height * share
                let rect = CGRect(x: CGFloat(i) * (width + gap), y: canvas.height - height, width: width, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(color))
            }
        }
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
    var track: LibraryTrack
    var lead: SongLead = .artwork
    /// Words under the title in place of "Artist • Album"; empty leaves the line out.
    var subtitle: String?
    var context = SongMenuContext()
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
    /// A song found online turns into the library song it became, in the same place; the turned
    /// row draws as that song and does not turn again.
    var turns = true
    let onTap: () -> Void

    /// What a swipe does on this row.
    enum SwipeKind {
        case none, playNext
        case remove(() -> Void)
    }

    @Environment(Player.self) private var player
    @Environment(LibraryActions.self) private var actions
    @Environment(Downloads.self) private var downloads
    @Environment(\.songSelection) private var selection

    private var key: String { selectKey ?? track.id }
    private var song: Song { track.asSong }
    private var selecting: Bool { selection?.active == true }
    private var picked: Bool { selection?.isPicked(key) == true }
    /// Whether this row's song is the one playing: the queue holds a library song by its library
    /// id, the row by the same id.
    private var isNow: Bool {
        if let item = player.currentItem, item.trackId == track.id { return true }
        return player.current.map { $0.id == song.id && $0.isExternal == song.isExternal } ?? false
    }

    var body: some View {
        if turns && track.isFound {
            // The check has its moment first where the row offers the add button; once turned,
            // the row's menu, swipe and what plays are the library song's.
            FindSwap(track: track, offersAdd: offersAdd || ownership) { shown in
                turned(shown)
            }
        } else {
            row
        }
    }

    /// This row as it draws `shown`: the find itself, or the library song it became.
    private func turned(_ shown: LibraryTrack) -> TrackRow {
        var copy = self
        copy.turns = false
        copy.track = shown
        return copy
    }

    /// Whether the find has reached the library.
    private var adopted: Bool { track.isFound && downloads.phase(track.nativeId) == .done }

    private var row: some View {
        Button {
            if selecting { selection?.toggle(key) } else { onTap() }
        } label: {
            face
                .padding(.horizontal, ListRow.side)
                .padding(.vertical, 4)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
                .opacity(outOfReach ? 0.4 : 1)
        }
        .buttonStyle(SqueezeStyle())
        .background {
            if picked {
                RoundedRectangle(cornerRadius: OctoRadius.row)
                    .fill(LibraryLook.accentSelected)
                    .overlay {
                        RoundedRectangle(cornerRadius: OctoRadius.row)
                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.12), .black.opacity(0.25)], startPoint: .top, endPoint: .bottom),
                                          lineWidth: 1)
                    }
                    .padding(.horizontal, ListRow.pickInset)
                    .padding(.vertical, 2)
            }
        }
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: OctoRadius.row))
        .contextMenu { SongMenuItems(subject: menuSubject) }
        .songSwipes(rowSwipe, enabled: !selecting)
        .accessibilityAddTraits(selecting && picked ? .isSelected : [])
        .accessibilityAction(named: "Play next") { actions.playNextUndoable(song) }
        .accessibilityAction(named: "Add to queue") { player.append([song]) }
    }

    private var menuSubject: SongSubject {
        var context = context
        if context.selectKey == nil, selection != nil { context.selectKey = key }
        return SongSubject(track: track, song: song, context: context, selection: selection)
    }

    private var rowSwipe: RowSwipe {
        switch swipe {
        case .none: .none
        case .playNext: .playNext { actions.playNextUndoable(song) }
        case .remove(let run): .remove(run)
        }
    }

    /// With no connection, a song that cannot play is drawn faint.
    private var outOfReach: Bool { actions.state.isOutOfReach(track) }

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
                        IconView(.starFilled, size: 14, color: OctoColor.accent)
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
                    IconView(.select, size: 22, color: .white)
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
                if rowAddSign(isFind: track.isFound, adopted: adopted, offersAdd: offersAdd) == .mark { NotInLibraryMark(artSize: 44) }
            }
            .overlay {
                if picked || isNow {
                    RoundedRectangle(cornerRadius: OctoRadius.artS).fill(.black.opacity(0.5))
                    if picked {
                        IconView(.select, size: 22, color: .white)
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
            if track.isFound && !adopted {
                AddToLibraryButton(song: song, size: 32, iconSize: 20)
            } else {
                IconView(.check, size: 20, color: OctoColor.accent)
                    .accessibilityLabel("In your library")
            }
        }
        .frame(width: 32)
    }

    @ViewBuilder
    private var sourceMark: some View {
        if !track.isFound {
            if !track.onPhone && actions.state.kept(track.id)?.status == .done {
                IconView(.downloaded, size: 14, color: OctoColor.textMuted)
                    .accessibilityLabel("Downloaded")
            } else if !track.onPhone {
                IconView(.cloud, size: 14, color: OctoColor.textMuted)
                    .accessibilityLabel("Streams from your server")
            }
        }
    }

    /// The length in a column at least as wide as "00:00", so lengths line up.
    private var lengthSlot: some View {
        ZStack(alignment: .trailing) {
            Text(lengthSlotSample).hidden()
            Text(rowLength(shownLengthMs(track.durationMs, learnedMs: player.learnedLengths[track.id].map(Int64.init))) ?? "")
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
    /// A place in a ranking, shown before the artwork.
    var rank: Int?
    /// The words under the title for the song the row shows, in place of `subtitle`, so a find
    /// that turns into its library song says the library song's.
    var describe: ((Song) -> String)?
    /// Stars the album's main song.
    var highlight = false
    /// Every row has a mark after its number: a check for a library song, the add button for a
    /// find.
    var ownership = false
    /// What a tap does in place of playing `list` from this song.
    var tap: (() -> Void)?
    /// Where the row's menu was opened from.
    var context = SongMenuContext()
    /// The name of the list the song plays in, for the queue's headings.
    var listName: String?
    @Environment(Player.self) private var player
    @Environment(Router.self) private var router
    @Environment(Downloads.self) private var downloads
    @Environment(LibraryActions.self) private var actions
    @Environment(\.songSelection) private var selection

    /// The row is picked by the song it was given, whichever song it shows.
    private var key: String { song.id }
    private var selecting: Bool { selection?.active == true }
    private var picked: Bool { selection?.isPicked(key) == true }

    var body: some View {
        if song.isExternal {
            FindSwap(find: song, offersAdd: offersAdd) { shown in line(shown) }
        } else {
            line(song)
        }
    }

    private func line(_ shown: Song) -> some View {
        Button {
            if selecting {
                selection?.toggle(key)
            } else if let tap {
                tap()
            } else {
                player.play(list, from: position, source: .played(listName))
            }
        } label: {
            HStack(spacing: 12) {
                lead(shown)
                if ownership { OwnershipMark(song: shown) }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if highlight {
                            IconView(.starFilled, size: 14, color: OctoColor.accent)
                                .accessibilityLabel("Most popular")
                        }
                        Text(shown.title)
                            .font(.octoBodySmall)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if shown.explicitStatus == "explicit" { ExplicitMark() }
                    }
                    let words = describe?(shown) ?? subtitle ?? songSubtitle(shown)
                    if !words.isEmpty {
                        Text(words)
                            .font(.octoCaption)
                            .foregroundStyle(OctoColor.textMuted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                // The length learned by playing, when the listing was off, else the listed one.
                let listedMs = shown.isExternal ? knownLengthMs(shown) : Int64(max(shown.duration, 0)) * 1_000
                let learned = (player.learnedLengths[actions.state.libraryId(shown) ?? shown.id] ?? player.learnedLengths[shown.id])
                    .map(Int64.init)
                Text(rowLength(shownLengthMs(listedMs, learnedMs: learned)) ?? "")
                    .font(.octoCaption.monospacedDigit())
                    .foregroundStyle(OctoColor.textMuted)
                switch rowEnd(sign(shown), librarySpace: addSpace, hasTrailing: false) {
                case .addButton: AddToLibraryButton(song: shown, size: 40, iconSize: 22)
                case .addSpace: Color.clear.frame(width: 40, height: 40)
                case .trailing: EmptyView()
                }
            }
            .padding(.horizontal, ListRow.side)
            .padding(.vertical, 4)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
            // With no connection, a song that cannot play is drawn faint.
            .opacity(actions.state.isOutOfReach(actions.state.provisional(shown)) ? 0.4 : 1)
        }
        .buttonStyle(SqueezeStyle())
        .background {
            if picked {
                RoundedRectangle(cornerRadius: OctoRadius.row)
                    .fill(LibraryLook.accentSelected)
                    .overlay {
                        RoundedRectangle(cornerRadius: OctoRadius.row)
                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.12), .black.opacity(0.25)], startPoint: .top, endPoint: .bottom),
                                          lineWidth: 1)
                    }
                    .padding(.horizontal, ListRow.pickInset)
                    .padding(.vertical, 2)
            }
        }
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: OctoRadius.row))
        .contextMenu { SongMenuItems(subject: menuSubject(shown)) }
        .songSwipes(.playNext { actions.playNextUndoable(shown) }, enabled: !selecting)
        .accessibilityAddTraits(selecting && picked ? .isSelected : [])
        .accessibilityAction(named: "Play next") { actions.playNextUndoable(shown) }
        .accessibilityAction(named: "Add to queue") { player.append([shown]) }
    }

    /// The song's menu, which offers Select on a list that can pick.
    private func menuSubject(_ shown: Song) -> SongSubject {
        var context = context
        if context.selectKey == nil, selection != nil { context.selectKey = key }
        return SongSubject(track: actions.state.provisional(shown), song: shown, context: context, selection: selection)
    }

    /// How the row says its song is not in the library.
    private func sign(_ shown: Song) -> AddSign {
        rowAddSign(isFind: shown.isExternal, adopted: downloads.phase(shown.id) == .done, offersAdd: offersAdd)
    }

    /// Whether the shown song is the one playing. A song from the server carries the server's id
    /// while the queue holds a library song by its library id, so both are compared.
    private func isCurrent(_ shown: Song) -> Bool {
        if player.current?.id == shown.id || player.current?.id == song.id { return true }
        guard let playing = player.currentItem?.trackId else { return false }
        return [shown, song].contains { playing == $0.id || playing == actions.state.libraryId($0) }
    }

    @ViewBuilder
    private func lead(_ shown: Song) -> some View {
        if showsCover {
            HStack(spacing: 10) {
                if let rank {
                    Text("\(rank)")
                        .font(.octoCaption.monospacedDigit())
                        .foregroundStyle(OctoColor.textMuted)
                        .frame(width: 20, alignment: .trailing)
                }
                BadgedCover(id: shown.coverArt, size: 44, radius: OctoRadius.artS, external: sign(shown) == .mark)
                    .overlay {
                        if picked || isCurrent(shown) {
                            RoundedRectangle(cornerRadius: OctoRadius.artS).fill(.black.opacity(0.5))
                            if picked {
                                IconView(.check, size: 20, color: .white)
                            } else {
                                NowPlayingBars(playing: player.isPlaying)
                            }
                        }
                    }
            }
        } else {
            let isCurrent = isCurrent(shown)
            ZStack(alignment: .trailing) {
                if picked {
                    IconView(.check, size: 18, color: .white)
                } else if isCurrent {
                    NowPlayingBars(playing: player.isPlaying, size: 14)
                } else if let number {
                    Text("\(number)")
                        .font(.octoBodySmall.monospacedDigit())
                        .foregroundStyle(OctoColor.textMuted)
                }
            }
            .frame(width: 28, alignment: .trailing)
        }
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
        .buttonStyle(PressScale(scale: 0.97))
        card
            .contextMenu {
                if !album.isExternal { CollectionMenuItems(subject: .album(library ?? actions.state.provisionalAlbum(album))) }
            }
            .onAppear { if let id = library?.id { actions.loadAlbumFacts(id) } }
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
                        if actions.state.isDownloaded(track) {
                            IconView(.downloaded, size: 12, color: OctoColor.textMuted)
                                .accessibilityLabel("Downloaded")
                        } else if !track.onPhone && !track.isFound {
                            IconView(.cloud, size: 12, color: OctoColor.textMuted)
                                .accessibilityLabel("Streams from your server")
                        }
                    }
                }
            }
            .frame(width: width, alignment: .leading)
            .opacity(actions.state.isOutOfReach(track) ? 0.4 : 1)
        }
        .buttonStyle(PressScale(scale: 0.97))
        .contextMenu { SongMenuItems(subject: SongSubject(track: track, song: song)) }
    }
}

/// A station or a Made for you list. With `open`, tapping opens its songs and the round play
/// button on its cover plays them at once; without, as for an internet radio station added to the
/// server, which has no list, tapping plays it. It dims while it starts.
struct StationCard: View {
    let name: String
    let coverArt: String?
    var songCount: Int?
    var loading = false
    /// The page of its songs.
    var open: Route?
    let play: () -> Void

    private static let size: CGFloat = 150

    var body: some View {
        if let open {
            NavigationLink(value: open) { card }
                .buttonStyle(PressScale(scale: 0.97))
                .accessibilityHint("Open \(name)")
                .overlay(alignment: .topLeading) {
                    playButton.frame(width: Self.size, height: Self.size, alignment: .bottomTrailing)
                }
        } else {
            Button(action: play) { card }
                .buttonStyle(PressScale(scale: 0.97))
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            Cover(id: coverArt, size: Self.size)
            Text(name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            if let songCount {
                Text(songCount == 1 ? "1 song" : "\(songCount) songs")
                    .font(.octoBodySmall)
                    .foregroundStyle(OctoColor.textSecondary)
            }
        }
        .frame(width: Self.size, alignment: .leading)
        .opacity(loading ? 0.5 : 1)
    }

    /// Plays the list at once, a spinner in its place while it starts. The glass circle is smaller
    /// than the 44 by 44 points it answers taps across.
    private var playButton: some View {
        Button(action: play) {
            ZStack {
                if loading {
                    LoadingSpinner(size: 18)
                } else {
                    Image(systemName: "play.fill").font(.system(size: 15, weight: .semibold))
                }
            }
            .frame(width: 22, height: 22)
            .foregroundStyle(.white)
            .padding(8)
            .glassEffect(Glass.octo.interactive(), in: .circle)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(loading)
        .padding(4)
        .accessibilityLabel("Play \(name)")
    }
}

/// An artist as a circle with the name under it. A library artist opens its menu on a long
/// press; one only on the server carries the not-in-library mark and opens as the server has it.
struct ArtistCircle: View {
    let id: String
    let name: String
    let coverArt: String?
    var size: CGFloat = 96
    var external = false
    var library: LibraryArtist?
    @Environment(LibraryActions.self) private var actions

    var body: some View {
        NavigationLink(value: external ? Route.onlineArtist(id: id, name: name) : Route.artist(id: id, name: name)) {
            VStack(spacing: 8) {
                BadgedCover(id: coverArt, size: size, radius: size / 2, external: external)
                Text(name).font(.octoCaption).foregroundStyle(.white).lineLimit(1).frame(width: size)
            }
        }
        .buttonStyle(PressScale(scale: 0.97))
        .contextMenu { if let library { CollectionMenuItems(subject: .artist(library)) } }
    }
}

/// An artist line: round picture, name, album count. A long press opens the artist's menu.
struct ArtistRow: View {
    let artist: LibraryArtist
    @Environment(LibraryActions.self) private var actions

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
            .padding(.horizontal, ListRow.side)
            .padding(.vertical, 4)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(SqueezeStyle())
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: OctoRadius.row))
        .contextMenu { CollectionMenuItems(subject: .artist(artist)) }
    }
}

/// A playlist's picture: its first cover, or with four, a 2 by 2 grid of quarter-size covers.
struct PlaylistCover: View {
    let covers: [String]
    var size: CGFloat
    var radius: CGFloat = OctoRadius.artS
    var notice: String?
    /// The list itself, for its designed cover; without it the mosaic is drawn.
    var id: String?
    var name = ""
    var footer: String?
    var line: String? = playlistCoverLine

    var body: some View {
        if AppSettings.shared.playlistCovers == .designed, let id {
            DesignedCover(id: id, name: name, covers: covers, size: size, radius: radius, line: line, footer: footer,
                          glyph: playlistGlyph(octoNotice: notice))
        } else {
            mosaic
        }
    }

    /// The covers of its first albums in a square.
    private var mosaic: some View {
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
                IconView(glyph, size: size * 0.36, color: .white)
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
    private var noticeGlyph: OctoIcon? {
        switch notice {
        case "review": .search
        case "duplicates": .copy
        case "liked": .liked
        default: nil
        }
    }

    private func quarter(_ index: Int) -> some View {
        ArtCover(artwork: covers[index], size: size / 2, radius: 0)
    }
}

extension PlaylistCover {
    init(playlist: PlaylistSummary, size: CGFloat, radius: CGFloat = OctoRadius.artS) {
        self.init(covers: playlist.covers, size: size, radius: radius, notice: playlist.octoNotice, id: playlist.id, name: playlist.name,
                  footer: playlistCoverFooter(playlist.songCount))
    }
}

/// A playlist line: its picture, the name, and a line under it with a cloud for one kept with
/// the server.
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
                            IconView(.cloud, size: 14, color: OctoColor.textMuted)
                                .accessibilityLabel("On your server")
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ListRow.side)
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
                            IconView(.chevron, size: 20, color: OctoColor.textMuted)
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
    /// The name of the list, for the queue's headings.
    var listName: String?
    @Environment(Player.self) private var player

    var body: some View {
        PlayShuffle(enabled: !songs.isEmpty) { player.play(songs, source: .played(listName)) } shuffle: {
            player.play(songs, source: .played(listName), shuffled: true)
        }
    }
}

/// A message in place of a page that could not load, with Try again.
struct LoadFailed: View {
    let message: String
    let retry: () async -> Void

    var body: some View {
        FailedView(message: message) { Task { await retry() } }
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
        let art = artworkOf(cover: album.coverArt, source: source)
        let isLibraryId = album.id.hasPrefix(source + ":") || source.isEmpty
        return LibraryAlbum(
            id: isLibraryId ? album.id : prefixed(album.id), sourceId: source,
            nativeId: isLibraryId ? String(album.id.dropFirst(source.isEmpty ? 0 : source.count + 1)) : album.id,
            title: album.name, searchKey: searchKey(album.name), sortKey: sortKey(album.name), artist: album.byline,
            artistId: prefixed(album.artistId), year: album.year, songCount: album.songCount,
            durationMs: Int64(album.duration) * 1_000, addedAt: 0, artwork: art)
    }
}

/// How far list rows sit from the screen's sides: songs, artists and playlists run close to the
/// edges, and a picked row's pill closer still.
enum ListRow {
    static let side: CGFloat = 12
    static let pickInset: CGFloat = 4
}
