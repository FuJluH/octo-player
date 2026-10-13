import ImageIO
import OctoKit
import SwiftUI
import UIKit

/// Station logos from the addresses the radio catalog gives: fetched once, at most 512 KB each,
/// cut down to the size drawn, and kept in memory while the app runs.
actor StationLogos {
    static let shared = StationLogos()

    nonisolated(unsafe) private let cache = NSCache<NSString, UIImage>()
    private var failed = Set<String>()
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
        if failed.contains(key) { return nil }
        if let running = running[key] { return await running.value }
        let session = session
        let task = Task<UIImage?, Never> { await Self.fetch(address, pixels: pixels, session: session) }
        running[key] = task
        let image = await task.value
        running[key] = nil
        if let image { cache.setObject(image, forKey: key as NSString) } else { failed.insert(key) }
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

    /// A steady color for the name: the same station always gets the same one.
    private var drawnColor: Color {
        var hash: UInt32 = 2_166_136_261
        for byte in name.lowercased().utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.55, brightness: 0.55)
    }
}
