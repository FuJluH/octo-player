import Foundation
import Network
import OctoKit
import Synchronization

/// Whether the phone has a connection, kept where any thread can read it.
final class OnlineWatch: @unchecked Sendable {
    static let shared = OnlineWatch()

    private let monitor = NWPathMonitor()
    private let isOnline = Atomic<Bool>(true)
    private let isMobile = Atomic<Bool>(false)

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            self?.isOnline.store(online, ordering: .relaxed)
            self?.isMobile.store(online && !path.usesInterfaceType(.wifi) && !path.usesInterfaceType(.wiredEthernet), ordering: .relaxed)
        }
        monitor.start(queue: DispatchQueue(label: "app.winters.octo.playback.network"))
    }

    var online: Bool { isOnline.load(ordering: .relaxed) }
    var onMobileData: Bool { isMobile.load(ordering: .relaxed) }
}

/// Everything opening a song needs from the app, taken on the main actor as the song loads:
/// the server in use, the other kept servers, and the stream size for this connection.
struct StreamContext: Sendable {
    let client: SubsonicClient?
    let sourceId: String?
    /// The source ids of every kept server.
    let keptSources: Set<String>
    let quality: StreamQuality
    /// Songs played are kept on the phone as they stream.
    let keeping: Bool
    /// The sign-in, asked again as each request goes out.
    let session: Session?
    /// When the app started.
    var startedAt = Date.distantPast

    @MainActor
    static func now(_ session: Session) -> StreamContext {
        let inUse = session.inUse
        return StreamContext(
            client: inUse?.client, sourceId: inUse?.sourceId,
            keptSources: Set(session.servers.map(\.sourceId)),
            quality: AppSettings.shared.qualityInUse,
            keeping: AppSettings.shared.offline.cacheSize != .off,
            session: session, startedAt: session.startedAt)
    }

