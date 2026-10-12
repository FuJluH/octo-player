import OctoKit
import SwiftUI

struct LibraryView: View {
    var body: some View {
        List {
            row("Playlists", "music.note.list", .playlists)
            row("Artists", "music.microphone", .artists)
            row("Albums", "square.stack", .albums)
            row("Favorites", "heart", .favorites)
        }
        .navigationTitle("Library")
    }

    private func row(_ title: String, _ icon: String, _ route: Route) -> some View {
        NavigationLink(value: route) {
            Label(title, systemImage: icon)
                .font(.octoBody)
        }
    }
}

struct PlaylistsView: View {
    @Environment(Session.self) private var session
    @State private var playlists: [Playlist] = []
    @State private var failure: String?

    var body: some View {
        List(playlists) { playlist in
            NavigationLink(value: Route.playlist(playlist)) {
                HStack(spacing: 12) {
                    Cover(id: playlist.coverArt, size: 54, radius: OctoRadius.artS)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(playlist.name).font(.octoBody).lineLimit(1)
                        Text("\(playlist.songCount) songs").font(.octoBodySmall).foregroundStyle(OctoColor.textSecondary)
                    }
                }
            }
        }
        .overlay { if let failure, playlists.isEmpty { LoadFailed(message: failure) { await load() } } }
        .navigationTitle("Playlists")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do { playlists = try await session.client?.playlists() ?? [] } catch { failure = error.localizedDescription }
    }
}

struct ArtistsView: View {
    @Environment(Session.self) private var session
    @State private var artists: [Artist] = []
    @State private var filter = ""
    @State private var failure: String?

    var body: some View {
        List(shown) { artist in
            NavigationLink(value: Route.artist(id: artist.id, name: artist.name)) {
                HStack(spacing: 12) {
                    Cover(id: artist.coverArt, size: 44, radius: 22)
                    Text(artist.name).font(.octoBody).lineLimit(1)
                }
            }
        }
        .searchable(text: $filter, prompt: "Filter artists")
        .overlay { if let failure, artists.isEmpty { LoadFailed(message: failure) { await load() } } }
        .navigationTitle("Artists")
        .task { if artists.isEmpty { await load() } }
    }

    private var shown: [Artist] {
        filter.isEmpty ? artists : artists.filter { $0.name.localizedStandardContains(filter) }
    }

    private func load() async {
        do { artists = try await session.client?.artists() ?? [] } catch { failure = error.localizedDescription }
    }
}

/// Every album, A to Z, a page at a time.
struct AlbumsView: View {
    @Environment(Session.self) private var session
    @State private var albums: [Album] = []
    @State private var done = false
    @State private var loading = false
    @State private var failure: String?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                ForEach(albums) { album in
                    AlbumTile(album: album, size: 160)
                        .onAppear { if album.id == albums.last?.id { Task { await more() } } }
                }
            }
            .padding(20)
        }
        .overlay { if let failure, albums.isEmpty { LoadFailed(message: failure) { await more() } } }
        .navigationTitle("Albums")
        .task { if albums.isEmpty { await more() } }
    }

    private func more() async {
        guard !loading, !done, let client = session.client else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await client.albumList(.alphabetical, size: 60, offset: albums.count)
            albums += page
            done = page.count < 60
        } catch {
            failure = error.localizedDescription
        }
    }
}

struct FavoritesView: View {
    @Environment(Session.self) private var session
    @State private var starred = SearchResult()
    @State private var failure: String?

    var body: some View {
        List {
            if !starred.album.isEmpty {
                Section("Albums") {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 14) { ForEach(starred.album) { AlbumTile(album: $0, size: 130) } }
                    }
                    .scrollIndicators(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                }
            }
            if !starred.song.isEmpty {
                Section("Songs") {
                    ForEach(Array(starred.song.enumerated()), id: \.offset) { position, song in
                        SongRow(song: song, list: starred.song, position: position)
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if let failure, starred.song.isEmpty { LoadFailed(message: failure) { await load() } }
        }
        .navigationTitle("Favorites")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do { starred = try await session.client?.starred() ?? SearchResult() } catch { failure = error.localizedDescription }
    }
}
