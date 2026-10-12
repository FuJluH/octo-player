import OctoKit
import SwiftUI

/// Library: one page of rows into each list, then the newest albums.
struct LibraryView: View {
    @Environment(Session.self) private var session
    @State private var newest: [Album] = []

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenTitle("Library")
                VStack(spacing: 0) {
                    row("Playlists", "music.note.list", .playlists)
                    divider
                    row("Favorites", "heart", .favorites)
                    divider
                    row("Artists", "music.microphone", .artists)
                    divider
                    row("Albums", "square.stack", .albums)
                }
                if !newest.isEmpty {
                    SectionTitle("Recently added").padding(.top, 24)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                        ForEach(newest) { album in
                            GeometryReader { box in AlbumCard(album: album, width: box.size.width) }
                                .aspectRatio(0.78, contentMode: .fit)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .barClearance()
        .refreshable { await load() }
        .task(id: session.client?.baseURL) { await load() }
    }

    private func row(_ title: String, _ icon: String, _ route: Route) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(OctoColor.accent)
                    .frame(width: 24)
                Text(title).font(.octoBody).foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OctoColor.textMuted)
            }
            .padding(.horizontal, 20)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressSqueeze())
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.08)).frame(height: 1).padding(.leading, 60).padding(.trailing, 20)
    }

    private func load() async {
        guard let client = session.client else { newest = []; return }
        newest = (try? await client.albumList(.newest, size: 20)) ?? newest
    }
}

/// A list page's header: the big title, a count, and Play and Shuffle as small glass pills.
struct ListHeader: View {
    let title: String
    let count: String
    var play: (() -> Void)?
    var shuffle: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.octoDisplay).tracking(-0.5).padding(.horizontal, 20).padding(.bottom, 6)
            HStack {
                Text(count).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                Spacer()
                if let play {
                    Button(action: play) { Label("Play", systemImage: "play.fill").font(.system(size: 14, weight: .semibold)) }
                        .buttonStyle(.glass)
                }
                if let shuffle {
                    Button(action: shuffle) { Image(systemName: "shuffle").font(.system(size: 15, weight: .semibold)) }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel("Shuffle")
                }
            }
            .padding(.leading, 20)
            .padding(.trailing, 13)
            .padding(.bottom, 6)
        }
        .padding(.top, detailTopGap)
    }
}

struct PlaylistsView: View {
    @Environment(Session.self) private var session
    @State private var playlists: [Playlist] = []
    @State private var failure: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ListHeader(title: "Playlists", count: playlists.count == 1 ? "1 playlist" : "\(playlists.count) playlists")
                if let failure, playlists.isEmpty { LoadFailed(message: failure) { await load() } }
                ForEach(playlists.filter { $0.octoList == nil }) { playlist in
                    NavigationLink(value: Route.playlist(playlist)) {
                        HStack(spacing: 14) {
                            Cover(id: playlist.coverArt, size: 56, radius: OctoRadius.artS)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.name).font(.octoBodySmall).foregroundStyle(.white).lineLimit(1)
                                Text(playlist.songCount == 1 ? "1 song" : "\(playlist.songCount) songs")
                                    .font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .frame(minHeight: 72)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressSqueeze())
                }
            }
        }
        .barClearance()
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do { playlists = try await session.client?.playlists() ?? [] } catch { failure = error.localizedDescription }
    }
}

