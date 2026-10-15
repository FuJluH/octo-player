import OctoKit
import SwiftUI

/// Library health: the checks that found something, one row each with its count, then the
/// server's trash and the way back from the last change, where it allows.
struct HealthPage: View {
    @Environment(Library.self) private var library
    @Environment(LibraryActions.self) private var actions
    @State private var model = HealthModel()

    var body: some View {
        let files = actions.state.files
        let canUndo = canRunAll(files.actions, files.lastUndo)
        let offers = model.offers
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ScreenTitle("Library health").padding(.top, detailTopGap).bigTitle()
                if let health = model.health {
                    let report = health.report
                    HealthWords(report.overview, muted: true)
                    if report.clean {
                        Text("Everything looks right")
                            .font(.octoSection)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .accessibilityAddTraits(.isHeader)
                        HealthWords(healthAllClear)
                    }
                    ForEach(Array(report.findings.enumerated()), id: \.element) { index, check in
                        if index > 0 { HealthHairline() }
                        NavigationLink(value: Route.library(.healthCheck(check.rawValue))) {
                            FindingRow(title: check.title, count: check.countLabel(report.count(check)))
                        }
                        .buttonStyle(SqueezeStyle())
                    }
                    if offers.restore || canUndo { Color.clear.frame(height: 12) }
                    if offers.restore {
                        NavigationLink(value: Route.library(.recentlyRemoved)) {
                            FindingRow(title: recentlyRemovedWords, count: "Songs deleted from disk, kept in the server's trash for now")
                        }
                        .buttonStyle(SqueezeStyle())
                    }
                    if canUndo {
                        if offers.restore { HealthHairline() }
                        Button { model.undoLast() } label: {
                            FindingRow(title: undoLastChangeWords, count: "Puts back what the last fix or delete changed", chevron: false)
                        }
                        .buttonStyle(SqueezeStyle())
                    }
                } else {
                    LibrarySpinner()
                }
            }
            .padding(.bottom, 140)
        }
        .inlineTitle("Library health")
        .healthSheet(model)
        .onAppear { model.attach(actions) }
        .onDisappear { model.leave() }
        .task(id: library.stamp(.library)) { await model.check(library) }
        .onChange(of: files.serverChanges) { _, _ in model.serverChanged() }
    }
}

/// One check: what it means, what to do, its fix for everything it found when the server can,
/// then its songs under their headings.
struct HealthCheckPage: View {
    let check: String
    @Environment(Library.self) private var library
    @Environment(LibraryActions.self) private var actions
    @State private var model = HealthModel()

    private var found: HealthCheck? { HealthCheck(rawValue: check) }

