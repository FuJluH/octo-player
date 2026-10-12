import OctoKit
import SwiftUI

/// Search: its own field under the title, the kinds to search, recent searches while the field
/// is empty, the library's answers first and, on Octo, what it found online below them.
struct SearchView: View {
    enum Kind: String, CaseIterable { case all = "All", songs = "Songs", albums = "Albums", artists = "Artists" }

    @Environment(Session.self) private var session
    @Environment(Player.self) private var player
    @AppStorage("search.recent") private var recentStore = ""
    @State private var query = ""
    @State private var kind: Kind = .all
    @State private var results = SearchResult()
    @State private var searching = false
    @State private var failure: String?
    @FocusState private var focused: Bool

    private var recent: [String] { recentStore.split(separator: "\n").map(String.init) }
    private var library: SearchResult {
        SearchResult(artist: results.artist, album: results.album.filter { !$0.isExternal }, song: results.song.filter { !$0.isExternal })
    }
    private var online: SearchResult {
        SearchResult(artist: [], album: results.album.filter(\.isExternal), song: results.song.filter(\.isExternal))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ScreenTitle("Search")
                field
                Picker("", selection: $kind) {
                    ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                content
            }
        }
        .barClearance()
        .scrollDismissesKeyboard(.immediately)
        .task(id: query) { await search() }
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(OctoColor.textMuted)
            TextField("Songs, albums, artists", text: $query)
                .font(.octoBody)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focused)
                .onSubmit { remember(query) }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(OctoColor.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(OctoColor.accent.opacity(focused ? 0.15 : 0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(OctoColor.accent.opacity(focused ? 0.6 : 0.1), lineWidth: focused ? 1.5 : 1))
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var content: some View {
        let text = query.trimmingCharacters(in: .whitespaces)
        if text.count < 2 {
            if recent.isEmpty {
                hint(session.client == nil ? "Search the music on your phone" : "Search your music and discover more")
            } else {
                HStack {
                    Text("Recent searches").font(.octoSection)
                    Spacer()
                    Button("Clear all") { recentStore = "" }.font(.octoBodySmall).buttonStyle(.plain).foregroundStyle(OctoColor.textSecondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                ForEach(recent, id: \.self) { item in
                    HStack {
                        Button { query = item } label: {
                            Text(item).font(.octoBody).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        Button { forget(item) } label: { Image(systemName: "xmark").foregroundStyle(OctoColor.textMuted) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(item)")
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 48)
                }
            }
        } else if let failure {
            hint(failure)
        } else if !searching, results.artist.isEmpty, results.album.isEmpty, results.song.isEmpty {
            hint("No results for \u{201C}\(text)\u{201D}")
        } else {
            sections(library)
            if kind != .artists, !online.album.isEmpty || !online.song.isEmpty {
                SectionTitle("Not in your library").padding(.top, 12)
                if kind == .all || kind == .songs {
                    ForEach(Array(online.song.enumerated()), id: \.offset) { position, song in
                        SongRow(song: song, list: online.song, position: position)
                    }
                }
                if (kind == .all || kind == .albums), !online.album.isEmpty {
                    Shelf(title: "Albums") { ForEach(online.album) { AlbumCard(album: $0) } }
                }
            }
        }
    }

    @ViewBuilder
    private func sections(_ found: SearchResult) -> some View {
        if (kind == .all || kind == .artists), !found.artist.isEmpty {
            Shelf(title: "Artists") {
                ForEach(found.artist) { ArtistCircle(id: $0.id, name: $0.name, coverArt: $0.coverArt) }
            }
        }
        if (kind == .all || kind == .albums), !found.album.isEmpty {
            Shelf(title: "Albums") { ForEach(found.album) { AlbumCard(album: $0) } }
        }
        if (kind == .all || kind == .songs), !found.song.isEmpty {
            SectionTitle("Songs").padding(.top, 8)
            ForEach(Array(found.song.enumerated()), id: \.offset) { position, song in
                SongRow(song: song, list: found.song, position: position)
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.octoBodySmall)
            .foregroundStyle(OctoColor.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2, let client = session.client else {
            results = SearchResult()
            failure = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        do {
            let found = try await client.search(text)
            guard !Task.isCancelled else { return }
            results = found
            failure = nil
        } catch {
            if !Task.isCancelled { failure = "Could not reach your server" }
        }
    }

    /// Ten recent searches, newest first, repeats moved to the top.
    private func remember(_ text: String) {
        let clean = text.split(separator: " ").joined(separator: " ")
        guard clean.count >= 2 else { return }
        let kept = [clean] + recent.filter { $0.caseInsensitiveCompare(clean) != .orderedSame }
        recentStore = kept.prefix(10).joined(separator: "\n")
    }

    private func forget(_ text: String) {
        recentStore = recent.filter { $0 != text }.joined(separator: "\n")
    }
}
