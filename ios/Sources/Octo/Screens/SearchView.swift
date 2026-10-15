import OctoKit
import SwiftUI

/// Search: its field under the title, the kinds to search, the "Library songs only" chip, recent
/// searches and the chart while the field is empty, the library's answers first and, on a server,
/// what it found beyond the library below them.
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
                    everything(found)
                } else {
                    oneKind(found)
                }
                tail(found, online)
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

    /// The server could not be asked, so say the library has none; then what it found online.
    @ViewBuilder
    private func tail(_ found: LibraryResults, _ online: DiscoverState) -> some View {
        if found.isEmpty, case .failed = online {
            SearchHint(text: "No results for \"\(trimmed)\"")
        }
        if !online.showsNothing {
            discoverSection(online, spaced: !found.isEmpty)
        }
    }

    /// A few of every kind, each kind with "See all" when it has more, and the named artist's top
    /// songs after the artists.
    @ViewBuilder
    private func everything(_ found: LibraryResults) -> some View {
        let kinds = [!found.artists.isEmpty, !found.albums.isEmpty, !found.playlists.isEmpty, !found.songs.isEmpty]
        let firstKind = kinds.firstIndex(of: true) ?? -1
        if !found.artists.isEmpty {
            kindTitle("Artists", more: found.moreArtists, kind: .artists, spaced: firstKind != 0)
            SideScroller {
                ForEach(found.artists) { artist in
                    ArtistCircle(id: artist.pageId(discovery.sourceId), name: artist.name, coverArt: coverId(of: artist.artwork),
                                 library: artist)
                        .simultaneousGesture(TapGesture().onEnded { model.keepSearch() })
                }
            }
        }
        if let top {
            rankedSection("top", "Top songs", top, shown: searchTopShown, open: topOpen, withArtist: false, spaced: true)
        }
        if !found.albums.isEmpty {
            kindTitle("Albums", more: found.moreAlbums, kind: .albums, spaced: firstKind != 1)
            SideScroller {
                ForEach(found.albums) { album in
                    AlbumCard(album: album.asAlbum)
                        .simultaneousGesture(TapGesture().onEnded { model.keepSearch() })
                }
            }
        }
        if !found.playlists.isEmpty {
            kindTitle("Playlists", more: found.morePlaylists, kind: .playlists, spaced: firstKind != 2)
            playlistRows(found)
        }
        if !found.songs.isEmpty {
            kindTitle("Songs", more: found.moreSongs, kind: .songs, spaced: firstKind != 3)
            songRows(found)
        }
    }

    private func playlistRows(_ found: LibraryResults) -> some View {
        ForEach(found.playlists) { summary in
            if let playlist = summary.asPlaylist(discovery.sourceId) {
                PlaylistListRow(summary: summary, playlist: playlist) { model.keepSearch() }
            }
        }
    }

    /// Library songs: no add button and no empty add space.
    private func songRows(_ found: LibraryResults) -> some View {
        let songs = found.songs.map(\.asSong)
        return ForEach(Array(found.songs.enumerated()), id: \.element.id) { position, track in
            SongRow(song: songs[position], list: songs, position: position, tap: { model.playSong(track) })
        }
    }

    private func kindTitle(_ text: String, more: Bool, kind: SearchFilter, spaced: Bool) -> some View {
        TitleRow(title: text, action: more ? "See all" : nil, top: spaced ? 12 : 0) { model.filter = kind }
    }

    /// All of one kind, as a list: rows for songs, artists and playlists, and covers two to a row
    /// for albums.
    @ViewBuilder
    private func oneKind(_ found: LibraryResults) -> some View {
        ForEach(found.artists) { artist in
            ArtistListRow(id: artist.pageId(discovery.sourceId), name: artist.name, coverArt: coverId(of: artist.artwork),
                          albumCount: artist.albumCount, library: artist) { model.keepSearch() }
        }
        let width = max(100, (listWidth - 40 - 14) / 2)
        ForEach(Array(stride(from: 0, to: found.albums.count, by: 2)), id: \.self) { start in
            HStack(alignment: .top, spacing: 14) {
                ForEach(found.albums[start..<min(start + 2, found.albums.count)]) { album in
                    AlbumCard(album: album.asAlbum, width: width)
                        .simultaneousGesture(TapGesture().onEnded { model.keepSearch() })
                }
                if start + 1 >= found.albums.count { Spacer(minLength: 0) }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
        }
        playlistRows(found)
        songRows(found)
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

    /// What the server has beyond the library: albums held in part first, then songs, albums and
    /// artists under "Not in your library". While it looks, or when it cannot be reached, a quiet
    /// line says so.
    @ViewBuilder
    private func discoverSection(_ online: DiscoverState, spaced: Bool) -> some View {
        let part: [OnlineAlbum] = if case .done(let found) = online { found.partAlbums } else { [] }
        if !part.isEmpty {
            TitleRow(title: partlyInLibraryText, top: spaced ? 12 : 0)
            SideScroller {
                ForEach(part) { OnlineAlbumCard(album: $0) { model.keepSearch() } }
            }
        }
        if part.isEmpty || !(online.foundNotInLibraryEmpty) {
            TitleRow(title: notInLibraryText, top: spaced || !part.isEmpty ? 12 : 0)
            switch online {
            case .loading:
                QuietNote(text: "Looking online")
            case .failed:
                QuietNote(text: "Could not reach your server")
            case .done(let found):
                if showsHint && !found.songs.isEmpty {
                    Text("Tap + to add a song to your library.")
                        .font(.octoCaption)
                        .foregroundStyle(OctoColor.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 2)
                        .onAppear { model.hintSeen() }
                }
                if !found.songs.isEmpty {
                    let songs = found.songs.map(\.asSong)
                    FindsSubtitle(text: "Songs")
                    ForEach(Array(songs.enumerated()), id: \.element.id) { position, song in
                        // A find that turns into its library song ends like the library songs
                        // listed above, at its length.
                        SongRow(song: song, list: songs, position: position, offersAdd: true, addSpace: false,
                                tap: { model.playFound(song) })
                            .id("discover:\(song.id)")
                    }
                }
                if !found.albums.isEmpty {
                    FindsSubtitle(text: "Albums")
                    SideScroller {
                        ForEach(found.albums) { OnlineAlbumCard(album: $0) { model.keepSearch() } }
                    }
                }
                if !found.artists.isEmpty {
                    FindsSubtitle(text: "Artists")
                    SideScroller {
                        ForEach(found.artists) { artist in
                            OnlineArtistCircle(id: artist.id, name: artist.name, coverArt: coverId(of: artist.artwork)) { model.keepSearch() }
                        }
                    }
                }
            case .idle:
                EmptyView()
            }
        }
    }

    /// The add hint line shows the first few visits, until a song has been added.
    private var showsHint: Bool {
        showsAddHint(AddHintState(shown: hintShown, added: hintAdded), countedThisVisit: model.hintCounted)
    }
}

private extension DiscoverState {
    /// Nothing to list under "Not in your library" in a finished search.
    var foundNotInLibraryEmpty: Bool {
        if case .done(let found) = self { return found.notInLibraryEmpty }
        return false
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
