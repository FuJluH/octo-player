import OctoKit
import SwiftUI
import UniformTypeIdentifiers

/// Saving the app's settings to a file, and putting them back from one. A restore first shows
/// what the file holds and how much of it this library has, and waits for the go-ahead.
struct BackupSettingsPage: View {
    var highlight: String?
    @Environment(Session.self) private var session
    @Environment(LyricsStore.self) private var lyrics
    @State private var model = BackupModel.shared
    @State private var saving: BackupDocument?
    @State private var opening = false
    /// Whether this visit of the page has begun, so coming back from another tab or a picker
    /// keeps where it is up to.
    @State private var visiting = false

    var body: some View {
        SettingsPageFrame(title: SettingsPage.backup.title, highlight: highlight) {
            if case .ready(let backup, let plan) = model.state {
                SettingsGroup(title: "In this backup", icon: SettingsIcon.backup,
                              footer: "Restoring replaces your settings and adds the rest to what you have.") {
                    ForEach(Array((BackupPlanner.describe(backup) + BackupPlanner.describe(plan)).enumerated()), id: \.offset) { _, line in
                        NoteRow(line)
                    }
                }
                SettingsGroup {
                    ActionRow(nil, title: "Restore", chevron: false) { Task { await model.restore(lyrics: lyrics) } }
                    ActionRow(nil, title: "Cancel", chevron: false) { model.cancel() }
                }
            } else {
                SettingsGroup(footer: "Settings, sound, playlists, likes and ratings, in one file. Never passwords or keys.") {
                    ActionRow(SettingsIndex.saveBackup, chevron: false, busy: model.working) {
                        Task { saving = await model.document(session: session) }
                    }
                    ActionRow(SettingsIndex.restoreBackup, chevron: false, enabled: !model.working) { opening = true }
                    if let note = model.note { NoteRow(note) }
                }
            }
        }
        .fileExporter(isPresented: Binding(get: { saving != nil }, set: { if !$0 { saving = nil } }), document: saving,
                      contentType: .json, defaultFilename: BackupFile.suggestedName(Date())) { result in
            switch result {
            case .success: model.saved(true)
            case .failure(let error): if (error as NSError).code != NSUserCancelledError { model.saved(false) }
            }
            saving = nil
        }
        .fileImporter(isPresented: $opening, allowedContentTypes: [.json, .plainText, .data]) { result in
            if case .success(let url) = result { Task { await model.open(url) } }
        }
        .onAppear {
            guard !visiting else { return }
            visiting = true
            model.visitStarted()
        }
    }
}

/// Where saving or restoring a backup is up to. Each visit of the page starts with nothing to
/// report; a save or restore still going when the page was left carries on and shows on the
/// next visit.
@MainActor
@Observable
final class BackupModel {
    static let shared = BackupModel()

    enum State {
        case idle
        case working
        case saved(Bool)
        /// A backup read and matched against the library, waiting to be restored.
        case ready(Backup, RestorePlan)
        case restored(RestorePlan)
        case problem(String)
    }

    private(set) var state: State = .idle

    private init() {}

    var working: Bool {
        if case .working = state { return true }
        return false
    }

    /// The words under the buttons once there is something to report.
    var note: String? {
        switch state {
        case .saved(let ok): ok ? "Backup saved." : "Couldn't write the backup there."
        case .restored(let plan): (["Restored."] + BackupPlanner.describe(plan)).joined(separator: "\n")
        case .problem(let message): message
        default: nil
        }
    }

    /// The backup as a file to save, built from everything as it is now.
    func document(session: Session) async -> BackupDocument {
        let before = state
        state = .working
        let document = BackupDocument(data: await Backups.shared.data(session: session))
        state = before
        return document
    }

    func saved(_ ok: Bool) { state = .saved(ok) }

    /// A fresh visit of the page: no note and no backup waiting, unless something is working.
    func visitStarted() {
        if !working { state = .idle }
    }

    func open(_ url: URL) async {
        state = .working
        switch await Backups.shared.read(url) {
        case .read(let backup): state = .ready(backup, await Backups.shared.plan(backup))
        case .tooNew: state = .problem("This backup was made by a newer Octo. Update the app to restore it.")
        case .notABackup: state = .problem("That file isn't an Octo backup.")
        }
    }

    func restore(lyrics: LyricsStore) async {
        guard case .ready(let backup, let plan) = state else { return }
        state = .working
        await Backups.shared.restore(backup, plan: plan, lyricsStore: lyrics)
        state = .restored(plan)
    }

    func cancel() { state = .idle }

    #if DEBUG
    /// Shows the review of a backup made here, as if it had been read from a file.
    func review(_ backup: Backup) async {
        state = .ready(backup, await Backups.shared.plan(backup))
    }
    #endif
}

/// A backup as a file the system's save picker writes.
struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
