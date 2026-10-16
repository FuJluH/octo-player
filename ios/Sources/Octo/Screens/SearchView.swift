import OctoKit
import SwiftUI

/// Search: its field under the title, the kinds to search, the "Library songs only" chip, recent
/// searches and the chart while the field is empty, then each kind as one list: the library's
/// answers first and, on a server, what it found beyond the library right after them.
struct SearchView: View {
    @Environment(Session.self) private var session
    @Environment(Player.self) private var player
    @Environment(Downloads.self) private var downloads
    @Environment(Discovery.self) private var discovery
    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @State private var model = SearchModel()
    @State private var listWidth: CGFloat = 390
    private var libraryOnly: Bool { AppSettings.shared.player.libraryOnly }
    @AppStorage(SearchModel.hintAddedKey) private var hintAdded = false
    @AppStorage(SearchModel.hintShownKey) private var hintShown = 0
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            ScreenTitle("Search")
            field
            Picker("Show", selection: $model.filter) {
                ForEach(SearchFilter.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            if model.signedIn {
                OnOffChip(text: LibraryOnlyWords.setting, on: libraryOnly) { AppSettings.shared.setLibraryOnly(!libraryOnly) }
                    .padding(.leading, 20)
                    .padding(.top, 10)
            }
            if looksLikeRadioSearch(trimmed) { liveRadioRow }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.top, 8)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { listWidth = $0 }
        .onAppear { model.attach(discovery: discovery, player: player, downloads: downloads) }
        .onChange(of: session.activeId) { _, _ in model.serverChanged() }
        .onChange(of: session.client == nil) { _, _ in model.serverChanged() }
        .onChange(of: library.stamp(.playlists)) { _, _ in model.playlistsChanged() }
        .onChange(of: router.searchText, initial: true) { _, asked in
            guard let asked else { return }
            router.searchText = nil
            model.text = asked
        }
        .background { WakeWatch(alsoOnActive: true) { model.shownAgain() } }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .driveSearch)) { note in
            if let text = note.object as? String { model.text = text }
        }
        .onReceive(NotificationCenter.default.publisher(for: .driveSearchKind)) { note in
            if let raw = note.object as? Int, let kind = SearchFilter(rawValue: raw) { model.filter = kind }
        }
        #endif
    }

    // MARK: The field

    private var field: some View {
        @Bindable var model = model
        return HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                if model.text.isEmpty {
                    Text("Songs, albums, artists")
                        .font(.octoBody)
                        .foregroundStyle(OctoColor.textMuted)
                        .lineLimit(1)
                        .accessibilityHidden(true)
                }
                TextField("", text: $model.text)
                    .font(.octoBody)
                    .foregroundStyle(.white)
                    .tint(OctoColor.accent)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($focused)
                    .onSubmit { focused = false }
                    .accessibilityLabel("Songs, albums, artists")
            }
            if !model.text.isEmpty {
                Button { model.text = "" } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(OctoColor.textMuted)
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, model.text.isEmpty ? 14 : 4)
        .frame(height: 48)
        .background(OctoColor.accent.opacity(focused ? 0.15 : 0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(OctoColor.accent.opacity(0.10), lineWidth: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(OctoColor.accent.opacity(focused ? 0.60 : 0), lineWidth: 1.5)
        }
        .animation(.easeOut(duration: 0.2), value: focused)
        .padding(.horizontal, 20)
    }

    /// Words about radio offer the live stations near the listener above the results.
    private var liveRadioRow: some View {
        NavigationLink(value: Route.liveRadioNear) {
            HStack(spacing: 14) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(OctoColor.accent)
                    .frame(width: 40, height: 40)
                    .glassEffect(Glass.octo, in: .circle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live radio near you").font(.octoBodySmall).foregroundStyle(.white)
                    Text("Stations on the air around you").font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(OctoColor.textMuted)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 56)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transition(.opacity)
    }

    // MARK: What shows under it

    private var top: RankedSongs<Song>? {
        libraryOnly ? model.topSongs?.inLibraryOnly(outside: \.isExternal) : model.topSongs
    }

    private var chart: RankedSongs<Song>? {
        libraryOnly ? model.chart?.inLibraryOnly(outside: \.isExternal) : model.chart
    }

    /// What the server found, of the kinds the filter shows, less any song the library results
    /// already list. "Library songs only" leaves it all out.
    private var online: DiscoverState {
        libraryOnly ? .idle : model.discover.only(model.filter).without(model.results?.listedFinds ?? [])
    }

    private var trimmed: String { model.text.trimmingCharacters(in: .whitespacesAndNewlines) }

    @ViewBuilder
    private var content: some View {
        let online = online
        if trimmed.isEmpty && (!model.recent.isEmpty || chart != nil) {
            recentList
        } else if let found = model.results {
            if found.isEmpty && online.showsNothing {
                SearchHint(text: "No results for \"\(trimmed)\"")
            } else {
                resultsList(found, online)
            }
        } else {
            SearchHint(text: model.signedIn ? "Search your music and discover more" : "Search the music on your phone")
        }
    }

    // MARK: Recent searches and the chart

    private var recentList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !model.recent.isEmpty {
                    TitleRow(title: "Recent searches", action: "Clear all") { model.forgetAll() }
                }
                ForEach(model.recent, id: \.self) { query in
                    HStack(spacing: 0) {
                        Button {
                            focused = false
                            model.searchAgain(query)
                        } label: {
                            Text(query)
                                .font(.octoBody)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Search again")
                        Button { model.forget(query) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(OctoColor.textMuted)
                                .frame(width: 40, height: 40)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(query)")
                    }
                    .frame(height: 48)
                    .padding(.leading, 20)
                    .padding(.trailing, 8)
                    .transition(.opacity)
                }
                if let chart {
                    rankedSection("chart", "Popular right now", chart, shown: topChartShown, open: chartOpen,
                                  withArtist: true, spaced: !model.recent.isEmpty)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.recent)
            .padding(.top, 12)
            .padding(.bottom, 140)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var chartOpen: Binding<Bool> { Binding(get: { model.chartOpen }, set: { model.chartOpen = $0 }) }
    private var topOpen: Binding<Bool> { Binding(get: { model.topOpen }, set: { model.topOpen = $0 }) }

    // MARK: Results

    private func resultsList(_ found: LibraryResults, _ online: DiscoverState) -> some View {
        ScrollViewReader { proxy in
            // A list, so the song rows take the system's swipes.
            LibraryList {
                Color.clear.frame(height: 0).id("top")
                if model.filter == .all {
                    everything(found, online)
                } else {
                    oneKind(found, online)
                }
            }
            .contentMargins(.top, 12, for: .scrollContent)
            .barClearance()
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: model.filter) { _, _ in proxy.scrollTo("top", anchor: .top) }
        }
        // Songs from the library and from the server can be picked together.
        .selectableSongs(pickable(found, online))
    }

    /// Every song shown, library ones first, then the finds and the top songs, each once.
    private func pickable(_ found: LibraryResults, _ online: DiscoverState) -> [Pickable] {
        let finds: [Song] = if case .done(let discovered) = online { discovered.songs.map(\.asSong) } else { [] }
        var seen = Set<String>()
        return (found.songs.map(\.asSong) + finds + (top?.songs.map(\.track) ?? []))
            .filter { seen.insert($0.id).inserted }
            .map { Pickable($0) }
    }

    /// A few of every kind, each kind one list: the library's first, then what the server found
    /// online. Songs come right under the artists, so songs found online are on the first screen
    /// whatever the library holds: a few library songs, then a few finds, or, while the server
    /// looks, a line that says so over rows that hold their place. An artist the library lacks joins
    /// the row of library artists, or, when there is none, gets a row of its own lower down, so
    /// nothing above the songs moves when it arrives.
    @ViewBuilder
    private func everything(_ found: LibraryResults, _ online: DiscoverState) -> some View {
        let finds = online.finds
        let onlineSongs = (finds?.songs ?? []).map(\.asSong)
        let onlineArtists = finds?.artists ?? []
        let onlineAlbums = (finds?.partAlbums ?? []) + (finds?.albums ?? [])
        let look = online.look(count: onlineSongs.count)
        let showsSongs = songsShown(library: found.songs.count, look: look)
        let firstIsArtists = !found.artists.isEmpty
        if !found.artists.isEmpty {
            kindTitle("Artists", more: found.moreArtists, kind: .artists, spaced: false)
            SideScroller {
                ForEach(found.artists) { artist in
                    ArtistCircle(id: artist.pageId(discovery.sourceId), name: artist.name, coverArt: coverId(of: artist.artwork),
                                 library: artist)
                        .simultaneousGesture(TapGesture().onEnded { model.keepSearch() })
                }
                ForEach(onlineArtists) { artist in
                    OnlineArtistCircle(id: artist.id, name: artist.name, coverArt: coverId(of: artist.artwork)) { model.keepSearch() }
                }
            }
        }
        if showsSongs {
            let more = moreSongsThanShown(library: found.songs.count + (found.moreSongs ? 1 : 0), online: onlineSongs.count)
            kindTitle("Songs", more: more, kind: .songs, spaced: firstIsArtists)
            songRows(found, limit: librarySongsShown, addSpace: online.wanted)
            outsideRows(look, kind: "songs", songs: Array(onlineSongs.prefix(onlineSongsShown)))
        }
        if let top {
            rankedSection("top", "Top songs", top, shown: searchTopShown, open: topOpen, withArtist: false, spaced: true)
        }
        if !found.albums.isEmpty || !onlineAlbums.isEmpty {
            kindTitle("Albums", more: found.moreAlbums, kind: .albums, spaced: firstIsArtists || showsSongs || top != nil)
            SideScroller {
                ForEach(found.albums) { album in
                    AlbumCard(album: album.asAlbum)
                        .simultaneousGesture(TapGesture().onEnded { model.keepSearch() })
                }
                ForEach(onlineAlbums) { OnlineAlbumCard(album: $0) { model.keepSearch() } }
            }
        }
        if !found.playlists.isEmpty {
            kindTitle("Playlists", more: found.morePlaylists, kind: .playlists, spaced: true)
            playlistRows(found)
        }
        if found.artists.isEmpty && !onlineArtists.isEmpty {
            kindTitle("Artists", more: false, kind: .artists, spaced: true)
            SideScroller {
                ForEach(onlineArtists) { artist in
                    OnlineArtistCircle(id: artist.id, name: artist.name, coverArt: coverId(of: artist.artwork)) { model.keepSearch() }
                }
            }
        }
    }

    private func playlistRows(_ found: LibraryResults) -> some View {
        ForEach(found.playlists) { summary in
            if let playlist = summary.asPlaylist(discovery.sourceId) {
                PlaylistListRow(summary: summary, playlist: playlist) { model.keepSearch() }
            }
        }
    }

    /// Library songs, the first `limit` of them. Beside songs found online they keep the add
    /// button's space empty, so the lengths line up.
    private func songRows(_ found: LibraryResults, limit: Int = .max, addSpace: Bool) -> some View {
        let shown = Array(found.songs.prefix(limit))
        let songs = found.songs.map(\.asSong)
        return ForEach(Array(shown.enumerated()), id: \.element.id) { position, track in
            SongRow(song: songs[position], list: songs, position: position, offersAdd: addSpace, addSpace: addSpace,
                    tap: { model.playSong(track) })
        }
    }

    private func kindTitle(_ text: String, more: Bool, kind: SearchFilter, spaced: Bool) -> some View {
        TitleRow(title: text, action: more ? "See all" : nil, top: spaced ? 12 : 0) { model.filter = kind }
    }

    /// All of one kind, as one list: rows for songs, artists and playlists, and covers two to a row
    /// for albums, the library's first and then those found online, with the line about looking
    /// online after them.
    @ViewBuilder
    private func oneKind(_ found: LibraryResults, _ online: DiscoverState) -> some View {
        let finds = online.finds
        switch model.filter {
        case .artists:
            ForEach(found.artists) { artist in
                ArtistListRow(id: artist.pageId(discovery.sourceId), name: artist.name, coverArt: coverId(of: artist.artwork),
                              albumCount: artist.albumCount, library: artist) { model.keepSearch() }
            }
            let artists = finds?.artists ?? []
            ForEach(artists) { artist in
                ArtistListRow(id: artist.id, name: artist.name, coverArt: coverId(of: artist.artwork), albumCount: artist.albumCount,
                              outside: true) { model.keepSearch() }
            }
            outsideRows(online.look(count: artists.count), kind: "artists", songs: [])
        case .albums:
            let width = max(100, (listWidth - 40 - 14) / 2)
            let cards = found.albums.map { AlbumItem.library($0) } + ((finds?.partAlbums ?? []) + (finds?.albums ?? [])).map { AlbumItem.online($0) }
            ForEach(Array(stride(from: 0, to: cards.count, by: 2)), id: \.self) { start in
                HStack(alignment: .top, spacing: 14) {
                    ForEach(cards[start..<min(start + 2, cards.count)]) { card in
                        switch card {
                        case .library(let album):
                            AlbumCard(album: album.asAlbum, width: width)
                                .simultaneousGesture(TapGesture().onEnded { model.keepSearch() })
                        case .online(let album):
                            OnlineAlbumCard(album: album, width: width) { model.keepSearch() }
                        }
                    }
                    if start + 1 >= cards.count { Spacer(minLength: 0) }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
            }
            outsideRows(online.look(count: cards.count - found.albums.count), kind: "albums", songs: [])
        case .playlists:
            playlistRows(found)
        default:
            songRows(found, addSpace: online.wanted)
            let songs = (finds?.songs ?? []).map(\.asSong)
            outsideRows(online.look(count: songs.count), kind: "songs", songs: songs)
        }
    }

    // MARK: Ranked lists

    /// A ranked list: its title, with "Show all" when it has more than `shown`, a quiet line saying
    /// what it is ranked by, and its songs, each with its place and cover, and the add button for
    /// a song not in the library. A tap plays the list from that song.
    @ViewBuilder
    private func rankedSection(_ key: String, _ title: String, _ list: RankedSongs<Song>, shown: Int, open: Binding<Bool>,
                               withArtist: Bool, spaced: Bool) -> some View {
        let action: String? = list.songs.count <= shown ? nil : (open.wrappedValue ? "Show fewer" : "Show all")
        TitleRow(title: title, action: action, top: spaced ? 12 : 0) { open.wrappedValue.toggle() }
        let about = [withArtist ? nil : list.artist, rankedBy(list.source)].compactMap { $0 }.joined(separator: " · ")
        if !about.isEmpty {
            Text(about)
                .font(.octoCaption)
                .foregroundStyle(OctoColor.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
        }
        let rows = open.wrappedValue ? list.songs : Array(list.songs.prefix(shown))
        let all = list.songs.map(\.track)
        ForEach(Array(rows.enumerated()), id: \.element.track.id) { _, ranked in
            let index = list.songs.firstIndex { $0.track.id == ranked.track.id } ?? 0
            SongRow(song: ranked.track, list: all, position: index, offersAdd: true, addSpace: true, rank: ranked.rank,
                    describe: { shownSong in
                        [withArtist && !(shownSong.artist ?? "").isEmpty ? shownSong.byline : nil,
                         rowAlbum(shownSong).isEmpty ? nil : rowAlbum(shownSong),
                         ranked.plays.map(playsText)].compactMap { $0 }.joined(separator: " • ")
                    }) { model.playRanked(list, index) }
                .id("\(key):\(ranked.track.id)")
        }
    }

    // MARK: Beyond the library

    /// Under the library's results of a kind: while the server looks, a line saying so over rows
    /// that hold the finds' place; when it found songs, the same line, quieter, the first few times a
    /// line saying what the plus does, then the songs; when it found none, or could not be asked, a line that says so
    /// plainly, with Try again for the second.
    @ViewBuilder
    private func outsideRows(_ look: OutsideLook, kind: String, songs: [Song]) -> some View {
        switch look {
        case .off:
            EmptyView()
        case .looking:
            OutsideLine(look: look, text: outsideLine(look, query: trimmed, kind: kind) ?? "")
            ForEach(0..<waitingRows, id: \.self) { n in WaitingRow(round: kind == "artists", n: n) }
        case .noneFound:
            OutsideLine(look: look, text: outsideLine(look, query: trimmed, kind: kind) ?? "")
        case .failed:
            OutsideLine(look: look, text: outsideLine(look, query: trimmed, kind: kind) ?? "", retry: model.retryOnline)
        case .found:
            // The line stays where it said it was looking, quieter, over the finds that took the
            // waiting rows' places.
            if !songs.isEmpty { OutsideLine(look: look, text: outsideLine(look, query: trimmed, kind: kind) ?? "") }
            if showsHint && !songs.isEmpty {
                Text("Tap + to add a song to your library.")
                    .font(.octoCaption)
                    .foregroundStyle(OctoColor.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 2)
                    .onAppear { model.hintSeen() }
            }
            ForEach(Array(songs.enumerated()), id: \.element.id) { position, song in
                SongRow(song: song, list: songs, position: position, offersAdd: true, addSpace: true,
                        tap: { model.playFound(song) })
                    .id("discover:\(song.id)")
            }
        }
    }

    /// The add hint line shows the first few visits, until a song has been added.
    private var showsHint: Bool {
        showsAddHint(AddHintState(shown: hintShown, added: hintAdded), countedThisVisit: model.hintCounted)
    }
}

private extension DiscoverState {
    /// What the server found, once it answered.
    var finds: Discovered? {
        if case .done(let found) = self { return found }
        return nil
    }

    /// Whether the server is asked at all, so library songs keep the add button's space and their
    /// lengths line up with the finds'.
    var wanted: Bool {
        if case .idle = self { return false }
        return true
    }
}

/// A library album or one found online, for the grid of albums.
private enum AlbumItem: Identifiable {
    case library(LibraryAlbum)
    case online(OnlineAlbum)

    var id: String {
        switch self {
        case .library(let album): album.id
        case .online(let album): "online:\(album.id)"
        }
    }
}

/// The line between the library's results and the server's, on the rows' lines: its mark centered
/// where their covers are, its words where their titles start. A small spinner while the server
/// looks, a warning mark and Try again when it could not be asked, the plus over the finds.
private struct OutsideLine: View {
    let look: OutsideLook
    let text: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                switch look {
                case .looking:
                    ProgressView().controlSize(.small).tint(OctoColor.accent)
                case .failed:
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                case .found:
                    Image(systemName: "plus").foregroundStyle(OctoColor.textMuted)
                default:
                    Image(systemName: "magnifyingglass").foregroundStyle(OctoColor.textMuted)
                }
            }
            .font(.system(size: 15, weight: .medium))
            .frame(width: 44, height: 18)
            .accessibilityHidden(true)
            Text(text)
                .font(.octoBodySmall)
                .foregroundStyle(look == .failed ? .white : look == .found ? OctoColor.textMuted : OctoColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                Button("Try again", action: retry)
                    .font(.octoBodySmall.weight(.semibold))
                    .foregroundStyle(OctoColor.accent)
                    .buttonStyle(.plain)
            }
        }
        .frame(minHeight: 48)
        .padding(.leading, ListRow.side)
        .padding(.trailing, 16)
        .accessibilityElement(children: .combine)
    }
}

/// A row that holds a find's place while the server looks: the shape of a song row (or an
/// artist's, round), in the faint fill of an empty cover, breathing slowly unless motion is
/// reduced, its lines a little longer or shorter from row to row.
private struct WaitingRow: View {
    let round: Bool
    let n: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        let fill = Color.white.opacity(0.10)
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: round ? 24 : OctoRadius.artS, style: .continuous)
                .fill(fill)
                .frame(width: round ? 48 : 44, height: round ? 48 : 44)
            VStack(alignment: .leading, spacing: 7) {
                Capsule().fill(fill).frame(width: [150, 118, 170, 132][n % 4], height: 11)
                Capsule().fill(fill).frame(width: [96, 84, 110, 72][n % 4], height: 9)
            }
            Spacer(minLength: 0)
        }
        .opacity(dim ? 0.45 : 1)
        .padding(.horizontal, ListRow.side)
        .padding(.vertical, 4)
        .frame(minHeight: round ? 64 : 56)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
        }
    }
}

#if DEBUG
extension Notification.Name {
    /// Sets Search's field, from a launch step.
    static let driveSearch = Notification.Name("octo.drive.search")
    /// Picks what Search shows, from a launch step.
    static let driveSearchKind = Notification.Name("octo.drive.search.kind")
}
#endif
