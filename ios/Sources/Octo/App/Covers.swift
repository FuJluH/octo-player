import OctoKit
import os
import SwiftUI
import Synchronization
import UIKit

/// Covers, kept by cover id and size rather than by address: every signed address carries a
/// fresh salt, so the address never repeats. Memory first, then a folder in Caches.
///
/// Sizes snap to a few steps, and a request is answered by a larger copy of the same cover when
/// one is at hand (in memory, on its way, or on disk), so one song is not fetched again for each
/// place it shows. The covers of the playing song and the next ones (`coming`) are fetched ahead
/// at the largest step and go straight to the server; every other cover waits for one of a few
/// lanes, newest request first, so a screen full of covers never holds up the player's.
actor Covers {
    static let shared = Covers()

    /// The pixel sizes asked of the server. The largest fits the player's card at 3x.
    static let steps = [160, 320, 640, 960]
    /// How many covers other than the player's load at once.
    private static let lanes = 4

    private nonisolated(unsafe) let memory = NSCache<NSString, UIImage>()
    private let folder: URL
    private var loading: [String: Task<UIImage?, Never>] = [:]
    private var ahead: Task<Void, Never>?
    /// The covers of the playing song and the next ones.
    private nonisolated let soon = Mutex<[String]>([])
    private var busyLanes = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init() {
        folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("covers")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        memory.countLimit = 300
        memory.totalCostLimit = 120 << 20
    }

    /// The step a request of `size` pixels is fetched at.
    static func step(for size: Int) -> Int { steps.first { $0 >= size } ?? steps[steps.count - 1] }

    private static func key(_ coverId: String, _ step: Int) -> String { "\(coverId)_\(step)" }

    /// The covers of the playing song and the next ones, in play order. They are fetched ahead
    /// at once, and from now on any request for them skips the lanes.
    nonisolated func coming(_ coverIds: [String], client: SubsonicClient?) {
        let ids = coverIds.filter { !isPhoneCover($0) }
        let changed = soon.withLock { held in
            guard held != ids else { return false }
            held = ids
            return true
        }
        if changed { Task { await warm(ids, client: client) } }
    }

    /// A copy already in memory, without waiting: the one for `size` or a larger one, else the
    /// largest smaller one, so a view can show something at once while the sharp one loads.
    nonisolated func cached(_ coverId: String, size: Int) -> (image: UIImage, sharp: Bool)? {
        let wanted = Covers.step(for: size)
        for step in Covers.steps where step >= wanted {
            if let hit = memory.object(forKey: Covers.key(coverId, step) as NSString) { return (hit, true) }
        }
        for step in Covers.steps.reversed() where step < wanted {
            if let hit = memory.object(forKey: Covers.key(coverId, step) as NSString) { return (hit, false) }
        }
        return nil
    }

    func image(_ coverId: String, size: Int, client: SubsonicClient?) async -> UIImage? {
        if isPhoneCover(coverId) {
            return await ArtworkCache.shared.image(coverId, px: size, client: client, signedInSource: nil)
        }
        guard let client else { return nil }
        let urgent = soon.withLock { $0.contains(coverId) }
        let wanted = urgent ? Covers.steps[Covers.steps.count - 1] : Covers.step(for: size)
        let larger = Covers.steps.filter { $0 >= wanted }
        if let hit = await atHand(coverId, larger) { return hit }
        let key = Covers.key(coverId, wanted)
        let files = larger.map { file(Covers.key(coverId, $0)) }
        if let saved = await Task.detached(priority: .userInitiated, operation: { await Covers.read(files, step: wanted) }).value {
            memory.setObject(saved, forKey: key as NSString, cost: Covers.cost(saved))
            return saved
        }
        if !urgent {
            await enterLane()
            if Task.isCancelled {
                leaveLane()
                return nil
            }
        }
        defer { if !urgent { leaveLane() } }
        if let hit = await atHand(coverId, larger) { return hit }
        let task = Task<UIImage?, Never> { await Covers.fetch(coverId, step: wanted, client: client, saveTo: files[0]) }
        loading[key] = task
        let image = await task.value
        loading[key] = nil
        if let image { memory.setObject(image, forKey: key as NSString, cost: Covers.cost(image)) }
        return image
    }

    /// The cover at one of these steps already in memory, or on its way.
    private func atHand(_ coverId: String, _ steps: [Int]) async -> UIImage? {
        for step in steps {
            if let hit = memory.object(forKey: Covers.key(coverId, step) as NSString) { return hit }
        }
        for step in steps {
            if let running = loading[Covers.key(coverId, step)], let image = await running.value { return image }
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

    /// The first of these saved files that opens, cut down to `step` when it is much larger.
    private static func read(_ files: [URL], step: Int) async -> UIImage? {
        for file in files {
            guard let data = try? Data(contentsOf: file), let image = UIImage(data: data) else { continue }
            let side = CGFloat(step) / image.scale
            if image.size.width > side * 1.25, let smaller = await image.byPreparingThumbnail(
                ofSize: CGSize(width: side, height: side * image.size.height / image.size.width)) {
                return smaller
            }
            return image.preparingForDisplay() ?? image
        }
        return nil
    }

    private static func fetch(_ coverId: String, step: Int, client: SubsonicClient, saveTo file: URL) async -> UIImage? {
        var request = URLRequest(url: client.coverURL(coverId, size: step))
        for (name, value) in client.headers { request.setValue(value, forHTTPHeaderField: name) }
        #if DEBUG
        let started = Date()
        defer { coverLog.notice("cover fetch \(coverId, privacy: .public) \(step) \(Int(Date().timeIntervalSince(started) * 1000)) ms") }
        #endif
        guard let (data, response) = try? await client.session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data)
        else { return nil }
        try? data.write(to: file, options: .atomic)
        return image.preparingForDisplay() ?? image
    }

    /// The bytes a decoded picture holds.
    private static func cost(_ image: UIImage) -> Int {
        Int(image.size.width * image.scale * image.size.height * image.scale * 4)
    }

    /// Fetches these covers together at the largest step, so the player has them the moment
    /// their songs play. A new call replaces the one before.
    private func warm(_ coverIds: [String], client: SubsonicClient?) {
        ahead?.cancel()
        let size = Covers.steps[Covers.steps.count - 1]
        ahead = Task {
            await withTaskGroup(of: Void.self) { group in
                for coverId in coverIds {
                    group.addTask { _ = await self.image(coverId, size: size, client: client) }
                }
            }
        }
    }

    private func file(_ key: String) -> URL {
        folder.appendingPathComponent(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key)
    }
}

/// A cover from the server, in a rounded square, on the plain tile while it loads or when there
/// is none. Covers 96 points and larger carry a faint rim on the picture.
struct Cover: View {
    let id: String?
    var size: CGFloat
    var radius: CGFloat = OctoRadius.artS
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
        .task(id: id) {
            guard let id, session.client != nil || isPhoneCover(id) else { image = nil; return }
            let client = session.client
            let pixels = Int(size * scale)
            let quick = Covers.shared.cached(id, size: pixels)
            if let quick {
                image = quick.image
                if quick.sharp { return }
            }
            let loaded = await Covers.shared.image(id, size: pixels, client: client)
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
