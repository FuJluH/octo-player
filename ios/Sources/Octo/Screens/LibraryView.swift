import OctoKit
import SwiftUI

/// One way into the library, like Albums or Songs.
private struct LibrarySection {
    let icon: String
    let label: String
    let route: Route
}

private let librarySections = [
    LibrarySection(icon: "music.note.list", label: "Playlists", route: .playlists),
    LibrarySection(icon: "heart", label: "Favorites", route: .favorites),
    LibrarySection(icon: "music.microphone", label: "Artists", route: .artists),
    LibrarySection(icon: "square.stack", label: "Albums", route: .albums),
    LibrarySection(icon: "music.note", label: "Songs", route: .library(.songs)),
    LibrarySection(icon: "guitars", label: "Genres", route: .library(.genres)),
    LibrarySection(icon: "folder", label: "Folders", route: .library(.folders)),
    LibrarySection(icon: "arrow.down.circle", label: "Downloads", route: .library(.downloads)),
    LibrarySection(icon: "clock.arrow.circlepath", label: "History", route: .library(.history(mostPlayed: false))),
    LibrarySection(icon: "checkmark.seal", label: "Library health", route: .library(.health)),
]

/// The library's front page: a menu of ways in, then the newest albums, two covers to a row.
struct LibraryView: View {
    @Environment(Library.self) private var library
    @Environment(Downloads.self) private var downloads
    @Environment(Router.self) private var router
    @State private var recent: [LibraryAlbum] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ScreenTitle("Library")
                ForEach(Array(librarySections.enumerated()), id: \.offset) { index, section in
                    if index > 0 { LibraryHairline() }
                    NavigationLink(value: section.route) {
                        SectionRow(icon: section.icon, label: section.label)
                    }
                    .buttonStyle(PressSqueeze())
                }
                if downloads.keepsLog {
                    LibraryHairline()
                    Button { router.showServerDownloads() } label: {
                        SectionRow(icon: MenuIcon.cloud, label: "Server downloads",
                                   detail: downloads.asked.isEmpty ? nil : "\(downloads.asked.count) on the way")
                    }
                    .buttonStyle(PressSqueeze())
                }
                if !recent.isEmpty {
                    SectionTitle("Recently added").padding(.top, 24)
                    ForEach(Array(stride(from: 0, to: recent.count, by: 2)), id: \.self) { start in
                        HStack(alignment: .top, spacing: 14) {
                            GridAlbumCard(album: recent[start])
                            if start + 1 < recent.count {
                                GridAlbumCard(album: recent[start + 1])
                            } else {
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                    }
                }
            }
        }
        .barClearance()
        .libraryRefreshable()
        .task(id: library.stamp(.library)) { recent = await library.recentAlbums(limit: 20) }
    }
}

/// One row of the front page's menu: an accent icon, the label, an optional detail and a chevron.
private struct SectionRow: View {
    let icon: String
    let label: String
    var detail: String?

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 19))
                .foregroundStyle(OctoColor.accent)
                .frame(width: 24, height: 24)
            Text(label).font(.octoBody).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
            if let detail { Text(detail).font(.octoCaption).foregroundStyle(OctoColor.textMuted) }
            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(OctoColor.textMuted)
                .frame(width: 22, height: 22)
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
        .contentShape(Rectangle())
    }
}

/// A hairline between menu rows, starting under the labels.
struct LibraryHairline: View {
    var leading: CGFloat = 60
    var trailing: CGFloat = 20

    var body: some View {
        Rectangle().fill(LibraryLook.hairline).frame(height: 1).padding(.leading, leading).padding(.trailing, trailing)
    }
}

extension View {
    /// Pull to refresh: syncs the server in use and reads the page again, together. A second
    /// pull while one runs is ignored; the server's problem is said, since the pull asked for it.
    func libraryRefreshable(_ reload: (@MainActor () async -> Void)? = nil) -> some View {
        modifier(LibraryRefresh(reload: reload))
    }
}

private struct LibraryRefresh: ViewModifier {
    let reload: (@MainActor () async -> Void)?
    @Environment(ServerSync.self) private var sync
    @Environment(Downloads.self) private var downloads
    @Environment(Router.self) private var router
    @Environment(Session.self) private var session
    @State private var running = false

    func body(content: Content) -> some View {
        content.refreshable {
            guard !running else { return }
            running = true
            defer { running = false }
            async let progress: Void = downloads.refreshProgress()
            async let page: Void = reload?() ?? ()
            if session.client != nil, let problem = await sync.syncNowAndWait() { router.show(problem) }
            _ = await (progress, page)
        }
    }
}

// MARK: Shared list page frame

