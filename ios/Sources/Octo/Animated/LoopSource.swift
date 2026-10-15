import AVFoundation
import Foundation
import OctoKit
import UIKit

/// The two shapes an album's animated art comes in, by the names their files are kept under.
enum LoopShape: String, Sendable {
    case square
    case tall
}

/// Where a loop's file comes from: the album's own copy when it is downloaded, else the shelf of
/// recently shown loops, else fetched there now. Each loop is the one file of the version that
/// suits its space on screen, so it plays from the phone and loops without a seam.
actor LoopSource {
    static let shared = LoopSource()

    /// Recently shown loops, at most 300 MB, in the caches the system may clear.
    let shelf: LoopShelf = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("loops")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return LoopShelf(dir: dir, maxBytes: 300 * 1024 * 1024)
    }()

    /// The file each clip's version was found in, by clip and space, for this run.
    private var located: [String: LoopFile] = [:]
    private var fetching: [String: Task<URL?, Never>] = [:]

    #if DEBUG
    /// Plays the clip's HLS playlist as it is, for checking how the player loops a stream.
    var streamsDirectly = false
    func setStreamsDirectly(_ on: Bool) { streamsDirectly = on }
    #endif

    /// A file to play for the clip in a space `pixels` big, or nil when it cannot be had now.
    func file(_ clip: AnimatedClip, albumId: String?, shape: LoopShape, pixels: CGSize, fetcher: LoopFetcher) async -> URL? {
        #if DEBUG
        if streamsDirectly { return URL(string: clip.video) }
        #endif
        if let albumId {
            let kept = offlineLoopFile(dir: OfflineLoops.dir, albumId: albumId, shape: shape.rawValue)
            if FileManager.default.fileExists(atPath: kept.path) { return kept }
        }
        let key = "\(clip.video)|\(Int(pixels.width))x\(Int(pixels.height))"
        if let running = fetching[key] { return await running.value }
        let task = Task<URL?, Never> {
            guard let file = await self.locate(clip, key: key, pixels: pixels, fetcher: fetcher) else { return nil }
            let target = shelf.file(for: file.url)
            if FileManager.default.fileExists(atPath: target.path) {
                shelf.touch(target)
                return target
            }
            guard await fetcher.fetch(file, to: target) else { return nil }
            shelf.trim(keep: [target])
            return target
        }
        fetching[key] = task
        let found = await task.value
        fetching[key] = nil
        return found
    }

    private func locate(_ clip: AnimatedClip, key: String, pixels: CGSize, fetcher: LoopFetcher) async -> LoopFile? {
        if let known = located[key] { return known }
        // The iPhone decodes HEVC in hardware, so either format will do.
        guard let file = await fetcher.locate(clip, width: Int(pixels.width), height: Int(pixels.height), codecs: [.avc, .hevc])
        else { return nil }
        located[key] = file
        return file
    }

    /// How the loop's first frame looks: whether its top is light, and its colors low down.
    func look(_ file: URL, topShare: CGFloat) async -> LoopLook? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
        generator.maximumSize = CGSize(width: 96, height: 128)
        guard let frame = try? await generator.image(at: .zero).image else { return nil }
        return loopLook(frame, topShare: topShare)
    }

    /// A small copy of the loop's first frame.
    func firstFrame(_ file: URL) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
        generator.maximumSize = CGSize(width: 96, height: 128)
        return try? await generator.image(at: .zero).image
    }

    /// The clip's still, from the downloaded album or the shelf, fetched when needed.
    func poster(_ clip: AnimatedClip, albumId: String?, shape: LoopShape, fetcher: LoopFetcher) async -> UIImage? {
        if let albumId {
            let kept = offlineLoopPoster(dir: OfflineLoops.dir, albumId: albumId, shape: shape.rawValue)
            if let image = UIImage(contentsOfFile: kept.path) { return await image.byPreparingForDisplay() ?? image }
        }
        guard let poster = clip.poster, let url = URL(string: poster) else { return nil }
        let target = shelf.dir.appendingPathComponent("posters").appendingPathComponent(shelf.file(for: url).deletingPathExtension().lastPathComponent + ".jpg")
        if !FileManager.default.fileExists(atPath: target.path) {
            guard await fetcher.fetchPoster(clip, to: target) else { return nil }
        }
        guard let image = UIImage(contentsOfFile: target.path) else { return nil }
        return await image.byPreparingForDisplay() ?? image
    }
}

/// What the player takes from a loop's picture: whether its top (under the status bar) is light,
/// and the average color of its lower part, which is what the blurred loop shows behind the
/// title and the controls (`0xFFRRGGBB`).
struct LoopLook: Equatable {
    var topLight: Bool
    var under: UInt32
}