    var body: some View {
        let files = actions.state.files
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ScreenTitle(found?.title ?? "Library health").padding(.top, detailTopGap).bigTitle()
                if let found {
                    if let health = model.health {
                        content(found, health)
                    } else {
                        LibrarySpinner()
                    }
                } else {
                    HealthWords("This check is not in this version of the app.", muted: true)
                }
            }
            .padding(.bottom, 140)
        }
        .inlineTitle(found?.title ?? "Library health")
        .healthSheet(model)
        .onAppear { model.attach(actions) }
        .onDisappear { model.leave() }
        .task(id: library.stamp(.library)) { await model.check(library) }
        .onChange(of: files.serverChanges) { _, _ in model.serverChanged() }
    }

    @ViewBuilder
    private func content(_ check: HealthCheck, _ health: PhoneHealth) -> some View {
        let lines = health.lines(check)
        let songs = health.songs(check)
        let groups = groupIndexes(lines)
        let fixAll = fixAllButton(check, health)
        HealthWords(check.meaning)
        HealthWords(fixAll.count > 0 ? check.fixMeaning : check.advice)
        if fixAll.count > 0 {
            AccentButton(check.fixAllLabel(fixAll.count), size: .medium, action: fixAll.open)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
        }
        if lines.isEmpty { HealthWords("Nothing to fix here any more.", muted: true) }
        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
            switch line {
            case .heading(let title, let detail):
                HeadingLine(title: title, detail: detail) { headingButton(check, health, groups[index], title) }
            case .song(let track, let note):
                TrackRow(track: track, subtitle: note, swipe: .none, trailing: songButton(check, health, groups[index], index, lines, track)) {
                    model.play(songs, from: track)
                }
            }
        }
    }

    /// Which set of copies or split album each line is under.
    private func groupIndexes(_ lines: [HealthLine]) -> [Int] {
        var at = -1
        return lines.map { line in
            if case .heading = line { at += 1 }
            return at
        }
    }

    @ViewBuilder
    private func headingButton(_ check: HealthCheck, _ health: PhoneHealth, _ group: Int, _ title: String) -> some View {
        let offers = model.offers
        switch check {
        case .duplicates:
            if offers.fixDuplicates, health.duplicatePlan(group, source: model.source) != nil {
                HealthRowButton("Fix", label: "Fix this song") {
                    model.open(.duplicate(title: title, group: health.copyGroups[group], keep: nil))
                }
            }
        case .splitAlbums:
            if offers.join, let plan = health.joinPlan(group, serverIds: model.serverIds) {
                HealthRowButton("Join", label: "Join this album") { model.open(.join(title: title, words: plan.0.words, steps: plan.1)) }
            }
        default:
            EmptyView()
        }
    }

    private func songButton(_ check: HealthCheck, _ health: PhoneHealth, _ group: Int, _ index: Int, _ lines: [HealthLine],
                            _ track: LibraryTrack) -> AnyView? {
        let offers = model.offers
        if check == .duplicates && offers.fixDuplicates {
            guard let plan = health.duplicatePlan(group, source: model.source), let copy = health.copyIn(group, trackId: track.id),
                  copy.id != plan.keep.id else { return nil }
            let title = headingOf(lines, index)
            return AnyView(HealthRowButton("Keep", label: "Keep this copy") {
                model.open(.duplicate(title: title, group: health.copyGroups[group], keep: copy))
            })
        }
        if offers.looksUp(check), let serverId = model.serverIds[track.id] {
            return AnyView(HealthRowButton("Look up", label: lookUpTagsWords) { model.lookUp([(track, serverId)]) })
        }
        return nil
    }

    /// The heading a line is under.
    private func headingOf(_ lines: [HealthLine], _ index: Int) -> String {
        for line in lines[...index].reversed() {
            if case .heading(let title, _) = line { return title }
        }
        return ""
    }

    /// What the button for every finding would do, and how many it takes: 0 hides it. Songs with
    /// no length go to Find higher quality, and songs with no track number are looked up first.
    private func fixAllButton(_ check: HealthCheck, _ health: PhoneHealth) -> (count: Int, open: () -> Void) {
        let offers = model.offers
        switch check {
        case .noLength:
            let asks = offers.upgrade ? model.upgradable(health.report.noLength) : []
            return (asks.count, { model.open(.upgrade(asks)) })
        case .noTrackNumber:
            let batch = offers.lookUp ? lookupBatch(health.report.songs(check), serverIds: model.serverIds) : []
            return (batch.count, { model.lookUp(batch) })
        default:
            let preview = health.fixAllPreview(check, offers: offers, source: model.source, serverIds: model.serverIds)
            return (preview.count, { model.open(.fixAll(check, preview)) })
        }
    }
}

/// The songs deleted from the server's disk that are still in its trash, each with how long it
/// has left and a way to put it back.
struct RecentlyRemovedPage: View {
    @Environment(LibraryActions.self) private var actions
    @State private var trash: LibraryTrash?
    @State private var problem: String?
    /// The server the trash shown is from: a song is put back there only.
    @State private var from: String?
    @State private var now = Int64(Date().timeIntervalSince1970 * 1_000)

