import OctoKit
import SwiftUI

/// What to tell someone when a read from the server fails.
func onlineFailureWords(_ error: Error) -> String {
    switch error {
    case let error as OctoError:
        switch error {
        case .notSubsonic: return "That address answered, but not like a music server. Check the port."
        case .http(let status) where [502, 503, 504].contains(status):
            return "The server isn't answering right now. It may be restarting, so try again in a moment."
        case .http: return "That address answered, but not like a music server. Check the port."
        case .wrongCredentials: return "Wrong username or password."
        case .authUnsupported(let code, _):
            return code == 41 ? "This account can't sign in with a token. Turn on Legacy sign-in under Advanced."
                : "The server doesn't take this way of signing in."
        case .notFound: return "That isn't on the server any more."
        case .server(_, let message): return "The server said: \(message)"
        }
    case is URLError:
        return "Couldn't reach the server. Check the address, and that you're on the right network."
    default:
        return "Something went wrong."
    }
}

/// Where a read of a page from the server has got to.
enum LoadState<T> {
    case loading
    case failed(String)
    case ready(T)

    var value: T? {
        if case .ready(let value) = self { return value }
        return nil
    }
}

/// Runs a read from the server. Nothing back means no server is signed in.
@MainActor
func loadOnline<T>(_ read: () async throws -> T?) async -> LoadState<T> {
    do {
        guard let value = try await read() else { return .failed("Sign in to your server to see this.") }
        return .ready(value)
    } catch {
        return .failed(onlineFailureWords(error))
    }
}

/// A page's loading spinner, or its failure with Try again, or the page.
struct LoadStateContent<T, Content: View>: View {
    let state: LoadState<T>
    let retry: () -> Void
    @ViewBuilder let content: (T) -> Content

    var body: some View {
        switch state {
        case .loading:
            AccentSpinner()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 16) {
                Text(message)
                    .font(.octoBodySmall)
                    .foregroundStyle(OctoColor.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Try again", action: retry)
                    .buttonStyle(.glassProminent)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready(let value):
            content(value)
        }
    }
}

// MARK: Online album

/// An album on the server that is not in the library. Songs the library has play as usual; the
/// rest can be added one by one or all at once.
struct OnlineAlbumView: View {
    let id: String
    let name: String
    @Environment(Discovery.self) private var discovery
    @Environment(Downloads.self) private var downloads
    @Environment(Player.self) private var player
    @State private var page: LoadState<OnlineAlbumPage> = .loading
    /// Set once the album is asked for here, cleared if the server says no.
    @State private var asked = false
    @State private var highlight: String?

