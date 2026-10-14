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
            let loaded = await StationLogos.shared.image(address, pixels: pixels)
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

/// A live station's cover: the song on air's artwork, else the station's logo, else its cover on
/// the server, else the tile Octo draws for it. Each picture is cut down to the size drawn, and
/// one that fails to load falls back to the next, so a station never shows an empty square.
struct LiveCover: View {
    /// The song's artwork address, empty when the station sends none.
    let artwork: String
    /// The station's logo address, empty when it has none.
    let logo: String
    /// The station's cover id on the server, for the server's own stations.
    let coverArt: String?
    let name: String
    var size: CGFloat
    var radius: CGFloat = OctoRadius.artS
    @Environment(Session.self) private var session
    @Environment(\.displayScale) private var scale
    @State private var picture: UIImage?
    @State private var serverCover: UIImage?

    var body: some View {
        ZStack {
            if let serverCover, logo.isEmpty {
                Image(uiImage: serverCover).resizable().scaledToFill()
            } else {
                StationLogo(address: logo, name: name, size: size, radius: radius)
            }
            if let picture, !artwork.isEmpty {
                Image(uiImage: picture)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .task(id: artwork) {
            guard !artwork.isEmpty else {
                picture = nil
                return
            }
            let pixels = Int(size * scale)
            if let quick = StationLogos.shared.cached(artwork, pixels: pixels) {
                picture = quick
                return
            }
            let loaded = await StationLogos.shared.image(artwork, pixels: pixels)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { picture = loaded }
        }
        .task(id: "\(coverArt ?? "")|\(logo.isEmpty)") {
            guard logo.isEmpty, let coverArt, !coverArt.isEmpty, let client = session.client else {
                serverCover = nil
                return
            }
            serverCover = await Covers.shared.image(coverArt, size: Int(size * scale), client: client)
        }
        .accessibilityHidden(true)
    }
}

extension LiveCover {
    /// The cover for what a station shows now.
    init(_ shown: LiveShown, coverArt: String?, size: CGFloat, radius: CGFloat = OctoRadius.artS) {
        self.init(artwork: shown.onAir.artwork, logo: shown.details.logo, coverArt: coverArt ?? (shown.details.coverArt.isEmpty ? nil : shown.details.coverArt),
                  name: shown.station, size: size, radius: radius)
    }
}
