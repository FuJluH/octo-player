import OctoKit
import SwiftUI

/// The app's icons, from Phosphor Icons (MIT): the Regular weight, and Fill for the transport
/// and for things that are on (a liked song, a rating, the selected tab). The outlines live in
/// `OctoIcon+Paths.swift`; draw them with `IconView` and tint in place.
enum OctoIcon: String, CaseIterable, Sendable {
    case previous, next, play, pause, shuffle, repeatAll, repeatOne, sleepTimer, queue, volumeDown, volumeUp
    case lossless, like, liked, more, playNext, addToQueue, addToPlaylist, rename, delete, album, artist
    case songs, genres, playlists, chevron, chevronBack, collapse, back, cloud, check, download, downloading
    case downloaded, addToLibrary, notInLibrary, radio, share, sound, star, starFilled, lyrics, folder, sort
    case filter, ascending, descending, info, select, close, history, pin, pinned, removeFromPlaylist
    case shareFile, ringtone, playback, appearance, library, scrobbling, backup, search, phone, home
    case homeSelected, searchSelected, librarySelected, settings, settingsSelected, cast, castConnected, tv
    case speaker, speakerGroup, headphones, globe, lock, lockOpen, key, sparkle, sync, storage, servers
    case timer, listeners, layout, wifi, camera, qrCode, copy, link, audioQuality, visible, hidden
    case minimize, maximize, restore, system, keyboard, loudness, balance, crossfade

    /// The outline in a unit square, read once.
    var outline: Path { IconOutlines.shared.path(for: self) }
}

/// Every icon's outline, read from its path data the first time it is drawn.
private final class IconOutlines: @unchecked Sendable {
    static let shared = IconOutlines()
    private var cache: [OctoIcon: Path] = [:]
    private let lock = NSLock()

    func path(for icon: OctoIcon) -> Path {
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[icon] { return hit }
        let made = Path(steps: PathData.steps(icon.pathData), scale: 1.0 / 256)
        cache[icon] = made
        return made
    }
}

extension Path {
    /// An outline from parsed path steps, scaled by `scale`.
    init(steps: [PathStep], scale: CGFloat) {
        self.init()
        for step in steps {
            switch step {
            case .move(let x, let y): move(to: CGPoint(x: x * scale, y: y * scale))
            case .line(let x, let y): addLine(to: CGPoint(x: x * scale, y: y * scale))
            case .cubic(let x1, let y1, let x2, let y2, let x, let y):
                addCurve(to: CGPoint(x: x * scale, y: y * scale),
                         control1: CGPoint(x: x1 * scale, y: y1 * scale),
                         control2: CGPoint(x: x2 * scale, y: y2 * scale))
            case .close: closeSubpath()
            }
        }
    }
}

/// An icon as a shape that fills its frame.
struct IconShape: Shape {
    let icon: OctoIcon

    func path(in rect: CGRect) -> Path {
        icon.outline.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
    }
}

/// An icon, `size` points square, in `color` (the foreground style by default).
struct IconView: View {
    let icon: OctoIcon
    var size: CGFloat = 24
    var color: Color?

    init(_ icon: OctoIcon, size: CGFloat = 24, color: Color? = nil) {
        self.icon = icon
        self.size = size
        self.color = color
    }

    var body: some View {
        Group {
            if let color {
                IconShape(icon: icon).fill(color)
            } else {
                IconShape(icon: icon).fill(.foreground)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The pause sign: two rounded bars on Phosphor's 256 grid, drawn at 0.8 about the middle.
struct PauseGlyph: View {
    var size: CGFloat = 22
    var color: Color = .white

    var body: some View {
        Canvas { context, canvas in
            let unit = canvas.width / 256
            func bar(_ x: CGFloat) -> Path {
                // 0.8 about the middle of the grid.
                let scale: CGFloat = 0.8
                let rect = CGRect(x: 128 + (x - 128) * scale, y: 128 + (32 - 128) * scale, width: 72 * scale, height: 192 * scale)
                return Path(roundedRect: CGRect(x: rect.minX * unit, y: rect.minY * unit, width: rect.width * unit, height: rect.height * unit),
                            cornerRadius: 16 * scale * unit)
            }
            context.fill(bar(40), with: .color(color))
            context.fill(bar(144), with: .color(color))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// ListenBrainz's mark, in its own navy and orange, never tinted.
struct ListenBrainzMark: View {
    var size: CGFloat = 24

    var body: some View {
        Canvas { context, canvas in
            let unit = canvas.width / 30
            var left = Path()
            left.addLines([CGPoint(x: 14.5, y: 1), CGPoint(x: 2.5, y: 8), CGPoint(x: 2.5, y: 22), CGPoint(x: 14.5, y: 29)].map { CGPoint(x: $0.x * unit, y: $0.y * unit) })
            left.closeSubpath()
            var right = Path()
            right.addLines([CGPoint(x: 15.5, y: 1), CGPoint(x: 27.5, y: 8), CGPoint(x: 27.5, y: 22), CGPoint(x: 15.5, y: 29)].map { CGPoint(x: $0.x * unit, y: $0.y * unit) })
            right.closeSubpath()
            context.fill(left, with: .color(Color(hex: 0x353070)))
            context.fill(right, with: .color(Color(hex: 0xEB743B)))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
