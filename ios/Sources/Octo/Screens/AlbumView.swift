import OctoKit
import SwiftUI

// MARK: Album

/// An album's page: the cover, the title and who it is by, the play line with the heart, Play
/// and Shuffle, sharing and downloading, then its songs disc by disc and more by the artist.
struct AlbumView: View {
    let album: Album
    @Environment(Library.self) private var library
    @Environment(LibraryState.self) private var state
    @Environment(LibraryActions.self) private var actions
    @Environment(Session.self) private var session
    @Environment(Downloads.self) private var downloads
    @Environment(Router.self) private var router
    @State private var shown: LibraryAlbum?
    @State private var tracks: [LibraryTrack] = []
    /// The server's listing with songs found online in their places, when it lists any.
    @State private var whole: [LibraryTrack]?
    @State private var more: [LibraryAlbum] = []
    @State private var highlight: String?
    @State private var onlyMine = false
    @State private var online: Album?
    /// The server album the page shares, once the look-up finds one.
    @State private var shareAlbumId: String?
    @State private var animated = AnimatedArtStore.shared
    /// The header's cover is on screen.
    @State private var coverShown = false
    /// The album on the server in use that most of the page's songs come from.
    @State private var serverAlbum: String?
    @Environment(\.shellAwake) private var awake

    /// The songs the page lists: the whole album with its finds, unless only the library's are
    /// wanted.
    private var listed: [LibraryTrack] {
        if let whole, !onlyMine, !libraryOnly { return whole }
        return tracks
    }

    /// The setting that leaves songs found online out everywhere.
    private var libraryOnly: Bool { AppSettings.shared.player.libraryOnly }

    /// Whether the page lists songs found online among the library's.
    private var mixed: Bool { whole != nil && !onlyMine && !libraryOnly }

    private var finds: [LibraryTrack] { (whole ?? []).filter(\.isFound) }

