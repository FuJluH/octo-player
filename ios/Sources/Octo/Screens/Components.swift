import OctoKit
import SwiftUI

// Octo's rows and cards, the same sizes as the other apps'.

/// The mark on the artwork of something not in the library: a small glass disc with a plus,
/// at the bottom right.
struct NotInLibraryMark: View {
    let artSize: CGFloat
    var round = false

    var body: some View {
        let size = min(20, max(12, artSize * 0.125))
        let inset = max(3, artSize * 0.04)
        Circle()
            .fill(.black.opacity(0.42))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: size * 0.6, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .glassEffect(.regular, in: .circle)
            .padding(round ? artSize * 0.1 : inset)
            .accessibilityLabel("Not in your library")
    }
}

/// A cover with the not-in-library mark when the item is not in the library.
struct BadgedCover: View {
    let id: String?
    var size: CGFloat
    var radius: CGFloat = OctoRadius.artM
    var external = false

    var body: some View {
        Cover(id: id, size: size, radius: radius)
            .overlay(alignment: .bottomTrailing) {
                if external { NotInLibraryMark(artSize: size, round: radius >= size / 2) }
            }
    }
}

/// Three bars that dance while a song plays and rest when it is paused.
struct NowPlayingBars: View {
    let playing: Bool
    var size: CGFloat = 16
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: !playing || reduceMotion)) { time in
            let phase = time.date.timeIntervalSinceReferenceDate / 2.4
            HStack(alignment: .bottom, spacing: size / 7 / 3) {
                ForEach(0..<3, id: \.self) { i in
                    let rest = [0.45, 0.8, 0.6][i]
                    let speed = [2.0, 3.0, 4.0][i]
                    let offset = [0, 0.3, 0.65][i]
                    let height = playing && !reduceMotion ? 0.25 + 0.75 * abs(sin((phase * speed + offset) * .pi)) : rest
                    Capsule().frame(width: size / 4, height: size * height)
                }
            }
            .frame(width: size, height: size, alignment: .bottom)
            .foregroundStyle(playing ? .white : OctoColor.textMuted)
            .shadow(color: playing ? .white.opacity(0.7) : .clear, radius: 2)
        }
        .accessibilityHidden(true)
    }
}

/// One song in a list. Tapping plays `list` from this song; holding opens its menu; swiping
/// right puts it next in the queue.
struct SongRow: View {
    let song: Song
    let list: [Song]
    let position: Int
    var showsCover = true
    var number: Int?
    /// Words under the title in place of "Artist • Album".
    var subtitle: String?
    /// Whether this list offers add: a find ends with the add button, and a library song keeps
    /// the same space empty when `addSpace` so lengths line up.
    var offersAdd = false
    var addSpace = false
    @Environment(Player.self) private var player
    @Environment(Router.self) private var router

    var body: some View {
        Button {
            player.play(list, from: position)
        } label: {
            HStack(spacing: 12) {
                lead
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(song.title)
                            .font(.octoBodySmall)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if song.explicitStatus == "explicit" { ExplicitMark() }
                    }
                    Text(subtitle ?? [song.byline, song.album ?? ""].filter { !$0.isEmpty }.joined(separator: " • "))
                        .font(.octoCaption)
                        .foregroundStyle(OctoColor.textMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(song.duration > 0 ? Duration.seconds(song.duration).formatted(.time(pattern: .minuteSecond)) : "")
                    .font(.octoCaption.monospacedDigit())
                    .foregroundStyle(OctoColor.textMuted)
                if offersAdd && song.isExternal {
                    AddToLibraryButton(song: song, size: 40, iconSize: 22)
                } else if offersAdd && addSpace {
                    Color.clear.frame(width: 40, height: 40)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressSqueeze())
        .contextMenu { SongActions(song: song) } preview: { SongPreview(song: song) }
        .swipeActions(edge: .leading) {
            Button {
                player.playNext([song])
                router.show("Playing next", done: true)
            } label: {
                Label("Play next", systemImage: "text.insert")
            }
            .tint(OctoColor.accent.opacity(0.6))
        }
        .accessibilityAction(named: "Play next") { player.playNext([song]) }
        .accessibilityAction(named: "Add to queue") { player.append([song]) }
    }

    private var isCurrent: Bool { player.current?.id == song.id }

    @ViewBuilder
    private var lead: some View {
        if showsCover {
            BadgedCover(id: song.coverArt, size: 44, radius: OctoRadius.artS, external: song.isExternal && !offersAdd)
                .overlay {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: OctoRadius.artS).fill(.black.opacity(0.5))
                        NowPlayingBars(playing: player.isPlaying)
                    }
                }
        } else {
            ZStack(alignment: .trailing) {
                if isCurrent {
                    NowPlayingBars(playing: player.isPlaying, size: 14)
                } else if let number {
                    Text("\(number)")
                        .font(.octoBodySmall.monospacedDigit())
                        .foregroundStyle(OctoColor.textMuted)
                }
            }
            .frame(width: 28, alignment: .trailing)
        }
    }
}

