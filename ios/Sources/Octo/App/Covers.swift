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

    func image(_ coverId: String, size: Int, client: SubsonicClient) async -> UIImage? {
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

/// A cover from the server, in a rounded square, with a quiet stand-in while it loads or when
/// there is none.
struct Cover: View {
    let id: String?
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
        .task(id: id) {
            guard let id, let client = session.client else { image = nil; return }
            let loaded = await Covers.shared.image(id, size: Int(size * scale), client: client)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}
