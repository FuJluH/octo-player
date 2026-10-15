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

/// Every song, in the chosen order, which the search above narrows: the words typed, and chips
/// for the quick filters, a rating, a genre and a decade. A tap plays the list as shown from that
/// song.
struct SongsPage: View {
    @Environment(Library.self) private var library
    @Environment(LibraryState.self) private var state
    @Environment(LibraryActions.self) private var actions
    @Environment(Router.self) private var router
    @Environment(\.octoReduceMotion) private var calm
    @State private var sorted: Sorted<LibraryTrack>?
    /// The songs as the filters leave them, in the chosen order; nil until first worked out.
    @State private var shown: Sorted<LibraryTrack>?
    /// The words typed and the chips on, for this visit only.
    @State private var query = LibraryQuery()
    @State private var searchOpen = false
    @State private var genreChoices: [String] = []
    @State private var decadeChoices: [Int] = []
    @FocusState private var fieldFocused: Bool

    /// Searching while the panel is open or any filter is on, so a page coming back with filters
    /// keeps its panel open.
    private var searching: Bool { searchOpen || query.filters }

    var body: some View {
        let order = state.order(.songs)
        let list = shown?.items ?? []
        ScrollViewReader { proxy in
            LibraryList {
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
                .bigTitle()
                if sorted != nil, searching {
                    searchPanel.transition(calm ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
                if let sorted {
                    if sorted.items.isEmpty {
                        EmptyLibraryNote()
                    } else if let shown {
                        if shown.items.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("No songs match these filters").font(.octoBodySmall).foregroundStyle(OctoColor.textMuted)
                                QuietButton("Clear filters") { query = query.cleared() }.padding(.leading, -10)
                            }
                            .padding(20)
                        } else {
                            ListPlayLine(count: query.filters ? filteredCount(shown: list.count, all: sorted.items.count)
                                         : countText(list.count, "song", "songs")) {
                                actions.play(list, source: "Songs")
                            } shuffle: {
                                actions.play(list, shuffled: true, source: "Songs")
                            }
                            FirstRowMark().id("first")
                            LetterRuns(items: list, headings: shown.headings, id: \.id) { position, track in
                                TrackRow(track: track) { actions.play(list, from: position, source: "Songs") }
                            }
                            Color.clear.frame(height: 140)
                        }
                    } else {
                        LibrarySpinner()
                    }
                } else {
                    LibrarySpinner()
                }
            }
            .animation(calm ? .easeOut(duration: 0.12) : .spring(response: 0.35, dampingFraction: 0.9), value: searching)
            .animation(.easeOut(duration: 0.25), value: shown?.order)
            .letterRail(shown?.headings, count: list.count, byName: order.by.byName) { index in
                let runs = letterRuns(shown?.headings ?? [])
                if runs.indices.contains(index), list.indices.contains(runs[index].start) {
                    proxy.scrollTo(list[runs[index].start].id, anchor: .top)
                }
            }
            .topOnNewOrder(shown?.order) { proxy.scrollTo("first", anchor: .top) }
        }
        .barClearance()
        .inlineTitle("Songs")
        .backAction(searching ? { closeSearch() } : nil)
        .backStopsPicking()
        .selectableSongs(state.pickables(list))
        .libraryRefreshable {}
        .onAppear {
            #if DEBUG
            if let words = LibraryDrive.pendingSearch {
                LibraryDrive.pendingSearch = nil
                searchOpen = true
                query = query.withText(words)
            }
            if let rules = LibraryDrive.pendingFilters {
                LibraryDrive.pendingFilters = nil
                searchOpen = true
                for rule in rules { query = query.setting(rule) }
            }
            #endif
        }
        .task(id: "\(library.stamp(.library, .likes, .ratings, .plays))|\(order.by.id)|\(order.descending)") {
            let read = await library.sortedSongs(order)
            sorted = read
            // The chips offer what the whole list has, not only what the filters leave.
            genreChoices = genresIn(read.items, fields: LibraryTrackFields())
            decadeChoices = decadesIn(read.items, fields: LibraryTrackFields())
            await applyFilters()
        }
        .task(id: query) { await applyFilters() }
    }

    /// Works the shown list out again from the whole list and the filters, away from the main
    /// thread. With no filters it is the whole list.
    private func applyFilters() async {
        guard let sorted else { return }
        guard query.filters else {
            shown = sorted
            return
        }
        let asked = query
        let fields = LibraryTrackFields(liked: state.likedIds, listening: libraryListening(await library.playedTracks()))
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        let result = await Task.detached(priority: .userInitiated) { filteredSongs(sorted, asked, fields: fields, now: now) }.value
        if asked == query { shown = result }
    }

    private func openSearch() {
        searchOpen = true
        Task {
            // One frame, so the field is laid out before it is asked.
            try? await Task.sleep(for: .milliseconds(16))
            fieldFocused = true
        }
    }

    /// Closing the search clears the words and every chip; the order stays.
    private func closeSearch() {
        fieldFocused = false
        searchOpen = false
        query = query.cleared()
    }

    /// A chip on comes off; another takes the place of any filter on its field.
    private func toggle(_ rule: QueryRule) {
        query = query.rules.contains(rule) ? query.without(rule) : query.setting(rule)
    }

