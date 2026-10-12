import OctoKit
import SwiftUI

/// The library pages beyond Albums, Artists, Playlists and Favorites.
enum LibraryPage: Hashable, Codable {
    case songs
    case genres
    case genre(String)
    case folders
    case history(mostPlayed: Bool)
    case downloads
    case health
    case healthCheck(String)
    case recentlyRemoved
    case favorites(FavoriteSegment?)
    case playlist(id: String)
}

extension LibraryPage {
    /// What kind of page this is, as the glow sees it.
    var ambientPage: AmbientPage {
        switch self {
        case .songs: .songs
        case .genres: .genres
        case .genre: .genre
        case .folders: .folders
        case .history: .history
        case .downloads: .downloads
        case .health: .libraryHealth
        case .healthCheck: .healthCheck
        case .recentlyRemoved: .healthTrash
        case .favorites(let segment): segment == .songs ? .liked : .favorites
        case .playlist: .playlist
        }
    }
}

/// The page for one of them.
struct LibraryPageView: View {
    let page: LibraryPage

    var body: some View {
        switch page {
        case .songs: SongsPage()
        case .genres: GenresPage()
        case .genre(let name): GenrePage(name: name)
        case .folders: FoldersPage()
        case .history(let mostPlayed): HistoryPage(mostPlayed: mostPlayed)
        case .downloads: DownloadsPage()
        case .health: HealthPage()
        case .healthCheck(let check): HealthCheckPage(check: check)
        case .recentlyRemoved: RecentlyRemovedPage()
        case .favorites(let segment): FavoritesView(opening: segment)
        case .playlist(let id): PlaylistPage(id: id)
        }
    }
}

// MARK: Songs

/// The quick filters on the Songs page, in their order.
enum QuickFilter: CaseIterable, Hashable {
    case favorites, week, month, year, neverPlayed, notLately, lossless

    var label: String {
        switch self {
        case .favorites: "Favorites"
        case .week: "Added in the last week"
        case .month: "Added in the last month"
        case .year: "Added in the last year"
        case .neverPlayed: "Never played"
        case .notLately: "Not played in the last 6 months"
        case .lossless: "Lossless"
        }
    }

    /// Filters on the same field replace each other.
    var field: Int {
        switch self {
        case .favorites: 0
        case .week, .month, .year: 1
        case .neverPlayed, .notLately: 2
        case .lossless: 3
        }
    }
}

/// What the Songs page is narrowed to: words, quick filters, a rating, a genre and a decade.
struct SongFilters: Equatable {
    var words = ""
    var quick: [QuickFilter] = []
    var rating: Int?
    var genre: String?
    var decade: Int?

    var any: Bool {
        !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !quick.isEmpty || rating != nil || genre != nil || decade != nil
    }

    /// A quick filter on takes the place of any other on the same field; on again takes it off.
    mutating func toggle(_ filter: QuickFilter) {
        if quick.contains(filter) {
            quick.removeAll { $0 == filter }
        } else {
            quick.removeAll { $0.field == filter.field }
            quick.append(filter)
        }
    }

    /// What a song needs to pass, worked out once for a whole list.
    struct Facts {
        var liked: Set<String>
        var played: [String: Listening]
        var ratings: (LibraryTrack) -> Int
        var now: Int64
    }

    func matches(_ track: LibraryTrack, _ facts: Facts) -> Bool {
        let words = foldedWords(self.words)
        if !words.isEmpty {
            let fields = [track.title, track.artist, track.album, track.genre].map(foldedText)
            for word in words where !fields.contains(where: { $0.contains(word) }) { return false }
        }
        let day: Int64 = 86_400_000
        let added = track.addedAt * 1_000
        let heard = facts.played[track.id]
        let lastPlayed = heard?.lastPlayedAt ?? 0
        for filter in quick {
            switch filter {
            case .favorites: if !facts.liked.contains(track.id) { return false }
            case .week: if added <= 0 || added < facts.now - 7 * day { return false }
            case .month: if added <= 0 || added < facts.now - 30 * day { return false }
            case .year: if added <= 0 || added < facts.now - 365 * day { return false }
            case .neverPlayed: if lastPlayed > 0 || (heard?.plays ?? 0) > 0 { return false }
            case .notLately: if lastPlayed > 0 && lastPlayed >= facts.now - 180 * day { return false }
            case .lossless: if !losslessTrack(track) { return false }
            }
        }
        if let rating, facts.ratings(track) < rating { return false }
        if let genre, foldedText(track.genre) != foldedText(genre) { return false }
        if let decade {
            guard let year = track.year, year >= decade, year < decade + 10 else { return false }
        }
        return true
    }

