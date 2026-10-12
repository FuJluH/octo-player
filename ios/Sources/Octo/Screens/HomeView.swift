import OctoKit
import SwiftUI

/// Home: one page of shelves, in the other apps' order. A shelf with nothing in it is left out,
/// title and all.
struct HomeView: View {
    @Environment(Session.self) private var session
    @Environment(Player.self) private var player
    @Environment(Router.self) private var router
    @State private var recent: [Album] = []
    @State private var madeForYou: [Playlist] = []
    @State private var stations: [RadioStation] = []
    @State private var chart: [Song] = []
    @State private var newest: [Album] = []
    @State private var favorites: [Album] = []
    @State private var random: [Album] = []
    @State private var artists: [Artist] = []
    @State private var starting: String?
    @State private var loadedFor: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ScreenTitle("Home")
                if session.client == nil {
                    emptyCard
                } else {
                    albums("Recently played", recent)
                    if !madeForYou.isEmpty {
                        Shelf(title: "Made for you") {
                            ForEach(madeForYou) { list in
                                StationCard(name: list.name, coverArt: list.coverArt, songCount: list.songCount,
                                            loading: starting == list.id) { Task { await play(list.id, list.name) } }
                            }
                        }
                    }
                    if !stations.isEmpty {
                        Shelf(title: "Stations") {
                            ForEach(stations) { station in
                                StationCard(name: station.name, coverArt: station.coverArt ?? station.id,
                                            loading: starting == station.id) { Task { await play(station.id, station.name) } }
                            }
                        }
                    }
                    if !chart.isEmpty {
                        Shelf(title: "Charts") {
                            ForEach(Array(chart.enumerated()), id: \.offset) { position, song in
                                SongCard(song: song, list: chart, position: position)
                            }
                        }
                    }
                    albums("Recently added", newest)
                    albums("Favorite albums", favorites, destination: .favorites)
                    albums("Something different", random)
                    if !artists.isEmpty {
                        Shelf(title: "Artists") {
                            ForEach(artists) { ArtistCircle(id: $0.id, name: $0.name, coverArt: $0.coverArt) }
                        }
                    }
                }
            }
        }
        .barClearance()
        .refreshable { await load() }
        .task(id: session.client?.baseURL) {
            guard loadedFor != session.activeId else { return }
            await load()
        }
    }

    @ViewBuilder
    private func albums(_ title: String, _ list: [Album], destination: Route? = nil) -> some View {
        if !list.isEmpty {
            Shelf(title: title, destination: destination) {
                ForEach(list) { AlbumCard(album: $0) }
            }
        }
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No music yet").font(.octoHeadline)
            Text("Songs on this phone and on your server show up here on their own.")
                .font(.octoBodySmall)
                .foregroundStyle(OctoColor.textSecondary)
            Button("Sign in to a server") { router.signIn = .signIn }
                .buttonStyle(.glassProminent)
                .padding(.top, 8)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func load() async {
        guard let client = session.client else { return }
        loadedFor = session.activeId
        let octo = session.isOcto
        let charts = session.profile?.has("octoTopSongs") ?? false
        async let recent = client.albumList(.recent, size: 20)
        async let newest = client.albumList(.newest, size: 20)
        async let random = client.albumList(.random, size: 20)
        async let starred = client.starred()
        async let lists = client.playlists()
        async let allArtists = client.artists()
        self.recent = (try? await recent) ?? self.recent
        self.newest = (try? await newest) ?? self.newest
        self.random = (try? await random) ?? self.random
        favorites = Array(((try? await starred)?.album ?? favorites).prefix(20))
        madeForYou = ((try? await lists) ?? []).filter { $0.octoList != nil }.sorted {
            (octoListKinds.firstIndex(of: $0.octoList ?? "") ?? 99) < (octoListKinds.firstIndex(of: $1.octoList ?? "") ?? 99)
        }
        artists = Array(((try? await allArtists) ?? []).shuffled().prefix(16))
        if charts { chart = Array(((try? await client.topChart(count: 10, chart: Charts.overall))?.songs ?? []).prefix(10)) }
        if octo { stations = (try? await client.stations()) ?? stations }
    }

    /// A station or Made for you list plays at once; it is a read-only playlist on Octo.
    private func play(_ id: String, _ name: String) async {
        guard starting == nil, let client = session.client else { return }
        starting = id
        defer { starting = nil }
        do {
            let songs = try await client.playlist(id).entry
            guard !songs.isEmpty else {
                router.show("Nothing is playing on \(name) right now")
                return
            }
            player.play(songs)
        } catch OctoError.notFound {
            stations.removeAll { $0.id == id }
            madeForYou.removeAll { $0.id == id }
            router.show("\(name) isn't on the server any more")
        } catch {
            router.show("Could not start \(name)")
        }
    }
}
