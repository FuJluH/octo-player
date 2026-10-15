import OctoKit
import os
import SwiftUI
import Synchronization
import UIKit

/// Covers for the views that take a cover by its id on the server in use, or by a stored artwork
/// reference. A server cover is kept under what the picture is (its server and id; Octo's painted
/// covers by the day), never its signed address, and asked for at 150, 300, 600 or 1 200 pixels.
/// A server's stand-in picture is never kept: the cover's fallback is drawn instead, or none.
/// Covers inside the phone's own music come from `ArtworkCache`.
///
/// A request is answered by a larger copy of the same cover when one is at hand (in memory, on
/// its way, or on disk), so one song is not fetched again for each place it shows. The covers of
/// the playing song and the next ones (`coming`) are fetched ahead at the largest size and go
/// straight to the server; every other cover waits for one of a few lanes, newest request first,
/// so a screen full of covers never holds up the player's.
actor Covers {
    static let shared = Covers()

    /// The server in use, which a bare cover id belongs to. Kept up to date by the app.
    nonisolated static let signedInSource = Mutex<String?>(nil)

    /// The pixel sizes asked of the server.
    static let steps = serverCoverSizes
    /// How many covers other than the player's load at once.
    private static let lanes = 4

    private nonisolated(unsafe) let memory = NSCache<NSString, UIImage>()
    private let folder: URL
    private var loading: [String: Task<(UIImage?, Bool), Never>] = [:]
    private var ahead: Task<Void, Never>?
    /// The covers of the playing song and the next ones, by what they are kept under.
    private nonisolated let soon = Mutex<[String]>([])
    private var busyLanes = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    /// Downloads the server answered with its stand-in this run, by their key.
    private var standIns = Set<String>()

    init() {
        folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("covers")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        memory.countLimit = 300
        memory.totalCostLimit = 120 << 20
    }

    /// The size a request of `size` pixels is fetched at.
    static func step(for size: Int) -> Int { serverCoverSize(wanted: size) }

    /// A server cover as a reference names it: its server, its id, whether it was found online,
    /// and its fallback.
    fileprivate struct ServerCover: Sendable {
        var source: String
        var coverId: String
        var online: Bool
        var fallback: String?

        /// What the cover is kept under, without its size.
        var base: String { serverCoverKey(sourceId: source, coverId: coverId, online: online) }

        func key(_ step: Int) -> String { "\(base)|\(step)" }

        func fallingBack() -> ServerCover? {
            fallback.map { ServerCover(source: source, coverId: $0, online: online) }
        }
    }

    /// The server cover a reference names; nil for a picture from the phone, or a bare id with no
    /// server in use.
    private nonisolated static func serverCover(_ reference: String, online: Bool) -> ServerCover? {
        if let ref = ArtworkRef.decode(reference) {
            guard case .server(let source, let coverId, let isOnline, let fallback) = ref else { return nil }
            return ServerCover(source: source, coverId: coverId, online: isOnline, fallback: fallback)
        }
        guard let source = signedInSource.withLock({ $0 }), !reference.isEmpty else { return nil }
        return ServerCover(source: source, coverId: reference, online: online)
    }

    /// The covers of the playing song and the next ones, in play order, each with whether it was
    /// found online. They are fetched ahead at once, and from now on any request for them skips
    /// the lanes.
    nonisolated func coming(_ covers: [(reference: String, online: Bool)], client: SubsonicClient?) {
        let picked = covers.compactMap { Covers.serverCover($0.reference, online: $0.online) }
        let bases = picked.map(\.base)
        let changed = soon.withLock { held in
            guard held != bases else { return false }
            held = bases
            return true
        }
        if changed { Task { await warm(picked, client: client) } }
    }

    /// A copy already in memory, without waiting: the one for `size` or a larger one, else the
    /// largest smaller one, so a view can show something at once while the sharp one loads.
    nonisolated func cached(_ reference: String, size: Int, online: Bool = false) -> (image: UIImage, sharp: Bool)? {
        guard let cover = Covers.serverCover(reference, online: online) else { return nil }
        let wanted = Covers.step(for: size)
        for step in Covers.steps where step >= wanted {
            if let hit = memory.object(forKey: cover.key(step) as NSString) { return (hit, true) }
        }
        for step in Covers.steps.reversed() where step < wanted {
            if let hit = memory.object(forKey: cover.key(step) as NSString) { return (hit, false) }
        }
        return nil
    }

    /// The picture for `reference` at `size` pixels: a stored artwork reference as it is, or a
    /// bare cover id of the server in use (`online` for a song or album found online). A cover
    /// from a server other than the one in use is not drawn.
    func image(_ reference: String, size: Int, client: SubsonicClient?, online: Bool = false) async -> UIImage? {
        if case .device = ArtworkRef.decode(reference) {
            return await ArtworkCache.shared.image(reference, px: size, client: client, signedInSource: nil)
        }
        guard let client, var cover = Covers.serverCover(reference, online: online),
              cover.source == Covers.signedInSource.withLock({ $0 }) else { return nil }
        let urgent = soon.withLock { $0.contains(cover.base) }
        let wanted = urgent ? Covers.steps[Covers.steps.count - 1] : Covers.step(for: size)
        while true {
            if let image = await load(cover, wanted, urgent: urgent, client: client) { return image }
            // The server had only its stand-in for this cover: its fallback, when it has one.
            guard standIns.contains(cover.key(wanted)), let next = cover.fallingBack() else { return nil }
            cover = next
        }
    }

    fileprivate func load(_ cover: ServerCover, _ wanted: Int, urgent: Bool, client: SubsonicClient) async -> UIImage? {
        let key = cover.key(wanted)
        if standIns.contains(key) { return nil }
        let larger = Covers.steps.filter { $0 >= wanted }
        if let hit = await atHand(cover, larger) { return hit }
        let files = larger.map { file(cover.key($0)) }
        let saved = await Task.detached(priority: .userInitiated, operation: { await Covers.read(files, step: wanted) }).value
        if let image = saved.image {
            memory.setObject(image, forKey: key as NSString, cost: Covers.cost(image))
            return image
        }
        if saved.standIn {
            standIns.insert(key)
            return nil
        }
        if !urgent {
            await enterLane()
            if Task.isCancelled {
                leaveLane()
                return nil
            }
        }
        defer { if !urgent { leaveLane() } }
        if let hit = await atHand(cover, larger) { return hit }
        let task = Task<(UIImage?, Bool), Never> { await Covers.fetch(cover.coverId, step: wanted, client: client, saveTo: files[0]) }
        loading[key] = task
        let (image, standIn) = await task.value
        loading[key] = nil
        if let image { memory.setObject(image, forKey: key as NSString, cost: Covers.cost(image)) }
        // The stand-in is not asked for again this run.
        if standIn { standIns.insert(key) }
        return image
    }

    /// The cover at one of these sizes already in memory, or on its way.
    private func atHand(_ cover: ServerCover, _ steps: [Int]) async -> UIImage? {
        for step in steps {
            if let hit = memory.object(forKey: cover.key(step) as NSString) { return hit }
        }
        for step in steps {
            if let running = loading[cover.key(step)], let image = await running.value.0 { return image }
        }
        return nil
    }

    private func enterLane() async {
        if busyLanes < Covers.lanes {
            busyLanes += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    /// Hands the lane to the newest waiting request, the one most likely still on screen.
    private func leaveLane() {
        if let next = waiting.popLast() { next.resume() } else { busyLanes -= 1 }
    }

    /// The first of these saved files that opens, cut down to `step` when it is much larger. A
    /// saved file that is the server's stand-in is let go, and said so.
    private static func read(_ files: [URL], step: Int) async -> (image: UIImage?, standIn: Bool) {
        for file in files {
            guard let data = try? Data(contentsOf: file) else { continue }
            if serverCoverMayBeStandIn(length: Int64(data.count)) && serverCoverIsStandIn([UInt8](data)) {
                try? FileManager.default.removeItem(at: file)
                return (nil, true)
            }
            guard let image = UIImage(data: data) else { continue }
            let side = CGFloat(step) / image.scale
            if image.size.width > side * 1.25, let smaller = await image.byPreparingThumbnail(
                ofSize: CGSize(width: side, height: side * image.size.height / image.size.width)) {
                return (smaller, false)
            }
            return (image.preparingForDisplay() ?? image, false)
        }
        return (nil, false)
    }

    /// One cover from the server at one size, saved on the phone; the server's stand-in is never
    /// saved, and said so.
    private static func fetch(_ coverId: String, step: Int, client: SubsonicClient, saveTo file: URL) async -> (UIImage?, Bool) {
        var request = URLRequest(url: client.coverURL(coverId, size: step))
        for (name, value) in client.headers { request.setValue(value, forHTTPHeaderField: name) }
        #if DEBUG
        let started = Date()
        defer { coverLog.notice("cover fetch \(coverId, privacy: .public) \(step) \(Int(Date().timeIntervalSince(started) * 1000)) ms") }
        #endif
        guard let (data, response) = try? await client.session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return (nil, false) }
        if serverCoverIsStandIn([UInt8](data)) { return (nil, true) }
        guard let image = UIImage(data: data) else { return (nil, false) }
        try? data.write(to: file, options: .atomic)
        return (image.preparingForDisplay() ?? image, false)
    }

    /// The bytes a decoded picture holds.
    private static func cost(_ image: UIImage) -> Int {
        Int(image.size.width * image.scale * image.size.height * image.scale * 4)
    }

    /// Fetches these covers together at the largest size, so the player has them the moment
    /// their songs play. A new call replaces the one before.
    private func warm(_ covers: [ServerCover], client: SubsonicClient?) {
        ahead?.cancel()
        guard let client else { return }
        let size = Covers.steps[Covers.steps.count - 1]
        ahead = Task {
            await withTaskGroup(of: Void.self) { group in
                for cover in covers {
                    group.addTask { _ = await self.load(cover, size, urgent: true, client: client) }
                }
            }
        }
    }

    private func file(_ key: String) -> URL { folder.appendingPathComponent(Hashes.sha1Hex(key)) }
}

/// A cover from the server, or from the phone's own music, in a rounded square, on the plain tile
/// while it loads or when there is none. Covers 96 points and larger carry a faint rim on the
/// picture.
struct Cover: View {
    let id: String?
    var size: CGFloat
    var radius: CGFloat = OctoRadius.artS
    /// A song or album found online keeps its covers apart.
    var online = false
    @Environment(Session.self) private var session
    @Environment(\.displayScale) private var scale
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(OctoColor.backgroundTertiary)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .overlay {
                        if size >= 96 {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .strokeBorder(Color(hex: 0xC8C8C8, opacity: 0.16), lineWidth: 1)
                        }
                    }
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .task(id: "\(id ?? "")|\(session.inUse?.sourceId ?? "")") {
            guard let id else { image = nil; return }
            let pixels = Int(size * scale)
            let quick = Covers.shared.cached(id, size: pixels, online: online)
            if let quick {
                image = quick.image
                if quick.sharp { return }
            }
            let loaded = await Covers.shared.image(id, size: pixels, client: session.client, online: online)
            if let loaded {
                if loaded !== image { withAnimation(.easeOut(duration: 0.2)) { image = loaded } }
            } else if quick == nil {
                withAnimation(.easeOut(duration: 0.2)) { image = nil }
            }
        }
    }
}

#if DEBUG
private let coverLog = Logger(subsystem: "app.winters.octo", category: "covers")
#endif

/// Whether a cover id is a cover inside the phone's own music rather than one on the server.
func isPhoneCover(_ id: String) -> Bool { id.hasPrefix("device:") }
