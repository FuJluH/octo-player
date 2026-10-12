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
    @State private var discTitles: [Int: String] = [:]
    @State private var more: [LibraryAlbum] = []
    @State private var highlight: String?
    @State private var onlyMine = false
    @State private var online: Album?

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
        .onChange(of: downloads.arrived) { _, _ in
            guard !finds.isEmpty else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(1_500))
                await read()
            }
        }
    }

    private func read() async {
        guard let found = await library.resolveAlbum(album.id) else {
            shown = nil
            if online == nil, let client = session.client, let full = try? await client.album(album.id) { online = full }
            return
        }
        shown = found
        tracks = await library.albumTracks(found.id)
        more = await library.artistAlbums(found.artistId)
            .filter { $0.id != found.id }
            .sorted { a, b in
                let ya = a.year ?? 0, yb = b.year ?? 0
                return ya != yb ? ya > yb : a.sortKey < b.sortKey
            }
        // The album as an Octo server lists it now: from the server album most of its songs came
        // from, with the songs the library lacks as finds in the server's order.
        if let (sent, resolved) = try? await state.data.discovery.libraryAlbum(tracks.map(\.id)) {
            let server = outsideAlbumSongs(sent, resolved)
            whole = server.contains(where: { isFind($0.id) }) ? wholeAlbum(tracks, server: server, adoptions: await library.adoptions()) : nil
        } else {
            whole = nil
        }
        if let client = session.client, isServerSource(found.sourceId), let full = try? await client.fullAlbum(found.nativeId) {
            discTitles = Dictionary(full.discTitles.map { ($0.disc, $0.title) }, uniquingKeysWith: { a, _ in a })
        }
        highlight = await mainSong(found)
    }

    /// The album's main song: the first of the artist's top songs on the server that is on this
    /// album, by id, else by title and artist.
    private func mainSong(_ found: LibraryAlbum) async -> String? {
        guard let client = session.client, !tracks.isEmpty else { return nil }
        let top: [Song]
        if session.profile?.has("octoTopSongs") == true,
           let ranked = try? await client.artistTopSongs(artist: found.artist, id: tracks.first?.serverArtistId, count: 30) {
            top = ranked.songs
        } else {
            top = (try? await client.topSongs(artist: found.artist, count: 30)) ?? []
        }
        for song in top {
            if let match = tracks.first(where: { $0.nativeId == song.id }) { return match.id }
            if let match = tracks.first(where: {
                SongIdentity.sameTitle(SongIdentity.stripFeatures($0.title), SongIdentity.stripFeatures(song.title)).isSame
                    && sameArtist($0.artist, song.artist ?? "")
            }) { return match.id }
        }
        return nil
    }

    private func details(_ album: LibraryAlbum) -> String {
        let count = mixed ? listed.count : album.songCount
        let length = mixed ? Int(listed.reduce(0) { $0 + $1.durationMs } / 1_000) : Int(album.durationMs / 1_000)
        return [album.year.map(String.init), songsCount(count), asLength(length)].compactMap { $0 }.joined(separator: " • ")
    }

    @ViewBuilder
    private func header(_ album: LibraryAlbum) -> some View {
        VStack(spacing: 0) {
            ArtCover(artwork: album.artwork, size: 240, radius: 10)
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
                actions.play(listed, name: shown?.title)
            } shuffle: {
                actions.play(listed, shuffled: true, name: shown?.title)
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
        let canShare = state.canShare && isServerSource(album.sourceId)
        if canShare || !serverOnly.isEmpty {
            HStack(spacing: 0) {
                if canShare {
                    Menu {
                        ShareLinkItems(target: .album(album.id), title: album.title)
                    } label: {
                        QuietActionLabel(icon: .share, text: "Share")
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
                Text(discTitles[disc.number].map { "Disc \(disc.number) · \($0)" } ?? "Disc \(disc.number)")
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
                    actions.play(list, from: position, name: shown?.title)
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

/// An album the library does not hold, as the server lists it.
private struct OnlineAlbum: View {
    let album: Album
    @Environment(Player.self) private var player

    var body: some View {
        VStack(spacing: 0) {
            BadgedCover(id: album.coverArt, size: 240, radius: 10, external: album.isExternal)
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
    @SceneStorage("artist.allSongs") private var allSongs = false
    @State private var moreAbout = false
    @State private var read = false

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
            .onChange(of: order) { _, _ in proxy.scrollTo("albums", anchor: .top) }
        }
        .barClearance()
        .inlineTitle(artist?.name ?? name)
        .pageArtwork(.artist(id: id, name: name), artist.flatMap { coverId(of: $0.artwork) })
        .backStopsPicking()
        .selectableSongs(state.pickables(songs))
        .libraryRefreshable {}
        .task(id: "\(id)|\(library.stamp(.library, .plays))|\(order.by.id)|\(order.descending)") { await readAll() }
        .onChange(of: downloads.arrived) { _, _ in
            Task {
                try? await Task.sleep(for: .milliseconds(1_500))
                await readExtras()
            }
        }
    }

    private func readAll() async {
        let found = await library.resolveArtist(id, name: name)
        artist = found
        if let found {
            songs = await library.artistTracks(found.id)
            albums = (await library.sortedAlbums(state.order(.artistAlbums), artistId: found.id)).items
        }
        read = true
        await readExtras()
    }

    /// Top songs, the biography and similar artists, from the server.
    private func readExtras() async {
        guard let artist, var extras = await extrasSource.forArtist(artist) else { return }
        if AppSettings.shared.player.libraryOnly { extras = extras.inLibraryOnly() }
        top = extras.topSongs
        offersAdd = top.contains(where: \.isFound)
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
                        if let artist { Task { await actions.startArtistRadio(artist.id) } }
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
                PlayShuffle { actions.play(songs, name: artist?.name ?? name) } shuffle: { actions.play(songs, shuffled: true, name: artist?.name ?? name) }
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
            TrackRow(track: track, subtitle: track.album) { actions.play(songs, from: position, name: artist?.name ?? name) }
        }
    }

    @ViewBuilder
    private var topSection: some View {
        SectionTitle("Top songs")
        ForEach(Array(top.enumerated()), id: \.element.id) { position, track in
            TrackRow(track: track,
                     subtitle: rowAlbum(title: track.title, album: track.album, find: track.isFound),
                     context: SongMenuContext(artistId: artist?.id), offersAdd: offersAdd, addSpace: offersAdd) {
                actions.play(top, from: position, name: artist?.name ?? name)
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

    private func aboutSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle("About").padding(.top, 8)
            Text(text)
                .font(.octoBodySmall)
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(moreAbout ? nil : 4)
                .padding(.horizontal, 20)
            if !moreAbout {
                Button("More") { moreAbout = true }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .buttonStyle(.plain)
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
                        ArtistCircle(id: other.id, name: other.name, coverArt: other.coverArt, external: other.library == nil,
                                     library: other.library)
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
    }
}


// MARK: Playlists

/// Every playlist: ways to make or import one, then the listener's own and the server's in the
/// chosen order.
struct PlaylistsView: View {
    @Environment(Library.self) private var library
    @Environment(LibraryState.self) private var state
    @Environment(LibraryActions.self) private var actions
    @Environment(ServerSync.self) private var sync
    @State private var playlists: [PlaylistSummary]?
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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    TitleWithButtons(title: "Playlists") { if playlists != nil { SortButton(list: .playlists) } }
                        .padding(.top, detailTopGap)
                        .bigTitle()
                    Button { actions.askNewPlaylist(.tracks([])) } label: {
                        PlaylistLine(name: "New playlist") { LeadTile(icon: .addToLibrary) }
                    }
                    .buttonStyle(SqueezeStyle())
                    if let open = LiveListHook.newLiveList {
                        Button { open(nil) } label: {
                            PlaylistLine(name: "New live list", subtitle: "Songs picked by rules, always up to date") {
                                LeadTile(icon: .filter, tinted: true)
                            }
                        }
                        .buttonStyle(SqueezeStyle())
                    }
                    Button { importing = true } label: {
                        PlaylistLine(name: "Import a playlist file", subtitle: "M3U or M3U8") { LeadTile(icon: .folder) }
                    }
                    .buttonStyle(SqueezeStyle())
                    if let importNote { importNoteView(importNote) }
                    ForEach(sortPlaylists(playlists ?? [], order)) { playlist in
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
                }
                .padding(.bottom, 20)
            }
            .onChange(of: order) { _, _ in
                if let first = sortPlaylists(playlists ?? [], order).first { proxy.scrollTo(first.id, anchor: .top) }
            }
        }
        .inlineTitle("Playlists")
        .barClearance()
        .libraryRefreshable {}
        .task { sync.syncAgain() }
        .task(id: library.stamp(.playlists, .library)) { playlists = await library.playlists() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.m3uPlaylist, .plainText, .data]) { result in
            if case .success(let url) = result { Task { await importFile(url) } }
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
        let match = matchM3u(entries, library: tracks.map { M3uSong($0.id, $0.title, $0.artist, $0.durationMs) }, paths: [:])
        let found = await library.tracks(ids: match.trackIds)
        if !entries.isEmpty, !found.isEmpty { actions.createPlaylist(name: name, tracks: found) }
        importNote = ImportNote(report: ImportReport(name, match.trackIds.count, entries.count, match.missed.map(\.shown)))
    }
}

/// A square tile for the lead lines: an icon on the quiet tile, or the live mark's tint.
private struct LeadTile: View {
    let icon: OctoIcon
    var tinted = false

    var body: some View {
        RoundedRectangle(cornerRadius: OctoRadius.artS)
            .fill(tinted ? OctoColor.accent.opacity(0.16) : OctoColor.backgroundTertiary)
            .overlay {
                IconView(icon, size: 24, color: tinted ? OctoColor.accent : .white)
            }
            .overlay { RoundedRectangle(cornerRadius: OctoRadius.artS).strokeBorder(.white.opacity(0.1), lineWidth: 1) }
            .frame(width: 56, height: 56)
    }
}

/// Where the live list editor plugs in: set by the app once it has one.
@MainActor
enum LiveListHook {
    /// Opens the live list editor, for a new list or with a page's filters to start from.
    static var newLiveList: ((LiveListSeed?) -> Void)?
}

/// What a page's filters give a new live list to start from.
struct LiveListSeed {
    var words: String
    var rules: [String]
    var order: ListOrder?
}

// MARK: Playlist

/// A playlist opened from the server's list: its page, by the library's copy of it.
struct PlaylistView: View {
    let playlist: Playlist
    @Environment(Library.self) private var library
    @State private var id: String?

    var body: some View {
        Group {
            if let id { PlaylistPage(id: id) } else { LibrarySpinner().padding(.top, detailTopGap) }
        }
        .task {
            let all = await library.playlists()
            var match: String?
            for summary in all {
                if summary.id == playlist.id { match = summary.id; break }
                if await library.playlist(summary.id)?.serverId == playlist.id { match = summary.id; break }
            }
            id = match ?? playlist.id
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
        .libraryRefreshable {}
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
                PlayShuffle { actions.play(tracks, name: playlist.name) } shuffle: { actions.play(tracks, shuffled: true, name: playlist.name) }
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
            actions.play(rows.map(\.track), from: position, name: playlist.name)
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
