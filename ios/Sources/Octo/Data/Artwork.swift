import AVFoundation
import MediaPlayer
import OctoKit
import SwiftUI
import UIKit

/// The pictures library rows carry (`LibraryTrack.artwork` and the like): covers from the server
/// in use, found online or painted by Octo, and covers inside the phone's own music. Server covers
/// are kept on disk under what the picture is, never its signed address; a server's stand-in
/// picture is let go and the cover's fallback drawn instead.
actor ArtworkCache {
    static let shared = ArtworkCache()

    private let memory = NSCache<NSString, UIImage>()
    private let folder: URL
    /// Downloads the server answered with its stand-in this run, by their disk key.
    private var standIns = Set<String>()
    private var loading: [String: Task<(UIImage?, Bool), Never>] = [:]

    /// The disk cache is trimmed back to this when it grows past it.
    private let diskLimit: Int64 = 400 * 1024 * 1024

    init() {
        folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("artwork")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        memory.countLimit = 400
        Task { await self.trim() }
    }

    /// The picture for a stored artwork reference at `px` pixels, or nil when there is none.
    func image(_ artwork: String?, px: Int, client: SubsonicClient?, signedInSource: String?) async -> UIImage? {
        guard let ref = ArtworkRef.decode(artwork) else { return nil }
        switch ref {
        case .server:
            guard let tries = serverCoverTries(ref, signedInSource: signedInSource, wantedPx: px, standIns: standIns),
                  let client
            else { return nil }
            for attempt in tries {
                if let image = await load(attempt, client: client) { return image }
            }
            return nil
        case .device(let key, let uri):
            let size = min(max(px > 0 ? px : 512, 96), 1024)
            let memoryKey = "device-art:\(key)|\(size)" as NSString
            if let hit = memory.object(forKey: memoryKey) { return hit }
            guard let image = await Self.devicePicture(uri: uri, size: size) else { return nil }
            memory.setObject(image, forKey: memoryKey)
            return image
        }
    }

    private func load(_ attempt: ServerCoverTry, client: SubsonicClient) async -> UIImage? {
        if let hit = memory.object(forKey: attempt.diskKey as NSString) { return hit }
        if let running = loading[attempt.diskKey] { return await running.value.0 }
        let file = folder.appendingPathComponent(Hashes.sha1Hex(attempt.diskKey))
        let task = Task<(UIImage?, Bool), Never> {
            if let data = try? Data(contentsOf: file) {
                if serverCoverMayBeStandIn(length: Int64(data.count)) && serverCoverIsStandIn([UInt8](data)) {
                    try? FileManager.default.removeItem(at: file)
                    return (nil, true)
                }
                if let image = UIImage(data: data) { return (image.preparingForDisplay() ?? image, false) }
            }
            var request = URLRequest(url: client.coverURL(attempt.coverId, size: attempt.px))
            for (name, value) in client.headers { request.setValue(value, forHTTPHeaderField: name) }
            guard let (data, response) = try? await client.session.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200
            else { return (nil, false) }
            if serverCoverIsStandIn([UInt8](data)) { return (nil, true) }
            guard let image = UIImage(data: data) else { return (nil, false) }
            try? data.write(to: file, options: .atomic)
            return (image.preparingForDisplay() ?? image, false)
        }
        loading[attempt.diskKey] = task
        let (image, standIn) = await task.value
        loading[attempt.diskKey] = nil
        if let image { memory.setObject(image, forKey: attempt.diskKey as NSString) }
        // The stand-in is not asked for again this run.
        if standIn { standIns.insert(attempt.diskKey) }
        return image
    }

    /// The cover inside a song on the phone: the media library's, or a file's own.
    private static func devicePicture(uri: String, size: Int) async -> UIImage? {
        guard let url = URL(string: uri) else { return nil }
        if url.scheme == "ipod-library" {
            guard let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value,
                  let persistent = UInt64(id)
            else { return nil }
            return await MainActor.run {
                let query = MPMediaQuery.songs()
                query.addFilterPredicate(MPMediaPropertyPredicate(value: NSNumber(value: persistent),
                                                                  forProperty: MPMediaItemPropertyPersistentID))
                return query.items?.first?.artwork?.image(at: CGSize(width: size, height: size))
            }
        }
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata) else { return nil }
        for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .commonIdentifierArtwork) {
            if let data = try? await item.load(.dataValue), let image = UIImage(data: data) {
                return await image.byPreparingThumbnail(ofSize: CGSize(width: size, height: size)) ?? image
            }
        }
        return nil
    }

    /// Lets go of the oldest pictures once the folder grows past its limit.
    private func trim() {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentAccessDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys)) else { return }
        let entries = files.compactMap { url -> (URL, Int64, Date)? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return (url, Int64(values.fileSize ?? 0), values.contentAccessDate ?? .distantPast)
        }
        var total = entries.reduce(Int64(0)) { $0 + $1.1 }
        guard total > diskLimit else { return }
        for (url, size, _) in entries.sorted(by: { $0.2 < $1.2 }) {
            try? FileManager.default.removeItem(at: url)
            total -= size
            if total <= diskLimit * 3 / 4 { break }
        }
    }
}

/// A library row's picture in a rounded square, with a quiet stand-in while it loads or when
/// there is none.
struct ArtworkView: View {
    let artwork: String?
    var size: CGFloat
    var radius: CGFloat = OctoRadius.artM
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
                    .transition(.opacity)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.3, weight: .semibold))
                    .foregroundStyle(OctoColor.textMuted)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .task(id: "\(artwork ?? "")|\(session.inUse?.sourceId ?? "")") {
            let loaded = await ArtworkCache.shared.image(artwork, px: Int(size * scale), client: session.client,
                                                         signedInSource: session.inUse?.sourceId)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}
