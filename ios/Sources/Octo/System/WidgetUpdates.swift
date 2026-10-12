import Observation
import OctoKit
import OctoSystem
import UIKit
import WidgetKit

/// Keeps the Now playing widget in step with the player: the song, its artist, whether it plays
/// and its cover go on the shelf the widget reads, and WidgetKit is asked to redraw. Only a new
/// song or a start or stop changes it, so nothing is done while music simply plays.
@MainActor
final class WidgetUpdates {
    private let player: Player
    private let shelf: WidgetShelf?
    /// What the shelf shows now.
    private var playback: WidgetPlayback?
    /// The cover's artwork reference for the song shown, and its picture once read.
    private var coverRef: String?
    private var cover: Data?
    /// Whether the cover for `coverRef` was tried, found or not.
    private var loaded = false
    private var loading: Task<Void, Never>?
    /// The cover changed since the shelf was last written.
    private var coverChanged = true
    /// What was last written, so the same thing is not written twice.
    private var written: WidgetPlayback?
    private var everWritten = false
    /// Closed from the lock screen: "Nothing playing" until music plays again.
    private var closed = false
    private var observers: [NSObjectProtocol] = []

    init(player: Player, shelf: WidgetShelf? = .shared()) {
        self.player = player
        self.shelf = shelf
    }

    func start() {
        follow()
        player.onClose = { [weak self] in
            self?.closed = true
            self?.show()
        }
        // The app going away: back to "Nothing playing".
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.clear() }
        })
    }

    private func follow() {
        withObservationTracking {
            show()
        } onChange: { [weak self] in
            Task { @MainActor in self?.follow() }
        }
    }

    /// Puts the music as it is on the widget.
    func show() {
        // Buffering after a press of play already shows pause.
        let playing = player.isPlaying || player.isWaiting
        if playing { closed = false }
        let item = closed ? nil : player.currentItem
        playback = item.map { WidgetPlayback(title: $0.title, artist: $0.artist, isPlaying: playing) }
        let ref = item?.artwork
        if ref != coverRef {
            coverRef = ref
            cover = nil
            loaded = false
            coverChanged = true
            loading?.cancel()
            loading = nil
        }
        // The cover is read once per song, and only with a widget placed. The words wait for it,
        // so the two change together.
        if let ref, !loaded, loading == nil {
            loading = Task { [weak self] in
                let placed = await Self.placed()
                var picture: Data?
                if placed { picture = await self?.coverData(ref) }
                guard let self, !Task.isCancelled, self.coverRef == ref else { return }
                guard placed else {
                    self.loading = nil
                    self.write()
                    return
                }
                self.cover = picture
                self.loaded = true
                self.loading = nil
                self.write()
            }
        }
        if loading == nil { write() }
    }

    /// Writes the shelf again even when nothing changed.
    func rewrite() {
        everWritten = false
        show()
    }

    /// Back to "Nothing playing", at once.
    func clear() {
        loading?.cancel()
        loading = nil
        playback = nil
        coverRef = nil
        cover = nil
        loaded = false
        coverChanged = true
        write()
    }

    private func write() {
        guard let shelf else { return }
        if everWritten, !coverChanged, written == playback { return }
        let update: WidgetShelf.Cover = coverChanged ? (cover.map { .new($0) } ?? .none) : .keep
        do {
            try shelf.write(playback, cover: update)
        } catch {
            return
        }
        written = playback
        everWritten = true
        coverChanged = false
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.nowPlaying)
    }

    /// Whether a Now playing widget is on the home screen.
    private static func placed() async -> Bool {
        let widgets = (try? await WidgetCenter.shared.currentConfigurations()) ?? []
        return widgets.contains { $0.kind == WidgetKind.nowPlaying }
    }

    /// The song's cover as a small square picture: the middle of the artwork, at most 300 px
    /// across. Nil when there is none.
    private func coverData(_ reference: String) async -> Data? {
        let session = player.session
        var image: UIImage?
        if ArtworkRef.decode(reference) != nil {
            image = await ArtworkCache.shared.image(reference, px: WidgetShelf.coverPixels, client: session.client,
                                                   signedInSource: session.inUse?.sourceId)
        } else if let client = session.client {
            image = await Covers.shared.image(reference, size: WidgetShelf.coverPixels, client: client)
        }
        guard let image else { return nil }
        return Self.square(image, pixels: WidgetShelf.coverPixels)
    }

    /// The middle square of a picture, scaled down to at most `pixels` across, as JPEG.
    static func square(_ image: UIImage, pixels: Int) -> Data? {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        let side = min(width, height)
        guard side > 0 else { return nil }
        let out = min(side, CGFloat(pixels))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let scale = out / side
        let drawn = UIGraphicsImageRenderer(size: CGSize(width: out, height: out), format: format).image { _ in
            image.draw(in: CGRect(x: -(width - side) / 2 * scale, y: -(height - side) / 2 * scale, width: width * scale, height: height * scale))
        }
        return drawn.jpegData(compressionQuality: 0.85)
    }
}
