import OctoKit
import SwiftUI
import Synchronization
import UIKit

/// Covers for the views that take a song's or an album's cover by its id on the server in use,
/// or by a stored artwork reference (a cover from the phone's own music). Everything is drawn
/// through `ArtworkCache`, so a server cover is asked for at 150, 300, 600 or 1 200 pixels, kept
/// under its server and id (Octo's painted covers by the day), and a server's stand-in picture is
/// never kept.
actor Covers {
    static let shared = Covers()

    /// The server in use, which a bare cover id belongs to. Kept up to date by the app.
    nonisolated static let signedInSource = Mutex<String?>(nil)

    /// The picture for `reference` at `size` pixels: a stored artwork reference as it is, or a
    /// bare cover id of the server in use (`online` for a song or album found online).
    func image(_ reference: String, size: Int, client: SubsonicClient?, online: Bool = false) async -> UIImage? {
        let source = Self.signedInSource.withLock { $0 }
        let artwork: String
        if ArtworkRef.decode(reference) != nil {
            artwork = reference
        } else {
            guard let source, !reference.isEmpty else { return nil }
            artwork = ArtworkRef.server(sourceId: source, coverId: reference, online: online).encode()
        }
        return await ArtworkCache.shared.image(artwork, px: size, client: client, signedInSource: source)
    }
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
            let loaded = await Covers.shared.image(id, size: Int(size * scale), client: session.client, online: online)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}