/// The play line under a list page's title: the count, room for one quiet action, then the small
/// Play pill and Shuffle button.
struct ListPlayLine<Extra: View>: View {
    let count: String
    let play: () -> Void
    let shuffle: () -> Void
    @ViewBuilder var extra: Extra

    var body: some View {
        HStack(spacing: 6) {
            Text(count)
                .font(.octoCaption)
                .foregroundStyle(OctoColor.textMuted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            extra
            PlayPills(play: play, shuffle: shuffle)
        }
        .padding(.leading, 20)
        .padding(.trailing, 13)
        .padding(.bottom, 6)
    }
}

extension ListPlayLine where Extra == EmptyView {
    init(count: String, play: @escaping () -> Void, shuffle: @escaping () -> Void) {
        self.init(count: count, play: play, shuffle: shuffle) { EmptyView() }
    }
}

/// Runs of rows under their letters, for a list ordered by name.
struct LetterRuns<Item, Row: View>: View {
    let items: [Item]
    let headings: [String]?
    let id: (Item) -> String
    @ViewBuilder let row: (Int, Item) -> Row

    var body: some View {
        if let headings, headings.count == items.count {
            let runs = letterRuns(headings)
            ForEach(Array(runs.enumerated()), id: \.offset) { index, run in
                Section {
                    ForEach(run.start..<(run.start + run.count), id: \.self) { position in
                        row(position, items[position]).id(id(items[position]))
                    }
                } header: {
                    LetterHeading(letter: run.letter).id("run-\(index)")
                }
            }
        } else {
            ForEach(Array(items.enumerated()), id: \.offset) { position, item in
                row(position, item).id(id(item))
            }
        }
    }
}

/// Where the letter rail jumps in a list with headings: each letter's first run.
func railTargets(_ headings: [String]?) -> [RailStop] {
    guard let headings else { return [] }
    var seen = Set<Character>()
    return letterRuns(headings).enumerated().compactMap { index, run in
        seen.insert(run.letter).inserted ? RailStop(run.letter, index) : nil
    }
}

extension View {
    /// The letter rail beside a long list ordered by name, clear of the floating bar.
    func letterRail(_ headings: [String]?, count: Int, byName: Bool, jump: @escaping (Int) -> Void) -> some View {
        overlay(alignment: .trailing) {
            if byName, count >= railMinItems, let headings {
                LetterRail(stops: railTargets(headings), jump: jump)
                    .padding(.top, 8)
                    .padding(.bottom, 132)
            }
        }
    }
}

// MARK: Albums

/// Every album, as a grid of covers, in the chosen order.
struct AlbumsView: View {
    @Environment(Library.self) private var library
    @Environment(LibraryState.self) private var state
    @Environment(LibraryActions.self) private var actions
    @Environment(Router.self) private var router
    @State private var sorted: Sorted<LibraryAlbum>?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        let order = state.order(.albums)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TitleWithButtons(title: "Albums") { SortButton(list: .albums) }
                        .padding(.top, detailTopGap)
                    if let sorted {
                        if sorted.items.isEmpty {
                            EmptyLibraryNote()
                        } else {
                            ListPlayLine(count: countText(sorted.items.count, "album", "albums")) {
                                playAll(sorted.items, shuffled: false)
                            } shuffle: {
                                Task { actions.play(await library.tracks(), shuffled: true) }
                            } extra: {
                                QuietButton("Random album") {
                                    if let album = sorted.items.randomElement() { router.go(.album(album.asAlbum)) }
                                }
                            }
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                                ForEach(sorted.items) { album in GridAlbumCard(album: album).id(album.id) }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                            .padding(.bottom, 140)
                            .animation(.easeOut(duration: 0.25), value: sorted.items.map(\.id))
                        }
                    } else {
                        LibrarySpinner()
                    }
                }
            }
            .letterRail(sorted?.headings, count: sorted?.items.count ?? 0, byName: order.by.byName) { index in
                if let items = sorted?.items, let headings = sorted?.headings {
                    let runs = letterRuns(headings)
                    if runs.indices.contains(index) { proxy.scrollTo(items[runs[index].start].id, anchor: .top) }
                }
            }
            .onChange(of: order) { _, _ in if let first = sorted?.items.first { proxy.scrollTo(first.id, anchor: .top) } }
        }
        .barClearance()
        .libraryRefreshable()
        .task(id: "\(library.stamp(.library, .plays))|\(order.by.id)|\(order.descending)") {
            sorted = await library.sortedAlbums(order)
        }
    }

    /// Plays every album in the order shown, each album's songs in album order.
    private func playAll(_ albums: [LibraryAlbum], shuffled: Bool) {
        Task {
            let places = await library.trackPlaces()
            let ids = songsInGroupOrder(places, groupOf: \.albumId, groups: albums.map(\.id))
            actions.play(await library.tracks(ids: ids), shuffled: shuffled)
        }
    }
}

