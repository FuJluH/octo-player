import OctoKit
import SwiftUI

/// The app's icons, each one of Apple's SF Symbols: the outline for a plain action, the filled
/// form for the transport and for things that are on (a liked song, a rating, the selected tab).
/// Draw them with `IconView` and tint in place.
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
    case minimize, maximize, restore, system, keyboard, loudness, balance, crossfade, stop

    /// The SF Symbol drawn for it.
    var symbol: String {
        switch self {
        case .previous: "backward.fill"
        case .next: "forward.fill"
        case .play: "play.fill"
        case .pause: "pause.fill"
        case .shuffle: "shuffle"
        case .repeatAll: "repeat"
        case .repeatOne: "repeat.1"
        case .sleepTimer: "moon.zzz"
        case .queue: "list.bullet"
        case .volumeDown: "speaker.fill"
        case .volumeUp: "speaker.wave.3.fill"
        case .lossless: "waveform"
        case .like: "heart"
        case .liked: "heart.fill"
        case .more: "ellipsis"
        case .playNext: "text.line.first.and.arrowtriangle.forward"
        case .addToQueue: "text.line.last.and.arrowtriangle.forward"
        case .addToPlaylist: "text.badge.plus"
        case .rename: "pencil"
        case .delete: "trash"
        case .album: "square.stack"
        case .artist: "music.microphone"
        case .songs: "music.note"
        case .genres: "guitars"
        case .playlists: "music.note.list"
        case .chevron: "chevron.right"
        case .chevronBack, .back: "chevron.left"
        case .collapse: "chevron.down"
        case .cloud: "cloud"
        case .check: "checkmark"
        case .download: "arrow.down.circle"
        case .downloading: "arrow.down.circle.dotted"
        case .downloaded: "arrow.down.circle.fill"
        case .addToLibrary: "plus"
        case .notInLibrary: "plus"
        case .radio: "dot.radiowaves.left.and.right"
        case .share: "square.and.arrow.up"
        case .sound: "slider.horizontal.3"
        case .star: "star"
        case .starFilled: "star.fill"
        case .lyrics: "quote.bubble"
        case .folder: "folder"
        case .sort: "arrow.up.arrow.down"
        case .filter: "line.3.horizontal.decrease"
        case .ascending: "arrow.up"
        case .descending: "arrow.down"
        case .info: "info.circle"
        case .select: "checkmark.circle"
        case .close: "xmark"
        case .history: "clock.arrow.circlepath"
        case .pin: "pin"
        case .pinned: "pin.fill"
        case .removeFromPlaylist: "minus.circle"
        case .shareFile: "square.and.arrow.up.on.square"
        case .ringtone: "bell"
        case .playback: "play.circle"
        case .appearance: "paintpalette"
        case .library: "square.stack"
        case .scrobbling: "chart.bar"
        case .backup: "arrow.clockwise.icloud"
        case .search, .searchSelected: "magnifyingglass"
        case .phone: "iphone"
        case .home: "house"
        case .homeSelected: "house.fill"
        case .librarySelected: "square.stack.fill"
        case .settings: "gearshape"
        case .settingsSelected: "gearshape.fill"
        case .cast, .castConnected: "airplay.audio"
        case .tv: "tv"
        case .speaker: "hifispeaker"
        case .speakerGroup: "hifispeaker.2"
        case .headphones: "headphones"
        case .globe: "globe"
        case .lock: "lock"
        case .lockOpen: "lock.open"
        case .key: "key"
        case .sparkle: "sparkles"
        case .sync: "arrow.triangle.2.circlepath"
        case .storage: "internaldrive"
        case .servers: "server.rack"
        case .timer: "timer"
        case .listeners: "person.2"
        case .layout: "rectangle.3.group"
        case .wifi: "wifi"
        case .camera: "camera"
        case .qrCode: "qrcode"
        case .copy: "doc.on.doc"
        case .link: "link"
        case .audioQuality: "waveform"
        case .visible: "eye"
        case .hidden: "eye.slash"
        case .minimize: "arrow.down.right.and.arrow.up.left"
        case .maximize: "arrow.up.left.and.arrow.down.right"
        case .restore: "arrow.uturn.backward"
        case .system: "gearshape.2"
        case .keyboard: "keyboard"
        case .loudness: "speaker.wave.2"
        case .balance: "dial.medium"
        case .crossfade: "arrow.triangle.merge"
        case .stop: "stop.fill"
        }
    }

    /// Whether the selected tab's or the on state's symbol is drawn bolder, as the system's
    /// tab bars do for a symbol without a filled form.
    var bold: Bool { self == .searchSelected }
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
        Image(systemName: icon.symbol)
            .font(.system(size: size * 0.8, weight: icon.bold ? .bold : .regular))
            .foregroundStyle(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.foreground))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The pause sign, `size` points square.
struct PauseGlyph: View {
    var size: CGFloat = 22
    var color: Color = .white

    var body: some View {
        IconView(.pause, size: size, color: color)
    }
}