/// What a held song row shows above its menu.
private struct SongPreview: View {
    let song: Song

    var body: some View {
        HStack(spacing: 12) {
            Cover(id: song.coverArt, size: 56, radius: OctoRadius.artS)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.octoBody).lineLimit(2)
                Text(song.byline).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .background(OctoColor.backgroundTertiary)
    }
}

/// Pressed rows and cards squeeze slightly.
struct PressSqueeze: ButtonStyle {
    var amount: CGFloat = 0.985

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? amount : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// What can be done with a song, in the other apps' groups.
struct SongActions: View {
    let song: Song
    @Environment(Player.self) private var player
    @Environment(Downloads.self) private var downloads
    @Environment(Session.self) private var session
    @Environment(Router.self) private var router

    var body: some View {
        Section {
            Button { player.playNext([song]); router.show("Playing next", done: true) } label: { Label("Play next", systemImage: "text.insert") }
            Button { player.append([song]); router.show("Added to the queue", done: true) } label: { Label("Add to queue", systemImage: "text.append") }
            Button { Task { await player.startRadio(from: song) } } label: { Label("Start radio", systemImage: "dot.radiowaves.left.and.right") }
        }
        Section {
            if song.isExternal {
                switch downloads.phase(song.id).state {
                case .none:
                    Button { Task { _ = await downloads.request(song) } } label: { Label("Add to your library", systemImage: "plus.circle") }
                case .requested:
                    Button {} label: { Label("Adding to your library", systemImage: "checkmark") }.disabled(true)
                case .done:
                    Button {} label: { Label("In your library", systemImage: "checkmark") }.disabled(true)
                }
            } else {
                Button { Task { await heart() } } label: {
                    Label(song.isStarred ? "Remove from Liked songs" : "Add to Liked songs", systemImage: song.isStarred ? "heart.slash" : "heart")
                }
            }
        }
        if !song.isExternal {
            Section {
                if let albumId = song.albumId {
                    NavigationLink(value: Route.album(Album(id: albumId, name: song.album ?? "", artist: song.artist ?? "", coverArt: song.coverArt))) {
                        Label("Go to album", systemImage: "square.stack")
                    }
                }
                if let artistId = song.artistId {
                    NavigationLink(value: Route.artist(id: artistId, name: song.artist ?? "")) {
                        Label("Go to artist", systemImage: "music.microphone")
                    }
                }
            }
        }
    }

    private func heart() async {
        guard let client = session.client else { return }
        do {
            if song.isStarred {
                try await client.unstar(songId: song.id)
                router.show("Removed from Liked songs")
            } else {
                try await client.star(songId: song.id)
                router.show("Added to Liked songs", done: true)
            }
        } catch {
            router.show(error.localizedDescription)
        }
    }

}

/// An album as a card: square cover, title and artist, 150 wide.
struct AlbumCard: View {
    let album: Album
    var width: CGFloat = 150