    /// The server in use as a request goes out: the address in use now (the home one while at
    /// home). In the first 3 s after the app starts, the saved sign-in gets until then to come
    /// back; after that, no server means none at once.
    func serverNow() -> (client: SubsonicClient, sourceId: String)? {
        guard let session else { return client.map { ($0, sourceId ?? "") } }
        let deadline = min(Date().addingTimeInterval(3), startedAt.addingTimeInterval(3))
        while true {
            let found = try? blocking { await MainActor.run { session.inUse.map { Unchecked(($0.client, $0.sourceId)) } } }
            if let found = found ?? nil { return found.value }
            if Date() >= deadline { return nil }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    /// Whether a song is another kept server's than the one in use: its id would be some other
    /// song here. A song kept under this server's old address, before it was edited, still plays.
    func fromAnotherServer(_ ref: StreamRef) -> Bool {
        guard let source = ref.sourceId else { return false }
        return source != sourceId && keptSources.contains(source)
    }

    /// The song with the request it loads with fixed in its address, by what is saved of it.
    func pinned(_ ref: StreamRef) -> StreamRef {
        if ref.pinned != nil { return ref }
        guard let source = ref.sourceId ?? sourceId else { return ref }
        let quality = quality
        var picked: StreamRequest?
        if keeping { picked = try? blocking { await StreamCache.shared.pick(source, ref, quality).request } }
        var pinnedRef = ref.pin(picked ?? ref.request(quality))
        pinnedRef.sourceId = source
        return pinnedRef
    }

    /// The name a server song is kept under, or nil when no server is known for it or songs are
    /// not kept. A saved copy of a file the server has since swapped is let go on the way.
    func savedKey(_ ref: StreamRef) -> String? {
        guard keeping, let source = ref.sourceId ?? sourceId else { return nil }
        let request = ref.request(quality)
        return try? blocking { await StreamCache.shared.savedKey(source, ref, request) }
    }

    /// A signed request for one load of a server song. Fails at once with no connection, no
    /// server, an unreadable address, or another server's song.
    func sign(_ ref: StreamRef) throws -> URLRequest {
        guard OnlineWatch.shared.online else { throw PlayError(.ioUnspecified, detail: "No connection") }
        guard let (client, inUse) = serverNow() else { throw PlayError(.ioUnspecified, detail: "No server signed in") }
        if let source = ref.sourceId, source != inUse, keptSources.contains(source) {
            throw PlayError(.ioUnspecified, detail: "Another server's song")
        }
        var request = URLRequest(url: client.streamURL(serverId: ref.serverId, request: ref.request(quality)))
        for (name, value) in client.headers { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }
}

/// A song the scout may not read: its server sends it whole from the start every time, so
/// reading its end would mean reading all of it.
struct NotSeekable: Error {}

/// Opens queue items for the decks and the scout: phone files and media library songs as they
/// are, server songs from their saved copy when it is whole, otherwise streamed and signed as
/// each request goes out, and saved as they play.
enum SongOpener {
    /// How a deck opens `item`. `scouting` asks the server first whether it sends parts of a
    /// song, and gives up when it does not.
    static func opener(_ item: QueueItem, context: StreamContext, outputRate: Double,
                       scouting: Bool = false) -> @Sendable (OpenToken) throws -> OpenedSong {
        let uri = item.uri
        let mime = item.mimeType
        let trackId = item.trackId
        return { token in
            if let ref = parseStreamUri(uri) {
                guard OnlineWatch.shared.online || context.keeping else { throw PlayError(.ioUnspecified, detail: "No connection") }
                let pinned = context.pinned(ref)
                let savedKey = context.savedKey(pinned)
                if let key = savedKey,
                   let saved = try? blocking({ await StreamCache.shared.savedFile(key) }),
                   let file = try? LocalFile(url: saved.url, contentType: saved.mimeType) {
                    // A saved copy that fails part way is passed over for the server's.
                    let copy = SavedCopy(file) {
                        try RemoteFile(online: { OnlineWatch.shared.online }) { try context.sign(pinned) }
                    }
                    token.adopt(copy)
                    return OpenedSong(decoder: try SongDecoder(source: copy, mimeType: saved.mimeType ?? mime, outputRate: outputRate), bytes: copy)
                }
                let remote = try RemoteFile(savedKey: savedKey, online: { OnlineWatch.shared.online }) {
                    try context.sign(pinned)
                }
                token.adopt(remote)
                if scouting && !remote.answersRanges() { throw NotSeekable() }
                if token.isCancelled { throw PlayError(.ioUnspecified, detail: "stopped") }
                return OpenedSong(decoder: try SongDecoder(source: remote, mimeType: pinned.request(context.quality).mimeType(pinned.mimeType),
                                                           outputRate: outputRate), bytes: remote)
            }
            // A server song's address that cannot be read names no song to ask for.
            if uri.lowercased().hasPrefix(streamScheme + ":") {
                guard OnlineWatch.shared.online else { throw PlayError(.ioUnspecified, detail: "No connection") }
                guard context.serverNow() != nil else { throw PlayError(.ioUnspecified, detail: "No server signed in") }
                throw PlayError(.ioUnspecified, detail: "No song id")
            }
            guard let url = URL(string: uri) else { throw PlayError(.fileNotFound, detail: "no address") }
            switch url.scheme?.lowercased() {
            case "file":
                let file = try LocalFile(url: url, contentType: mime)
                token.adopt(file)
                if let decoder = try? SongDecoder(source: file, mimeType: mime, outputRate: outputRate) {
                    return OpenedSong(decoder: decoder, bytes: file)
                }
                return OpenedSong(decoder: try AssetDecoder(url: url, outputRate: outputRate), bytes: file)
            case "http" where isRadio(trackId), "https" where isRadio(trackId):
                // A live station: read as it comes, with no length and no end; an HLS one by
                // its playlist, any other with its ICY titles.
                guard OnlineWatch.shared.online else { throw PlayError(.ioUnspecified, detail: "No connection") }
                return try openStation(url, hls: looksLikeHls(uri) || isHlsPlaylistType(mime), trackId: trackId, mime: mime,
                                       token: token, outputRate: outputRate)
            case "http", "https":
                let remote = try RemoteFile(online: { OnlineWatch.shared.online }) {
                    guard OnlineWatch.shared.online else { throw PlayError(.ioUnspecified, detail: "No connection") }
                    return URLRequest(url: url)
                }
                token.adopt(remote)
                return OpenedSong(decoder: try SongDecoder(source: remote, mimeType: mime, outputRate: outputRate), bytes: remote)
            default:
                // A song of the phone's media library.
                return OpenedSong(decoder: try AssetDecoder(url: url, outputRate: outputRate), bytes: nil)
            }
        }
    }

    /// Opens a live station at `url`: as HLS, or as a stream with ICY titles. A stream that
    /// answers with an HLS playlist is read as HLS, and an HLS address that holds a plain playlist
    /// of whole streams plays its first stream, at most `hops` times over. A source whose sound
    /// cannot start is stopped at once.
    private static func openStation(_ url: URL, hls: Bool, trackId: String, mime: String?, token: OpenToken,
                                    outputRate: Double, hops: Int = 3) throws -> OpenedSong {
        if token.isCancelled { throw PlayError(.ioUnspecified, detail: "stopped") }
        if hls {
            let bytes = HlsBytes(url: url)
            token.adopt(bytes)
            do {
                return OpenedSong(decoder: try LiveStreamDecoder(bytes: bytes, mimeType: nil, outputRate: outputRate), bytes: bytes)
            } catch {
                bytes.cancel()
                guard hops > 0, let entry = bytes.plainEntry else { throw error }
                return try openStation(entry, hls: looksLikeHls(entry.absoluteString), trackId: trackId, mime: nil, token: token,
                                       outputRate: outputRate, hops: hops - 1)
            }
        }
        let bytes = LiveBytes(request: URLRequest(url: url)) { title in LiveTitleBoard.post(trackId, title) }
        token.adopt(bytes)
        do {
            return OpenedSong(decoder: try LiveStreamDecoder(bytes: bytes, mimeType: isHlsPlaylistType(mime) ? nil : mime,
                                                             outputRate: outputRate), bytes: bytes)
        } catch {
            bytes.cancel()
            guard hops > 0, let playlist = bytes.playlistAddress else { throw error }
            return try openStation(playlist, hls: true, trackId: trackId, mime: nil, token: token, outputRate: outputRate, hops: hops - 1)
        }
    }
}
