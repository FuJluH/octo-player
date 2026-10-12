import OctoKit
import SwiftUI

/// Search: the library first, and on Octo the songs and albums it found online too, each marked
/// with the octopus.
struct SearchView: View {
    @Environment(Session.self) private var session
    @State private var query = ""
    @State private var results = SearchResult()
    @State private var searching = false
    @State private var failure: String?

    var body: some View {
        List {
            if !results.artist.isEmpty {
                Section("Artists") {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 16) {
                            ForEach(results.artist) { artist in
                                NavigationLink(value: Route.artist(id: artist.id, name: artist.name)) {
                                    VStack(spacing: 6) {
                                        Cover(id: artist.coverArt, size: 88, radius: 44)
                                        Text(artist.name).font(.octoCaption).lineLimit(1).frame(width: 88)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                }
            }
            if !results.album.isEmpty {
                Section("Albums") {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 14) {
                            ForEach(results.album) { AlbumTile(album: $0, size: 130) }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                }
            }
            if !results.song.isEmpty {
                Section("Songs") {
                    ForEach(Array(results.song.enumerated()), id: \.offset) { position, song in
                        SongRow(song: song, list: results.song, position: position)
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if query.isEmpty {
                ContentUnavailableView("Search your music", systemImage: "magnifyingglass",
                                       description: Text(session.isOcto ? "Octo looks online too." : "Artists, albums and songs."))
            } else if let failure {
                ContentUnavailableView("Couldn't search", systemImage: "wifi.exclamationmark", description: Text(failure))
            } else if !searching, results.artist.isEmpty, results.album.isEmpty, results.song.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Artists, albums, songs")
        .task(id: query) { await search() }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let client = session.client else {
            results = SearchResult()
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        do {
            let found = try await client.search(text)
            guard !Task.isCancelled else { return }
            results = found
            failure = nil
        } catch {
            if !Task.isCancelled { failure = error.localizedDescription }
        }
    }
}
