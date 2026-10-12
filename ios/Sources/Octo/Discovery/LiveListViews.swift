import OctoKit
import SwiftUI

/// What a live list shows with no songs.
let noMatchesNote = "No songs match right now. As songs are added, played and liked, the ones that match show up here."

/// What the editor shows when its rules pick nothing.
let noRuleMatches = "No songs match these rules yet. Take a rule off, or pick Any of these so a song needs to match only one."

/// A live list's own picture: the rules glyph lit in the accent on a faint wash of it.
struct LiveMarkTile: View {
    let size: CGFloat
    var radius: CGFloat = OctoRadius.artM

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(OctoColor.accent.opacity(0.16))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: size * 0.42 * 0.7, weight: .semibold))
                    .foregroundStyle(OctoColor.accent)
            }
            .accessibilityHidden(true)
    }
}

/// A list's picture: its designed cover when playlist covers are designed, else the first covers
/// of the songs it holds, or the live mark tile when none.
private struct LiveListCover: View {
    let id: String
    let name: String
    let songs: [LibraryTrack]
    let size: CGFloat

    var body: some View {
        let artworks = Array(uniqueArtworks.prefix(4))
        let covers = artworks.compactMap { coverId(of: $0) }
        if AppSettings.shared.playlistCovers == .designed {
            DesignedCover(id: id, name: name, covers: artworks, size: size, radius: 10, line: liveListCoverLine)
        } else if covers.isEmpty {
            LiveMarkTile(size: size, radius: 10)
        } else if covers.count < 4 {
            Cover(id: covers[0], size: size, radius: 10)
        } else {
            let half = size / 2
            VStack(spacing: 0) {
                HStack(spacing: 0) { Cover(id: covers[0], size: half, radius: 0); Cover(id: covers[1], size: half, radius: 0) }
                HStack(spacing: 0) { Cover(id: covers[2], size: half, radius: 0); Cover(id: covers[3], size: half, radius: 0) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    /// One cover per album, in the songs' order, as the songs keep them.
    private var uniqueArtworks: [String] {
        var seen = Set<String>()
        return songs.compactMap { track in
            guard seen.insert(track.albumId).inserted, let artwork = track.artwork, coverId(of: artwork) != nil else { return nil }
            return artwork
        }
    }
}

/// One live list: its picture, name and size, one quiet line saying what it picks, Play and
/// Shuffle, and its songs. More opens its options, where its rules are edited.
struct LiveListView: View {
    let id: String
    @Environment(LiveListStore.self) private var store
    @Environment(LiveLibrary.self) private var liveLibrary
    @Environment(Library.self) private var library
    @Environment(Player.self) private var player
    @Environment(Router.self) private var router
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var renaming = false
    @State private var deleting = false
    @State private var newName = ""

    var body: some View {
        let list = store.byId(id)
        let songs = list.flatMap { liveLibrary.songs($0.query) } ?? []
        let playable = songs.map(\.asSong)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let list {
                    VStack(spacing: 0) {
                        LiveListCover(id: list.id, name: list.name, songs: songs, size: 240)
                            .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
                        Text(list.name)
                            .font(.octoTitle)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.top, 20)
                        HStack {
                            let total = songs.reduce(Int64(0)) { $0 + $1.durationMs } / 1_000
                            Text([songCountLine(songs.count), songs.isEmpty ? nil : Int(total).spokenLength].compactMap { $0 }.joined(separator: " • "))
                                .font(.octoCaption)
                                .foregroundStyle(OctoColor.textMuted)
                            Spacer()
                            options(list, songs)
                        }
                        .frame(minHeight: 44)
                        .padding(.top, 14)
                        PlayButtons(songs: playable).padding(.top, 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, detailTopGap)
                    .padding(.bottom, 12)
                    Text(liveListSummary(list.query, count: nil))
                        .font(.octoCaption)
                        .foregroundStyle(OctoColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 12)
                    if songs.isEmpty {
                        Text(noMatchesNote).font(.octoBodySmall).foregroundStyle(OctoColor.textMuted).padding(20)
                    }
                    ForEach(Array(playable.enumerated()), id: \.element.id) { index, song in
                        SongRow(song: song, list: playable, position: index)
                    }
                }
            }
        }
        .barClearance()
        .selectableSongs(playable.map { Pickable($0) })
        .task(id: library.stamp(.library, .likes, .plays)) { await liveLibrary.read() }
        .task(id: PickKey(version: liveLibrary.version, query: list?.query)) { if let list { await liveLibrary.pick(list.query) } }
        // Leaves the page once the list is deleted.
        .onChange(of: list == nil) { _, gone in if gone { dismiss() } }
        .opensWhenAsked("rename_live_list") {
            guard let list else { return }
            newName = list.name
            renaming = true
        }
        .opensWhenAsked("delete_live_list") { if list != nil { deleting = true } }
    }

    /// The live list's options, under its name.
    private func options(_ list: LiveList, _ songs: [LibraryTrack]) -> some View {
        Menu {
            Section(list.name) {
                Button { router.go(.liveListEditor(id: list.id)) } label: { Label("Edit rules", systemImage: "line.3.horizontal.decrease") }
                Button {
                    newName = list.name
                    renaming = true
                } label: { Label("Rename", systemImage: "pencil") }
                Button {
                    let copy = store.duplicate(list)
                    router.show("Made a copy: \(copy.name)", done: true)
                } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                Button { Task { await saveCopy(list, songs) } } label: { Label("Save a copy as a playlist", systemImage: "music.note.list") }
            }
            Button(role: .destructive) { deleting = true } label: { Label("Delete", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More")
        .namePopover(isPresented: $renaming, title: "Rename live list", placeholder: "Live list name", action: "Save",
                     initial: newName) { name in
            store.rename(id, to: name)
            renaming = false
        }
        .confirmationDialog("Delete \"\(list.name)\"?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { store.remove(list.id) }
        } message: {
            Text("The songs stay in your library.")
        }
    }

    /// A playlist named as the live list with the songs it holds now; it does not follow the rules.
    private func saveCopy(_ list: LiveList, _ songs: [LibraryTrack]) async {
        guard !songs.isEmpty else {
            router.show(nothingToCopy(list.name))
            return
        }
        guard let client = session.client else { return }
        do {
            try await client.createPlaylist(name: list.name, songIds: songs.map(\.asSong.id))
            router.show(liveCopyMessage(list.name, count: songs.count), done: true)
        } catch {
            router.show(onlineFailureWords(error))
        }
    }
}

/// A live list's editor: its name, words, rules as chips (a tap takes one off) with Add a rule,
/// whether a song needs to match all or any of them once there are two, the order and how many. The
/// songs it would pick show under it as the rules change. A new one offers starters while the
/// listener has no live lists.
struct LiveListEditView: View {
    let id: String?
    var start: LibraryQuery?
    @Environment(LiveListStore.self) private var store
    @Environment(LiveLibrary.self) private var liveLibrary
    @Environment(Library.self) private var library
    @Environment(Player.self) private var player
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var draft: LiveListDraft?
    @State private var starters = false

    var body: some View {
        let draft = self.draft ?? editorStart(id.flatMap { store.byId($0) }, start: start)
        let query = draft.query
        let picked = liveLibrary.songs(query)
        let preview = picked ?? []
        let playable = preview.map(\.asSong)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ScreenTitle(id == nil ? "New live list" : "Edit live list")
                GlassInput(liveListName(query), text: Binding(get: { draft.name }, set: { self.draft = LiveListDraft(name: $0, query: query) }))
                    .padding(.horizontal, 20)
                Text("Picks songs from your whole library that match these rules, and keeps up as songs are added, played and liked.")
                    .font(.octoCaption)
                    .foregroundStyle(OctoColor.textMuted)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                GlassInput("With these words", text: Binding(get: { query.text }, set: { update(query.withText($0)) }))
                    .padding(.horizontal, 20)
                FlowRow(spacing: 8) {
                    ForEach(Array(query.rules.enumerated()), id: \.offset) { _, rule in
                        OnOffChip(text: rule.label(), on: true) { update(query.without(rule)) }
                    }
                    addRuleMenu(query)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                if query.asksMatch() {
                    HStack(spacing: 8) {
                        Text("A song needs to match").font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                        OnOffChip(text: "All of these", on: query.match == .all) { update(query.matching(.all)) }
                        OnOffChip(text: "Any of these", on: query.match == .any) { update(query.matching(.any)) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
                HStack(spacing: 0) {
                    Text("Order").font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                    orderMenu(query)
                    Text("How many").font(.octoCaption).foregroundStyle(OctoColor.textMuted).padding(.leading, 12)
                    limitMenu(query)
                }
                .padding(.horizontal, 20)
                HStack(spacing: 10) {
                    AccentButton(id == nil ? "Make live list" : "Save") { save(draft) }
                    GlazeButton("Cancel") { dismiss() }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                if starters {
                    SectionTitle("Or start with one of these")
                    ForEach(liveListStarters, id: \.name) { starter in
                        Button { make(starter) } label: {
                            HStack(spacing: 14) {
                                LiveMarkTile(size: 44, radius: OctoRadius.artS)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(starter.name).font(.octoBodySmall).foregroundStyle(.white).lineLimit(1)
                                    Text(starter.detail).font(.octoCaption).foregroundStyle(OctoColor.textMuted).lineLimit(2)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 6)
                            .frame(minHeight: 64)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(SqueezeStyle())
                    }
                }
                if picked != nil {
                    Text(preview.isEmpty ? noRuleMatches : matchWords(preview.count))
                        .font(.octoCaption)
                        .foregroundStyle(OctoColor.textMuted)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    ForEach(Array(playable.enumerated()), id: \.element.id) { index, song in
                        SongRow(song: song, list: playable, position: index)
                    }
                }
            }
            .padding(.top, detailTopGap)
        }
        .barClearance()
        .scrollDismissesKeyboard(.immediately)
        .task(id: library.stamp(.library, .likes, .plays)) { await liveLibrary.read() }
        .task(id: PickKey(version: liveLibrary.version, query: query)) { await liveLibrary.pick(query) }
        .onAppear {
            if self.draft == nil { self.draft = editorStart(id.flatMap { store.byId($0) }, start: start) }
            starters = offersStarters(store.lists, id: id, start: start)
        }
    }

    /// Add a rule, as a system menu: the groups of rules and the pages that ask which from the
    /// library each open as a menu of their own, the current pick checked; a pick adds or takes
    /// off the rule.
    private func addRuleMenu(_ query: LibraryQuery) -> some View {
        Menu {
            Section("Add a rule") {
                ForEach(Array(liveListRuleMenu().enumerated()), id: \.offset) { _, item in
                    let (words, pick) = item
                    if case .rule(let rule) = pick {
                        MenuPick(words, checked: query.rules.contains(rule)) { update(currentQuery.toggling(rule)) }
                    } else {
                        Menu(words) {
                            RulePageItems(title: words, rules: { rules(for: pick) }, query: query) { update(currentQuery.toggling($0)) }
                        }
                    }
                }
            }
        } label: {
            Text(query.rules.isEmpty ? "Add a rule" : "Add another rule")
                .font(DiscoveryStyle.label)
                .foregroundStyle(OctoColor.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(minHeight: 36)
                .background(Color.white.opacity(0.07), in: Capsule())
                .contentShape(Capsule())
        }
        .menuOrder(.fixed)
    }

    /// The order, from the orders a live list can keep, as a system menu; picking the one in use
    /// turns it round.
    private func orderMenu(_ query: LibraryQuery) -> some View {
        let now = query.sort?.order
        return Menu {
            Section("Order") {
                ForEach(liveListSorts, id: \.self) { by in
                    MenuPick(by.label, checked: by == now) {
                        if by == now, let sort = currentQuery.sort {
                            update(currentQuery.sorted(by: QuerySort(by, descending: !sort.descending)))
                        } else {
                            update(currentQuery.sorted(by: by))
                        }
                    }
                }
            }
        } label: {
            quietLabel(query.sort.flatMap(sortWords).map(capitalizedFirst) ?? "In library order")
        }
        .menuOrder(.fixed)
    }

    private func limitMenu(_ query: LibraryQuery) -> some View {
        Menu {
            Section("How many songs") {
                ForEach(Array(liveListLimits.enumerated()), id: \.offset) { _, limit in
                    MenuPick(limitWords(limit), checked: limit == query.limit) { update(currentQuery.limited(to: limit)) }
                }
            }
        } label: {
            quietLabel(limitWords(query.limit))
        }
        .menuOrder(.fixed)
    }

    /// A menu's label drawn as the quiet button beside its name.
    private func quietLabel(_ text: String) -> some View {
        Text(text)
            .font(.octoLabel)
            .foregroundStyle(OctoColor.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Capsule())
    }

    private var currentQuery: LibraryQuery { (draft ?? editorStart(id.flatMap { store.byId($0) }, start: start)).query }

    private func update(_ query: LibraryQuery) {
        let now = draft ?? editorStart(id.flatMap { store.byId($0) }, start: start)
        draft = LiveListDraft(name: now.name, query: query)
    }

    /// The rules a page of Add a rule offers: a group's own, or those the library holds.
    private func rules(for pick: RulePick) -> [(String, QueryRule)] {
        let tracks = liveLibrary.tracks
        let fields = liveLibrary.fields
        switch pick {
        case .group(let group): return group.choices.map { ($0.words, $0.rule) }
        case .rating: return ratingRules
        case .genre: return genresIn(tracks, fields: fields).map { ($0, FilterPresets.genre($0)) }
        case .artist: return artistsIn(tracks, fields: fields).map { ($0, FilterPresets.artist($0)) }
        case .year: return decadesIn(tracks, fields: fields).reversed().map { ("The \($0)s", FilterPresets.decade($0)) }
        case .rule(let rule): return [("", rule)]
        }
    }

    /// Keeps the list, then opens it: a new one in place of the editor, an edited one goes back.
    private func save(_ draft: LiveListDraft) {
        if let id, var old = store.byId(id) {
            old.name = draft.savedName
            old.query = draft.query
            store.save(old)
            dismiss()
        } else {
            let saved = store.save(LiveList.new(name: draft.savedName, query: draft.query, now: msSince1970()))
            dismiss()
            router.go(.liveList(id: saved.id))
        }
    }

    /// A starter the listener picked, made as it is.
    private func make(_ starter: LiveListStarter) {
        let saved = store.save(LiveList.new(name: starter.name, query: starter.query, now: msSince1970()))
        dismiss()
        router.go(.liveList(id: saved.id))
    }

    private func capitalizedFirst(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }
}



/// One page of Add a rule, as the items of its own menu: the current pick is checked; a pick
/// adds or takes off the rule. Its rules are worked out when the menu draws it, not with the
/// editor.
private struct RulePageItems: View {
    let title: String
    let rules: () -> [(String, QueryRule)]
    let query: LibraryQuery
    let toggle: (QueryRule) -> Void

    var body: some View {
        let rules = rules()
        let picked = pickedIn(rules.map(\.1), query: query)
        Section(title) {
            ForEach(Array(rules.enumerated()), id: \.offset) { index, choice in
                MenuPick(choice.0, checked: index == picked) { toggle(choice.1) }
            }
        }
    }
}

/// Which songs to work out: a query, against the library as last read.
private struct PickKey: Hashable {
    let version: Int
    let query: LibraryQuery?
}