/// The look of a picture whose top `topShare` the status bar sits on.
func loopLook(_ picture: CGImage?, topShare: CGFloat) -> LoopLook? {
    guard let picture, picture.width > 0, picture.height > 0 else { return nil }
    func average(from: CGFloat, to: CGFloat) -> UInt32? {
        let top = Int((CGFloat(picture.height) * min(max(from, 0), 1)).rounded())
        let rows = max(1, Int((CGFloat(picture.height) * min(max(to - from, 0), 1)).rounded()))
        guard let band = picture.cropping(to: CGRect(x: 0, y: top, width: picture.width, height: rows)) else { return nil }
        let width = 16, height = 4
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(band, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var r = 0, g = 0, b = 0
        for i in 0..<(width * height) {
            r += Int(bytes[i * 4])
            g += Int(bytes[i * 4 + 1])
            b += Int(bytes[i * 4 + 2])
        }
        let n = width * height
        return 0xFF00_0000 | UInt32(r / n) << 16 | UInt32(g / n) << 8 | UInt32(b / n)
    }
    guard let top = average(from: 0, to: topShare), let under = average(from: 0.55, to: 1) else { return nil }
    // Over 0.4 relative luminance dark words read better than white ones.
    return LoopLook(topLight: relativeLuminance(top) > 0.4, under: under)
}

/// A small copy of a picture, for reading its colors.
func loopSample(_ picture: CGImage?) -> CGImage? {
    guard let picture else { return nil }
    let width = 96, height = max(1, Int((96 * CGFloat(picture.height) / CGFloat(max(picture.width, 1))).rounded()))
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    context.interpolationQuality = .medium
    context.draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}

/// The brightest stretch of one row of a picture (`share` of the way down), as `0xFFRRGGBB`: the
/// row cut into eight, the one with the most light, so words over it are judged by their hardest
/// part. The middle nine tenths of the width only, as the edges are cropped off on screen.
func loopRowColor(_ picture: CGImage, share: CGFloat) -> UInt32? {
    let row = min(max(Int(CGFloat(picture.height) * share), 0), picture.height - 1)
    guard let line = picture.cropping(to: CGRect(x: 0, y: row, width: picture.width, height: 1)) else { return nil }
    let width = 40
    var bytes = [UInt8](repeating: 0, count: width * 4)
    let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(data: buffer.baseAddress, width: width, height: 1, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return false }
        context.draw(line, in: CGRect(x: 0, y: 0, width: width, height: 1))
        return true
    }
    guard drawn else { return nil }
    var best: UInt32?
    var bestLight = -1.0
    for part in 0..<8 {
        var r = 0, g = 0, b = 0
        let from = 2 + Int(Double(part) * 4.5), count = 4
        for x in from..<min(from + count, width - 2) {
            r += Int(bytes[x * 4]); g += Int(bytes[x * 4 + 1]); b += Int(bytes[x * 4 + 2])
        }
        let color = 0xFF00_0000 | UInt32(r / count) << 16 | UInt32(g / count) << 8 | UInt32(b / count)
        let light = relativeLuminance(color)
        if light > bestLight {
            bestLight = light
            best = color
        }
    }
    return best
}

/// The fetcher for a clip's addresses: one that leads to the server goes with the server's own
/// connection and headers (a proxy in front of it may want them); Apple's own go plainly.
@MainActor
func loopFetcher(for clip: AnimatedClip, client: SubsonicClient?) -> LoopFetcher {
    if let client, let host = URL(string: clip.video)?.host, host == client.baseURL.host {
        let headers = client.headers
        return LoopFetcher(session: client.session) { url in url.host == host ? headers : [:] }
    }
    return LoopFetcher(session: .shared)
}

/// The space a loop of `shape` is picked for, in pixels: the square at the screen's full
/// sharpness, the tall one at twice the points at most, both less the enlarging allowed.
@MainActor
func loopPixels(_ shape: LoopShape, points: CGSize, scale: CGFloat) -> CGSize {
    let used = (shape == .square ? scale : min(scale, 2)) / loopEnlargeAllowed
    return CGSize(width: (points.width * used).rounded(), height: (points.height * used).rounded())
}

/// How far a loop may be enlarged to fit its space: a tenth, far less than a moving picture shows,
/// and it saves decoding the next version up, often twice the pixels or more.
let loopEnlargeAllowed: CGFloat = 1.1

/// Downloaded albums keep their animated art on the phone: its answer, and both loops and their
/// stills beside the songs, so the album shows it with no connection. They go when the album's
/// last downloaded song goes.
@MainActor
final class OfflineLoops {
    static let shared = OfflineLoops()