// MARK: Artists

/// Every artist, in the chosen order, under letters when by name.
struct ArtistsView: View {
    @Environment(Library.self) private var library
    @Environment(LibraryState.self) private var state
    @Environment(LibraryActions.self) private var actions
    @State private var sorted: Sorted<LibraryArtist>?

    var body: some View {
        let order = state.order(.artists)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    TitleWithButtons(title: "Artists") { SortButton(list: .artists) }
                        .padding(.top, detailTopGap)
                    if let sorted {
                        if sorted.items.isEmpty {
                            EmptyLibraryNote()
                        } else {
                            ListPlayLine(count: countText(sorted.items.count, "artist", "artists")) {
                                playAll(sorted.items)
                            } shuffle: {
                                Task { actions.play(await library.tracks(), shuffled: true) }
                            }
                            LetterRuns(items: sorted.items, headings: sorted.headings, id: \.id) { _, artist in
                                ArtistRow(artist: artist)
                            }
                            Color.clear.frame(height: 140)
                        }
                    } else {
                        LibrarySpinner()
                    }
                }
            }
            .letterRail(sorted?.headings, count: sorted?.items.count ?? 0, byName: order.by.byName) { index in
                proxy.scrollTo("run-\(index)", anchor: .top)
            }
            .onChange(of: order) { _, _ in if let first = sorted?.items.first { proxy.scrollTo(first.id, anchor: .top) } }
        }
        .barClearance()
        .libraryRefreshable()
        .task(id: "\(library.stamp(.library, .plays))|\(order.by.id)|\(order.descending)") {
            sorted = await library.sortedArtists(order)
        }
    }

    /// Plays every artist in the order shown, artist by artist, each album by album.
    private func playAll(_ artists: [LibraryArtist]) {
        Task {
            let places = await library.trackPlaces()
            let ids = songsInGroupOrder(places, groupOf: \.artistId, groups: artists.map(\.id))
            actions.play(await library.tracks(ids: ids))
        }
    }
}

// MARK: Favorites

/// Favorites: hearted songs, albums and artists, in three segments.
struct FavoritesView: View {
    var opening: FavoriteSegment?
    @Environment(Library.self) private var library
    @Environment(LibraryState.self) private var state
    @Environment(LibraryActions.self) private var actions
    @Environment(Router.self) private var router
    @State private var segment: FavoriteSegment?
    @State private var songs: [LibraryTrack]?
    @State private var albums: [LikedAlbum]?
    @State private var artists: [LikedArtist]?
    @State private var likedAt: [String: Int64] = [:]
    @State private var selection = SongSelection()

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    TitleWithButtons(title: "Favorites") {
                        switch segment {
                        case .songs: SortButton(list: .liked)
                        case .albums, .artists: SortButton(list: .favorites)
                        case nil: EmptyView()
                        }
                    }
                    .padding(.top, detailTopGap)
                    if let segment {
                        GlassSegments(options: FavoriteSegment.allCases.map { ($0, $0.rawValue) },
                                      selection: Binding(get: { segment }, set: { self.segment = $0 }))
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                        switch segment {
                        case .songs: songsSegment
                        case .albums: albumsSegment
                        case .artists: artistsSegment
                        }
                    } else {
                        LibrarySpinner()
                    }
                }
            }
            .onChange(of: state.order(.liked)) { _, _ in proxy.scrollTo("liked-top", anchor: .top) }
        }
        .barClearance()
        .libraryRefreshable()
        .selectable(selection, songs: (songs ?? []).map { Pickable(key: $0.id, track: $0) })
        .task(id: "\(library.stamp(.library, .likes, .favorites))|\(state.order(.liked).by.id)|\(state.order(.liked).descending)|\(state.order(.favorites).by.id)|\(state.order(.favorites).descending)") {
            await read()
        }
    }

    private func read() async {
        let liked = await library.likedTracks()
        var times: [String: Int64] = [:]
        if let rows = try? await library.store.tracks(sql: "SELECT t.*, CAST(l.likedAt AS TEXT) AS heading FROM liked_track l JOIN track t ON t.id = l.trackId") {
            for row in rows { times[row.track.id] = Int64(row.heading ?? "") ?? 0 }
        }
        likedAt = times
        let order = state.order(.liked)
        if let sorted = try? await library.store.tracks(sql: songQuery(order.by.song ?? .dateLiked, descending: order.descending, scope: .liked).sql) {
            songs = sorted.map(\.track)
        } else {
            songs = liked
        }
        let favorites = state.order(.favorites)
        albums = sortFavorites(await library.likedAlbums(), order: favorites, likedAt: \.likedAt, name: { $0.album.sortKey }, id: { $0.album.id })
        artists = sortFavorites(await library.likedArtists(), order: favorites, likedAt: \.likedAt, name: { $0.artist.sortKey }, id: { $0.artist.id })
        if segment == nil {
            segment = opening ?? firstSegment(songs: songs?.count ?? 0, albums: albums?.count ?? 0, artists: artists?.count ?? 0)
        }
    }

    @ViewBuilder
    private var songsSegment: some View {
        if let songs {
            if songs.isEmpty {
                MutedNote("No liked songs yet. Tap the heart in the player to add the song that is playing, or long press any song and choose Add to Liked songs.")
            } else {
                ListPlayLine(count: countText(songs.count, "song", "songs")) {
                    actions.play(songs)
                } shuffle: {
                    actions.play(songs, shuffled: true)
                }
                .padding(.bottom, 6)
                Color.clear.frame(height: 0).id("liked-top")
                ForEach(Array(songs.enumerated()), id: \.element.id) { position, track in
                    TrackRow(track: track, context: SongMenuContext(selecting: selection.active, selectKey: track.id),
                             selection: selection, swipe: .remove { unlike(track) }) {
                        actions.play(songs, from: position)
                    }
                }
            }
        } else {
            LibrarySpinner()
        }
    }

    /// Unlikes at once, with an Undo that likes it again at its own time, so it returns to its place.
    private func unlike(_ track: LibraryTrack) {
        let when = likedAt[track.id]
        songs?.removeAll { $0.id == track.id }
        actions.setLiked([track], false)
        router.show("Removed from Liked songs", action: "Undo") { [actions] in actions.setLiked([track], true, at: when) }
    }

    @ViewBuilder
    private var albumsSegment: some View {
        if let albums {
            if albums.isEmpty {
                MutedNote("Heart an album from its page or its menu to keep it here.")
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(albums, id: \.album.id) { liked in GridAlbumCard(album: liked.album) }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 140)
            }
        } else {
            LibrarySpinner()
        }
    }

    @ViewBuilder
    private var artistsSegment: some View {
        if let artists {
            if artists.isEmpty {
                MutedNote("Heart an artist from their page or their menu to keep them here.")
            } else {
                ForEach(artists, id: \.artist.id) { liked in ArtistRow(artist: liked.artist) }
            }
        } else {
            LibrarySpinner()
        }
    }
}

