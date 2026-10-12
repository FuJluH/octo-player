import OctoKit
import SwiftUI
import UIKit

/// Covers, kept by cover id and size rather than by address: every signed address carries a
/// fresh salt, so the address never repeats. Memory first, then a folder in Caches.
actor Covers {
    static let shared = Covers()

    private let memory = NSCache<NSString, UIImage>()
    private let folder: URL
    private var loading: [String: Task<UIImage?, Never>] = [:]

    init() {
        folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("covers")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        memory.countLimit = 300
    }

    func image(_ coverId: String, size: Int, client: SubsonicClient?) async -> UIImage? {
        if isPhoneCover(coverId) {
            return await ArtworkCache.shared.image(coverId, px: size, client: client, signedInSource: nil)
        }
        guard let client else { return nil }
        let key = "\(coverId)_\(size)"
        if let hit = memory.object(forKey: key as NSString) { return hit }
        if let running = loading[key] { return await running.value }
        let file = folder.appendingPathComponent(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key)
        let task = Task<UIImage?, Never> {
            if let data = try? Data(contentsOf: file), let image = UIImage(data: data) { return image }
            var request = URLRequest(url: client.coverURL(coverId, size: size))
            for (name, value) in client.headers { request.setValue(value, forHTTPHeaderField: name) }
            guard let (data, response) = try? await client.session.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = UIImage(data: data)
            else { return nil }
            try? data.write(to: file, options: .atomic)
            return image.preparingForDisplay() ?? image
        }
        loading[key] = task
        let image = await task.value
        loading[key] = nil
        if let image { memory.setObject(image, forKey: key as NSString) }
        return image
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
            let loaded = await Covers.shared.image(id, size: Int(size * scale), client: client)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}

/// Whether a cover id is a cover inside the phone's own music rather than one on the server.
func isPhoneCover(_ id: String) -> Bool { id.hasPrefix("device:") }