struct ArtistsView: View {
    @Environment(Session.self) private var session
    @State private var artists: [Artist] = []
    @State private var failure: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                ListHeader(title: "Artists", count: artists.count == 1 ? "1 artist" : "\(artists.count.formatted()) artists")
                if let failure, artists.isEmpty { LoadFailed(message: failure) { await load() } }
                ForEach(groups, id: \.letter) { group in
                    Section {
                        ForEach(group.artists) { artist in
                            NavigationLink(value: Route.artist(id: artist.id, name: artist.name)) {
                                HStack(spacing: 14) {
                                    Cover(id: artist.coverArt, size: 48, radius: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(artist.name).font(.octoBodySmall).foregroundStyle(.white).lineLimit(1)
                                        Text(artist.albumCount == 1 ? "1 album" : "\(artist.albumCount) albums")
                                            .font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                .frame(minHeight: 64)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressSqueeze())
                        }
                    } header: {
                        Text(group.letter)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(OctoColor.textMuted)
                            .frame(minWidth: 26, minHeight: 26)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(.horizontal, 20)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
        .barClearance()
        .task { if artists.isEmpty { await load() } }
    }

    private var groups: [(letter: String, artists: [Artist])] {
        Dictionary(grouping: artists) { artist -> String in
            let first = artist.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).first.map(String.init)?.uppercased() ?? "#"
            return first.range(of: "^[A-Z]$", options: .regularExpression) == nil ? "#" : first
        }
        .map { ($0.key, $0.value) }
        .sorted { $0.letter == "#" ? false : ($1.letter == "#" ? true : $0.letter < $1.letter) }
    }

    private func load() async {
        do {
            artists = try await session.client?.artists() ?? []
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// Every album, A to Z, a page at a time.
struct AlbumsView: View {
    @Environment(Session.self) private var session
    @Environment(Player.self) private var player
    @State private var albums: [Album] = []
    @State private var done = false
    @State private var loading = false
    @State private var failure: String?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ListHeader(title: "Albums", count: albums.count == 1 ? "1 album" : "\(albums.count.formatted()) albums")
                if let failure, albums.isEmpty { LoadFailed(message: failure) { await more() } }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(albums) { album in
                        GeometryReader { box in AlbumCard(album: album, width: box.size.width) }
                            .aspectRatio(0.78, contentMode: .fit)
                            .onAppear { if album.id == albums.last?.id { Task { await more() } } }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }
        }
        .barClearance()
        .task { if albums.isEmpty { await more() } }
    }

    private func more() async {
        guard !loading, !done, let client = session.client else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await client.albumList(.alphabetical, size: 120, offset: albums.count)
            albums += page
            done = page.count < 120
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// Favorites: songs, albums and artists hearted, in three segments.
struct FavoritesView: View {
    @Environment(Session.self) private var session
    @Environment(Player.self) private var player
    @State private var starred = SearchResult()
    @State private var segment = 0
    @State private var loaded = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("Favorites").font(.octoDisplay).tracking(-0.5).padding(.horizontal, 20).padding(.top, detailTopGap)
                Picker("", selection: $segment) {
                    Text("Songs").tag(0)
                    Text("Albums").tag(1)
                    Text("Artists").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                switch segment {
                case 0:
                    if starred.song.isEmpty, loaded {
                        empty("No liked songs yet. Tap the heart in the player to add the song that is playing, or long press any song and choose Add to Liked songs.")
                    } else {
                        HStack {
                            Text(starred.song.count == 1 ? "1 song" : "\(starred.song.count) songs").font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                            Spacer()
                            PlayButtons(songs: starred.song).frame(maxWidth: 240)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                        ForEach(Array(starred.song.enumerated()), id: \.offset) { position, song in
                            SongRow(song: song, list: starred.song, position: position)
                        }
                    }
                case 1:
                    if starred.album.isEmpty, loaded {
                        empty("Heart an album from its page or its menu to keep it here.")
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                            ForEach(starred.album) { album in
                                GeometryReader { box in AlbumCard(album: album, width: box.size.width) }
                                    .aspectRatio(0.78, contentMode: .fit)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                default:
                    if starred.artist.isEmpty, loaded {
                        empty("Heart an artist from their page or their menu to keep them here.")
                    } else {
                        ForEach(starred.artist) { artist in
                            NavigationLink(value: Route.artist(id: artist.id, name: artist.name)) {
                                HStack(spacing: 14) {
                                    Cover(id: artist.coverArt, size: 48, radius: 24)
                                    Text(artist.name).font(.octoBodySmall).foregroundStyle(.white)
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                .frame(minHeight: 64)
                            }
                            .buttonStyle(PressSqueeze())
                        }
                    }
                }
            }
        }
        .barClearance()
        .refreshable { await load() }
        .task { await load() }
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(.octoBodySmall)
            .foregroundStyle(OctoColor.textMuted)
            .padding(20)
    }

    private func load() async {
        starred = (try? await session.client?.starred()) ?? starred
        if !loaded {
            segment = !starred.song.isEmpty ? 0 : (!starred.album.isEmpty ? 1 : (!starred.artist.isEmpty ? 2 : 0))
        }
        loaded = true
    }
}
