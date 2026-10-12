import OctoKit
import SwiftUI

struct AlbumView: View {
    let album: Album
    @Environment(Session.self) private var session
    @State private var full: Album?
    @State private var starred: Bool?
    @State private var failure: String?

    private var shown: Album { full ?? album }
    private var songs: [Song] { full?.song ?? [] }

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    BadgedCover(id: shown.coverArt, size: 260, radius: OctoRadius.artL, external: shown.isExternal)
                        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
                    VStack(spacing: 4) {
                        Text(shown.name)
                            .font(.octoTitle)
                            .multilineTextAlignment(.center)
                        if let artistId = shown.artistId {
                            NavigationLink(value: Route.artist(id: artistId, name: shown.artist)) {
                                Text(shown.byline).font(.octoBody).foregroundStyle(OctoColor.accentHover)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(shown.byline).font(.octoBody).foregroundStyle(OctoColor.textSecondary)
                        }
                        Text(details)
                            .font(.octoCaption)
                            .foregroundStyle(OctoColor.textMuted)
                    }
                    PlayButtons(songs: songs)
                }
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(Array(songs.enumerated()), id: \.offset) { position, song in
                    SongRow(song: song, list: songs, position: position, showsCover: false, number: song.track ?? position + 1)
                }
            }
        }
        .listStyle(.plain)
        .overlay { if let failure, full == nil { LoadFailed(message: failure) { await load() } } }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await toggleHeart() } } label: {
                    Image(systemName: isStarred ? "heart.fill" : "heart")
                }
                .accessibilityLabel(isStarred ? "Remove heart" : "Heart")
            }
        }
        .task { await load() }
    }

    private var isStarred: Bool { starred ?? (shown.starred != nil) }

    private var details: String {
        var parts: [String] = []
        if let year = shown.year { parts.append(String(year)) }
        if shown.songCount > 0 { parts.append("\(shown.songCount) songs") }
        if shown.duration > 0 { parts.append(shown.duration.spokenLength) }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        do { full = try await session.client?.album(album.id) } catch { failure = error.localizedDescription }
    }

    private func toggleHeart() async {
        guard let client = session.client else { return }
        let next = !isStarred
        starred = next
        do {
            if next { try await client.star(albumId: album.id) } else { try await client.unstar(albumId: album.id) }
        } catch {
            starred = !next
        }
    }
}

struct PlaylistView: View {
    let playlist: Playlist
    @Environment(Session.self) private var session
    @State private var full: Playlist?
    @State private var failure: String?

    private var songs: [Song] { full?.entry ?? [] }

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    Cover(id: playlist.coverArt, size: 240, radius: OctoRadius.artL)
                        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
                    VStack(spacing: 4) {
                        Text(playlist.name).font(.octoTitle).multilineTextAlignment(.center)
                        if let comment = (full ?? playlist).comment, !comment.isEmpty {
                            Text(comment).font(.octoBodySmall).foregroundStyle(OctoColor.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        Text("\((full ?? playlist).songCount) songs · \((full ?? playlist).duration.spokenLength)")
                            .font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                    }
                    PlayButtons(songs: songs)
                }
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(Array(songs.enumerated()), id: \.offset) { position, song in
                    SongRow(song: song, list: songs, position: position)
                }
            }
        }
        .listStyle(.plain)
        .overlay { if let failure, full == nil { LoadFailed(message: failure) { await load() } } }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do { full = try await session.client?.playlist(playlist.id) } catch { failure = error.localizedDescription }
    }
}

struct ArtistView: View {
    let id: String
    let name: String
    @Environment(Session.self) private var session
    @Environment(Player.self) private var player
    @State private var artist: Artist?
    @State private var top: [Song] = []
    @State private var failure: String?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Cover(id: artist?.coverArt, size: 180, radius: 90)
                        Text(name).font(.octoTitle).multilineTextAlignment(.center)
                    }
                    Spacer()
                }
                if !top.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Top Songs").font(.octoHeadline)
                            Spacer()
                            Button { Task { if let first = top.first { await player.startRadio(from: first) } } } label: {
                                Label("Radio", systemImage: "dot.radiowaves.left.and.right")
                            }
                            .buttonStyle(.glass)
                        }
                        ForEach(Array(top.prefix(5).enumerated()), id: \.offset) { position, song in
                            SongRow(song: song, list: top, position: position)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                if let albums = artist?.album, !albums.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Albums").font(.octoHeadline)
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                            ForEach(albums) { AlbumTile(album: $0, size: 160) }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 16)
        }
        .overlay { if let failure, artist == nil { LoadFailed(message: failure) { await load() } } }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        guard let client = session.client else { return }
        do {
            artist = try await client.artist(id)
            top = (try? await client.topSongs(artist: name)) ?? []
        } catch {
            failure = error.localizedDescription
        }
    }
}
