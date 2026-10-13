import Foundation

// Server songs kept on the phone as real files, one at a time, in the order asked for: asked for
// by hand, or kept in step with rules (Liked songs, and chosen playlists). The rules below are
// what the download queue decides; the queue itself lives with the app.

/// How often a running download writes how far it has got.
public let downloadProgressEveryMs: Int64 = 500

/// How far a running download may say it has got before its file is saved.
public let downloadProgressCap: Float = 0.99

/// How long rule changes settle before the downloads follow them.
public let downloadRulesSettleMs: Int64 = 1_500

/// How many times a download that broke off with a connection is tried before it is marked
/// failed.
public let downloadTries = 3

/// How long between those tries.
public let downloadRetryAfterMs: Int64 = 5_000

/// How long the file of a download removed by hand is set aside, so the removal can be taken
/// back. A little longer than the undo line stays up.
public let downloadUndoKeepMs: Int64 = 10_000

/// The folder downloads are saved in.
public let downloadFolderName = "Octo"

/// The folder inside it where removed files wait out their undo.
public let downloadAsideFolderName = ".removed"

/// What a download is called while it is still being written.
public func downloadPartName(_ fileName: String) -> String { fileName + ".part" }

/// What a removed file is called while it waits out its undo: unique by `stamp`.
public func downloadAsideName(_ fileName: String, stamp: Int64) -> String { "\(stamp)-\(fileName)" }

/// One download, by its server and the song's id there.
public func downloadKey(_ sourceId: String, _ serverId: String) -> String { "\(sourceId)|\(serverId)" }

/// Whether a removal can be taken back: every finished download kept its file. Unfinished ones
/// only need to wait in line again.
public func canRestore(_ removed: [(state: DownloadStatus, fileKept: Bool)]) -> Bool {
    !removed.isEmpty && !removed.contains { $0.state == .done && !$0.fileKept }
}

/// How a removed download comes back: a finished one whose file moved back as it was, a failed
/// one as it was, anything else waiting to download again from the start.
public func restoredDownload(_ row: KeptDownload, fileBack: Bool) -> KeptDownload {
    if row.state == .done && fileBack { return row }
    if row.state == .failed { return row }
    var waiting = row
    waiting.state = .queued
    waiting.progress = 0
    waiting.path = ""
    waiting.sizeBytes = 0
    waiting.fileSize = nil
    return waiting
}

/// Every download, by library song. With two for one song, the later row wins.
public func downloadsByTrack(_ rows: [KeptDownload]) -> [String: KeptDownload] {
    var byTrack: [String: KeptDownload] = [:]
    for row in rows { byTrack[row.trackId] = row }
    return byTrack
}

/// Library songs downloaded and ready to play.
public func downloadedTrackIds(_ rows: [KeptDownload]) -> Set<String> {
    Set(downloadsByTrack(rows).filter { $0.value.state == .done }.keys)
}

/// The downloads of the server in use, each library song with every reason it is kept. Another
/// kept server's files stay as they are until it is in use again: its songs are not in the
/// library meanwhile, and would look unwanted. Nothing is held with no server in use.
public func downloadsHeld(_ rows: [KeptDownload], serverInUse: String?) -> [String: Set<String>] {
    guard let serverInUse else { return [:] }
    var held: [String: Set<String>] = [:]
    for row in rows where row.sourceId == serverInUse { held[row.trackId, default: []].formUnion(row.reasons) }
    return held
}

/// Downloads asked for by hand: songs not held yet are added, wanted by hand; songs already held
/// keep their reasons and gain the hand's.
public func planManualDownloads(held: [String: Set<String>], trackIds: [String]) -> DownloadPlan {
    var plan = DownloadPlan()
    for trackId in trackIds {
        if let reasons = held[trackId] {
            plan.change[trackId] = reasons.union([DownloadReasons.manual])
        } else {
            plan.add[trackId] = [DownloadReasons.manual]
        }
    }
    return plan
}

/// What is left keeping a song once its download is removed by hand. Empty when the download
/// itself goes; otherwise a rule still keeps it.
public func reasonsAfterManualRemoval(_ reasons: Set<String>) -> Set<String> {
    reasons.subtracting([DownloadReasons.manual])
}

/// Whether the queue may run now: a server is signed in, and the phone is on Wi-Fi when
/// downloads wait for it, or online at all when they do not.
public func downloadMayRunNow(signedIn: Bool, wifiOnly: Bool, onWifi: Bool, online: Bool) -> Bool {
    signedIn && (wifiOnly ? onWifi : online)
}

/// Whether a running download stops to wait for a connection: leaving Wi-Fi pauses one that
/// waits for it.
public func downloadLeftWifi(wifiOnly: Bool, onWifi: Bool) -> Bool { wifiOnly && !onWifi }

/// Whether a running download writes how far it has got now, `lastMs` being when it last did
/// (0 before the first time).
public func downloadProgressDue(nowMs: Int64, lastMs: Int64) -> Bool { nowMs - lastMs >= downloadProgressEveryMs }

/// How far a download has got, from 0 up to `downloadProgressCap`, or nil when its length is
/// not known.
public func downloadProgress(written: Int64, length: Int64) -> Float? {
    guard length > 0 else { return nil }
    return min(max(Float(written) / Float(length), 0), downloadProgressCap)
}

/// What a download does after it broke off.
public enum DownloadAfterFailure: Sendable, Equatable {
    /// No connection: it waits in line for one, however long that takes, and its tries start
    /// over.
    case waitForConnection
    /// The server said no, or every try is used: it is marked failed.
    case fail
    /// It waits in line again, after this pause.
    case retry(afterMs: Int64)
}

