import OctoKit
import SwiftUI

// The sheet over a Library health page that shows a fix before it runs, how far it has got, and
// how it went, with its Undo.

/// How long a preview list gets before the rest is only counted.
private let previewLines = 100

extension View {
    /// The health page's sheet, half the screen tall to begin with; a swipe down closes it.
    func healthSheet(_ model: HealthModel) -> some View {
        sheet(isPresented: Binding(get: { model.sheet != nil }, set: { if !$0 { model.close() } })) {
            HealthSheetView(model: model)
                .presentationDetents([.medium, .large])
        }
    }
}

/// The sheet's current page, kept while it slides away after it was closed.
private struct HealthSheetView: View {
    let model: HealthModel
    @State private var last: HealthSheet?

    var body: some View {
        Group {
            if let sheet = model.sheet ?? last { page(sheet) }
        }
        .onAppear { if let sheet = model.sheet { last = sheet } }
        .onChange(of: model.sheetRevision) { _, _ in if let sheet = model.sheet { last = sheet } }
    }

    @ViewBuilder
    private func page(_ sheet: HealthSheet) -> some View {
        switch sheet {
        case .duplicate(let title, let group, let keep):
            DuplicateSheet(model: model, title: title, group: group, keep: keep)
                .id("\(title)|\(keep?.id ?? "")|\(model.sheetRevision)")
        case .fixAll(let check, let preview):
            SheetPage(title: check.title) {
                SheetButtons(check.fixAllLabel(preview.count), onConfirm: { model.run(preview.steps) }, onCancel: model.close)
            } content: {
                SheetWords(check.fixMeaning)
                PreviewLines(lines: preview.lines)
            }
        case .join(let title, let words, let steps):
            SheetPage(title: title) {
                SheetButtons("Join", onConfirm: { model.run(steps) }, onCancel: model.close)
            } content: {
                SheetWords(words)
            }
        case .upgrade(let songs):
            SheetPage(title: HealthCheck.noLength.title) {
                SheetButtons(HealthCheck.noLength.fixAllLabel(songs.count), onConfirm: { model.upgrade(songs) }, onCancel: model.close)
            } content: {
                SheetWords(HealthCheck.noLength.fixMeaning)
                PreviewLines(lines: songs.map { ($0.title, nil) })
            }
        case .lookUp:
            LookUpSheet(model: model).id(model.lookups.round)
        case .running:
            RunningSheet(model: model)
        case .done(let outcome, let server):
            let undo = outcome.undo
            SheetPage(title: "Done") {
                if canRunAll(model.files?.actions, undo) {
                    SheetButtons("Undo", cancel: "Close", onConfirm: { model.run(undo, undo: true, on: server) }, onCancel: model.close)
                } else {
                    AccentButton("Close", action: model.close)
                }
            } content: {
                SheetWords(outcome.summary(), live: true)
            }
        }
    }
}

/// One set of copies: which is kept and why, which go to the server's trash, the kept copy's
/// blank tags filled from the others (each can be left out), and, where the copies disagree, which
/// value to keep.
private struct DuplicateSheet: View {
    let model: HealthModel
    let title: String
    let group: DuplicateGroup<SourceTrack>
    let keep: SourceTrack?
    /// Tags left out, and the copy each differing tag is taken from.
    @State private var skipped: [String: Bool] = [:]
    @State private var choices: [String: String] = [:]