    /// Lossless by the file's type or its format.
    private func losslessTrack(_ track: LibraryTrack) -> Bool {
        guard let mime = track.mimeType else { return false }
        return isLosslessMime(mime) || isLosslessKind(formatOf(mime))
    }
}

/// Lower case with accents gone.
func foldedText(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
}

/// Typed words, split on spaces, tabs and new lines, each folded.
func foldedWords(_ text: String) -> [String] {
    text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map { foldedText(String($0)) }.filter { !$0.isEmpty }
}

/// Every song, in the chosen order, with a search and filter chips.
struct SongsPage: View {
    @Environment(Library.self) private var library
    @Environment(LibraryState.self) private var state
    @Environment(LibraryActions.self) private var actions
    @State private var sorted: Sorted<LibraryTrack>?
    @State private var shown: [LibraryTrack]?
    @State private var shownHeadings: [String]?
    @State private var filters = SongFilters()
    @State private var searchOpen = false
    @State private var genreChoices: [String] = []
    @State private var decadeChoices: [Int] = []
    @FocusState private var fieldFocused: Bool

    private var searching: Bool { searchOpen || filters.any }

    var body: some View {
        let order = state.order(.songs)
        let list = shown ?? []
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    TitleWithButtons(title: "Songs") {
                        if let sorted, !sorted.items.isEmpty {
                            GlassIconButton(icon: searching ? .close : .search,
                                            label: searching ? "Close the search" : "Search these songs", lit: searching) {
                                if searching { closeSearch() } else { openSearch() }
                            }
                        }
                        SortButton(list: .songs)
                    }
                    .padding(.top, detailTopGap)
                    if searching { searchPanel.transition(.opacity.combined(with: .move(edge: .top))) }
                    if let sorted {
                        if sorted.items.isEmpty {
                            EmptyLibraryNote()
                        } else if shown == nil {
                            LibrarySpinner()
                        } else if list.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("No songs match these filters").font(.octoBodySmall).foregroundStyle(OctoColor.textMuted)
                                QuietButton("Clear filters") { filters = SongFilters() }.padding(.leading, -10)
                            }
                            .padding(20)
                        } else {
                            ListPlayLine(count: filters.any ? filteredCount(shown: list.count, all: sorted.items.count)
                                         : countText(list.count, "song", "songs")) {
                                actions.play(list)
                            } shuffle: {
                                actions.play(list, shuffled: true)
                            }
                            LetterRuns(items: list, headings: shownHeadings, id: \.id) { position, track in
                                TrackRow(track: track) { actions.play(list, from: position) }
                            }
                            Color.clear.frame(height: 140)
                        }
                    } else {
                        LibrarySpinner()
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.9), value: searching)
            }
            .letterRail(shownHeadings, count: list.count, byName: order.by.byName) { index in proxy.scrollTo("run-\(index)", anchor: .top) }
            .onChange(of: order) { _, _ in if let first = list.first { proxy.scrollTo(first.id, anchor: .top) } }
        }
        .barClearance()
        .backAction(searching ? { closeSearch() } : nil)
        .backStopsPicking()
        .selectableSongs(state.pickables(list))
        .libraryRefreshable {}
        .onAppear {
            #if DEBUG
            if let words = LibraryDrive.pendingSearch {
                LibraryDrive.pendingSearch = nil
                searchOpen = true
                filters.words = words
            }
            #endif
        }
        .task(id: "\(library.stamp(.library, .likes, .ratings, .plays))|\(order.by.id)|\(order.descending)") {
            let read = await library.sortedSongs(order)
            sorted = read
            genreChoices = genresOf(read.items)
            decadeChoices = Array(Set(read.items.compactMap { $0.year.map { $0 / 10 * 10 } })).sorted(by: >)
            await applyFilters()
        }
        .task(id: filters) { await applyFilters() }
    }

    /// Works the shown list out again from the whole list and the filters.
    private func applyFilters() async {
        guard let sorted else { return }
        guard filters.any else {
            shown = sorted.items
            shownHeadings = sorted.headings
            return
        }
        let facts = SongFilters.Facts(liked: state.likedIds, played: songListening(await library.playedTracks()),
                                      ratings: { state.rating(of: $0) }, now: Int64(Date().timeIntervalSince1970 * 1_000))
        var items: [LibraryTrack] = []
        var headings: [String] = []
        for (index, track) in sorted.items.enumerated() where filters.matches(track, facts) {
            items.append(track)
            if let all = sorted.headings { headings.append(all[index]) }
        }
        shown = items
        shownHeadings = sorted.headings == nil ? nil : headings
    }

    /// Each genre once, case and accents folded, the first spelling kept, sorted A to Z.
    private func genresOf(_ tracks: [LibraryTrack]) -> [String] {
        var seen: [String: String] = [:]
        for track in tracks where !track.genre.trimmingCharacters(in: .whitespaces).isEmpty {
            let key = foldedText(track.genre)
            if seen[key] == nil { seen[key] = track.genre }
        }
        return seen.values.sorted { naturalSortKey($0) < naturalSortKey($1) }
    }

    private func openSearch() {
        searchOpen = true
        Task {
            try? await Task.sleep(for: .milliseconds(16))
            fieldFocused = true
        }
    }

    /// Closing the search clears the words and every filter; the order stays.
    private func closeSearch() {
        fieldFocused = false
        searchOpen = false
        filters = SongFilters()
    }

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                IconView(.search, size: 20, color: OctoColor.textMuted)
                TextField("Search songs", text: $filters.words)
                    .focused($fieldFocused)
                    .submitLabel(.search)
                    .onSubmit { fieldFocused = false }
                    .autocorrectionDisabled()
                if !filters.words.isEmpty {
                    Button { filters.words = "" } label: {
                        IconView(.close, size: 18, color: OctoColor.textMuted).frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear the words")
                }
            }
            .padding(.leading, 14)
            .frame(minHeight: 44)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 20)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    if filters.any {
                        FilterChip(text: "Clear all", on: false) { filters = SongFilters() }
                        if let open = LiveListHook.newLiveList {
                            FilterChip(text: "Save as live list", on: false) {
                                open(LiveListSeed(words: filters.words.trimmingCharacters(in: .whitespacesAndNewlines),
                                                  rules: chipWords, order: state.order(.songs)))
                            }
                        }
                    }
                    ForEach(QuickFilter.allCases, id: \.self) { filter in
                        FilterChip(text: filter.label, on: filters.quick.contains(filter)) { filters.toggle(filter) }
                    }
                    askingChip(on: filters.rating.map { "Rating at least \($0)" }, off: "Rating", title: "Rating",
                               answers: [(5, "5 stars"), (4, "4 stars or more"), (3, "3 stars or more"), (2, "2 stars or more"), (1, "1 star or more")]) {
                        filters.rating = $0
                    } clear: { filters.rating = nil }
                    if !genreChoices.isEmpty || filters.genre != nil {
                        askingChip(on: filters.genre.map { "Genre is \($0)" }, off: "Genre", title: "Genre",
                                   answers: genreChoices.map { ($0, $0) }) { filters.genre = $0 } clear: { filters.genre = nil }
                    }
                    if !decadeChoices.isEmpty || filters.decade != nil {
                        askingChip(on: filters.decade.map { "From the \($0)s" }, off: "Year", title: "Year",
                                   answers: decadeChoices.map { ($0, "The \($0)s") }) { filters.decade = $0 } clear: { filters.decade = nil }
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, 2)
        .padding(.bottom, 10)
    }

    /// The words of every filter on, for a live list made from them.
    private var chipWords: [String] {
        var out = filters.quick.map(\.label)
        if let rating = filters.rating { out.append("Rating at least \(rating)") }
        if let genre = filters.genre { out.append("Genre is \(genre)") }
        if let decade = filters.decade { out.append("From the \(decade)s") }
        return out
    }

    /// A chip that asks a question when off and reads as its filter when on; a tap on it then
    /// takes the filter off.
    @ViewBuilder
    private func askingChip<T: Hashable>(on: String?, off: String, title: String, answers: [(T, String)],
                                         pick: @escaping (T) -> Void, clear: @escaping () -> Void) -> some View {
        if let on {
            FilterChip(text: on, on: true, action: clear)
        } else {
            Menu {
                Section(title) {
                    ForEach(answers.indices, id: \.self) { index in
                        Button(answers[index].1) { pick(answers[index].0) }
                    }
                }
            } label: {
                chipLabel(off, on: false)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isToggle)
        }
    }
}