    var body: some View {
        LibraryList {
            if let shown {
                header(shown)
                about
                songs(shown)
                if !more.isEmpty {
                    Shelf(title: "More by \(shown.artist)") {
                        ForEach(more) { other in AlbumCard(album: other.asAlbum, library: other) }
                    }
                    .padding(.top, 16)
                }
            } else if let online {
                OnlineAlbum(album: online)
            }
        }
        .barClearance()
        .inlineTitle(shown?.title ?? online?.name ?? album.name)
        .pageArtwork(.album(album), shown.flatMap { coverId(of: $0.artwork) } ?? album.coverArt)
        .backStopsPicking()
        .selectableSongs(state.pickables(listed))
        .libraryRefreshable {}
        .task(id: "\(album.id)|\(library.stamp(.library, .ratings, .finds))") { await read() }
        .task(id: "\(shown?.id ?? "")|\(state.canShare)") { await lookUpShareAlbum() }
        .task(id: loopAlbumId) { _ = await animated.want(loopAlbumId) }
        .onChange(of: downloads.arrived) { _, _ in
            guard !finds.isEmpty else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(1_500))
                await read()
            }
        }
    }

    /// Finds the server album most of the page's songs came from; "Share" is hidden while it
    /// looks and when it finds none.
    private func lookUpShareAlbum() async {
        shareAlbumId = nil
        guard state.canShare, let id = shown?.id else { return }
        let found = await state.data.controls.shareableAlbumId(id)
        if !Task.isCancelled { shareAlbumId = found }
    }

    private func read() async {
        guard let found = await library.resolveAlbum(album.id) else {
            shown = nil
            if online == nil, let client = session.client, let full = try? await client.album(album.id) {
                animated.note(full.id, full.animatedArt)
                online = full
            }
            return
        }
        shown = found
        tracks = await library.albumTracks(found.id)
        serverAlbum = await state.data.controls.shareableAlbumId(found.id)
        more = await library.artistAlbums(found.artistId)
            .filter { $0.id != found.id }
            .sorted { a, b in
                let ya = a.year ?? 0, yb = b.year ?? 0
                return ya != yb ? ya > yb : a.sortKey < b.sortKey
            }
        // The album as Octo lists it now, found from its songs' copies there: the songs it marks as
        // outside the library join the library's in the server's order.
        if let listing = try? await state.data.discovery.libraryAlbum(tracks.map(\.id)) {
            let server = outsideAlbumSongs(listing.sent, listing.resolved)
            var adoptions: [String: String] = [:]
            for (serverId, trackId) in downloads.adoptions ?? [:] { adoptions[findId(serverId)] = trackId }
            whole = server.contains(where: \.isFound) ? wholeAlbum(tracks, server: server, adoptions: adoptions) : nil
        } else {
            whole = nil
        }
        highlight = await mainSong(found)
    }

    /// The album's main song: of its songs, the one that comes first in the artist's top songs on
    /// the server, by id, else by title (features left out) and artist.
    private func mainSong(_ found: LibraryAlbum) async -> String? {
        guard let client = session.client, !tracks.isEmpty, !found.artist.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let key = "\(client.credentials.username)@\(client.baseURL.absoluteString)|\(SongIdentity.key(found.artist))"
        let ranked: [TopSongRef]
        if let kept = TopSongsKept.byKey[key] {
            ranked = kept
        } else {
            let top: [Song]?
            if session.profile?.has("octoTopSongs") == true,
               let answer = try? await client.artistTopSongs(artist: found.artist, id: tracks.first?.serverArtistId,
                                                             count: albumHighlightRanked) {
                top = answer.songs
            } else {
                top = try? await client.topSongs(artist: found.artist, count: albumHighlightRanked)
            }
            // Nothing kept when the server could not be reached, so it is asked again next time.
            guard let top else { return nil }
            ranked = top.map { TopSongRef(id: $0.id, title: $0.title, artist: $0.artist ?? $0.byline) }
            TopSongsKept.byKey[key] = ranked
        }
        let hit = albumHighlight(tracks.map { (id: $0.nativeId, title: $0.title, artist: $0.artist) }, ranked)
        return hit.flatMap { native in tracks.first { $0.nativeId == native }?.id }
    }

    private func details(_ album: LibraryAlbum) -> String {
        let count = mixed ? listed.count : album.songCount
        let length = mixed ? Int(listed.reduce(0) { $0 + $1.durationMs } / 1_000) : Int(album.durationMs / 1_000)
        return [album.year.map(String.init), songsCount(count), asLength(length)].compactMap { $0 }.joined(separator: " • ")
    }

    /// The album on the server in use whose animated art the header plays: the one its songs'
    /// server copies come from, or the server's own album the page shows.
    private var loopAlbumId: String? { serverAlbum ?? online?.id }

    @ViewBuilder
    private func header(_ album: LibraryAlbum) -> some View {
        VStack(spacing: 0) {
            ArtCover(artwork: album.artwork, size: 240, radius: 10)
                .overlay {
                    if let clip = AppSettings.shared.animatedArt.onAlbumPage(animated.known(loopAlbumId)) {
                        CoverLoop(clip: clip, albumId: loopAlbumId, side: 240, radius: 10, shown: coverShown && awake)
                    }
                }
                .onAppear { coverShown = true }
                .onDisappear { coverShown = false }
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                .frame(maxWidth: .infinity)
            Text(album.title)
                .font(.octoTitle)
                .multilineTextAlignment(.center)
                .padding(.top, 20)
                .bigTitle()
            Button { router.go(.artist(id: album.artistId, name: album.artist)) } label: {
                Text(album.artist).font(.octoBody).foregroundStyle(OctoColor.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            HStack(spacing: 8) {
                Text(details(album))
                    .font(.octoCaption)
                    .foregroundStyle(OctoColor.textMuted)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                FavoriteHeart(on: state.favoriteAlbumIds.contains(album.id)) {
                    actions.setFavorite(album: album.id, !state.favoriteAlbumIds.contains(album.id))
                }
            }
            .padding(.top, 14)
            PlayShuffle(enabled: !listed.isEmpty) {
                actions.play(listed, source: album.title)
            } shuffle: {
                actions.play(listed, shuffled: true, source: album.title)
            }
            .padding(.top, 10)
            quietActions(album)
        }
        .padding(.horizontal, 20)
        .padding(.top, detailTopGap)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func quietActions(_ album: LibraryAlbum) -> some View {
        let serverOnly = tracks.filter { !$0.onPhone }
        let canShare = state.canShare && shareAlbumId != nil
        if canShare || !serverOnly.isEmpty {
            HStack(spacing: 0) {
                if canShare {
                    Menu {
                        ShareLinkItems(target: .album(album.id), title: album.title, heading: "Share \"\(album.title)\"")
                    } label: {
                        HStack(spacing: 0) {
                            QuietActionLabel(icon: .share, text: "Share")
                            if actions.makingLink?.target == .album(album.id) { LoadingSpinner(size: 18) }
                        }
                    }
                    .buttonStyle(.plain)
                }
                if !serverOnly.isEmpty {
                    let held = serverOnly.filter { state.kept($0.id) != nil }.count
                    let done = serverOnly.filter { state.kept($0.id)?.status == .done }.count
                    QuietAction(icon: held < serverOnly.count ? .download : (done < serverOnly.count ? .downloading : .downloaded),
                                text: albumDownloadLabel(songs: serverOnly.count, held: held, done: done),
                                enabled: held < serverOnly.count) {
                        state.offline.download(serverOnly.map(\.id))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, -10)
            .padding(.top, 4)
        }
        if !finds.isEmpty {
            HStack(spacing: 0) {
                addMissing
                if !libraryOnly {
                    QuietAction(icon: .library, text: "Only my songs", checked: onlyMine) { onlyMine.toggle() }
                }
                Spacer(minLength: 0)
                if let note = albumLibraryNote(inLibrary: tracks.count, songs: (whole ?? tracks).count) {
                    Text(note).font(.octoCaption).foregroundStyle(OctoColor.textMuted).lineLimit(1)
                }
            }
            .padding(.leading, -10)
        }
    }

    /// Asks the server to add every song on the album it lacks, not asked for yet.
    @ViewBuilder
    private var addMissing: some View {
        let waiting = finds.filter { downloads.state($0.asSong.id) == .none }
        if !waiting.isEmpty {
            QuietAction(icon: .addToLibrary, text: addMissingLabel(missing: waiting.count)) {
                Task { for song in waiting.map(\.asSong) { _ = await downloads.request(song) } }
            }
        } else if finds.contains(where: { downloads.state($0.asSong.id) == .requested }) {
            QuietAction(icon: .downloading, text: downloads.keepsLog ? "Adding, show downloads" : "Adding",
                        enabled: downloads.keepsLog) { router.showServerDownloads() }
        }
    }

    @ViewBuilder
    private var about: some View {
        let genre = albumGenre(tracks.map(\.genre))
        let average = averageRating(tracks.map { state.rating(of: $0) })
        if genre != nil || average != nil {
            HStack(spacing: 16) {
                if let genre {
                    Button { router.go(.library(.genre(genre))) } label: {
                        Text(genre).font(.octoCaption).foregroundStyle(OctoColor.accent).padding(.vertical, 6).padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Open genre")
                }
                if let average {
                    HStack(spacing: 4) {
                        IconView(.starFilled, size: 12, color: OctoColor.textMuted)
                        Text("\(starsText(average)) average").font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(averageRatingSpoken(average))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private func songs(_ album: LibraryAlbum) -> some View {
        let list = listed
        let discs = discGroups(list)
        ForEach(Array(discs.enumerated()), id: \.offset) { _, disc in
            if discs.count > 1 {
                Text("Disc \(disc.number)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(OctoColor.textMuted)
                    .padding(.leading, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 4)
            }
            ForEach(disc.positions, id: \.self) { position in
                let track = list[position]
                TrackRow(track: track, lead: .number(track.trackNo), subtitle: track.artist == album.artist ? "" : track.artist,
                         context: SongMenuContext(albumId: album.id), ownership: mixed, highlighted: track.id == highlight) {
                    actions.play(list, from: position, source: album.title)
                }
            }
        }
    }

    /// Songs by disc (no disc number counts as disc 1), discs in the order they first appear.
    private func discGroups(_ list: [LibraryTrack]) -> [(number: Int, positions: [Int])] {
        var order: [Int] = []
        var groups: [Int: [Int]] = [:]
        for (position, track) in list.enumerated() {
            let disc = track.discNo ?? 1
            if groups[disc] == nil { order.append(disc) }
            groups[disc, default: []].append(position)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }
}

/// The artists' top songs read for marking albums' main songs, by server, user and artist, for as
/// long as the app runs.
@MainActor
private enum TopSongsKept {
    static var byKey: [String: [TopSongRef]] = [:]
}

/// An album the library does not hold, as the server lists it.
private struct OnlineAlbum: View {
    let album: Album
    @Environment(Player.self) private var player
    @Environment(\.shellAwake) private var awake
    @State private var animated = AnimatedArtStore.shared
    @State private var coverShown = false

    var body: some View {
        VStack(spacing: 0) {
            BadgedCover(id: album.coverArt, size: 240, radius: 10, external: album.isExternal)
                .overlay {
                    if let clip = AppSettings.shared.animatedArt.onAlbumPage(animated.known(album.id)) {
                        CoverLoop(clip: clip, albumId: album.id, side: 240, radius: 10, shown: coverShown && awake)
                    }
                }
                .onAppear { coverShown = true }
                .onDisappear { coverShown = false }
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            Text(album.name).font(.octoTitle).multilineTextAlignment(.center).padding(.top, 20).bigTitle()
            Text(album.byline).font(.octoBody).foregroundStyle(OctoColor.textSecondary).padding(.top, 4)
            PlayButtons(songs: album.song).padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.top, detailTopGap)
        .padding(.bottom, 12)
        ForEach(Array(album.song.enumerated()), id: \.offset) { position, song in
            SongRow(song: song, list: album.song, position: position, showsCover: false, number: song.track ?? position + 1,
                    subtitle: song.byline == album.byline ? "" : song.byline, offersAdd: true, addSpace: true)
        }
    }
}

// MARK: Artist

/// An artist's page: the picture and name, Radio, the heart, Play and Shuffle, their songs, top
/// songs from the server, albums on their shelves, the biography and similar artists.
struct ArtistView: View {
    let id: String
    let name: String
    @Environment(Library.self) private var library
    @Environment(LibraryState.self) private var state
    @Environment(LibraryActions.self) private var actions
    @Environment(Session.self) private var session
    @Environment(Downloads.self) private var downloads
    @Environment(ArtistExtrasSource.self) private var extrasSource
    @State private var artist: LibraryArtist?
    @State private var songs: [LibraryTrack] = []
    @State private var albums: [LibraryAlbum] = []
    @State private var top: [LibraryTrack] = []
    @State private var offersAdd = false
    @State private var biography: String?
    @State private var similar: [(id: String, name: String, coverArt: String?, library: LibraryArtist?)] = []
    @State private var allSongs = false
    @State private var moreAbout = false
    @State private var aboutClipped = false
    @State private var read = false
    /// The order the albums shown are in.
    @State private var albumsOrder: ListOrder?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        let order = state.order(.artistAlbums)
        ScrollViewReader { proxy in
            LibraryList {
                header
                if !songs.isEmpty { songsSection }
                if !top.isEmpty { topSection }
                shelves
                if let biography { aboutSection(biography) }
                if !similar.isEmpty { similarSection }
                Color.clear.frame(height: 20)
            }
            .topOnNewOrder(albumsOrder) { proxy.scrollTo("albums", anchor: .top) }
        }
        .barClearance()
        .inlineTitle(artist?.name ?? name)
        .pageArtwork(.artist(id: id, name: name), artist.flatMap { coverId(of: $0.artwork) })
        .libraryRefreshable { await askAgain() }
        .task(id: "\(id)|\(library.stamp(.library, .plays))|\(order.by.id)|\(order.descending)") { await readAll() }
        .onChange(of: downloads.arrived) { _, _ in
            // A top song downloaded from here turns into a library song once its check has landed.
            Task {
                try? await Task.sleep(for: .milliseconds(1_500))
                if top.contains(where: { $0.isFound && downloads.state($0.asSong.id) == .done }) { await askAgain() }
            }
        }
    }

    private func readAll() async {
        let found = await library.resolveArtist(id, name: name)
        artist = found
        if let found {
            songs = await library.artistTracks(found.id)
            let sorted = await library.sortedAlbums(state.order(.artistAlbums), artistId: found.id)
            albums = sorted.items
            albumsOrder = sorted.order
        }
        read = true
        await readExtras()
    }

    /// A pull: what the server said about the artist is forgotten and asked for again.
    private func askAgain() async {
        guard let artist else { return }
        extrasSource.forget(artist.id)
        await readExtras()
    }

    /// Top songs, the biography and similar artists, from the server.
    private func readExtras() async {
        guard let artist, var extras = await extrasSource.forArtist(artist) else { return }
        if AppSettings.shared.player.libraryOnly { extras = extras.inLibraryOnly() }
        top = extras.topSongs
        // Once offered, kept while the page is open, so lengths do not shift when the last find
        // turns into a library song.
        offersAdd = offersAdd || top.contains(where: \.isFound)
        biography = extras.about
        var people: [(id: String, name: String, coverArt: String?, library: LibraryArtist?)] = []
        for other in extras.similar {
            var mine: LibraryArtist?
            if let id = other.libraryId { mine = await library.artist(id) }
            people.append((mine?.id ?? other.serverId, mine?.name ?? other.name, coverId(of: mine?.artwork ?? other.artwork), mine))
        }
        similar = people
    }

    private var header: some View {
        VStack(spacing: 0) {
            ArtCover(artwork: artist?.artwork, size: 160, radius: 80)
            Text(artist?.name ?? name).font(.octoTitle).multilineTextAlignment(.center).padding(.top, 16).bigTitle()
            if let artist {
                Text("\(albumsCount(artist.albumCount)) • \(songsCount(artist.songCount))")
                    .font(.octoCaption)
                    .foregroundStyle(OctoColor.textMuted)
                    .padding(.top, 4)
            }
            HStack(spacing: 0) {
                if !songs.isEmpty {
                    QuietAction(icon: .radio, text: "Radio") {
                        let seeds = songs
                        Task { await actions.startRadio(seeds: seeds) }
                    }
                    .padding(.leading, -10)
                }
                Spacer(minLength: 0)
                if let artist {
                    FavoriteHeart(on: state.favoriteArtistIds.contains(artist.id)) {
                        actions.setFavorite(artist: artist.id, !state.favoriteArtistIds.contains(artist.id))
                    }
                }
            }
            .padding(.top, 8)
            if !songs.isEmpty {
                PlayShuffle { actions.play(songs, source: artistName) } shuffle: { actions.play(songs, shuffled: true, source: artistName) }
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, detailTopGap)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var songsSection: some View {
        HStack {
            SectionTitle("Songs")
            if songs.count > 10 {
                QuietButton(allSongs ? "Show fewer" : "See all") { allSongs.toggle() }.padding(.trailing, 10)
            }
        }
        ForEach(Array(songs.prefix(allSongs ? songs.count : 10).enumerated()), id: \.element.id) { position, track in
            TrackRow(track: track, subtitle: track.album) { actions.play(songs, from: position, source: artistName) }
        }
    }

    /// The artist's name as the queue names what it plays from.
    private var artistName: String { artist?.name ?? name }

    @ViewBuilder
    private var topSection: some View {
        SectionTitle("Top songs")
        ForEach(Array(top.enumerated()), id: \.element.id) { position, track in
            TrackRow(track: track,
                     subtitle: rowAlbum(title: track.title, album: track.album, find: track.isFound),
                     context: SongMenuContext(artistId: artist?.id), offersAdd: offersAdd, addSpace: offersAdd) {
                actions.play(top, from: position, source: artistName)
            }
        }
    }

    @ViewBuilder
    private var shelves: some View {
        let groups = groupReleases(albums, types: \.types, own: { $0.artistId == (artist?.id ?? id) })
        let titled = groups.count > 1 || !songs.isEmpty || !top.isEmpty
        ForEach(Array(groups.enumerated()), id: \.offset) { index, shelf in
            if index == 0, albums.count > 1 {
                SortBar(name: titled ? shelf.group.title : nil, list: .artistAlbums).padding(.top, 8).id("albums")
            } else if titled {
                SectionTitle(shelf.group.title).padding(.top, 8)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                ForEach(shelf.items) { album in GridAlbumCard(album: album) }
            }
            .padding(.horizontal, 20)
            .animation(.easeOut(duration: 0.25), value: shelf.items.map(\.id))
        }
    }

    /// The biography, four lines at first; "More", shown only when it is cut short, shows the rest.
    private func aboutSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("About").padding(.top, 8)
            Text(text)
                .font(.octoBodySmall)
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(moreAbout ? nil : 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    // The whole text, measured where it cannot be seen, against the four lines.
                    if !moreAbout {
                        GeometryReader { shown in
                            Text(text)
                                .font(.octoBodySmall)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(width: shown.size.width, alignment: .leading)
                                .hidden()
                                .onGeometryChange(for: Bool.self) { $0.size.height > shown.size.height + 1 } action: { aboutClipped = $0 }
                        }
                    }
                }
                .padding(.horizontal, 20)
            if aboutClipped && !moreAbout {
                Button("More") { moreAbout = true }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .buttonStyle(.plain)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 20)
            }
        }
    }

    private var similarSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Similar artists").padding(.top, 8)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(similar, id: \.id) { other in
                        // One the library does not have opens as the server shows it.
                        if let mine = other.library {
                            ArtistCircle(id: other.id, name: other.name, coverArt: other.coverArt, library: mine)
                        } else {
                            OnlineArtistCircle(id: other.id, name: other.name, coverArt: other.coverArt)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
    }
}


// MARK: Playlists

/// Every playlist: ways to make or import one, then the live lists in the order they were made,
/// then the listener's own playlists and the server's in the chosen order, then, on a server that
/// runs Octo, the lists Octo made under "From Octo", by kind. A list Octo made is only there.
struct PlaylistsView: View {
    @Environment(Library.self) private var library
    @Environment(LibraryState.self) private var state
    @Environment(LibraryActions.self) private var actions
    @Environment(ServerSync.self) private var sync
    @Environment(Router.self) private var router
    @Environment(LiveListStore.self) private var liveLists
    @Environment(LiveLibrary.self) private var liveLibrary
    @Environment(Discovery.self) private var discovery
    @State private var playlists: [PlaylistSummary]?
    /// Octo's lists in their groups, kept through a failed read.
    @State private var octoGroups: [(group: OctoListGroup, lists: [Playlist])] = []
    /// The server's id for each of the listener's playlists kept in step with one.
    @State private var serverIds: [String: String] = [:]
    @State private var importing = false
    @State private var importNote: ImportNote?

    /// How the last import went, until the page closes.
    struct ImportNote {
        var working = false
        var failed = false
        var report: ImportReport?
        var showMissed = false
    }

    var body: some View {
        let order = state.order(.playlists)
        let claimed = Set(octoGroups.flatMap { $0.lists.map(\.id) })
        let gone = discovery.goneLists
        let shown = sortPlaylists(playlists ?? [], order).filter { !claimed.contains(serverIds[$0.id] ?? $0.id) }
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    FirstRowMark().id("top")
                    TitleWithButtons(title: "Playlists") { if playlists != nil { SortButton(list: .playlists) } }
                        .padding(.top, detailTopGap)
                        .bigTitle()
                    ForEach(playlistsLead(importNote: importNote != nil), id: \.self) { lead in
                        switch lead {
                        case .newPlaylist:
                            Button { actions.askNewPlaylist(.tracks([])) } label: {
                                PlaylistLine(name: "New playlist") { LeadTile(icon: .addToLibrary) }
                            }
                            .buttonStyle(SqueezeStyle())
                        case .newLiveList:
                            Button { router.go(.liveListEditor(id: nil)) } label: {
                                PlaylistLine(name: "New live list", subtitle: "Songs picked by rules, always up to date") {
                                    LiveMarkTile(size: 56, radius: OctoRadius.artS)
                                }
                            }
                            .buttonStyle(SqueezeStyle())
                        case .importFile:
                            Button { importing = true } label: {
                                PlaylistLine(name: "Import a playlist file", subtitle: "M3U or M3U8") { LeadTile(icon: .folder) }
                            }
                            .buttonStyle(SqueezeStyle())
                        case .importNote:
                            if let importNote { importNoteView(importNote) }
                        }
                    }
                    ForEach(liveLists.lists, id: \.id) { list in
                        NavigationLink(value: Route.liveList(id: list.id)) {
                            PlaylistLine(name: list.name, subtitle: liveListCoverLine) { liveCover(list) }
                        }
                        .buttonStyle(SqueezeStyle())
                        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: OctoRadius.row))
                        .contextMenu { LiveListOptionsItems(list: list) }
                    }
                    ForEach(shown) { playlist in
                        NavigationLink(value: Route.library(.playlist(id: playlist.id))) {
                            PlaylistLine(name: playlist.name, subtitle: songsCount(playlist.songCount), onServer: playlist.onServer) {
                                PlaylistCover(playlist: playlist, size: 56)
                            }
                        }
                        .buttonStyle(SqueezeStyle())
                        .id(playlist.id)
                        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: OctoRadius.row))
                        .contextMenu { CollectionMenuItems(subject: .playlist(playlist)) }
                    }
                    fromOcto
                }
                .padding(.bottom, 20)
                .animation(.easeOut(duration: 0.25), value: shown.map(\.id))
            }
            .topOnNewOrder(playlists == nil ? nil : order) { proxy.scrollTo("top", anchor: .top) }
        }
        .inlineTitle("Playlists")
        .barClearance()
        .libraryRefreshable {}
        .task { sync.syncAgain() }
        .task(id: library.stamp(.playlists, .library)) {
            let all = await library.playlists()
            var ids: [String: String] = [:]
            for summary in all where summary.onServer {
                if let serverId = await library.playlist(summary.id)?.serverId { ids[summary.id] = serverId }
            }
            serverIds = ids
            playlists = all
        }
        .task(id: "\(discovery.server ?? "")|\(library.stamp(.playlists))") {
            if let groups = try? await discovery.octoListGroups() { octoGroups = groups }
        }
        .task(id: library.stamp(.library, .likes, .plays)) { await liveLibrary.read() }
        .task(id: LiveCoversKey(version: liveLibrary.version, queries: liveLists.lists.map(\.query))) {
            for list in liveLists.lists { await liveLibrary.pick(list.query) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.m3uPlaylist, .plainText, .data]) { result in
            if case .success(let url) = result { Task { await importFile(url) } }
        }
    }

    /// The lists Octo made for the listener, under a heading for each kind. Each opens as the
    /// server has it; a station there plays as a station.
    @ViewBuilder
    private var fromOcto: some View {
        let gone = discovery.goneLists
        if octoGroups.contains(where: { $0.lists.contains { !gone.contains($0.id) } }) {
            SectionTitle("From Octo").padding(.top, 24).padding(.bottom, 4)
            ForEach(octoGroups.filter { !$0.lists.allSatisfy { gone.contains($0.id) } }, id: \.group) { entry in
                Text(entry.group.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(OctoColor.textMuted)
                    .padding(.leading, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)
                ForEach(entry.lists.filter { !gone.contains($0.id) }) { list in
                    NavigationLink(value: Route.playlist(list)) {
                        PlaylistLine(name: list.name, subtitle: songsCount(list.songCount)) {
                            Cover(id: list.coverArt ?? list.id, size: 56)
                        }
                    }
                    .buttonStyle(SqueezeStyle())
                }
            }
        }
    }

    /// A live list's picture: designed from its name on the colors of the covers of the first
    /// albums it holds now, or in the mosaic style its rules mark.
    @ViewBuilder
    private func liveCover(_ list: LiveList) -> some View {
        let songs = liveLibrary.songs(list.query) ?? []
        let covers = mosaicCovers(songs.map { (album: $0.albumId, art: $0.artwork) })
        if AppSettings.shared.playlistCovers == .designed {
            DesignedCover(id: list.id, name: list.name, covers: covers, size: 56, line: liveListCoverLine)
        } else {
            LiveMarkTile(size: 56, radius: OctoRadius.artS)
        }
    }

    @ViewBuilder
    private func importNoteView(_ note: ImportNote) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(note.working ? "Importing…" : note.failed ? "That file couldn't be read." : note.report.map(importSummary) ?? "")
                .font(.octoBodySmall)
                .foregroundStyle(OctoColor.textMuted)
            if let report = note.report, !report.missed.isEmpty {
                Button(note.showMissed ? "Hide songs not found" : "Show \(report.missed.count) not found") {
                    importNote?.showMissed.toggle()
                }
                .font(.octoCaption)
                .foregroundStyle(OctoColor.textSecondary)
                .buttonStyle(.plain)
                .padding(.vertical, 8)
                .accessibilityValue(note.showMissed ? "Shown" : "Hidden")
                if note.showMissed {
                    ForEach(Array(report.missed.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.octoCaption).foregroundStyle(OctoColor.textMuted).lineLimit(2)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    /// Reads a playlist file, finds its songs in the library and makes a playlist of them.
    private func importFile(_ url: URL) async {
        importNote = ImportNote(working: true)
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), data.count <= playlistFileLimit else {
            importNote = ImportNote(failed: true)
            return
        }
        let entries = parseM3u(playlistText(data))
        let name = playlistNameOf(url.lastPathComponent)
        let tracks = await library.tracks()
        // Where each phone song's file sits, by library id, for lines that name a file.
        let files = actions.state.data.device.files
        var paths: [String: String] = [:]
        for copy in (try? await library.store.sourceTracks(deviceSource)) ?? [] where !copy.mergedId.isEmpty {
            if let native = Int64(copy.nativeId), let path = files[native], paths[copy.mergedId] == nil { paths[copy.mergedId] = path }
        }
        let match = matchM3u(entries, library: tracks.map { M3uSong($0.id, $0.title, $0.artist, $0.durationMs) }, paths: paths)
        let found = await library.tracks(ids: match.trackIds)
        // The note under the lead lines says how it went.
        if !entries.isEmpty, !found.isEmpty { actions.state.data.playlists.create(name, trackIds: found.map(\.id)) }
        importNote = ImportNote(report: ImportReport(name, match.trackIds.count, entries.count, match.missed.map(\.shown)))
    }
}

/// A square tile for the lead lines: an icon at 40% of the tile on the quiet tile, with the rim.
private struct LeadTile: View {
    let icon: OctoIcon

    var body: some View {
        RoundedRectangle(cornerRadius: OctoRadius.artS)
            .fill(OctoColor.backgroundTertiary)
            .overlay { IconView(icon, size: 56 * 0.4, color: .white) }
            .overlay { RoundedRectangle(cornerRadius: OctoRadius.artS).strokeBorder(.white.opacity(0.1), lineWidth: 1) }
            .frame(width: 56, height: 56)
    }
}

/// The live lists whose songs are worked out for their pictures, against the library as last read.
private struct LiveCoversKey: Hashable {
    let version: Int
    let queries: [LibraryQuery]
}

// MARK: Playlist

/// A playlist opened from the server's list: its page, by the library's copy of it. One of Octo's
/// lists, and any list the library keeps no copy of, opens as the server has it.
struct PlaylistView: View {
    let playlist: Playlist
    @Environment(Library.self) private var library
    @Environment(Session.self) private var session
    @State private var id: String?
    @State private var serverOnly = false

    var body: some View {
        Group {
            if let id {
                PlaylistPage(id: id)
            } else if serverOnly {
                ServerListPage(playlist: playlist)
            } else {
                LibrarySpinner().padding(.top, detailTopGap)
            }
        }
        .task {
            if opensAsServerList(playlist, runsOcto: session.runsOcto, listener: session.client?.credentials.username ?? "") {
                serverOnly = true
                return
            }
            let all = await library.playlists()
            var match: String?
            for summary in all {
                if summary.id == playlist.id { match = summary.id; break }
                if await library.playlist(summary.id)?.serverId == playlist.id { match = summary.id; break }
            }
            if let match { id = match } else { serverOnly = true }
        }
    }
}

/// A list on the server the library keeps no copy of, like a station or a Made for you list: its
/// cover and name, Play and Shuffle, then the songs it has lined up now. It cannot be changed
/// here. A station plays as a station, from a row, Play or Shuffle alike, adding more of its
/// songs as it runs low. A list the server answers is gone says so, and leaves Home.
struct ServerListPage: View {
    let playlist: Playlist
    @Environment(Discovery.self) private var discovery
    @Environment(Player.self) private var player
    @State private var page: LoadState<[Song]> = .loading

    var body: some View {
        LoadStateView(state: page, retry: { Task { await reload() } }) { songs in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header(songs)
                    if songs.isEmpty {
                        MutedNote("Nothing is lined up on \(playlist.name) right now.", vertical: 20)
                    }
                    ForEach(Array(songs.enumerated()), id: \.element.id) { position, song in
                        SongRow(song: song, list: songs, position: position, offersAdd: true, addSpace: true, tap: {
                            play(songs, from: position)
                        })
                    }
                    Color.clear.frame(height: 20)
                }
            }
            .barClearance()
        }
        .inlineTitle(playlist.name)
        .task { if page.value == nil { await reload() } }
    }

    private func header(_ songs: [Song]) -> some View {
        let seconds = songs.reduce(0) { $0 + $1.duration }
        let details = [songsCount(songs.count), seconds > 0 ? asLength(seconds) : nil].compactMap { $0 }.joined(separator: " · ")
        return VStack(spacing: 0) {
            Cover(id: playlist.coverArt, size: 240, radius: 10)
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            Text(playlist.name).font(.octoTitle).multilineTextAlignment(.center).padding(.top, 20).bigTitle()
            Text(details)
                .font(.octoCaption)
                .foregroundStyle(OctoColor.textMuted)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 14)
            if !songs.isEmpty {
                PlayShuffle { play(songs) } shuffle: { play(songs, shuffled: true) }
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, detailTopGap)
        .padding(.bottom, 16)
    }

    private func play(_ songs: [Song], from position: Int = 0, shuffled: Bool = false) {
        player.playServerList(songs, from: position, id: playlist.id, name: playlist.name, octoGroup: playlist.octoGroup,
                              shuffled: shuffled)
    }

    private func reload() async {
        page = .loading
        do {
            page = .ready(try await discovery.stationSongs(playlist.id))
        } catch OctoError.notFound {
            discovery.listGone(playlist.id)
            page = .failed(stationGoneLine(playlist.name))
        } catch {
            // A read that was canceled keeps what the page had.
            guard let words = userMessage(for: error) else { return }
            page = .failed(words)
        }
    }
}

/// A playlist's page: its cover and name, the play line with Reorder, More, Play and Shuffle,
/// then its songs, which can be swiped away, picked, and dragged into another order by their
/// handles while reordering.
struct PlaylistPage: View {
    let id: String
    @Environment(Library.self) private var library
    @Environment(LibraryState.self) private var state
    @Environment(LibraryActions.self) private var actions
    @Environment(\.dismiss) private var dismiss
    @State private var summary: PlaylistSummary?
    @State private var rows: [PlaylistTrack] = []
    @State private var phoneOnly = 0
    @State private var read = false
    @State private var editMode: EditMode = .inactive

    private var reordering: Bool { editMode.isEditing }

    var body: some View {
        LibraryList {
            if let summary {
                header(summary)
                KeepDownloadedLine(tracks: rows.map(\.track), playlistId: summary.id)
                if summary.onServer, phoneOnly > 0 {
                    Text(phoneOnlyNote(phoneOnly))
                        .font(.octoBodySmall)
                        .foregroundStyle(OctoColor.textMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 8)
                }
                if read, rows.isEmpty {
                    MutedNote("This playlist is empty. Long press any song and choose Add to playlist.", vertical: 20)
                }
                ForEach(Array(rows.enumerated()), id: \.element.itemId) { position, row in
                    playlistRow(position, row, summary)
                }
                .onMove(perform: reordering ? { from, to in move(from, to, summary) } : nil)
                Color.clear.frame(height: 20)
            }
        }
        .environment(\.editMode, $editMode)
        .barClearance()
        .inlineTitle(summary?.name ?? "")
        .backAction(reordering ? { editMode = .inactive } : nil)
        .backStopsPicking()
        .selectableSongs(state.pickables(rows)) { picked in
            guard let summary else { return }
            actions.remove(picked.compactMap { Int64($0.key) }, from: summary)
        }
        .task(id: "\(id)|\(library.stamp(.playlists, .library))") { await readPage() }
    }

    private func readPage() async {
        let all = await library.playlists()
        guard let found = all.first(where: { $0.id == id }) else {
            if read { dismiss() }
            read = true
            return
        }
        summary = found
        rows = await state.playlistTracks(id)
        phoneOnly = (try? await library.store.phoneOnlyCount(id)) ?? 0
        read = true
    }

    @ViewBuilder
    private func header(_ playlist: PlaylistSummary) -> some View {
        let tracks = rows.map(\.track)
        let length = Int(tracks.reduce(0) { $0 + $1.durationMs } / 1_000)
        VStack(spacing: 0) {
            PlaylistCover(playlist: playlist, size: 240, radius: 10)
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            Text(playlist.name).font(.octoTitle).multilineTextAlignment(.center).padding(.top, 20).bigTitle()
            HStack(spacing: 8) {
                Text(rows.isEmpty ? "0 songs" : "\(songsCount(rows.count)) · \(asLength(length))")
                    .font(.octoCaption)
                    .foregroundStyle(OctoColor.textMuted)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if rows.count > 1 { ReorderButton(editMode: $editMode) }
                Menu {
                    PlaylistOptionsItems(playlist: playlist, serverOnly: tracks.contains { !$0.onPhone && !$0.isFound }) { dismiss() }
                } label: {
                    QuietActionLabel(icon: .more, text: "More")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More")
            }
            .padding(.top, 14)
            if !rows.isEmpty {
                PlayShuffle { actions.play(tracks, source: playlist.name) } shuffle: { actions.play(tracks, shuffled: true, source: playlist.name) }
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, detailTopGap)
        .padding(.bottom, 16)
    }

    private func playlistRow(_ position: Int, _ row: PlaylistTrack, _ playlist: PlaylistSummary) -> some View {
        TrackRow(
            track: row.track,
            context: SongMenuContext(playlistId: playlist.id, playlistItemId: row.itemId, selectKey: String(row.itemId)),
            selectKey: String(row.itemId),
            swipe: reordering ? .none : .remove {
                rows.removeAll { $0.itemId == row.itemId }
                actions.remove([row.itemId], from: playlist)
            }
        ) {
            actions.play(rows.map(\.track), from: position, source: playlist.name)
        }
    }

    /// Moves a row where it was dropped: into the place of the row that was there.
    private func move(_ from: IndexSet, _ to: Int, _ playlist: PlaylistSummary) {
        guard let start = from.first, rows.indices.contains(start) else { return }
        let item = rows[start].itemId
        var moved = rows
        moved.move(fromOffsets: from, toOffset: to)
        guard let landed = moved.firstIndex(where: { $0.itemId == item }), landed != start else { return }
        let landing = rows[landed].itemId
        rows = moved
        actions.move(item, onto: landing, in: playlist)
    }
}

/// Reorder, or Done while reordering, on a playlist page: the rows show their handles while
/// reordering. Hidden while the list is picking songs.
private struct ReorderButton: View {
    @Binding var editMode: EditMode
    @Environment(\.songSelection) private var selection

    var body: some View {
        let reordering = editMode.isEditing
        if selection?.active != true {
            QuietAction(icon: reordering ? .check : .sort, text: reordering ? "Done" : "Reorder", checked: reordering) {
                withAnimation { editMode = reordering ? .inactive : .active }
            }
        }
    }
}
