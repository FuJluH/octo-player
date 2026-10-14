import ImageIO
import OctoKit
import SwiftUI
import UIKit

/// Station logos from the addresses the radio catalog gives: fetched once, at most 512 KB each,
/// cut down to the size drawn, and kept in memory while the app runs.
actor StationLogos {
    static let shared = StationLogos()

    nonisolated(unsafe) private let cache = NSCache<NSString, UIImage>()
    /// When each logo last failed; it is tried again once `retryAfter` has passed.
    private var failed: [String: Date] = [:]
    private static let retryAfter: TimeInterval = 10 * 60
    private var running: [String: Task<UIImage?, Never>] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.urlCache = URLCache(memoryCapacity: 0, diskCapacity: 32 << 20)
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    /// The largest logo file fetched.
    private static let maxBytes = 512 << 10

    nonisolated func cached(_ address: String, pixels: Int) -> UIImage? {
        cache.object(forKey: "\(pixels)|\(address)" as NSString)
    }

    func image(_ address: String, pixels: Int) async -> UIImage? {
        let key = "\(pixels)|\(address)"
        if let kept = cache.object(forKey: key as NSString) { return kept }
        if let at = failed[key], Date().timeIntervalSince(at) < Self.retryAfter { return nil }
        if let running = running[key] { return await running.value }
        let session = session
        let task = Task<UIImage?, Never> { await Self.fetch(address, pixels: pixels, session: session) }
        running[key] = task
        let image = await task.value
        running[key] = nil
        if let image {
            cache.setObject(image, forKey: key as NSString)
            failed[key] = nil
        } else {
            failed[key] = Date()
        }
        return image
    }

    private static func fetch(_ address: String, pixels: Int, session: URLSession) async -> UIImage? {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https" || url.scheme == "http" else { return nil }
        guard let (bytes, response) = try? await session.bytes(for: URLRequest(url: url)),
              ((response as? HTTPURLResponse)?.statusCode ?? 0) == 200,
              response.expectedContentLength <= Int64(maxBytes) else { return nil }
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count > maxBytes { return nil }
            }
        } catch {
            return nil
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
        ]
        guard let cut = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cut)
    }
}

/// A station's logo, or, without one, a tile Octo draws: the station's initials over a color
/// picked from its name, with the live radio symbol.
struct StationLogo: View {
    let address: String
    let name: String
    var size: CGFloat
    var radius: CGFloat = OctoRadius.artS
    @Environment(\.displayScale) private var scale
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(drawnColor.gradient)
            if let image {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.white)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.06)
                    .transition(.opacity)
            } else {
                VStack(spacing: size * 0.04) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: size * 0.22, weight: .semibold))
                    if size >= 64 {
                        Text(initials).font(.system(size: size * 0.2, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.5)
                    }
                }
                .foregroundStyle(.white.opacity(0.92))
                .accessibilityHidden(true)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .task(id: address) {
            let pixels = Int(size * scale)
            guard !address.isEmpty else {
                image = nil
                return
            }
            if let quick = StationLogos.shared.cached(address, pixels: pixels) {
                image = quick
                return
            }
            // Another station's logo never stays while this one loads: the drawn tile shows.
            image = nil
            let loaded = await StationLogos.shared.image(address, pixels: pixels)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }

    private var initials: String {
        let words = name.split { !$0.isLetter && !$0.isNumber }.prefix(2)
        return words.compactMap { $0.first.map { String($0).uppercased() } }.joined()
    }

    private var drawnColor: Color { Color(hue: stationHue(name), saturation: 0.55, brightness: 0.55) }
}

/// A steady hue for a station's name, 0 to 1: the same station always gets the same one.
func stationHue(_ name: String) -> Double {
    var hash: UInt32 = 2_166_136_261
    for byte in name.lowercased().utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
    return Double(hash % 360) / 360
}

/// The tile Octo draws for a station with no picture, as an image for the lock screen: the
/// station's color, lighter at the top, with the live radio symbol.
func drawnStationTile(_ name: String, pixels: Int) -> UIImage {
    let side = CGFloat(max(pixels, 1))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
        let hue = stationHue(name)
        let top = UIColor(hue: hue, saturation: 0.5, brightness: 0.65, alpha: 1)
        let bottom = UIColor(hue: hue, saturation: 0.55, brightness: 0.5, alpha: 1)
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1]) {
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: side), options: [])
        }
        let config = UIImage.SymbolConfiguration(pointSize: side * 0.22, weight: .semibold)
        if let symbol = UIImage(systemName: "dot.radiowaves.left.and.right", withConfiguration: config)?
            .withTintColor(UIColor.white.withAlphaComponent(0.92), renderingMode: .alwaysOriginal) {
            symbol.draw(at: CGPoint(x: (side - symbol.size.width) / 2, y: (side - symbol.size.height) / 2))
        }
    }
}