    var body: some View {
        let files = actions.state.files
        let canRestore = files.actions?.canRestore == true
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ScreenTitle(recentlyRemovedWords).padding(.top, detailTopGap).bigTitle()
                if let trash {
                    HealthWords(keepsFor(trash.keepDays), muted: true)
                    if trash.songs.isEmpty {
                        HealthWords("Nothing is in the server's trash.", muted: true)
                    } else if canRestore && trash.songs.count > 1 {
                        AccentButton("\(putBackWords) all", size: .medium) { putBack(trash.songs) }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                    }
                    ForEach(trash.songs) { song in
                        TrashRow(song: song, gone: goneText(goneAtMillis: goneAtMillis(song.goneAt), nowMillis: now), canRestore: canRestore) {
                            putBack([song])
                        }
                    }
                } else if let problem {
                    HealthWords(problem, muted: true)
                } else {
                    LibrarySpinner()
                }
            }
            .padding(.bottom, 140)
        }
        .inlineTitle(recentlyRemovedWords)
        .task(id: files.serverChanges) {
            trash = nil
            problem = nil
            await load()
        }
    }

    private func load() async {
        let files = actions.state.files
        let on = files.server()
        do {
            let read = try await files.trash()
            guard files.server() == on else { return }
            from = on
            trash = read
            problem = nil
        } catch {
            problem = "Could not read the server's trash. \(userMessage(error))"
        }
    }

    /// Puts songs back in the library, then reads the trash again. How it went is said in a line,
    /// with an Undo that deletes them again.
    private func putBack(_ songs: [TrashedSong]) {
        guard !songs.isEmpty else { return }
        let ids = Set(songs.map(\.id))
        trash?.songs.removeAll { ids.contains($0.id) }
        actions.state.files.launch(songs.map(\.restoreStep), on: from) { _ in
            Task { await load() }
            return false
        }
    }
}

// MARK: Pieces

/// A paragraph of a health page.
struct HealthWords: View {
    let text: String
    var muted = false

    init(_ text: String, muted: Bool = false) {
        self.text = text
        self.muted = muted
    }

    var body: some View {
        Text(text)
            .font(.octoBodySmall)
            .foregroundStyle(muted ? OctoColor.textMuted : OctoColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
    }
}

/// A hairline between rows, inset at both sides.
private struct HealthHairline: View {
    var body: some View { OctoColor.hairline.frame(height: 1).padding(.horizontal, 20) }
}

/// A row of the front page: what it is over its count, and a chevron.
private struct FindingRow: View {
    let title: String
    let count: String
    var chevron = true

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.octoBody).foregroundStyle(.white)
                Text(count).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if chevron { IconView(.chevron, size: 22, color: OctoColor.textMuted) }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A heading over a set of copies or a split album, with its own fix.
private struct HeadingLine<Action: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var action: Action

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.octoLabel).foregroundStyle(.white).accessibilityAddTraits(.isHeader)
                Text(detail).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            action
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }
}

/// A small word button at the end of a row; `label` is what it does, for screen readers.
struct HealthRowButton: View {
    let text: String
    let label: String
    let action: () -> Void

    init(_ text: String, label: String, action: @escaping () -> Void) {
        self.text = text
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.octoLabel)
                .foregroundStyle(OctoColor.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// One song in the server's trash: its name, where it was from, what replaced it, and how long it
/// has left.
private struct TrashRow: View {
    let song: TrashedSong
    let gone: String
    let canRestore: Bool
    let putBack: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(song.title).font(.octoBody).foregroundStyle(.white)
                let from = [song.artist, song.album].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: " • ")
                if !from.isEmpty { Text(from).font(.octoCaption).foregroundStyle(OctoColor.textMuted) }
                if song.replaced {
                    Text(replacedText(was: song.was, now: song.now))
                        .font(.octoCaption)
                        .foregroundStyle(OctoColor.textSecondary)
                        .accessibilityLabel(replacedSpoken(was: song.was, now: song.now))
                }
                Text(gone).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if canRestore { HealthRowButton(putBackWords, label: "\(putBackWords) \(song.title)", action: putBack) }
        }
        .padding(.leading, 20)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .frame(minHeight: 60)
    }
}