/// What a download does after it broke off for the `tried`th time (counting this one).
/// `noConnection` is for a phone with no connection, or off Wi-Fi when downloads wait for it.
/// `serverRefused` is for an answer the server gave with an error status: asking again will not
/// change it.
public func downloadAfterFailure(noConnection: Bool, serverRefused: Bool, tried: Int) -> DownloadAfterFailure {
    if noConnection { return .waitForConnection }
    if serverRefused || tried >= downloadTries { return .fail }
    return .retry(afterMs: downloadRetryAfterMs)
}

/// New downloads, held back where they may not go yet.
public struct NewDownloads: Sendable, Equatable {
    /// Rows to queue.
    public var kept: [KeptDownload]
    /// Rows the server in use's family plan refuses: offline copies are off for this account.
    public var refused: [KeptDownload]

    public init(kept: [KeptDownload], refused: [KeptDownload]) {
        self.kept = kept
        self.refused = refused
    }
}

/// Queues new downloads, each from the best copy on the server. Only songs that can be
/// downloaded (on a server and not on the phone) are queued; `copies` are their server copies,
/// each by the library song it was merged into. `refusedSource` is the server in use when its
/// family plan has offline copies off for this account.
public func newDownloads(wanted: [String: Set<String>], downloadable: Set<String>, copies: [SourceTrack], now: Int64,
                         refusedSource: String? = nil) -> NewDownloads {
    var byTrack: [String: [SourceTrack]] = [:]
    for copy in copies { byTrack[copy.mergedId, default: []].append(copy) }
    let rows = wanted.keys.filter(downloadable.contains).sorted().compactMap { trackId -> KeptDownload? in
        guard let copy = downloadBestCopy(byTrack[trackId] ?? []), let reasons = wanted[trackId] else { return nil }
        return KeptDownload(trackId: trackId, sourceId: copy.sourceId, serverId: copy.nativeId, path: "", sizeBytes: 0, format: nil,
                            state: .queued, progress: 0, addedAt: now, reason: DownloadReasons.join(reasons), title: copy.title,
                            artist: copy.artist)
    }
    return NewDownloads(kept: rows.filter { $0.sourceId != refusedSource }, refused: rows.filter { $0.sourceId == refusedSource })
}

// The best copy to download

/// The best sounding of a song's server copies, the first among equals.
public func downloadBestCopy(_ copies: [SourceTrack]) -> SourceTrack? {
    guard var best = copies.first else { return nil }
    for next in copies.dropFirst() where downloadCompareQuality(next, best) > 0 { best = next }
    return best
}

/// Above zero when `a` sounds better than `b`: lossless beats lossy, then the higher sample
/// rate, the deeper bits, and last the higher bitrate. A fact only one of them has is skipped.
public func downloadCompareQuality(_ a: SourceTrack, _ b: SourceTrack) -> Int {
    let lossless = downloadCompareFlags(downloadIsLossless(a.mimeType), downloadIsLossless(b.mimeType))
    if lossless != 0 { return lossless }
    let rate = downloadCompareKnown(a.sampleRate, b.sampleRate)
    if rate != 0 { return rate }
    let bits = downloadCompareKnown(a.bitDepth, b.bitDepth)
    if bits != 0 { return bits }
    return downloadCompareKnown(downloadBitrate(a), downloadBitrate(b))
}

private func downloadCompareFlags(_ a: Bool, _ b: Bool) -> Int { a == b ? 0 : (a ? 1 : -1) }

private func downloadCompareKnown(_ a: Int?, _ b: Int?) -> Int {
    guard let a, let b, a > 0, b > 0 else { return 0 }
    return a == b ? 0 : (a < b ? -1 : 1)
}

private let downloadLosslessTypes: Set<String> = [
    "audio/flac", "audio/x-flac", "audio/alac", "audio/wav", "audio/x-wav", "audio/wave", "audio/vnd.wave",
    "audio/aiff", "audio/x-aiff", "audio/ape", "audio/x-ape", "audio/wavpack", "audio/x-wavpack",
]

/// Whether a type of audio is lossless.
public func downloadIsLossless(_ mimeType: String?) -> Bool {
    mimeType.map { downloadLosslessTypes.contains($0.lowercased()) } ?? false
}

/// Bits per second, as the source says, or worked out from the file's size and length. Servers
/// speak in kilobits, so a small number is read as that.
public func downloadBitrate(_ copy: SourceTrack) -> Int? {
    if let bitrate = copy.bitrate, bitrate > 0 { return bitrate < 10_000 ? bitrate * 1000 : bitrate }
    guard let size = copy.sizeBytes, size > 0, copy.durationMs > 0 else { return nil }
    let bitsPerSecond = Double(size) * 8 / (Double(copy.durationMs) / 1000)
    return Int(min(bitsPerSecond, Double(Int32.max)))
}

extension StreamQuality {
    /// The most a stream of this size may carry, or nil for the file as it is.
    var downloadKbps: Int? {
        switch self {
        case .original: nil
        case .mp3(let kbps): kbps
        }
    }
}

/// What a download asks the server for: nil for its file as it is, else an MP3 of at most this
/// many kbps. A lossy file already within the size comes as it is: making it an MP3 would only
/// lose quality.
public func downloadMaxKbps(mimeType: String?, bitrate: Int?, quality: StreamQuality) -> Int? {
    guard let cap = quality.downloadKbps else { return nil }
    if !downloadIsLossless(mimeType), let bitrate, bitrate / 1000 <= cap { return nil }
    return cap
}

/// The type of file a download makes: the server's, or MP3 when a smaller one is asked for.
public func downloadFormat(serverMimeType: String?, maxKbps: Int?) -> String? {
    maxKbps == nil ? serverMimeType : "audio/mpeg"
}