    var body: some View {
        LoadStateContent(state: page, retry: { Task { await reload() } }) { found in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header(found)
                    let mixed = found.songs.contains(where: \.isExternal)
                    ForEach(Array(found.songs.enumerated()), id: \.element.id) { index, song in
                        // Only say who is singing when it is not the album's artist.
                        SongRow(song: song, list: found.songs, position: index, showsCover: false, number: index + 1,
                                describe: { $0.byline != found.album.artist ? $0.byline : "" },
                                highlight: song.id == highlight, ownership: mixed) { player.play(found.songs, from: index) }
                    }
                }
            }
            .barClearance()
        }
        .task { if page.value == nil { await reload() } }
        .task(id: page.value?.album.id) { await markHighlight() }
        .onChange(of: downloads.arrived) { _, _ in
            // A song from here that joins the library turns into a library song on the page,
            // once its check has landed.
            Task {
                try? await Task.sleep(for: .milliseconds(checkHoldMs + swapFadeDurationMs))
                let songs = page.value?.songs ?? []
                if songs.contains(where: { $0.isExternal && downloads.state($0.id) == .done }) { await refresh() }
            }
        }
    }

    /// Whether the album is on its way: asked for here, or every song from it that is not in the
    /// library already asked for.
    private func downloading(_ found: OnlineAlbumPage) -> Bool {
        let finds = found.songs.filter(\.isExternal)
        return asked || (!finds.isEmpty && finds.allSatisfy { downloads.state($0.id) != .none })
    }

    private func header(_ found: OnlineAlbumPage) -> some View {
        let album = found.album
        // The length only adds up when every song's length is known.
        let lengths = found.songs.map { $0.isExternal ? Int(knownLengthMs($0) / 1_000) : $0.duration }
        let length = !lengths.isEmpty && lengths.allSatisfy { $0 > 0 } ? lengths.reduce(0, +).spokenLength : nil
        let details = [album.year.map(String.init), album.songCount == 1 ? "1 song" : "\(album.songCount) songs", length]
            .compactMap { $0 }.joined(separator: " • ")
        let artistId = album.artistId.flatMap { $0.isEmpty ? nil : $0 }
        return VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                Cover(id: album.coverArt, size: 240, radius: 10)
                    .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
                Text(album.name)
                    .font(.octoTitle)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
                if let artistId {
                    NavigationLink(value: Route.onlineArtist(id: artistId, name: album.artist)) {
                        Text(album.artist).font(.octoBody).foregroundStyle(OctoColor.accent)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                } else {
                    Text(album.artist).font(.octoBody).foregroundStyle(OctoColor.textSecondary).padding(.top, 4)
                }
                HStack {
                    Text(details)
                        .font(.octoCaption)
                        .foregroundStyle(OctoColor.textMuted)
                        .lineLimit(2)
                    Spacer()
                }
                .frame(minHeight: 44)
                .padding(.top, 14)
                PlayButtons(songs: found.songs).padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            // The cover stays clean. The plus adds the album to the library; for an album partly
            // there, a note says how much of it is.
            if found.songs.contains(where: \.isExternal) {
                let busy = downloading(found)
                HStack(spacing: 0) {
                    Button { add(found) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 17))
                            Text(busy ? "Adding" : "Add to your library")
                                .font(DiscoveryStyle.label)
                                .lineLimit(1)
                        }
                        .foregroundStyle(OctoColor.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 12)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                    .opacity(busy ? 0.6 : 1)
                    if let note = albumLibraryNote(songs: found.songs.count,
                                                   outside: found.songs.filter { isOutsideLibrary($0, adopted: downloads.adopted) }.count) {
                        Spacer(minLength: 0)
                        Text(note)
                            .font(.octoCaption)
                            .foregroundStyle(OctoColor.textMuted)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                    }
                }
                .padding(.horizontal, 10)
            }
        }
        .padding(.top, detailTopGap)
        .padding(.bottom, 12)
    }

    /// Has the server download the whole album into the library.
    private func add(_ found: OnlineAlbumPage) {
        asked = true
        Task {
            if !(await downloads.requestAlbum(id, songs: found.songs, title: found.album.name)) { asked = false }
        }
    }

    private func reload() async {
        page = .loading
        page = await loadOnline { try await discovery.album(id) }
    }

    /// Asks the server again, keeping the page as it is if it cannot answer.
    private func refresh() async {
        let fresh = await loadOnline { try await discovery.album(id) }
        if case .ready = fresh { page = fresh }
    }

    /// The album's main song: the one first in the artist's top songs on the server.
    private func markHighlight() async {
        guard let found = page.value else { return }
        let ranked = await discovery.artistTopRefs(found.album.artist)
        highlight = albumHighlight(found.songs.map { ($0.id, $0.title, $0.byline) }, ranked)
    }
}

// MARK: Online artist

/// An artist on the server that is not in the library, with their albums.
struct OnlineArtistView: View {
    let id: String
    let name: String
    @Environment(Discovery.self) private var discovery
    @State private var page: LoadState<Artist> = .loading
    @State private var width: CGFloat = 390

