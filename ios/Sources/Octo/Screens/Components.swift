import OctoKit
import SwiftUI

/// Octo's mark on a cover: this came through Octo, not from your library.
struct ProvenanceBadge: View {
    var size: CGFloat

    var body: some View {
        OctopusMark(tint: .white)
            .padding(size * 0.18)
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(OctoColor.lavender.opacity(0.6)), in: .circle)
    }
}

/// A cover with Octo's mark in its corner when the item is not in the library.
struct BadgedCover: View {
    let id: String?
    var size: CGFloat
    var radius: CGFloat = OctoRadius.artM
    var external = false

    var body: some View {
        Cover(id: id, size: size, radius: radius)
            .overlay(alignment: .topLeading) {
                if external {
                    ProvenanceBadge(size: max(16, size * 0.28))
                        .padding(size * 0.04)
                }
            }
    }
}

/// One song in a list. Tapping plays `list` from this song; holding offers the rest.
struct SongRow: View {
    let song: Song
    let list: [Song]
    let position: Int
    var showsCover = true
    var number: Int?
    @Environment(Player.self) private var player

    var body: some View {
        Button {
            player.play(list, from: position)
        } label: {
            HStack(spacing: 12) {
                if showsCover {
                    BadgedCover(id: song.coverArt, size: 46, radius: OctoRadius.artS, external: song.isExternal)
                } else if let number {
                    Text("\(number)")
                        .font(.octoBodySmall.monospacedDigit())
                        .foregroundStyle(OctoColor.textMuted)
                        .frame(width: 26)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.octoBody)
                        .foregroundStyle(isCurrent ? OctoColor.accentHover : OctoColor.textPrimary)
                        .lineLimit(1)
                    Text(song.byline)
                        .font(.octoBodySmall)
                        .foregroundStyle(OctoColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if song.duration > 0 {
                    Text(Duration.seconds(song.duration).formatted(.time(pattern: .minuteSecond)))
                        .font(.octoCaption.monospacedDigit())
                        .foregroundStyle(OctoColor.textMuted)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { SongActions(song: song) }
        .swipeActions(edge: .leading) {
            Button { player.playNext([song]) } label: { Label("Play Next", systemImage: "text.insert") }
                .tint(OctoColor.lavender)
        }
        .swipeActions(edge: .trailing) {
            Button { player.append([song]) } label: { Label("Add to Queue", systemImage: "text.append") }
                .tint(OctoColor.accent)
        }
    }

    private var isCurrent: Bool { player.current?.id == song.id }
}

/// What can be done with a song, for its menu.
struct SongActions: View {
    let song: Song
    @Environment(Player.self) private var player
    @Environment(Session.self) private var session

    var body: some View {
        Button { player.playNext([song]) } label: { Label("Play Next", systemImage: "text.insert") }
        Button { player.append([song]) } label: { Label("Add to Queue", systemImage: "text.append") }
        Button { Task { await player.startRadio(from: song) } } label: { Label("Start Radio", systemImage: "dot.radiowaves.left.and.right") }
        Divider()
        Button {
            guard let client = session.client else { return }
            Task {
                if song.isStarred { try? await client.unstar(songId: song.id) } else { try? await client.star(songId: song.id) }
            }
        } label: {
            Label(song.isStarred ? "Remove Heart" : (song.isExternal ? "Heart and Add to Library" : "Heart"),
                  systemImage: song.isStarred ? "heart.slash" : "heart")
        }
        if let albumId = song.albumId, !song.isExternal {
            NavigationLink(value: Route.album(Album(id: albumId, name: song.album ?? "", artist: song.artist ?? "",
                                                    coverArt: song.coverArt))) {
                Label("Go to Album", systemImage: "square.stack")
            }
        }
        if let artistId = song.artistId, !song.isExternal {
            NavigationLink(value: Route.artist(id: artistId, name: song.artist ?? "")) {
                Label("Go to Artist", systemImage: "music.microphone")
            }
        }
    }
}

/// An album as a tile: its cover, name and artist.
struct AlbumTile: View {
    let album: Album
    var size: CGFloat = 160

    var body: some View {
        NavigationLink(value: Route.album(album)) {
            VStack(alignment: .leading, spacing: 6) {
                BadgedCover(id: album.coverArt, size: size, external: album.isExternal)
                Text(album.name)
                    .font(.octoBodySmall.weight(.semibold))
                    .foregroundStyle(OctoColor.textPrimary)
                    .lineLimit(1)
                Text(album.byline)
                    .font(.octoCaption)
                    .foregroundStyle(OctoColor.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: size, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

/// A playlist as a tile.
struct PlaylistTile: View {
    let playlist: Playlist
    var size: CGFloat = 160

    var body: some View {
        NavigationLink(value: Route.playlist(playlist)) {
            VStack(alignment: .leading, spacing: 6) {
                Cover(id: playlist.coverArt, size: size)
                Text(playlist.name)
                    .font(.octoBodySmall.weight(.semibold))
                    .foregroundStyle(OctoColor.textPrimary)
                    .lineLimit(1)
                Text("\(playlist.songCount) songs")
                    .font(.octoCaption)
                    .foregroundStyle(OctoColor.textSecondary)
            }
            .frame(width: size, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

/// A titled row of tiles that scrolls sideways.
struct Shelf<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.octoHeadline)
                .padding(.horizontal, 20)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) { content }
                    .scrollTargetLayout()
                    .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

/// Play and Shuffle, side by side, for an album or a playlist.
struct PlayButtons: View {
    let songs: [Song]
    @Environment(Player.self) private var player

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button { player.play(songs) } label: {
                    Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                Button { player.shuffle(songs) } label: {
                    Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
            .font(.octoBody.weight(.semibold))
        }
        .disabled(songs.isEmpty)
    }
}

/// A message in place of a page that could not load.
struct LoadFailed: View {
    let message: String
    let retry: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't load", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { Task { await retry() } }
                .buttonStyle(.glass)
        }
    }
}

extension Int {
    /// "1 hr 4 min" or "38 min", for an album's or playlist's length.
    var spokenLength: String {
        Duration.seconds(self).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
