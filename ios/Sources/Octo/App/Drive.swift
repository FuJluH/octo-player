#if DEBUG
import Foundation
import OctoKit
import SwiftUI

/// Steps named in the OCTO_DRIVE launch variable, run one after another once the app has
/// started, to bring it to a given state from outside. Steps are separated by ";":
///
/// - `wait:SECONDS`
/// - `tab:home`, `tab:search`, `tab:library`, `tab:settings` (the tab in use again goes back to
///   its first page, or scrolls it to the top)
/// - `reselect` taps the tab in use again; `back` goes back once
/// - `barplayer` grows the bar's small player; `showtabs` folds it back into the round button
/// - `player` opens the full player, `close` closes it, `lyrics` opens its lyrics
/// - `list:NAME` plays the server playlist with that name
/// - `found:TEXT` plays the songs not in the library that a search for TEXT finds
/// - `search:TEXT` plays the library songs a search for TEXT finds
/// - `pause`
/// - `toast:TEXT` a plain message; `undo:TEXT` a message with Undo; `done:TEXT` one with a check
/// - `dialog` a question with Delete and Cancel; `choice` a choice list; `sheet` a glass sheet;
///   `popup` a glass menu with a second page; `menu:page` opens it on its second page
/// - `reducemotion:on`, `reducemotion:off` sets Octo's own Reduce motion
/// - `glow:off`, `glow:subtle`, `glow:rich` sets the artwork's glow
/// - `select:N` picks N songs of the queue (or of a sample list), showing the selection bar;
///   `unselect` ends the picking
@MainActor
enum Drive {
    static func run(session: Session, player: Player, router: Router, prompts: Prompts, motion: MotionSettings,
                    overlays: Overlays? = nil, ambience: AmbientSettings? = nil,
                    selectionBar: SelectionBarState? = nil) async {
        guard let script = ProcessInfo.processInfo.environment["OCTO_DRIVE"], !script.isEmpty else { return }
        for _ in 0..<40 where session.client == nil { try? await Task.sleep(for: .milliseconds(250)) }
        try? await Task.sleep(for: .seconds(1))
        for step in script.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) where !step.isEmpty {
            let (name, value) = split(step)
            switch name {
            case "wait": try? await Task.sleep(for: .seconds(Double(value) ?? 1))
            case "tab": if let tab = AppTab(rawValue: value) { router.drive = .tab(tab) }
            case "reselect": router.drive = .reselect
            case "back": router.drive = .back
            case "barplayer": router.drive = .barPlayer
            case "showtabs": router.drive = .showTabs
            case "player": router.drive = .openPlayer
            case "close": router.drive = .closePlayer
            case "lyrics": router.drive = .lyrics
            case "pause": player.pause()
            case "toast": router.show(value.isEmpty ? "Added to the queue" : value)
            case "undo": router.undoable(value.isEmpty ? "Removed from the queue" : value) { router.done("Put back") }
            case "done": router.done(value.isEmpty ? "Added to Liked songs" : value)
            case "dialog":
                prompts.confirm("Delete this song from disk?",
                                detail: "This takes it off the server's disk and out of your library.",
                                confirm: "Delete") { router.done("Deleted") }
            case "choice":
                prompts.choose("Sort by", [Choice("Name"), Choice("Artist"), Choice("Recently added"),
                                           Choice("Year", detail: "Only albums have a year", enabled: false)],
                               selected: 0) { router.show("Sorted by \(["Name", "Artist", "Recently added", "Year"][$0])") }
            case "sheet":
                if let overlays { DriveSamples.sheet(overlays, router: router) }
            case "popup", "menu":
                if let overlays { DriveSamples.menu(overlays, router: router, deeper: value == "page") }
            case "reducemotion": motion.reduceMotion = value != "off"
            case "select":
                guard let selectionBar else { continue }
                let pool = player.queue.isEmpty ? (1...6).map { Song(id: "sample-\($0)", title: "Song \($0)") } : player.queue
                let selection = SongSelection()
                let target = SelectionTarget(selection: selection)
                target.list = pool.map { Pickable($0) }
                selectionBar.attach(target)
                for song in pool.prefix(max(1, Int(value) ?? 2)) {
                    if selection.active { selection.toggle(song.id) } else { selection.start(song.id) }
                }
                DriveSamples.selections.append(target)
            case "unselect":
                for target in DriveSamples.selections {
                    target.selection.clear()
                    selectionBar?.detach(target)
                }
                DriveSamples.selections = []
            case "glow":
                if let strength = AmbientStrength(rawValue: value.capitalized) { ambience?.prefs.strength = strength }
            case "list":
                guard let client = session.client,
                      let list = try? await client.playlists().first(where: { $0.name.caseInsensitiveCompare(value) == .orderedSame }),
                      let full = try? await client.playlist(list.id)
                else { continue }
                player.play(full.entry, from: 0)
            case "found", "search":
                guard let client = session.client, let found = try? await client.search(value) else { continue }
                let songs = found.song.filter { name == "found" ? $0.isExternal : !$0.isExternal }
                if !songs.isEmpty { player.play(songs, from: 0) }
            default: break
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
    }

    private static func split(_ step: String) -> (String, String) {
        guard let colon = step.firstIndex(of: ":") else { return (step, "") }
        return (String(step[..<colon]), String(step[step.index(after: colon)...]))
    }
}

/// The shell's sheet and menu as the drive steps show them.
@MainActor
enum DriveSamples {
    /// The picks the drive steps made, so `unselect` can end them.
    static var selections: [SelectionTarget] = []