    var body: some View {
        let offers = model.offers
        let fix = duplicateFix(group, serverCopyHealth, keep: keep ?? group.best)
        let fills = fix.fills.filter { skipped[$0.tag] != true }
        let changes = fills + fix.picked(choices)
        SheetPage(title: title) {
            SheetButtons("Fix", onConfirm: { model.run(fix.serverSteps(changes, edit: offers.edit)) }, onCancel: model.close)
        } content: {
            SheetHeading("Keeps")
            SheetLine(title: copyLine(fix.keep), detail: fix.why)
            SheetHeading("Moves to the server's trash")
            ForEach(fix.remove, id: \.id) { copy in
                HStack(spacing: 0) {
                    SheetLine(title: copyLine(copy), detail: nil).frame(maxWidth: .infinity, alignment: .leading)
                    HealthRowButton("Keep", label: "Keep this copy instead") {
                        model.open(.duplicate(title: title, group: group, keep: copy))
                    }
                }
            }
            if offers.edit && !fix.fills.isEmpty {
                SheetHeading("Fills in")
                ForEach(fix.fills, id: \.tag) { change in
                    CheckRow(text: change.words, checked: skipped[change.tag] != true) { skipped[change.tag] = !$0 }
                }
            }
            if offers.edit && !fix.differs.isEmpty {
                SheetHeading("Where the copies disagree")
                ForEach(fix.differs, id: \.tag) { choice in
                    SheetWords(fixTagName(choice.tag), muted: true)
                    let keptFrom = choices[choice.tag] ?? fix.keep.nativeId
                    let keptValue = choice.value(of: keptFrom)
                    ForEach(onceEach(choice.values), id: \.id) { value in
                        PickRow(text: value.value, picked: keptValue == value.value) { choices[choice.tag] = value.id }
                    }
                }
            }
            if let note = fix.note { SheetWords(note, muted: true) }
        }
    }

    /// Each value once, from the first copy that has it.
    private func onceEach(_ values: [(id: String, value: String)]) -> [(id: String, value: String)] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.value).inserted }
    }

    /// A copy by its name and sound, and its album.
    private func copyLine(_ copy: SourceTrack) -> String {
        let album = copy.album.trimmingCharacters(in: .whitespacesAndNewlines)
        return album.isEmpty ? copyName(copy, serverCopyHealth) : "\(copyName(copy, serverCopyHealth)), on \(album)"
    }
}

/// Songs being looked up, then everything found, each change ticked or not to begin with as the
/// shared rules say, and one button that writes the ticked ones.
private struct LookUpSheet: View {
    let model: HealthModel
    /// Changes ticked off, by song and tag.
    @State private var skipped: [String: Bool] = [:]

    private func key(_ serverId: String, _ tag: String) -> String { "\(serverId)/\(tag)" }

    var body: some View {
        let state = model.lookups
        let picked = state.songs.map { song in
            (song, song.changes.filter { change, on in skipped[key(song.serverId, change.tag)].map { !$0 } ?? on }.map(\.0))
        }
        let count = picked.reduce(0) { $0 + $1.1.count }
        let title = state.total == 1 ? lookUpTagsWords : "Looking up \(countText(state.total, "song", "songs"))"
        SheetPage(title: title) {
            if !state.finished {
                GlazeButton("Stop", action: model.stopLookUp)
            } else if count == 0 {
                AccentButton("Close", action: model.close)
            } else {
                SheetButtons(count == 1 ? "Write 1 change" : "Write \(count) changes", onConfirm: {
                    model.run(picked.compactMap { retagStep($0.0.serverId, title: $0.0.track.title, changes: $0.1) })
                }, onCancel: model.close)
            }
        } content: {
            if !state.finished {
                SheetWords("Looked up \(state.songs.count) of \(state.total)", muted: true, live: true)
                ProgressLine(done: state.songs.count, total: state.total)
            } else if !state.songs.contains(where: { !$0.changes.isEmpty }) {
                SheetWords("Nothing to change: the tags found say what the files say already, or nothing was found.", muted: true)
            }
            ForEach(Array(state.songs.enumerated()), id: \.offset) { _, song in
                if state.total > 1 { SheetHeading(song.track.title) }
                if let problem = song.problem {
                    SheetWords(problem, muted: true)
                } else if let lookup = song.lookup, lookup.found {
                    if song.changes.isEmpty {
                        SheetWords("\(lookup.origin) The file says the same already.", muted: true)
                    } else {
                        SheetWords(lookup.origin, muted: true)
                        ForEach(song.changes, id: \.0.tag) { change, first in
                            let k = key(song.serverId, change.tag)
                            CheckRow(text: change.words, checked: skipped[k].map { !$0 } ?? first) { skipped[k] = !$0 }
                        }
                    }
                } else {
                    let detail = song.lookup?.detail.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
                    SheetWords(detail ?? "Nothing was found for this song.", muted: true)
                }
            }
        }
    }
}

