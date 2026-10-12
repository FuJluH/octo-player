import OctoKit
import SwiftUI

/// The header every collection page shares: the cover, the title, who it is by, the details
/// line with the heart, and Play and Shuffle.
struct CollectionHeader: View {
    let coverArt: String?
    let title: String
    var byline: String?
    var bylineRoute: Route?
    let details: String
    var heart: Binding<Bool>?
    let songs: [Song]
    var round = false

    var body: some View {
        VStack(spacing: 0) {
            Cover(id: coverArt, size: round ? 160 : 240, radius: round ? 80 : 10)
                .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
            Text(title)
                .font(.octoTitle)
                .multilineTextAlignment(.center)
                .padding(.top, 20)
            if let byline, !byline.isEmpty {
                if let bylineRoute {
                    NavigationLink(value: bylineRoute) {
                        Text(byline).font(.octoBody).foregroundStyle(OctoColor.accent)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                } else {
                    Text(byline).font(.octoBody).foregroundStyle(OctoColor.textSecondary).padding(.top, 4)
                }
            }
            HStack {
                Text(details)
                    .font(.octoCaption)
                    .foregroundStyle(OctoColor.textMuted)
                    .lineLimit(2)
                Spacer()
                if let heart {
                    Button { heart.wrappedValue.toggle() } label: {
                        Image(systemName: heart.wrappedValue ? "heart.fill" : "heart")
                            .font(.system(size: 22))
                            .foregroundStyle(heart.wrappedValue ? .white : .white.opacity(0.6))
                            .shadow(color: heart.wrappedValue ? .white.opacity(0.5) : .clear, radius: 6)
                            .symbolEffect(.bounce, value: heart.wrappedValue)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Favorite")
                    .accessibilityValue(heart.wrappedValue ? "In favorites" : "Not in favorites")
                }
            }
            .padding(.top, 14)
            if !songs.isEmpty {
                PlayButtons(songs: songs).padding(.top, 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, detailTopGap)
        .padding(.bottom, 12)
    }
}

struct AlbumView: View {
    let album: Album
    @Environment(Session.self) private var session
    @Environment(Router.self) private var router
    @State private var full: Album?
    @State private var more: [Album] = []
    @State private var starred: Bool?
    @State private var failure: String?

    private var shown: Album { full ?? album }
    private var songs: [Song] { full?.song ?? [] }
    private var discs: [Int: [Song]] { Dictionary(grouping: songs) { $0.discNumber ?? 1 } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                CollectionHeader(
                    coverArt: shown.coverArt, title: shown.name, byline: shown.byline,
                    bylineRoute: shown.artistId.map { Route.artist(id: $0, name: shown.artist) },
                    details: details, heart: heartBinding, songs: songs)
                if let failure, full == nil { LoadFailed(message: failure) { await load() } }
                ForEach(discs.keys.sorted(), id: \.self) { disc in
                    if discs.count > 1 {
                        Text("Disc \(disc)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(OctoColor.textMuted)
                            .padding(.leading, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 4)
                    }
                    ForEach(discs[disc] ?? []) { song in
                        let position = songs.firstIndex(of: song) ?? 0
                        SongRow(song: song, list: songs, position: position, showsCover: false, number: song.track ?? position + 1,
                                subtitle: song.byline == shown.byline ? "" : song.byline)
                    }
                }
                if !more.isEmpty {
                    Shelf(title: "More by \(shown.byline)") { ForEach(more) { AlbumCard(album: $0) } }
                        .padding(.top, 16)
                }
            }
        }
        .barClearance()
        .task { await load() }
    }

    private var details: String {
        [shown.year.map(String.init), shown.songCount > 0 ? "\(shown.songCount) songs" : nil,
         shown.duration > 0 ? shown.duration.spokenLength : nil].compactMap { $0 }.joined(separator: " • ")
    }

    private var heartBinding: Binding<Bool> {
        Binding(get: { starred ?? (shown.starred != nil) }, set: { on in
            starred = on
            Task {
                guard let client = session.client else { return }
                do {
                    if on { try await client.star(albumId: album.id) } else { try await client.unstar(albumId: album.id) }
                } catch {
                    starred = !on
                    router.show(error.localizedDescription)
                }
            }
        })
    }

    private func load() async {
        guard let client = session.client else { return }
        do {
            full = try await client.album(album.id)
            if let artistId = full?.artistId, let artist = try? await client.artist(artistId) {
                more = artist.album.filter { $0.id != album.id }
            }
        } catch {
            failure = error.localizedDescription
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                let shown = full ?? playlist
                CollectionHeader(
                    coverArt: shown.coverArt, title: shown.name, byline: shown.comment,
                    details: shown.songCount == 0 ? "0 songs" : "\(shown.songCount) songs · \(shown.duration.spokenLength)",
                    songs: songs)
                if let failure, full == nil { LoadFailed(message: failure) { await load() } }
                if full != nil, songs.isEmpty {
                    Text("This playlist is empty. Long press any song and choose Add to playlist.")
                        .font(.octoBodySmall).foregroundStyle(OctoColor.textMuted).padding(20)
                }
                ForEach(Array(songs.enumerated()), id: \.offset) { position, song in
                    SongRow(song: song, list: songs, position: position)
                }
            }
        }
        .barClearance()
        .refreshable { await load() }
        .task { await load() }
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
    @State private var showsAllTop = false
    @State private var failure: String?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    Cover(id: artist?.coverArt, size: 160, radius: 80)
                    Text(name).font(.octoTitle).multilineTextAlignment(.center).padding(.top, 16)
                    if let artist {
                        Text("\(artist.albumCount) albums")
                            .font(.octoCaption)
                            .foregroundStyle(OctoColor.textMuted)
                            .padding(.top, 4)
                    }
                    HStack {
                        if let first = top.first {
                            Button { Task { await player.startRadio(from: first) } } label: {
                                Label("Radio", systemImage: "dot.radiowaves.left.and.right")
                                    .font(.octoBodySmall)
                                    .foregroundStyle(OctoColor.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    .padding(.top, 12)
                    if !top.isEmpty { PlayButtons(songs: top).padding(.top, 4) }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, detailTopGap)
                if let failure, artist == nil { LoadFailed(message: failure) { await load() } }
                if !top.isEmpty {
                    SectionTitle("Top songs").padding(.top, 12)
                    ForEach(Array(top.prefix(showsAllTop ? top.count : 5).enumerated()), id: \.offset) { position, song in
                        SongRow(song: song, list: top, position: position, subtitle: song.album ?? "")
                    }
                    if top.count > 5 {
                        Button(showsAllTop ? "Show fewer" : "Show all") { showsAllTop.toggle() }
                            .font(.octoBodySmall)
                            .foregroundStyle(OctoColor.textSecondary)
                            .buttonStyle(.plain)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                    }
                }
                if let albums = artist?.album, !albums.isEmpty {
                    SectionTitle("Albums").padding(.top, 12)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                        ForEach(albums.sorted { ($0.year ?? 0) > ($1.year ?? 0) }) { album in
                            GeometryReader { box in AlbumCard(album: album, width: box.size.width) }
                                .aspectRatio(0.78, contentMode: .fit)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .barClearance()
        .task { await load() }
    }

    private func load() async {
        guard let client = session.client else { return }
        do {
            artist = try await client.artist(id)
            if session.profile?.has("octoTopSongs") == true,
               let ranked = try? await client.artistTopSongs(artist: name, id: id, count: 20) {
                top = ranked.songs
            } else {
                top = (try? await client.topSongs(artist: name, count: 20)) ?? []
            }
        } catch {
            failure = error.localizedDescription
        }
    }
}
