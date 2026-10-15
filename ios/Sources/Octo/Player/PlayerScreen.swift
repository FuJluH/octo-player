import Observation
import OctoKit
import SwiftUI
import UIKit

/// States of the full player asked for from outside: the drive steps.
@MainActor
@Observable
final class PlayerDrive {
    static let shared = PlayerDrive()

    struct Request: Equatable {
        let id = UUID()
        let name: String
        let value: String
    }

    private(set) var request: Request?

    func ask(_ name: String, _ value: String = "") { request = Request(name: name, value: value) }
    func taken() { request = nil }
}

/// What the library knows about the song playing: the library song it is, its rating, how many
/// songs its album has, and its tempo. Read again when the song changes and when the library's
/// ratings or songs change, so a rating set elsewhere shows at once.
@MainActor
@Observable
final class PlayerSongFacts {
    private(set) var songId: String?
    /// The library song, nil for a song the library does not have.
    private(set) var trackId: String?
    private(set) var rating = 0
    private(set) var albumSongs = 0
    private(set) var bpm: Int?
    @ObservationIgnored private var reading: Task<Void, Never>?

    /// Reads the facts for `song`, which the queue holds as `item`.
    func follow(_ song: Song?, item: QueueItem?, library: Library) {
        reading?.cancel()
        let changed = song?.id != songId
        songId = song?.id
        bpm = item?.bpm
        if changed {
            trackId = nil
            rating = 0
            albumSongs = 0
        }
        guard let song else { return }
        // Finds, stations and opened files are not library songs.
        let outside = item.map { $0.isFind || $0.trackId.hasPrefix("radio:") || $0.trackId.hasPrefix("file:") } ?? false
        let known = outside ? nil : item?.trackId
        reading = Task {
            let id: String? = if outside { nil } else if let known { known } else { await Self.libraryId(song, library: library) }
            guard !Task.isCancelled else { return }
            trackId = id
            guard let id, let track = await library.track(id) else { return }
            guard !Task.isCancelled else { return }
            rating = track.rating
            if !track.albumId.isEmpty, let album = await library.album(track.albumId) {
                albumSongs = album.songCount
            }
        }
    }

    /// The library song a song playing is: by its own id when that is a library id, else by its
    /// id on the server in use.
    static func libraryId(_ song: Song, library: Library) async -> String? {
        if song.isExternal || isFind(song.id) { return nil }
        if await library.track(song.id) != nil { return song.id }
        guard let server = library.serverInUse else { return nil }
        return try? await library.store.libraryLinks(server, [song.id]).first?.trackId
    }

    /// Shows a rating at once, before the library has saved it.
    func showRating(_ stars: Int) { rating = stars }
}

/// While the player shows, the status bar's clock and icons take the player's word color: dark
/// over a light background, light otherwise. A clear window above the app, which never takes a
/// touch, carries the style; it goes when the player closes.
struct PlayerStatusBar: UIViewRepresentable {
    let dark: Bool

    func makeUIView(context: Context) -> StatusBarHost { StatusBarHost() }

    func updateUIView(_ view: StatusBarHost, context: Context) { view.dark = dark }

    static func dismantleUIView(_ view: StatusBarHost, coordinator: ()) { view.release() }
}

final class StatusBarHost: UIView {
    private var window2: UIWindow?
    private let controller = StatusBarController()

    var dark = false {
        didSet {
            guard dark != oldValue else { return }
            controller.dark = dark
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window2 == nil, let scene = window?.windowScene else { return }
        let overlay = PassThroughWindow(windowScene: scene)
        overlay.windowLevel = .normal + 1
        overlay.backgroundColor = .clear
        overlay.isUserInteractionEnabled = false
        overlay.accessibilityElementsHidden = true
        controller.dark = dark
        overlay.rootViewController = controller
        overlay.isHidden = false
        window2 = overlay
    }

    func release() {
        window2?.isHidden = true
        window2?.rootViewController = nil
        window2 = nil
    }
}

private final class PassThroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

private final class StatusBarController: UIViewController {
    var dark = false {
        didSet { setNeedsStatusBarAppearanceUpdate() }
    }

    override func loadView() {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        self.view = view
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { dark ? .darkContent : .lightContent }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }
}