    static func sheet(_ overlays: Overlays, router: Router) {
        let id = UUID()
        overlays.showSheet(id, tall: false, scrolls: true, content: AnyView(
            VStack(alignment: .leading, spacing: 0) {
                Text("Sleep timer").font(.octoSection).padding(.horizontal, 20).padding(.vertical, 10)
                ForEach(["15 minutes", "30 minutes", "45 minutes", "1 hour", "End of song"], id: \.self) { item in
                    Button {
                        overlays.hideSheet(id)
                        router.done("Sleeping in \(item)")
                    } label: {
                        Text(item).font(.octoBodySmall).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .padding(.horizontal, 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(SqueezeStyle())
                }
                OctoSwitchRow()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .padding(.bottom, 12)
        )) { overlays.hideSheet(id) }
    }

    static func menu(_ overlays: Overlays, router: Router, deeper: Bool) {
        let id = UUID()
        let pages = PopupPages("actions")
        if deeper { pages.open("rate") }
        overlays.showPopup(id, anchor: nil, title: "Song", content: AnyView(
            PopupPager(pages: pages) { page, canGoBack in
                if page == "actions" {
                    GlassMenuPage {
                        GlassMenuHeader(title: "A song", subtitle: "An artist") {
                            RoundedRectangle(cornerRadius: OctoRadius.artS).fill(OctoColor.backgroundTertiary).frame(width: 40, height: 40)
                        }
                        GlassMenuSeparator()
                    } content: {
                        GlassMenuAction(.playNext, "Play next") {
                            overlays.hidePopup(id)
                            router.done("Playing next")
                        }
                        GlassMenuAction(.addToQueue, "Add to queue") {
                            overlays.hidePopup(id)
                            router.undoable("Added to the queue") {}
                        }
                        GlassMenuSeparator()
                        GlassMenuAction(.star, "Rate", opensPage: true) { pages.open("rate") }
                        GlassMenuAction(.delete, "Delete from disk", destructive: true) {}
                        GlassMenuAction(.download, "Download", detail: "Not while offline", enabled: false) {}
                    }
                } else {
                    GlassMenuPage {
                        GlassMenuBack(title: "Rate") { pages.back() }
                    } content: {
                        GlassMenuOptions(options: (0...5).map { Choice($0 == 0 ? "No rating" : String(repeating: "★", count: $0)) },
                                         selected: 0) { _ in overlays.hidePopup(id) }
                    }
                }
            }
        ), dismiss: { overlays.hidePopup(id) }, back: { pages.back() })
    }
}

private struct OctoSwitchRow: View {
    @State private var on = false

    var body: some View {
        HStack {
            Text("Fade out at the end").font(.octoBodySmall).foregroundStyle(.white)
            Spacer()
            OctoSwitch(isOn: $on, label: "Fade out at the end")
        }
    }
}
#endif