    var body: some View {
        NavigationLink(value: Route.album(album)) {
            VStack(alignment: .leading, spacing: 8) {
                BadgedCover(id: album.coverArt, size: width, external: album.isExternal)
                VStack(alignment: .leading, spacing: 1) {
                    Text(album.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(album.byline)
                        .font(.octoCaption)
                        .foregroundStyle(OctoColor.textMuted)
                        .lineLimit(1)
                    if album.isExternal, let owned = album.ownedCount, owned > 0, album.songCount > 0 {
                        Text("\(owned) of \(album.songCount) in your library")
                            .font(.octoCaption)
                            .foregroundStyle(OctoColor.textMuted)
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: width, alignment: .leading)
        }
        .buttonStyle(PressSqueeze(amount: 0.97))
    }
}

/// A song as a card, for shelves of songs.
struct SongCard: View {
    let song: Song
    let list: [Song]
    let position: Int
    var width: CGFloat = 150
    @Environment(Player.self) private var player

    var body: some View {
        Button { player.play(list, from: position) } label: {
            VStack(alignment: .leading, spacing: 8) {
                BadgedCover(id: song.coverArt, size: width, external: song.isExternal)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(song.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        if song.explicitStatus == "explicit" { ExplicitMark(size: 12) }
                    }
                    Text(song.byline).font(.octoCaption).foregroundStyle(OctoColor.textMuted).lineLimit(1)
                }
            }
            .frame(width: width, alignment: .leading)
        }
        .buttonStyle(PressSqueeze(amount: 0.97))
        .contextMenu { SongActions(song: song) }
    }
}

/// A station or a Made for you list: tapping plays it.
struct StationCard: View {
    let name: String
    let coverArt: String?
    var songCount: Int?
    var loading = false
    let play: () -> Void

    var body: some View {
        Button(action: play) {
            VStack(alignment: .leading, spacing: 8) {
                Cover(id: coverArt, size: 150)
                Text(name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                if let songCount {
                    Text(songCount == 1 ? "1 song" : "\(songCount) songs")
                        .font(.octoBodySmall)
                        .foregroundStyle(OctoColor.textSecondary)
                }
            }
            .frame(width: 150, alignment: .leading)
            .opacity(loading ? 0.5 : 1)
        }
        .buttonStyle(PressSqueeze(amount: 0.97))
    }
}

/// An artist as a circle with the name under it.
struct ArtistCircle: View {
    let id: String
    let name: String
    let coverArt: String?
    var size: CGFloat = 96

    var body: some View {
        NavigationLink(value: Route.artist(id: id, name: name)) {
            VStack(spacing: 8) {
                Cover(id: coverArt, size: size, radius: size / 2)
                Text(name).font(.octoCaption).foregroundStyle(.white).lineLimit(1).frame(width: size)
            }
        }
        .buttonStyle(PressSqueeze(amount: 0.97))
    }
}

/// A titled row of cards that scrolls sideways. A title that leads to its own page carries a
/// chevron.
struct Shelf<Content: View>: View {
    let title: String
    var destination: Route?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let destination {
                    NavigationLink(value: destination) {
                        HStack(spacing: 2) {
                            Text(title).font(.octoSection)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(OctoColor.textMuted)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(title)")
                } else {
                    Text(title).font(.octoSection)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 10)
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

/// Play and Shuffle side by side, as glass capsules of equal width.
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
            .font(.octoBody)
        }
        .disabled(songs.isEmpty)
    }
}

/// A message in place of a page that could not load, with Try again.
struct LoadFailed: View {
    let message: String
    let retry: () async -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(message)
                .font(.octoBodySmall)
                .foregroundStyle(OctoColor.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await retry() } }
                .buttonStyle(.glassProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

extension Int {
    /// "1 hr 12 min" or "48 min", for an album's or playlist's length.
    var spokenLength: String {
        let minutes = (self + 30) / 60
        return minutes >= 60 ? "\(minutes / 60) hr \(minutes % 60) min" : "\(minutes) min"
    }
}
