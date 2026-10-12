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

    @MainActor
    static func now(_ session: Session) -> StreamContext {
        let inUse = session.inUse
        return StreamContext(
            client: inUse?.client, sourceId: inUse?.sourceId,
            keptSources: Set(session.servers.map(\.sourceId)),
            quality: AppSettings.shared.qualityInUse,
            keeping: AppSettings.shared.offline.cacheSize != .off)
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
        let saved = keeping
        let request = chooseRequest(
            source, ref, quality,
            fullySaved: { key in saved && ((try? blocking { await StreamCache.shared.isFullySaved(key) }) ?? false) },
            partlySaved: { key in saved && ((try? blocking { await StreamCache.shared.isPartlySaved(key) }) ?? false) })
        var pinnedRef = ref.pin(request)
        pinnedRef.sourceId = source
        return pinnedRef
    }

    /// The name a server song is kept under, or nil when no server is known for it.
    func savedKey(_ ref: StreamRef) -> String? {
        guard keeping, let source = ref.sourceId ?? sourceId else { return nil }
        return streamCacheKey(source, ref, ref.request(quality))
    }

    /// A signed request for one load of a server song. Fails at once with no connection, no
    /// server, an unreadable address, or another server's song.
    func sign(_ ref: StreamRef) throws -> URLRequest {
        guard OnlineWatch.shared.online else { throw PlayError(.ioUnspecified, detail: "No connection") }
        guard let client else { throw PlayError(.ioUnspecified, detail: "No server signed in") }
        if fromAnotherServer(ref) { throw PlayError(.ioUnspecified, detail: "Another server's song") }
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
        return { token in
            if let ref = parseStreamUri(uri) {
                guard OnlineWatch.shared.online || context.keeping else { throw PlayError(.ioUnspecified, detail: "No connection") }
                let pinned = context.pinned(ref)
                if let key = context.savedKey(pinned),
                   let saved = try? blocking({ await StreamCache.shared.savedFile(key) }),
                   let file = try? LocalFile(url: saved.url, contentType: saved.mimeType) {
                    token.adopt(file)
                    return OpenedSong(decoder: try SongDecoder(source: file, mimeType: saved.mimeType ?? mime, outputRate: outputRate), bytes: file)
                }
                let remote = try RemoteFile(savedKey: context.savedKey(pinned), online: { OnlineWatch.shared.online }) {
                    try context.sign(pinned)
                }
                token.adopt(remote)
                if scouting && !remote.answersRanges() { throw NotSeekable() }
                if token.isCancelled { throw PlayError(.ioUnspecified, detail: "stopped") }
                return OpenedSong(decoder: try SongDecoder(source: remote, mimeType: pinned.request(context.quality).mimeType(pinned.mimeType),
                                                           outputRate: outputRate), bytes: remote)
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
}
