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
    @State private var selection = SongSelection()

    /// The songs the page lists: the whole album with its finds, unless only the library's are
    /// wanted.
    private var listed: [LibraryTrack] {
        if let whole, !onlyMine { return whole }
        return tracks
    }

    private var finds: [LibraryTrack] { (whole ?? []).filter(\.isFound) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
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
        }
        .barClearance()
        .libraryRefreshable { await read() }
        .selectable(selection, songs: listed.map { Pickable(key: $0.id, track: $0) })
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
        guard let client = session.client, isServerSource(found.sourceId) else { return }
        if let full = try? await client.fullAlbum(found.nativeId) {
            discTitles = Dictionary(full.discTitles.map { ($0.disc, $0.title) }, uniquingKeysWith: { a, _ in a })
            let songs = full.song.map(\.plain)
            if songs.contains(where: \.isExternal) {
                let held = Dictionary((await library.libraryTracks(for: songs.filter { !$0.isExternal })).map { ($0.nativeId, $0) },
                                      uniquingKeysWith: { a, _ in a })
                var listedTracks = songs.map { song in held[song.id] ?? state.provisional(song) }
                let listedIds = Set(listedTracks.map(\.id))
                listedTracks += tracks.filter { !listedIds.contains($0.id) }
                whole = listedTracks
            } else {
                whole = nil
            }
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
        let count = whole != nil && !onlyMine ? listed.count : album.songCount
        let length = whole != nil && !onlyMine ? Int(listed.reduce(0) { $0 + $1.durationMs } / 1_000) : Int(album.durationMs / 1_000)
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
            NavigationLink(value: Route.artist(id: album.artistId, name: album.artist)) {
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
                    actions.setFavorite(album: album, !state.favoriteAlbumIds.contains(album.id))
                }
            }
            .padding(.top, 14)
            PlayShuffle(enabled: !listed.isEmpty) {
                actions.play(listed)
            } shuffle: {
                actions.play(listed, shuffled: true)
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
        if canShare || (state.kept.available && !serverOnly.isEmpty) {
            HStack(spacing: 0) {
                if canShare {
                    Menu {
                        ShareLinkItems(ids: [album.nativeId], title: album.title)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: MenuIcon.share).font(.system(size: 15)).frame(width: 18, height: 18)
                            Text("Share").font(LibraryLook.label)
                        }
                        .foregroundStyle(OctoColor.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 12)
                    }
                }
                if state.kept.available, !serverOnly.isEmpty {
                    let held = serverOnly.filter { state.kept.status($0.id) != nil }.count
                    let done = serverOnly.filter { state.kept.status($0.id)?.status == .done }.count
                    QuietAction(icon: held < serverOnly.count ? MenuIcon.download : (done < serverOnly.count ? MenuIcon.downloading : MenuIcon.downloaded),
                                text: albumDownloadLabel(songs: serverOnly.count, held: held, done: done),
                                enabled: held < serverOnly.count) {
                        state.kept.download(serverOnly.map(\.id))
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
                QuietAction(icon: "music.note.house", text: "Only my songs", checked: onlyMine) { onlyMine.toggle() }
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
            QuietAction(icon: MenuIcon.addToLibrary, text: addMissingLabel(missing: waiting.count)) {
                Task { for song in waiting.map(\.asSong) { _ = await downloads.request(song) } }
            }
        } else if finds.contains(where: { downloads.state($0.asSong.id) == .requested }) {
            QuietAction(icon: MenuIcon.downloading, text: downloads.keepsLog ? "Adding, show downloads" : "Adding",
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
                    NavigationLink(value: Route.library(.genre(genre))) {
                        Text(genre).font(.octoCaption).foregroundStyle(OctoColor.accent).padding(.vertical, 6).padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Open genre")
                }
                if let average {
                    HStack(spacing: 4) {
                        Image(systemName: MenuIcon.starFilled).font(.system(size: 10)).foregroundStyle(OctoColor.textMuted)
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
                         context: SongMenuContext(albumId: album.id, selecting: selection.active, selectKey: track.id),
                         selection: selection, ownership: whole != nil && !onlyMine, highlighted: track.id == highlight) {
                    actions.play(list, from: position)
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
            Text(album.name).font(.octoTitle).multilineTextAlignment(.center).padding(.top, 20)
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header
                    if !songs.isEmpty { songsSection }
                    if !top.isEmpty { topSection }
                    shelves.id("albums")
                    if let biography { aboutSection(biography) }
                    if !similar.isEmpty { similarSection }
                }
                .padding(.bottom, 20)
            }
            .onChange(of: order) { _, _ in proxy.scrollTo("albums", anchor: .top) }
        }
        .barClearance()
        .libraryRefreshable { await readAll() }
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
        guard let client = session.client else { return }
        let serverId = artist.flatMap { a in a.id.hasPrefix(a.sourceId + ":") ? String(a.id.dropFirst(a.sourceId.count + 1)) : nil } ?? id
        let named = artist?.name ?? name
        let ranked: [Song]
        if session.profile?.has("octoTopSongs") == true, let list = try? await client.artistTopSongs(artist: named, id: serverId, count: 10) {
            ranked = list.songs
        } else {
            ranked = ((try? await client.topSongs(artist: named, count: 10)) ?? []).filter { sameArtist($0.artist ?? "", named) }
        }
        let held = Dictionary((await library.libraryTracks(for: ranked.filter { !$0.isExternal })).map { ($0.nativeId, $0) },
                              uniquingKeysWith: { a, _ in a })
        top = Array(ranked.prefix(10)).map { held[$0.id] ?? state.provisional($0) }
        if top.contains(where: \.isFound) { offersAdd = true }
        if let about = try? await client.artistAbout(serverId) {
            biography = about.biography.flatMap(cleanBiography)
            var seen = Set<String>()
            var people: [(id: String, name: String, coverArt: String?, library: LibraryArtist?)] = []
            for other in about.similarArtist where !other.id.isEmpty && other.name.caseInsensitiveCompare(named) != .orderedSame {
                guard seen.insert(other.id).inserted else { continue }
                let mine = await library.resolveArtist(other.id, name: other.name)
                people.append((mine?.id ?? other.id, mine?.name ?? other.name, mine?.coverId ?? other.coverArt, mine))
            }
            similar = people
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            ArtCover(artwork: artist?.artwork, size: 160, radius: 80)
            Text(artist?.name ?? name).font(.octoTitle).multilineTextAlignment(.center).padding(.top, 16)
            if let artist {
                Text("\(albumsCount(artist.albumCount)) • \(songsCount(artist.songCount))")
                    .font(.octoCaption)
                    .foregroundStyle(OctoColor.textMuted)
                    .padding(.top, 4)
            }
            HStack(spacing: 0) {
                if !songs.isEmpty {
                    QuietAction(icon: MenuIcon.radio, text: "Radio") {
                        Task {
                            await actions.startRadio(await state.playable(Array(songs.prefix(1))))
                        }
                    }
                    .padding(.leading, -10)
                }
                Spacer(minLength: 0)
                if let artist {
                    FavoriteHeart(on: state.favoriteArtistIds.contains(artist.id)) {
                        actions.setFavorite(artist: artist, !state.favoriteArtistIds.contains(artist.id))
                    }
                }
            }
            .padding(.top, 8)
            if !songs.isEmpty {
                PlayShuffle { actions.play(songs) } shuffle: { actions.play(songs, shuffled: true) }
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, detailTopGap)
        .padding(.bottom, 8)
    }

    private var songsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionTitle("Songs")
                if songs.count > 10 {
                    QuietButton(allSongs ? "Show fewer" : "See all") { allSongs.toggle() }.padding(.trailing, 10)
                }
            }
            ForEach(Array(songs.prefix(allSongs ? songs.count : 10).enumerated()), id: \.element.id) { position, track in
                TrackRow(track: track, subtitle: track.album) { actions.play(songs, from: position) }
            }
        }
    }

    private var topSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Top songs")
            ForEach(Array(top.enumerated()), id: \.element.id) { position, track in
                TrackRow(track: track,
                         subtitle: rowAlbum(title: track.title, album: track.album, find: track.isFound),
                         context: SongMenuContext(artistId: artist?.id), offersAdd: offersAdd, addSpace: offersAdd) {
                    actions.play(top, from: position)
                }
            }
        }
    }

    @ViewBuilder
    private var shelves: some View {
        let groups = groupReleases(albums, types: \.types, own: { $0.artistId == (artist?.id ?? id) })
        let titled = groups.count > 1 || !songs.isEmpty || !top.isEmpty
        ForEach(Array(groups.enumerated()), id: \.offset) { index, shelf in
            if index == 0, albums.count > 1 {
                SortBar(name: titled ? shelf.group.title : nil, list: .artistAlbums).padding(.top, 8)
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

/// A biography as plain text: the "Read more" link servers add at the end is dropped, then every
/// tag, and the rest is written out as characters with tidy spacing. Nothing when no words are left.
func cleanBiography(_ html: String) -> String? {
    var text = html.trimmingCharacters(in: .whitespacesAndNewlines)
    func replace(_ pattern: String, _ with: String, options: NSRegularExpression.Options = [.caseInsensitive]) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: with)
    }
    replace(#"<a\b[^>]*>\s*read more\b[^<]*</a>\s*\.?\s*$"#, "")
    replace(#"<br\s*/?>|</p\s*>"#, "\n")
    replace(#"<[^>]*>"#, "", options: [])
    if let numbered = try? NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);") {
        var out = ""
        var last = text.startIndex
        for match in numbered.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text), let code = Range(match.range(at: 1), in: text) else { continue }
            out += text[last..<whole.lowerBound]
            let digits = String(text[code])
            let value = digits.hasPrefix("x") ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
            if let value, let scalar = Unicode.Scalar(value) { out.unicodeScalars.append(scalar) } else { out += text[whole] }
            last = whole.upperBound
        }
        out += text[last...]
        text = out
    }
    for (name, character) in [("&quot;", "\""), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] {
        text = text.replacingOccurrences(of: name, with: character, options: .caseInsensitive)
    }
    text = text.replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
    replace("[ \t\u{00A0}]+", " ", options: [])
    if let gaps = try? NSRegularExpression(pattern: #"\s*\n\s*(\n\s*)*"#) {
        var out = ""
        var last = text.startIndex
        for match in gaps.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text) else { continue }
            out += text[last..<whole.lowerBound]
            out += text[whole].filter { $0 == "\n" }.count > 1 ? "\n\n" : "\n"
            last = whole.upperBound
        }
        out += text[last...]
        text = out
    }
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
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
                    Button { actions.newPlaylist(with: []) } label: {
                        PlaylistLine(name: "New playlist") { LeadTile(icon: MenuIcon.addToLibrary) }
                    }
                    .buttonStyle(PressSqueeze())
                    if let open = LiveListHook.newLiveList {
                        Button { open(nil) } label: {
                            PlaylistLine(name: "New live list", subtitle: "Songs picked by rules, always up to date") {
                                LeadTile(icon: MenuIcon.filter, tinted: true)
                            }
                        }
                        .buttonStyle(PressSqueeze())
                    }
                    Button { importing = true } label: {
                        PlaylistLine(name: "Import a playlist file", subtitle: "M3U or M3U8") { LeadTile(icon: MenuIcon.folder) }
                    }
                    .buttonStyle(PressSqueeze())
                    if let importNote { importNoteView(importNote) }
                    ForEach(sortPlaylists(playlists ?? [], order)) { playlist in
                        NavigationLink(value: Route.library(.playlist(id: playlist.id))) {
                            PlaylistLine(name: playlist.name, subtitle: songsCount(playlist.songCount), onServer: playlist.onServer) {
                                PlaylistCover(covers: playlist.covers, size: 56, notice: playlist.octoNotice)
                            }
                        }
                        .buttonStyle(.plain)
                        .id(playlist.id)
                        .contextMenu {
                            CollectionActions(target: .playlist(playlist.id), playlist: playlist)
                        } preview: {
                            MenuHeader(artwork: playlist.covers.first, title: playlist.name, line: songsCount(playlist.songCount))
                        }
                    }
                }
                .padding(.bottom, 20)
            }
            .onChange(of: order) { _, _ in
                if let first = sortPlaylists(playlists ?? [], order).first { proxy.scrollTo(first.id, anchor: .top) }
            }
        }
        .barClearance()
        .libraryRefreshable()
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
        if !entries.isEmpty, !found.isEmpty { await actions.createPlaylist(name: name, tracks: found) }
        importNote = ImportNote(report: ImportReport(name, match.trackIds.count, entries.count, match.missed.map(\.shown)))
    }
}