    /// Opens a new live list's editor started from these filters, in this list's order.
    private func saveAsLiveList() {
        let order = sorted?.order ?? state.order(.songs)
        let sort = order.by.song.flatMap { QuerySort.By(rawValue: $0.rawValue) }.map { QuerySort($0, descending: order.descending) }
        router.go(.liveListFrom(query: liveListQueryFrom([], filters: query, order: sort).toJSON()))
    }

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                IconView(.search, size: 20, color: OctoColor.textMuted)
                TextField("Search songs", text: Binding(get: { query.text }, set: { query = query.withText($0) }))
                    .focused($fieldFocused)
                    .submitLabel(.search)
                    .onSubmit { fieldFocused = false }
                    .autocorrectionDisabled()
                if !query.text.isEmpty {
                    Button { query = query.withText("") } label: {
                        IconView(.close, size: 20, color: OctoColor.textMuted).frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear the words")
                }
            }
            .padding(.leading, 14)
            .frame(minHeight: 44)
            .glassEffect(Glass.octo, in: .capsule)
            .padding(.horizontal, 20)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    if query.filters {
                        QuietButton("Clear all") { query = query.cleared() }
                        QuietButton("Save as live list") { saveAsLiveList() }
                    }
                    ForEach(FilterPresets.simple, id: \.self) { rule in
                        FilterChip(text: rule.label(), on: query.rules.contains(rule)) { toggle(rule) }
                    }
                    askingChip(.rating, off: "Rating", title: "Rating",
                               answers: (1...5).reversed().map { (FilterPresets.ratingWords($0), FilterPresets.ratingAtLeast($0)) })
                    if !genreChoices.isEmpty || query.rules.contains(where: { $0.field == .genre }) {
                        askingChip(.genre, off: "Genre", title: "Genre", answers: genreChoices.map { ($0, FilterPresets.genre($0)) })
                    }
                    if !decadeChoices.isEmpty || query.rules.contains(where: { $0.field == .year }) {
                        askingChip(.year, off: "Year", title: "Year",
                                   answers: decadeChoices.reversed().map { ("The \($0)s", FilterPresets.decade($0)) })
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, 2)
        .padding(.bottom, 10)
    }

    /// A chip that asks which first, from a menu that opens on it. On, it reads as its filter and
    /// a tap takes the filter off without asking.
    @ViewBuilder
    private func askingChip(_ field: QueryField, off: String, title: String, answers: [(String, QueryRule)]) -> some View {
        if let on = query.rules.first(where: { $0.field == field }) {
            FilterChip(text: on.label(), on: true) { query = query.without(on) }
        } else {
            Menu {
                Section(title) {
                    ForEach(answers.indices, id: \.self) { index in
                        Button(answers[index].0) { query = query.setting(answers[index].1) }
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
                ScreenTitle("Genres").padding(.top, detailTopGap).bigTitle()
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
        .inlineTitle("Genres")
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
    /// The order the songs shown are in.
    @State private var songsOrder: ListOrder?
    @State private var gridWidth: CGFloat = 390

    var body: some View {
        let order = state.order(.genreSongs)
        ScrollViewReader { proxy in
            LibraryList {
                    VStack(spacing: 0) {
                        Text(name).font(.octoTitle).multilineTextAlignment(.center).frame(maxWidth: .infinity).bigTitle()
                        PlayRow(details: "\(albumsCount(albums.count)) • \(songsCount(songs.count))") {
                            actions.play(songs, source: name)
                        } shuffle: {
                            actions.play(songs, shuffled: true, source: name)
                        }
                        .padding(.top, 14)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, detailTopGap)
                    .padding(.bottom, 20)
                    albumGrid
                    if !songs.isEmpty {
                        FirstRowMark()
                        SortBar(name: "Songs", list: .genreSongs).id("songs")
                    }
                    ForEach(Array(songs.enumerated()), id: \.element.id) { position, track in
                        TrackRow(track: track) { actions.play(songs, from: position, source: name) }
                    }
                    Color.clear.frame(height: 20)
            }
            .animation(.easeOut(duration: 0.25), value: songsOrder)
            .topOnNewOrder(songsOrder) { proxy.scrollTo("songs", anchor: .top) }
        }
        .barClearance()
        .inlineTitle(name)
        .backStopsPicking()
        .selectableSongs(state.pickables(songs))
        .task(id: "\(name)|\(library.stamp(.library, .likes, .ratings, .plays))|\(order.by.id)|\(order.descending)") {
            albums = await library.genreAlbums(name).sorted { $0.sortKey < $1.sortKey }
            let sorted = await library.sortedSongs(order, scope: .genre(name))
            songs = sorted.items
            songsOrder = sorted.order
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
        LibraryList {
            ScreenTitle("History").padding(.top, detailTopGap).bigTitle()
            GlassSegments(options: [(false, "Recently played"), (true, "Most played")], selection: $mostPlayed)
                .padding(.horizontal, 20)
            if mostPlayed { mostPlayedList } else { recentList }
            Color.clear.frame(height: 20)
        }
        .barClearance()
        .inlineTitle("History")
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
        actions.play(once, from: once.firstIndex { $0.id == track.id } ?? 0, source: "History")
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
                ForEach(Array(most.enumerated()), id: \.offset) { _, played in
                    TrackRow(track: played.track,
                             subtitle: "\(played.track.artist) • \(played.plays == 1 ? "1 play" : "\(played.plays) plays")") {
                        playFrom(played.track, in: tracks)
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
        LibraryList {
            TitleWithButtons(title: "Downloads") { if !rows.isEmpty { SortButton(list: .downloads) } }
                .padding(.top, detailTopGap)
                .bigTitle()
            if rows.isEmpty {
                MutedNote("Songs you download play without a connection. Long press a song and choose Download, or keep a playlist downloaded from its page.")
            } else {
                summary(rows)
                ForEach(shown) { row in downloadRow(row, shown) }
            }
            Color.clear.frame(height: 20)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: shown.map(\.id))
        .barClearance()
        .inlineTitle("Downloads")
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
        .songSwipes(.remove { remove(row) }, enabled: byHand)
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
