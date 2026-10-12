import Foundation

// What the song menu and the collection menus offer, in which groups, and their words.

/// The choices in a song's menu, in the order shown.
public enum SongAction: CaseIterable, Sendable {
    case playNext, addToQueue, startRadio, download, requestCopy, addToLastPlaylist, addToPlaylist, removeFromPlaylist, select
    case keepOffline, findFlac, shareFile, share, like, rate, goToAlbum, goToArtist, setAsSound, deleteFromPhone
    case removeFromMyLibrary, deleteFromDisk, info, findSongs
}

/// Where the menu was opened, as the choices care about it.
public struct MenuPlace: Equatable, Sendable {
    /// On the page of the song's own album, or its own artist.
    public var onAlbumPage = false
    public var onArtistPage = false
    /// On a row of a playlist page, which can be taken out.
    public var inPlaylist = false
    /// In a list that can pick songs, and not picking already.
    public var selectable = false

    public init(onAlbumPage: Bool = false, onArtistPage: Bool = false, inPlaylist: Bool = false, selectable: Bool = false) {
        self.onAlbumPage = onAlbumPage
        self.onArtistPage = onArtistPage
        self.inPlaylist = inPlaylist
        self.selectable = selectable
    }
}

/// Where a song's menu was opened from: the album page it is on, the artist page, or its row on
/// a playlist page. `selecting` says whether the list is picking already, nil when it cannot
/// pick; `selectKey` is the row's key in it.
public struct SongMenuContext: Equatable, Sendable {
    public var albumId: String?
    public var artistId: String?
    public var playlistId: String?
    public var playlistItemId: Int64?
    public var selecting: Bool?
    public var selectKey: String?

    public init(albumId: String? = nil, artistId: String? = nil, playlistId: String? = nil, playlistItemId: Int64? = nil,
                selecting: Bool? = nil, selectKey: String? = nil) {
        self.albumId = albumId
        self.artistId = artistId
        self.playlistId = playlistId
        self.playlistItemId = playlistItemId
        self.selecting = selecting
        self.selectKey = selectKey
    }
}

/// What the context means for one song: "Go to album" only leads somewhere from a page other
/// than that album's.
public func menuPlace(_ context: SongMenuContext, albumId: String, artistId: String) -> MenuPlace {
    MenuPlace(
        onAlbumPage: context.albumId != nil && context.albumId == albumId,
        onArtistPage: context.artistId != nil && context.artistId == artistId,
        inPlaylist: context.playlistId != nil && context.playlistItemId != nil,
        selectable: context.selecting == false && context.selectKey != nil)
}

/// What a song's menu offers. A song found online offers the add instead of the library's
/// choices. `offline` is a library song only on a server, or one already kept. `phone` is a song
/// with a file on the phone. `lastPlaylist` is a playlist added to lately. `upgrade` is an Octo
/// server that can look for a better copy. `findSongs` is a server that can run the song's
/// search again. `disk` is a server that lets this user delete its copy. `requestCopy` and
/// `removeFromMine` are for family members.
public func songActions(
    find: Bool, radio: Bool, share: Bool = false, offline: Bool = false, place: MenuPlace = MenuPlace(), phone: Bool = false,
    lastPlaylist: Bool = false, upgrade: Bool = false, findSongs: Bool = false, disk: Bool = false, requestCopy: Bool = false,
    removeFromMine: Bool = false
) -> [SongAction] {
    var out: [SongAction] = [.playNext, .addToQueue]
    if radio { out.append(.startRadio) }
    if find {
        out.append(.download)
        if requestCopy { out.append(.requestCopy) }
        if place.inPlaylist { out.append(.removeFromPlaylist) }
        if place.selectable { out.append(.select) }
    } else {
        if lastPlaylist { out.append(.addToLastPlaylist) }
        out.append(.addToPlaylist)
        if place.inPlaylist { out.append(.removeFromPlaylist) }
        if place.selectable { out.append(.select) }
        if offline { out.append(.keepOffline) }
        if upgrade { out.append(.findFlac) }
        if phone { out.append(.shareFile) }
        if share { out.append(.share) }
        out.append(.like)
        out.append(.rate)
        if !place.onAlbumPage { out.append(.goToAlbum) }
        if !place.onArtistPage { out.append(.goToArtist) }
        if phone {
            out.append(.setAsSound)
            out.append(.deleteFromPhone)
        }
        if removeFromMine { out.append(.removeFromMyLibrary) }
        if disk { out.append(.deleteFromDisk) }
    }
    out.append(.info)
    if findSongs { out.append(.findSongs) }
    return out
}

/// How a song's menu groups its actions, top to bottom: playing it, keeping it, going to its
/// album or artist, sharing and looking into it, and last, what takes it away.
private let songMenuOrder: [[SongAction]] = [
    [.playNext, .addToQueue, .startRadio],
    [.addToLastPlaylist, .addToPlaylist, .like, .rate, .download, .requestCopy, .keepOffline, .findFlac],
    [.goToAlbum, .goToArtist],
    [.share, .shareFile, .setAsSound, .info, .findSongs, .select],
    [.removeFromPlaylist, .deleteFromPhone, .removeFromMyLibrary, .deleteFromDisk],
]