    /// Where the loops are kept: in the downloads' own folder, not backed up.
    nonisolated static var dir: URL {
        let dir = OfflineDownloads.folder.appendingPathComponent("loops")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var kept: [String: AnimatedArt] = [:]
    private var settle: Task<Void, Never>?
    /// Albums asked about this run that had nothing to keep.
    private var askedNothing = Set<String>()

    private init() {
        if let data = try? Data(contentsOf: Self.index), let read = try? JSONDecoder().decode([String: AnimatedArt].self, from: data) {
            kept = read
        }
    }

    private static var index: URL { dir.appendingPathComponent("kept.json") }

    /// The answer kept with a downloaded album.
    func art(_ albumId: String) -> AnimatedArt? { kept[albumId] }

    /// The downloads changed: once they settle, albums with a downloaded song get their loops,
    /// and albums with none left lose theirs.
    func follow(library: Library, session: Session) {
        settle?.cancel()
        settle = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.sync(library: library, session: session)
        }
    }

    private func sync(library: Library, session: Session) async {
        let store = library.store
        let rows = ((try? await store.allDownloads()) ?? []).filter { $0.state == .done }
        var wanted = Set<String>()
        var here = Set<String>()
        for row in rows {
            guard let copy = try? await store.serverCopy(row.sourceId, row.serverId),
                  let albumId = serverId(of: copy.albumId, sourceId: copy.sourceId)
            else { continue }
            wanted.insert(albumId)
            if row.sourceId == session.inUse?.sourceId { here.insert(albumId) }
        }
        for albumId in kept.keys where !wanted.contains(albumId) { forget(albumId) }
        save()
        sweep(keeping: wanted)
        // Nothing fetched on mobile data while downloads wait for Wi-Fi.
        let settings = AppSettings.shared
        guard !(settings.offline.wifiOnly && settings.onMobileData) else { return }
        let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen
        let points = screen?.bounds.size ?? CGSize(width: 430, height: 932)
        let scale = screen?.scale ?? 3
        for albumId in here.sorted() where kept[albumId] == nil && !askedNothing.contains(albumId) {
            guard !Task.isCancelled else { return }
            guard let art = await AnimatedArtStore.shared.want(albumId) else {
                askedNothing.insert(albumId)
                continue
            }
            let client = session.client
            var whole = true
            for (shape, clip) in [(LoopShape.square, art.square), (.tall, art.tall)] {
                guard let clip, clip.playable else { continue }
                let fetcher = loopFetcher(for: clip, client: client)
                let side = shape == .square ? CGSize(width: points.width, height: points.width) : points
                let pixels = loopPixels(shape, points: side, scale: scale)
                let target = offlineLoopFile(dir: Self.dir, albumId: albumId, shape: shape.rawValue)
                let fetched = await Task.detached {
                    guard let file = await fetcher.locate(clip, width: Int(pixels.width), height: Int(pixels.height), codecs: [.avc, .hevc])
                    else { return false }
                    _ = await fetcher.fetchPoster(clip, to: offlineLoopPoster(dir: OfflineLoops.dir, albumId: albumId, shape: shape.rawValue))
                    return await fetcher.fetch(file, to: target)
                }.value
                whole = whole && fetched
            }
            // Kept only once its loops are on the phone; a fetch cut short is tried again later.
            guard whole, wanted.contains(albumId) else { continue }
            kept[albumId] = art
            save()
        }
    }

    private func forget(_ albumId: String) {
        kept[albumId] = nil
        for shape in [LoopShape.square, .tall] {
            try? FileManager.default.removeItem(at: offlineLoopFile(dir: Self.dir, albumId: albumId, shape: shape.rawValue))
            try? FileManager.default.removeItem(at: offlineLoopPoster(dir: Self.dir, albumId: albumId, shape: shape.rawValue))
        }
    }

    /// Takes away every file that belongs to no album with a downloaded song, such as the loops
    /// of a fetch cut short for an album since let go.
    private func sweep(keeping albums: Set<String>) {
        var names = Set([Self.index.lastPathComponent])
        for albumId in albums {
            for shape in [LoopShape.square, .tall] {
                names.insert(offlineLoopFile(dir: Self.dir, albumId: albumId, shape: shape.rawValue).lastPathComponent)
                names.insert(offlineLoopPoster(dir: Self.dir, albumId: albumId, shape: shape.rawValue).lastPathComponent)
            }
        }
        for file in (try? FileManager.default.contentsOfDirectory(at: Self.dir, includingPropertiesForKeys: nil)) ?? []
        where !names.contains(file.lastPathComponent) && file.pathExtension != "part" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(kept) else { return }
        try? data.write(to: Self.index, options: .atomic)
    }
}