/// Steps on their way: how many are done, with a way to stop between two.
private struct RunningSheet: View {
    let model: HealthModel

    var body: some View {
        SheetPage(title: "Changing the files") {
            GlazeButton("Stop", action: model.stop)
        } content: {
            if let run = model.files?.progress {
                SheetWords("\(run.done) of \(run.total) done", muted: true, live: true)
                ProgressLine(done: run.done, total: run.total)
            } else {
                SheetWords("Starting", muted: true)
            }
            SheetWords("Closing this lets it carry on. It says how it went when it is done.", muted: true)
        }
    }
}

// MARK: Pieces

/// A sheet page: its title in the bar, then what it shows, which scrolls, then its buttons, which
/// stay in view at the bottom.
private struct SheetPage<Buttons: View, Content: View>: View {
    let title: String
    @ViewBuilder var buttons: Buttons
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) { buttons }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
        }
    }
}

private struct SheetButtons: View {
    let confirm: String
    var cancel = "Cancel"
    let onConfirm: () -> Void
    let onCancel: () -> Void

    init(_ confirm: String, cancel: String = "Cancel", onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.confirm = confirm
        self.cancel = cancel
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        AccentButton(confirm, action: onConfirm)
        GlazeButton(cancel, action: onCancel)
    }
}

private struct SheetHeading: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.headline)
            .padding(.top, 14)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct SheetWords: View {
    let text: String
    var muted = false
    var live = false

    init(_ text: String, muted: Bool = false, live: Bool = false) {
        self.text = text
        self.muted = muted
        self.live = live
    }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(muted ? .secondary : .primary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
            .accessibilityAddTraits(live ? .updatesFrequently : [])
    }
}

/// One thing a fix does, and a line under it.
private struct SheetLine: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            if let detail { Text(detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(.vertical, 4)
    }
}

private struct PreviewLines: View {
    let lines: [(String, String?)]

    var body: some View {
        ForEach(Array(lines.prefix(previewLines).enumerated()), id: \.offset) { _, line in SheetLine(title: line.0, detail: line.1) }
        if lines.count > previewLines { SheetWords("And \(countText(lines.count - previewLines, "more", "more")).", muted: true) }
    }
}

/// A change that can be left out: a tick in a box when it is in.
private struct CheckRow: View {
    let text: String
    let checked: Bool
    let change: (Bool) -> Void

    var body: some View {
        Button { change(!checked) } label: {
            HStack(spacing: 12) {
                Mark(on: checked, round: false)
                Text(text).font(.subheadline).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 44)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? [.isToggle, .isSelected] : .isToggle)
    }
}

/// One of a few values, the one kept marked.
private struct PickRow: View {
    let text: String
    let picked: Bool
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 12) {
                Mark(on: picked, round: true)
                Text(text).font(.subheadline).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 44)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

/// A tick in a box for a change that is in, or a filled circle for the value kept.
private struct Mark: View {
    let on: Bool
    let round: Bool

    var body: some View {
        let symbol = round ? (on ? "checkmark.circle.fill" : "circle") : (on ? "checkmark.square.fill" : "square")
        Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(on ? OctoColor.accent : Color.secondary)
            .frame(width: 24, height: 24)
    }
}

/// How far along, as the system's progress bar.
private struct ProgressLine: View {
    let done: Int
    let total: Int

    var body: some View {
        ProgressView(value: Double(min(max(done, 0), max(total, 1))), total: Double(max(total, 1)))
            .tint(OctoColor.accent)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .accessibilityHidden(true)
    }
}