/// The actions offered, in their groups, leaving out empty groups.
public func songMenuGroups(_ actions: [SongAction]) -> [[SongAction]] {
    songMenuOrder.map { group in group.filter(actions.contains) }.filter { !$0.isEmpty }
}

/// The add row's words for a song not in the library, and how its adding is going.
public func downloadLabel(_ state: DownloadState) -> String {
    switch state {
    case .none: "Add to your library"
    case .requested: "Adding to your library"
    case .done: "In your library"
    }
}

/// The row's words for a library song downloaded to the phone, or not yet. `byHand` is a
/// download asked for from a menu, which can be removed here; one a rule keeps goes with its rule.
public func keepOfflineLabel(_ state: DownloadStatus?, byHand: Bool) -> String {
    switch state {
    case nil: "Download"
    case .queued: "Waiting to download"
    case .downloading: "Downloading"
    case .done: byHand ? "Remove download" : "Kept downloaded"
    case .failed: "Download failed, try again"
    }
}

/// Whether the row can be tapped.
public func keepOfflineEnabled(_ state: DownloadStatus?, byHand: Bool) -> Bool {
    state == nil || state == .failed || (state == .done && byHand)
}

/// The rating a tap on a star gives: that many stars, or none when the song already has exactly
/// that many.
public func nextRating(current: Int, tapped: Int) -> Int { tapped == current ? 0 : tapped }

/// "3 stars", or nothing for a song not rated yet.
public func starsLabel(_ rating: Int) -> String? {
    if rating <= 0 { return nil }
    return rating == 1 ? "1 star" : "\(rating) stars"
}

// MARK: Collections

/// The choices in a collection's menu, in the order shown.
public enum CollectionAction: CaseIterable, Sendable {
    case play, shuffle, playNext, addToQueue, addToPlaylist, download, findFlac, startRadio
    case addToFavorites, removeFromFavorites, pinToHome, unpin, moveToFront
    case goToArtist, rename, duplicate, delete
}

/// Where a collection stands on Home: not pinned, pinned, or pinned first.
public enum PinSpot: Sendable {
    case none, pinned, first
}

private let playing: [CollectionAction] = [.play, .shuffle, .playNext, .addToQueue]

private func favoriteRow(_ favorite: Bool) -> CollectionAction { favorite ? .removeFromFavorites : .addToFavorites }

private func pinRows(_ spot: PinSpot) -> [CollectionAction] {
    switch spot {
    case .none: [.pinToHome]
    case .pinned: [.unpin, .moveToFront]
    case .first: [.unpin]
    }
}

/// An album can be downloaded when some of its songs are only on a server and not downloaded
/// yet. `lossy` is how many of its songs an Octo server could look for a better copy of.
public func albumActions(canDownload: Bool, favorite: Bool = false, pin: PinSpot = .none, radio: Bool = false,
                         lossy: Int = 0) -> [CollectionAction] {
    var out = playing
    if radio { out.append(.startRadio) }
    out.append(.addToPlaylist)
    if canDownload { out.append(.download) }
    if lossy > 0 { out.append(.findFlac) }
    out.append(favoriteRow(favorite))
    out += pinRows(pin)
    out.append(.goToArtist)
    return out
}

public func artistActions(radio: Bool, favorite: Bool = false, pin: PinSpot = .none) -> [CollectionAction] {
    var out = playing
    if radio { out.append(.startRadio) }
    out.append(favoriteRow(favorite))
    out += pinRows(pin)
    return out
}

/// An empty playlist has nothing to play, only itself to pin, rename, copy or delete.
public func playlistActions(empty: Bool, pin: PinSpot = .none) -> [CollectionAction] {
    var out: [CollectionAction] = empty ? [] : playing
    out += pinRows(pin)
    out += [.rename, .duplicate, .delete]
    return out
}

private let collectionMenuOrder: [[CollectionAction]] = [
    [.play, .shuffle, .playNext, .addToQueue, .startRadio],
    [.addToPlaylist, .addToFavorites, .removeFromFavorites, .download, .findFlac],
    [.pinToHome, .unpin, .moveToFront],
    [.goToArtist],
    [.rename, .duplicate, .delete],
]

/// The actions offered, in their groups, leaving out empty groups.
public func collectionMenuGroups(_ actions: [CollectionAction]) -> [[CollectionAction]] {
    collectionMenuOrder.map { group in group.filter(actions.contains) }.filter { !$0.isEmpty }
}

/// Where a pin is in the row Home shows.
public func pinSpot<Key: Equatable>(_ shown: [Key], _ key: Key) -> PinSpot {
    switch shown.firstIndex(of: key) {
    case nil: .none
    case 0: .first
    default: .pinned
    }
}