// MARK: Reading sorted lists

extension Library {
    /// Every song in an order, by the order's SQL, then by plays for the play orders.
    func sortedSongs(_ order: ListOrder, scope: SongScope = .all) async -> Sorted<LibraryTrack> {
        let sort = order.by.song ?? .title
        let query = songQuery(sort, descending: order.descending, scope: scope)
        let rows = (try? await store.tracks(sql: query.sql, args: query.args)) ?? []
        let tracks = rows.map(\.track)
        if sort.byListening {
            let listening = songListening(await playedTracks())
            return Sorted(items: byListening(tracks, id: \.id, listening: listening, mostPlayed: sort == .mostPlayed,
                                             descending: order.descending), order: order, headings: nil)
        }
        return Sorted(items: tracks, order: order, headings: sort.byName ? rows.map { $0.heading ?? "" } : nil)
    }

    func sortedAlbums(_ order: ListOrder, artistId: String? = nil) async -> Sorted<LibraryAlbum> {
        let sort = order.by.album ?? .title
        let query = albumQuery(sort, descending: order.descending, artistId: artistId)
        let rows = (try? await store.albums(sql: query.sql, args: query.args)) ?? []
        let albums = rows.map(\.album)
        if sort.byListening {
            let listening = albumListening(await playedTracks(), await playedAlbums())
            return Sorted(items: byListening(albums, id: \.id, listening: listening, mostPlayed: sort == .mostPlayed,
                                             descending: order.descending), order: order, headings: nil)
        }
        return Sorted(items: albums, order: order, headings: sort.byName ? rows.map { $0.heading ?? "" } : nil)
    }

    func sortedArtists(_ order: ListOrder) async -> Sorted<LibraryArtist> {
        let sort = order.by.artist ?? .name
        let query = artistQuery(sort, descending: order.descending)
        let rows = (try? await store.artists(sql: query.sql, args: query.args)) ?? []
        let artists = rows.map(\.artist)
        if sort.byListening {
            let listening = artistListening(await playedTracks())
            return Sorted(items: byListening(artists, id: \.id, listening: listening, mostPlayed: sort == .mostPlayed,
                                             descending: order.descending), order: order, headings: nil)
        }
        return Sorted(items: artists, order: order, headings: sort.byName ? rows.map { $0.heading ?? "" } : nil)
    }
}