    var body: some View {
        LoadStateContent(state: page, retry: { Task { await reload() } }) { artist in
            let columns = max(1, Int((width - 40 + 14) / (150 + 14)))
            let cell = (width - 40 - 14 * CGFloat(columns - 1)) / CGFloat(columns)
            ScrollView {
                VStack(spacing: 0) {
                    // The picture stays clean; the line under the name says it.
                    Cover(id: artist.coverArt, size: 160, radius: 80)
                    Text(artist.name)
                        .font(.octoTitle)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)
                    Text("\(artist.album.count == 1 ? "1 album" : "\(artist.album.count) albums") • \(notInLibraryText)")
                        .font(.octoCaption)
                        .foregroundStyle(OctoColor.textMuted)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, detailTopGap)
                .padding(.bottom, 8 + 18)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: 14, alignment: .top), count: columns),
                          alignment: .leading, spacing: 18) {
                    ForEach(artist.album) { album in
                        OnlineAlbumCard(album: counted(album), width: cell)
                    }
                }
                .padding(.horizontal, 20)
            }
            .barClearance()
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .task { if page.value == nil { await reload() } }
    }

    /// An online album's owned count is kept only when the server marks the album external.
    private func counted(_ album: Album) -> Album {
        var shown = album
        if !album.isExternal { shown.ownedCount = nil }
        return shown
    }

    private func reload() async {
        page = .loading
        page = await loadOnline { try await discovery.artist(id) }
    }
}

// MARK: Charts

/// The charts and new songs an Octo server reads from Apple Music, one at a time, picked with the
/// chips: the chart country's most played songs, Best New Songs, Trending Songs and a chart per
/// genre. A song the library has plays from it; any other has the add button at the end of its
/// row.
struct ChartsView: View {
    @Environment(Discovery.self) private var discovery
    @Environment(Player.self) private var player
    @State private var choices: [ChartChoice] = []
    @State private var selected = Charts.overall
    /// The chosen chart's songs, or nil while they are on their way.
    @State private var list: ChartList<Song>?
    /// Whether the server answered with nothing it can show.
    @State private var none = false
    @State private var loading: Task<Void, Never>?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ScreenTitle("Charts")
                if !choices.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(choices) { choice in
                                OnOffChip(text: choice.label, on: choice.id == selected) { pick(choice.id) }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .scrollIndicators(.hidden)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                }
                if none {
                    quiet("This server doesn't have charts.")
                } else if let list {
                    if list.songs.isEmpty {
                        quiet("Nothing in this chart right now. Try another.")
                    } else {
                        if let caption = chartCaption(source: list.source, chart: list.chart, country: list.country) {
                            quiet(caption)
                        }
                        Button { play(list, 0) } label: {
                            Text("Play all").font(DiscoveryStyle.label)
                        }
                        .buttonStyle(.glass)
                        .padding(.leading, 20)
                        .padding(.bottom, 8)
                        let all = list.songs.map(\.track)
                        ForEach(Array(list.songs.enumerated()), id: \.element.track.id) { index, ranked in
                            SongRow(song: ranked.track, list: all, position: index, offersAdd: true, addSpace: true, rank: ranked.rank,
                                    describe: { shown in
                                        [shown.byline.isEmpty ? nil : shown.byline, rowAlbum(shown).isEmpty ? nil : rowAlbum(shown),
                                         ranked.plays.map(playsText)].compactMap { $0 }.joined(separator: " • ")
                                    }) { play(list, index) }
                                .id("chart:\(list.chart):\(ranked.track.id)")
                        }
                    }
                } else {
                    ProgressView()
                        .tint(OctoColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                }
            }
            .padding(.top, detailTopGap)
        }
        .barClearance()
        .task {
            guard choices.isEmpty, list == nil else { return }
            load()
            choices = (await discovery.chartChoices())?.chart ?? []
            if choices.isEmpty, !(await discovery.offersCharts()) { none = true }
        }
    }

    private func quiet(_ text: String) -> some View {
        Text(text)
            .font(.octoCaption)
            .foregroundStyle(OctoColor.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
    }

    private func pick(_ chart: String) {
        if chart == selected { return }
        selected = chart
        load()
    }

    private func load() {
        loading?.cancel()
        list = nil
        let chart = selected
        loading = Task {
            let got = await discovery.chart(chart)
            guard !Task.isCancelled, chart == selected else { return }
            list = got ?? ChartList(chart: chart, name: nil, source: "", country: nil, songs: [])
        }
    }

    private func play(_ list: ChartList<Song>, _ index: Int) {
        player.play(list.songs.map(\.track), from: max(0, index))
    }
}
