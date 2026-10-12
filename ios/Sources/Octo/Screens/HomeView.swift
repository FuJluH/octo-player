import OctoKit
import SwiftUI

/// Home: Octo's Made for you lists first, then what's new and what gets played.
struct HomeView: View {
    @Environment(Session.self) private var session
    @State private var madeForYou: [Playlist] = []
    @State private var newest: [Album] = []
    @State private var recent: [Album] = []
    @State private var frequent: [Album] = []
    @State private var rediscover: [Album] = []
    @State private var failure: String?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                if let failure, !loaded {
                    LoadFailed(message: failure) { await load() }
                }
                if !madeForYou.isEmpty {
                    Shelf(title: "Made for You") {
                        ForEach(madeForYou) { PlaylistTile(playlist: $0) }
                    }
                }
                shelf("Recently Added", newest)
                shelf("Recently Played", recent)
                shelf("Most Played", frequent)
                shelf("Rediscover", rediscover)
            }
            .padding(.vertical, 12)
        }
        .navigationTitle("Home")
        .task { if !loaded { await load() } }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func shelf(_ title: String, _ albums: [Album]) -> some View {
        if !albums.isEmpty {
            Shelf(title: title) {
                ForEach(albums) { AlbumTile(album: $0) }
            }
        }
    }

    private func load() async {
        guard let client = session.client else { return }
        do {
            async let lists = client.playlists()
            async let newest = client.albumList(.newest, size: 20)
            async let recent = client.albumList(.recent, size: 20)
            async let frequent = client.albumList(.frequent, size: 20)
            async let random = client.albumList(.random, size: 20)
            let made = (try? await lists)?.filter { $0.octoList != nil } ?? []
            madeForYou = made.sorted {
                (octoListKinds.firstIndex(of: $0.octoList ?? "") ?? 99) < (octoListKinds.firstIndex(of: $1.octoList ?? "") ?? 99)
            }
            self.newest = try await newest
            self.recent = (try? await recent) ?? []
            self.frequent = (try? await frequent) ?? []
            rediscover = (try? await random) ?? []
            loaded = true
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }
}
