import Foundation
import Observation
import OctoKit

/// The animated art the app knows of, for the server in use: one `AnimatedArtBook` per server
/// connection, the answers kept with downloaded albums, and the asking ahead as songs change.
/// Views read `known(_:)`, which follows the book, and ask with `want(_:)`.
@MainActor
@Observable
final class AnimatedArtStore {
    static let shared = AnimatedArtStore()

    /// Counts up each time an answer arrives, so views reading `known` draw again.
    private(set) var version = 0

    @ObservationIgnored private weak var session: Session?
    @ObservationIgnored private var book: AnimatedArtBook?
    @ObservationIgnored private var bookKey: String?
    @ObservationIgnored private var watches: [AnyObject] = []

    #if DEBUG
    /// Art every album shows, for checking the screens on a device before a server offers any.
    var standIn: AnimatedArt? {
        didSet { version += 1 }
    }
    #endif

    /// The server albums of library songs whose album the library made, by song, found through
    /// the songs' copies on the server; nil when a song has none there.
    @ObservationIgnored private var lookedUp: [String: String?] = [:]
    @ObservationIgnored private var lookingUp = Set<String>()
    @ObservationIgnored private weak var library: Library?

    /// Starts following the songs the player plays, asking about their albums' art ahead.
    func attach(session: Session, player: Player, library: Library) {
        self.session = session
        self.library = library
        watches.append(Watch({ [weak self, weak player] in
            guard let self, let player else { return [String]() }
            return albumsToAsk(playing: self.albumId(of: player.current), next: player.upNext.prefix(1).map { self.albumId(of: $0) })
        }) { [weak self] ids in
            guard let self, AppSettings.shared.animatedArt != .off else { return }
            self.currentBook()?.ahead(ids)
        })
    }

    /// The server's own id for the album of a song the queue holds, the same id an album page
    /// asks by, so both find one answer; nil for a song with no album on the server in use. A
    /// song whose album the library made is looked up through its copies, and has its album a
    /// moment later.
    func albumId(of song: Song?) -> String? {
        _ = version
        guard let song, !song.isExternal, !isFind(song.id), !isRadio(song.id) else { return nil }
        if let albumId = song.albumId, albumId.hasPrefix(findPrefix) { return nil }
        let here = session?.inUse?.sourceId
        switch animatedAlbum(song.albumId, serverInUse: here) {
        case .server(let id): return id
        case .none: return nil
        case .lookUp:
            if let known = lookedUp[song.id] { return known }
            lookUp(song.id, serverInUse: here)
            return nil
        }
    }

    private func lookUp(_ trackId: String, serverInUse: String?) {
        guard let serverInUse, let library, lookingUp.insert(trackId).inserted else { return }
        Task { [weak self] in
            let copies = await library.copies(trackId)
            guard let self else { return }
            self.lookingUp.remove(trackId)
            self.lookedUp[trackId] = .some(serverAlbumId(copies: copies, serverInUse: serverInUse))
            self.version += 1
        }
    }

    /// What is known of the album's art right now: a downloaded album's own, else the book's.
    func known(_ albumId: String?) -> AnimatedArt? {
        _ = version
        guard let albumId, !albumId.isEmpty else { return nil }
        #if DEBUG
        if let standIn { return standIn }
        #endif
        if let kept = OfflineLoops.shared.art(albumId) { return kept }
        if case .has(let art) = currentBook()?.peek(albumId) { return art }
        return nil
    }

    /// The album's art, asking the server when it is not known yet.
    func want(_ albumId: String?) async -> AnimatedArt? {
        guard let albumId, !albumId.isEmpty, AppSettings.shared.animatedArt != .off else { return nil }
        if let known = known(albumId) { return known }
        return await currentBook()?.art(albumId)
    }

    /// The art getAlbum came with.
    func note(_ albumId: String, _ art: AnimatedArt?) {
        currentBook()?.note(albumId, art)
    }

    /// The book for the connection in use, made anew when it changes (another server, user,
    /// address, or its extensions read again); nil with no server.
    private func currentBook() -> AnimatedArtBook? {
        guard let session, let client = session.client else {
            book = nil
            bookKey = nil
            return nil
        }
        let key = "\(client.credentials.username)@\(client.baseURL.absoluteString)#\(session.generation)"
        if key == bookKey, let book { return book }
        let made = AnimatedArtBook(offered: { [weak self] in await self?.offered() }, ask: { await client.animatedArt($0) })
        made.changed = { [weak self] in Task { @MainActor in self?.version += 1 } }
        book = made
        bookKey = key
        // Another server: its albums are other ones.
        lookedUp = [:]
        return made
    }

    /// Whether the server in use lists animated art; nil while that is not known.
    private func offered() -> Bool? {
        guard let session, session.client != nil else { return nil }
        let extensions = session.extensions
        if extensions.isEmpty && session.profile == nil { return nil }
        return extensions.contains { $0 == octoAnimatedArt || $0.hasPrefix(octoAnimatedArt + ":") }
    }
}
