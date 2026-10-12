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

/// A picture made of the first covers of the songs a list holds, or the live mark tile when none.
private struct LiveListCover: View {
    let songs: [LibraryTrack]
    let size: CGFloat

    var body: some View {
        let covers = Array(uniqueCovers.prefix(4))
        if covers.isEmpty {
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

    /// One cover per album, in the songs' order.
    private var uniqueCovers: [String] {
        var seen = Set<String>()
        return songs.compactMap { track in
            guard seen.insert(track.albumId).inserted else { return nil }
            return coverId(of: track.artwork)
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
    @State private var newName = ""
    @State private var deleting = false

    var body: some View {
        let list = store.byId(id)
        let songs = list.map { liveLibrary.pick($0.query) } ?? []
        let playable = songs.map(\.asSong)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let list {
                    VStack(spacing: 0) {
                        LiveListCover(songs: songs, size: 240)
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
        .task(id: library.stamp(.library, .likes, .plays)) { await liveLibrary.read() }
        // Leaves the page once the list is deleted.
        .onChange(of: list == nil) { _, gone in if gone { dismiss() } }
        .alert("Rename live list", isPresented: $renaming) {
            TextField("Live list name", text: $newName)
            Button("Save") { store.rename(id, to: newName) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete \"\(list?.name ?? "")\"?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { store.remove(id) }
        } message: {
            Text("The songs stay in your library.")
        }
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
    @State private var asking: RuleAsk?
    @State private var choosingRule = false
    @State private var choosingOrder = false
    @State private var choosingLimit = false

    /// A page of rules to pick from.
    struct RuleAsk: Identifiable {
        let title: String
        let rules: [(String, QueryRule)]
        var id: String { title }
    }

    var body: some View {
        let draft = self.draft ?? editorStart(id.flatMap { store.byId($0) }, start: start)
        let query = draft.query
        let preview = liveLibrary.pick(query)
        let playable = preview.map(\.asSong)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ScreenTitle(id == nil ? "New live list" : "Edit live list")
                InputField(text: Binding(get: { draft.name }, set: { self.draft = LiveListDraft(name: $0, query: query) }),
                           placeholder: liveListName(query))
                Text("Picks songs from your whole library that match these rules, and keeps up as songs are added, played and liked.")
                    .font(.octoCaption)
                    .foregroundStyle(OctoColor.textMuted)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                InputField(text: Binding(get: { query.text }, set: { update(query.withText($0)) }), placeholder: "With these words")
                FlowChips(spacing: 8) {
                    ForEach(Array(query.rules.enumerated()), id: \.offset) { _, rule in
                        OnOffChip(text: rule.label(), on: true) { update(query.without(rule)) }
                    }
                    OnOffChip(text: query.rules.isEmpty ? "Add a rule" : "Add another rule", on: false) { choosingRule = true }
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
                    QuietAction(query.sort.flatMap(sortWords).map(capitalizedFirst) ?? "In library order") { choosingOrder = true }
                    Text("How many").font(.octoCaption).foregroundStyle(OctoColor.textMuted).padding(.leading, 12)
                    QuietAction(limitWords(query.limit)) { choosingLimit = true }
                }
                .padding(.horizontal, 20)
                HStack(spacing: 10) {
                    Button(id == nil ? "Make live list" : "Save") { save(draft) }.buttonStyle(.glassProminent)
                    Button("Cancel") { dismiss() }.buttonStyle(.glass)
                }
                .font(DiscoveryStyle.label)
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
                        .buttonStyle(PressSqueeze())
                    }
                }
                if liveLibrary.version > 0 {
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
        .onAppear {
            if self.draft == nil { self.draft = editorStart(id.flatMap { store.byId($0) }, start: start) }
            starters = offersStarters(store.lists, id: id, start: start)
        }
        .confirmationDialog("Add a rule", isPresented: $choosingRule, titleVisibility: .visible) {
            ForEach(Array(liveListRuleMenu().enumerated()), id: \.offset) { _, entry in
                Button(entry.0) { pick(entry.1) }
            }
        }
        .sheet(item: $asking) { ask in
            RulePage(ask: ask, query: currentQuery) { rule in update(currentQuery.toggling(rule)) }
        }
        .confirmationDialog("Order", isPresented: $choosingOrder, titleVisibility: .visible) {
            ForEach(liveListSorts, id: \.self) { sort in
                Button(sort.label) { update(currentQuery.sorted(by: sort)) }
            }
        }
        .confirmationDialog("How many songs", isPresented: $choosingLimit, titleVisibility: .visible) {
            ForEach(Array(liveListLimits.enumerated()), id: \.offset) { _, limit in
                Button(limitWords(limit)) { update(currentQuery.limited(to: limit)) }
            }
        }
    }

    private var currentQuery: LibraryQuery { (draft ?? editorStart(id.flatMap { store.byId($0) }, start: start)).query }

    private func update(_ query: LibraryQuery) {
        let now = draft ?? editorStart(id.flatMap { store.byId($0) }, start: start)
        draft = LiveListDraft(name: now.name, query: query)
    }

    /// The page of choices to ask next.
    private func pick(_ pick: RulePick) {
        let tracks = liveLibrary.tracks
        let fields = liveLibrary.fields
        switch pick {
        case .group(let group): asking = RuleAsk(title: group.title, rules: group.choices.map { ($0.words, $0.rule) })
        case .rating: asking = RuleAsk(title: "Rating", rules: ratingRules)
        case .genre: asking = RuleAsk(title: "Genre", rules: genresIn(tracks, fields: fields).map { ($0, FilterPresets.genre($0)) })
        case .artist: asking = RuleAsk(title: "Artist", rules: artistsIn(tracks, fields: fields).map { ($0, FilterPresets.artist($0)) })
        case .year: asking = RuleAsk(title: "Year", rules: decadesIn(tracks, fields: fields).reversed().map { ("The \($0)s", FilterPresets.decade($0)) })
        case .rule(let rule): update(currentQuery.toggling(rule))
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

/// One page of rules: the current pick is ticked; a tap adds or takes off the rule.
private struct RulePage: View {
    let ask: LiveListEditView.RuleAsk
    let query: LibraryQuery
    let toggle: (QueryRule) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let picked = pickedIn(ask.rules.map(\.1), query: query)
        NavigationStack {
            List {
                ForEach(Array(ask.rules.enumerated()), id: \.offset) { index, entry in
                    Button {
                        toggle(entry.1)
                        dismiss()
                    } label: {
                        HStack {
                            Text(entry.0).foregroundStyle(.white)
                            Spacer()
                            if index == picked { Image(systemName: "checkmark").foregroundStyle(OctoColor.accent) }
                        }
                    }
                }
            }
            .navigationTitle(ask.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

/// A text field sunk into the surface, the way Octo's inputs look.
struct InputField: View {
    @Binding var text: String
    let placeholder: String
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder).font(.octoBody).foregroundStyle(OctoColor.textMuted).lineLimit(1).accessibilityHidden(true)
            }
            TextField("", text: $text)
                .font(.octoBody)
                .foregroundStyle(.white)
                .focused($focused)
                .accessibilityLabel(placeholder)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(OctoColor.accent.opacity(focused ? 0.15 : 0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(OctoColor.accent.opacity(0.10), lineWidth: 1))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(OctoColor.accent.opacity(focused ? 0.6 : 0), lineWidth: 1.5))
        .padding(.horizontal, 20)
    }
}

/// Chips that wrap onto the next line.
struct FlowChips: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var line: CGFloat = 0
        var widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += line + spacing
                x = 0
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += line + spacing
                x = bounds.minX
                line = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