// MARK: Genres

/// Every genre with its song count and a cover from its songs.
struct GenresPage: View {
    @Environment(Library.self) private var library
    @State private var genres: [GenreSummary]?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ScreenTitle("Genres").padding(.top, detailTopGap)
                if let genres {
                    if genres.isEmpty {
                        MutedNote("None of your songs has a genre yet")
                    }
                    ForEach(genres, id: \.name) { genre in
                        NavigationLink(value: Route.library(.genre(genre.name))) {
                            HStack(spacing: 12) {
                                ArtCover(artwork: genre.artwork, size: 48, radius: 6)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(genre.name).font(.octoBodySmall).foregroundStyle(.white).lineLimit(1)
                                    Text(songsCount(genre.songCount)).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 20)
                            .frame(height: 64)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(SqueezeStyle())
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .barClearance()
        .libraryRefreshable {}
        .task(id: library.stamp(.library)) { genres = await library.genres() }
    }
}

/// One genre: its albums, then its songs in the chosen order.
struct GenrePage: View {
    let name: String
    @Environment(Library.self) private var library
    @Environment(LibraryState.self) private var state
    @Environment(LibraryActions.self) private var actions
    @State private var albums: [LibraryAlbum] = []
    @State private var songs: [LibraryTrack] = []
    @State private var gridWidth: CGFloat = 390

    var body: some View {
        let order = state.order(.genreSongs)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 0) {
                        Text(name).font(.octoTitle).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                        Text("\(albumsCount(albums.count)) • \(songsCount(songs.count))")
                            .font(.octoCaption)
                            .foregroundStyle(OctoColor.textMuted)
                            .padding(.top, 14)
                        PlayShuffle(enabled: !songs.isEmpty) { actions.play(songs) } shuffle: { actions.play(songs, shuffled: true) }
                            .padding(.top, 10)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, detailTopGap)
                    .padding(.bottom, 20)
                    albumGrid
                    if !songs.isEmpty { SortBar(name: "Songs", list: .genreSongs).id("songs") }
                    ForEach(Array(songs.enumerated()), id: \.element.id) { position, track in
                        TrackRow(track: track) { actions.play(songs, from: position) }
                    }
                }
                .padding(.bottom, 20)
            }
            .onChange(of: order) { _, _ in proxy.scrollTo("songs", anchor: .top) }
        }
        .barClearance()
        .backStopsPicking()
        .selectableSongs(state.pickables(songs))
        .libraryRefreshable {}
        .task(id: "\(name)|\(library.stamp(.library, .likes, .ratings, .plays))|\(order.by.id)|\(order.descending)") {
            albums = await library.genreAlbums(name).sorted { $0.sortKey < $1.sortKey }
            songs = await library.sortedSongs(order, scope: .genre(name)).items
        }
    }

    /// As many 150-wide columns as fit in the width less 40, every card the same width, a short
    /// last row padded with empty cells.
    @ViewBuilder
    private var albumGrid: some View {
        let columns = max(1, Int((gridWidth - 40 + 14) / (150 + 14)))
        let width = max(0, (gridWidth - 40 - CGFloat(columns - 1) * 14) / CGFloat(columns))
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(stride(from: 0, to: albums.count, by: columns)), id: \.self) { start in
                HStack(alignment: .top, spacing: 14) {
                    ForEach(start..<(start + columns), id: \.self) { index in
                        if index < albums.count {
                            AlbumCard(album: albums[index].asAlbum, width: width, library: albums[index])
                        } else {
                            Color.clear.frame(width: width, height: 1)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
    }
}

// MARK: History

/// What was played: the latest plays under a heading per day, or the most played over a range.
struct HistoryPage: View {
    @State var mostPlayed: Bool
    @Environment(Library.self) private var library
    @Environment(LibraryActions.self) private var actions
    @State private var days: [HistoryDay]?
    @State private var most: [PlayedTrack]?
    @State private var range: HistoryRange = .fourWeeks

    private static let time: DateFormatter = {
        let format = DateFormatter()
        format.timeStyle = .short
        format.dateStyle = .none
        return format
    }()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ScreenTitle("History").padding(.top, detailTopGap)
                GlassSegments(options: [(false, "Recently played"), (true, "Most played")], selection: $mostPlayed)
                    .padding(.horizontal, 20)
                if mostPlayed { mostPlayedList } else { recentList }
            }
            .padding(.bottom, 20)
        }
        .barClearance()
        .task(id: library.stamp(.plays, .library)) {
            days = await library.historyDays(limit: 500)
        }
        .task(id: "\(range)|\(library.stamp(.plays, .library))") {
            most = await library.mostPlayed(range, limit: 100)
        }
    }

    @ViewBuilder
    private var recentList: some View {
        if let days {
            if days.isEmpty {
                MutedNote("Nothing played yet", vertical: 24)
            } else {
                let plays = days.flatMap(\.plays)
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    SectionTitle(day.label).padding(.top, 8)
                    ForEach(Array(day.plays.enumerated()), id: \.offset) { _, play in
                        TrackRow(track: play.track,
                                 subtitle: "\(play.track.artist) • \(Self.time.string(from: Date(timeIntervalSince1970: Double(play.at) / 1_000)))") {
                            playFrom(play.track, in: plays.map(\.track))
                        }
                    }
                }
            }
        } else {
            LibrarySpinner()
        }
    }

    /// Plays every song listed, each once where it first shows, from the tapped one's first showing.
    private func playFrom(_ track: LibraryTrack, in all: [LibraryTrack]) {
        var seen = Set<String>()
        let once = all.filter { seen.insert($0.id).inserted }
        actions.play(once, from: once.firstIndex { $0.id == track.id } ?? 0)
    }

    @ViewBuilder
    private var mostPlayedList: some View {
        HStack {
            Spacer()
            Menu {
                Picker("Most played in", selection: $range) {
                    ForEach(HistoryRange.allCases, id: \.self) { range in Text(range.label).tag(range) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(range.label).font(LibraryLook.label)
                    IconView(.collapse, size: 14)
                }
                .foregroundStyle(OctoColor.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Most played, \(range.label)")
            .accessibilityHint("Change the time range")
        }
        .padding(.top, 8)
        .padding(.horizontal, 10)
        if let most {
            if most.isEmpty {
                MutedNote(range == .allTime ? "Nothing played yet"
                          : range == .fourWeeks ? "Nothing played in the last 4 weeks" : "Nothing played in the last 6 months", vertical: 24)
            } else {
                let tracks = most.map(\.track)
                ForEach(Array(most.enumerated()), id: \.offset) { position, played in
                    TrackRow(track: played.track,
                             subtitle: "\(played.track.artist) • \(played.plays == 1 ? "1 play" : "\(played.plays) plays")") {
                        actions.play(tracks, from: position)
                    }
                }
            }
        } else {
            LibrarySpinner()
        }
    }
}

// MARK: Downloads

/// Songs downloaded to the phone from the server in use: the ones on their way with how far they
/// are, then the ones on the phone. One asked for by hand can be swiped away or held to remove it.
struct DownloadsPage: View {
    @Environment(Library.self) private var library
    @Environment(LibraryState.self) private var state
    @Environment(LibraryActions.self) private var actions
    @Environment(OfflineDownloads.self) private var offline
    @State private var confirming = false
    @State private var playlistNames: [String: String] = [:]
    @State private var removals = 0

    var body: some View {
        let order = state.order(.downloads)
        let rows = offline.rows
        let shown = sortDownloads(rows, order, done: { $0.state == .done }, title: \.title, id: \.trackId, size: \.sizeBytes,
                                  addedAt: \.addedAt)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                TitleWithButtons(title: "Downloads") { if !rows.isEmpty { SortButton(list: .downloads) } }
                    .padding(.top, detailTopGap)
                if rows.isEmpty {
                    MutedNote("Songs you download play without a connection. Long press a song and choose Download, or keep a playlist downloaded from its page.")
                } else {
                    summary(rows)
                    ForEach(shown) { row in downloadRow(row, shown) }
                }
            }
            .padding(.bottom, 20)
            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: shown.map(\.id))
        }
        .barClearance()
        .sensoryFeedback(.impact, trigger: removals)
        .task(id: library.stamp(.playlists)) {
            playlistNames = Dictionary((await library.playlists()).map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        }
    }

    private func summary(_ rows: [DownloadListRow]) -> some View {
        let done = rows.filter { $0.state == .done }
        return VStack(alignment: .leading, spacing: 0) {
            Text("\(songsCount(done.count)) · \(sizeLabel(done.reduce(0) { $0 + $1.sizeBytes }))")
                .font(.octoCaption)
                .foregroundStyle(OctoColor.textMuted)
            if confirming {
                Text("Remove every download from this phone? Liked songs and playlists stop being kept downloaded too.")
                    .font(.octoBodySmall)
                    .foregroundStyle(OctoColor.textSecondary)
                    .padding(.top, 10)
                HStack(spacing: 12) {
                    AccentButton("Remove all", size: .medium) {
                        offline.removeAll()
                        confirming = false
                    }
                    GlazeButton("Cancel", size: .medium) { confirming = false }
                }
                .padding(.top, 12)
            } else {
                GlazeButton("Remove all", size: .medium) { confirming = true }
                    .padding(.top, 12)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func downloadRow(_ row: DownloadListRow, _ shown: [DownloadListRow]) -> some View {
        let reasons = DownloadReasons.parse(row.reason)
        let byHand = reasons.contains(DownloadReasons.manual)
        let detail = downloadDetail(row.state, progress: Double(row.progress), sizeBytes: row.sizeBytes, reasons: reasons,
                                    playlistNames: playlistNames)
        return Button {
            switch row.state {
            case .failed: offline.retry(row.trackId)
            case .done:
                Task {
                    let done = shown.filter { $0.state == .done }
                    let tracks = await library.tracks(ids: done.map(\.trackId))
                    actions.play(tracks, from: tracks.firstIndex { $0.id == row.trackId } ?? 0)
                }
            default: break
            }
        } label: {
            HStack(spacing: 12) {
                ArtCover(artwork: row.artwork, size: 44, radius: 6)
                VStack(alignment: .leading, spacing: 2) {
                    SongTitleLine(row.title, explicit: row.explicit == true)
                    Text("\(row.artist) · \(detail)")
                        .font(.octoCaption)
                        .foregroundStyle(row.state == .failed ? OctoColor.textSecondary : OctoColor.textMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .frame(height: 60)
            .overlay(alignment: .bottom) {
                if row.state == .downloading {
                    GeometryReader { box in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.white.opacity(0.08))
                            Rectangle().fill(OctoColor.accent).frame(width: box.size.width * CGFloat(row.progress))
                        }
                    }
                    .frame(height: 2)
                    .padding(.leading, 76)
                    .padding(.trailing, 20)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SqueezeStyle())
        .rowSwipe(.remove { remove(row) }, enabled: byHand)
        .contextMenu {
            if byHand {
                Button("Remove download", systemImage: OctoIcon.delete.symbol, role: .destructive) { remove(row) }
            }
        }
        .accessibilityAction(named: "Remove download") { if byHand { remove(row) } }
    }

    private func remove(_ row: DownloadListRow) {
        removals += 1
        actions.removeDownload(row.trackId)
    }
}