/// A live station's picture from one place it can come from, at `pixels`: at once when it is
/// kept in memory, nil otherwise.
func cachedLiveCover(_ source: LiveCoverSource, pixels: Int) -> UIImage? {
    switch source {
    case .octo(let coverArt, let online): Covers.shared.cached(coverArt, size: pixels, online: online)?.image
    case .artwork(let address), .logo(let address): StationLogos.shared.cached(address, pixels: pixels)
    case .server(let coverArt): Covers.shared.cached(coverArt, size: pixels, online: false)?.image
    }
}

/// A live station's picture from one place it can come from, at `pixels`, or nil when it does
/// not load.
func loadLiveCover(_ source: LiveCoverSource, pixels: Int, client: SubsonicClient?) async -> UIImage? {
    switch source {
    case .octo(let coverArt, let online): await Covers.shared.image(coverArt, size: pixels, client: client, online: online)
    case .artwork(let address), .logo(let address): await StationLogos.shared.image(address, pixels: pixels)
    case .server(let coverArt): await Covers.shared.image(coverArt, size: pixels, client: client)
    }
}

/// The first of `sources` that loads, best first, with where it came from; nil when none does.
func loadFirstLiveCover(_ sources: [LiveCoverSource], pixels: Int, client: SubsonicClient?) async -> (LiveCoverSource, UIImage)? {
    for source in sources {
        if Task.isCancelled { return nil }
        if let image = await loadLiveCover(source, pixels: pixels, client: client) { return (source, image) }
    }
    return nil
}

/// A live station's cover: the song on air's cover in Octo, else the artwork the station sent,
/// else its logo, else its cover on the server. The tile Octo draws for the station shows at
/// once, drawn on the phone, and stays until one of those loads; a picture that stops being one
/// of them (another station, another song) gives way to the tile, never to an empty square.
struct LiveCover: View {
    let sources: [LiveCoverSource]
    let name: String
    var size: CGFloat
    var radius: CGFloat = OctoRadius.artS
    @Environment(Session.self) private var session
    @Environment(\.displayScale) private var scale
    @State private var picture: (source: LiveCoverSource, image: UIImage)?

    var body: some View {
        ZStack {
            StationLogo(address: "", name: name, size: size, radius: radius)
            if let picture, sources.contains(picture.source) {
                Group {
                    if case .logo = picture.source {
                        ZStack {
                            Color.white
                            Image(uiImage: picture.image).resizable().scaledToFit().padding(size * 0.06)
                        }
                    } else {
                        Image(uiImage: picture.image).resizable().scaledToFill()
                    }
                }
                .frame(width: size, height: size)
                .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .task(id: sources) {
            let pixels = Int(size * scale)
            // The best picture kept in memory shows at once.
            if let best = sources.first(where: { cachedLiveCover($0, pixels: pixels) != nil }),
               let image = cachedLiveCover(best, pixels: pixels) {
                picture = (best, image)
                if best == sources.first { return }
            }
            let shown = picture.flatMap { current in sources.firstIndex(of: current.source) } ?? sources.count
            guard shown > 0 else { return }
            // Only pictures better than the one showing are worth the wait.
            guard let found = await loadFirstLiveCover(Array(sources.prefix(shown)), pixels: pixels, client: session.client),
                  !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { picture = found }
        }
        .accessibilityHidden(true)
    }
}

extension LiveCover {
    /// The cover for what a station shows now, with the song on air's cover in Octo once it is
    /// known.
    @MainActor
    init(_ shown: LiveShown, coverArt: String?, size: CGFloat, radius: CGFloat = OctoRadius.artS) {
        self.init(sources: liveCoverSources(octo: LiveLookup.shared.cover(shown.onAir), shown: shown, serverCover: coverArt),
                  name: shown.station, size: size, radius: radius)
    }

    /// A station's own cover, with no song: its logo, else its server cover.
    init(logo: String, coverArt: String?, name: String, size: CGFloat, radius: CGFloat = OctoRadius.artS) {
        var sources: [LiveCoverSource] = []
        if !logo.isEmpty { sources.append(.logo(logo)) }
        if let coverArt, !coverArt.isEmpty { sources.append(.server(coverArt)) }
        self.init(sources: sources, name: name, size: size, radius: radius)
    }
}