/// A square tile for the lead lines: an icon on the quiet tile, or the live mark's tint.
private struct LeadTile: View {
    let icon: String
    var tinted = false

    var body: some View {
        RoundedRectangle(cornerRadius: OctoRadius.artS)
            .fill(tinted ? OctoColor.accent.opacity(0.16) : OctoColor.backgroundTertiary)
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(tinted ? OctoColor.accent : .white)
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

/// A playlist's page: its cover and name, the play line with More, Play and Shuffle, then its
/// songs, which can be dragged into another order, swiped away and picked.
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
    @State private var selection = SongSelection()
    @State private var dragging: Int64?
    @State private var dragOffset: CGFloat = 0
    @State private var rowHeight: CGFloat = 56
    @State private var step = 0

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
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
                }
            }
            .padding(.bottom, 20)
        }
        .barClearance()
        .sensoryFeedback(.selection, trigger: step)
        .selectable(selection, songs: rows.map { Pickable(key: String($0.itemId), track: $0.track) }) { picked in
            guard let summary else { return }
            actions.remove(Set(picked.compactMap { Int64($0.key) }), from: summary)
        }
        .task(id: "\(id)|\(library.stamp(.playlists, .library))|\(state.revision)") { await readPage() }
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
            PlaylistCover(covers: playlist.covers, size: 240, radius: 10, notice: playlist.octoNotice)
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            Text(playlist.name).font(.octoTitle).multilineTextAlignment(.center).padding(.top, 20)
            HStack(spacing: 8) {
                Text(rows.isEmpty ? "0 songs" : "\(songsCount(rows.count)) · \(asLength(length))")
                    .font(.octoCaption)
                    .foregroundStyle(OctoColor.textMuted)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Menu {
                    PlaylistOptions(playlist: playlist, hasServerOnly: tracks.contains { !$0.onPhone }) { dismiss() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "ellipsis").font(.system(size: 15)).frame(width: 18, height: 18)
                        Text("More").font(LibraryLook.label)
                    }
                    .foregroundStyle(OctoColor.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
                }
                .accessibilityLabel("More")
            }
            .padding(.top, 14)
            if !rows.isEmpty {
                PlayShuffle { actions.play(tracks) } shuffle: { actions.play(tracks, shuffled: true) }
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, detailTopGap)
        .padding(.bottom, 16)
    }

    private func playlistRow(_ position: Int, _ row: PlaylistTrack, _ playlist: PlaylistSummary) -> some View {
        let lifted = dragging == row.itemId
        return TrackRow(
            track: row.track,
            context: SongMenuContext(playlistId: playlist.id, playlistItemId: row.itemId, selecting: selection.active, selectKey: String(row.itemId)),
            selection: selection, selectKey: String(row.itemId),
            swipe: dragging == nil ? .remove { actions.remove([row.itemId], from: playlist) } : .none,
            trailing: selection.active ? nil : AnyView(handle(row, position, playlist))
        ) {
            actions.play(rows.map(\.track), from: position)
        }
        .background(lifted ? OctoColor.backgroundTertiary : .clear, in: RoundedRectangle(cornerRadius: OctoRadius.row))
        .shadow(color: lifted ? .black.opacity(0.4) : .clear, radius: 6, y: 2)
        .offset(y: offset(for: position, row))
        .zIndex(lifted ? 1 : 0)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if position == 0 { rowHeight = $0 } }
    }

    /// How far a row moves while another is dragged past it.
    private func offset(for position: Int, _ row: PlaylistTrack) -> CGFloat {
        guard let dragging, let from = rows.firstIndex(where: { $0.itemId == dragging }) else { return 0 }
        if row.itemId == dragging { return dragOffset }
        let to = target(from)
        if from < to, position > from, position <= to { return -rowHeight }
        if from > to, position >= to, position < from { return rowHeight }
        return 0
    }

    private func target(_ from: Int) -> Int {
        min(max(from + Int((dragOffset / max(rowHeight, 1)).rounded()), 0), rows.count - 1)
    }

    /// Two short lines that move the row when dragged.
    private func handle(_ row: PlaylistTrack, _ position: Int, _ playlist: PlaylistSummary) -> some View {
        VStack(spacing: 4) {
            Capsule().frame(width: 18, height: 2)
            Capsule().frame(width: 18, height: 2)
        }
        .foregroundStyle(OctoColor.textMuted)
        .frame(width: 40, height: 40)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if dragging == nil { dragging = row.itemId }
                let before = target(position)
                dragOffset = value.translation.height
                if target(position) != before { step += 1 }
            }
            .onEnded { _ in
                let to = target(position)
                let landing = rows[to].itemId
                dragging = nil
                dragOffset = 0
                if to != position {
                    var moved = rows
                    let item = moved.remove(at: position)
                    moved.insert(item, at: to)
                    rows = moved
                    actions.move(row.itemId, onto: landing, in: playlist)
                }
            })
        .accessibilityLabel("Reorder")
        .accessibilityAdjustableAction { direction in
            let to = direction == .increment ? position + 1 : position - 1
            guard rows.indices.contains(to) else { return }
            actions.move(row.itemId, onto: rows[to].itemId, in: playlist)
        }
    }
}

/// The playlist's options: rename, download, export and delete.
struct PlaylistOptions: View {
    let playlist: PlaylistSummary
    var hasServerOnly = false
    var deleted: (@MainActor () -> Void)?
    @Environment(LibraryActions.self) private var actions

    var body: some View {
        Section(playlist.name) {
            Button { actions.rename(playlist) } label: { Label("Rename", systemImage: MenuIcon.rename) }
            if actions.state.kept.available, hasServerOnly {
                Button {
                    Task { actions.state.kept.download(await actions.state.playlistTracks(playlist.id).map(\.track).filter { !$0.onPhone }.map(\.id)) }
                } label: { Label("Download", systemImage: MenuIcon.download) }
            }
            Button { actions.exportPlaylist(playlist) } label: { Label("Export as M3U", systemImage: MenuIcon.share) }
            Button(role: .destructive) { actions.delete(playlist, then: deleted) } label: { Label("Delete", systemImage: MenuIcon.delete) }
        }
    }
}
