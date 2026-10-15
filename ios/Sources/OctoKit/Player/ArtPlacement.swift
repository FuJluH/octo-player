import Foundation

/// Where the upright full player puts its artwork in the room left between the top line and the
/// controls: as wide as the room allows (the full width on tall phones), a calm margin under the
/// top line, and whatever height is left shared a third above the artwork and two thirds below
/// it, so the artwork never floats in the middle of a tall screen. On a small phone the artwork
/// shrinks to fit and nothing is cut. Songs and live stations use the same room, so changing
/// between them does not move the artwork.
public struct ArtPlacement: Sendable, Equatable {
    /// The artwork's side, in points.
    public let side: Double
    /// The room above the artwork, in points.
    public let top: Double

    /// The margin under the top line.
    public static let topMargin = 12.0
    /// The least room kept between the artwork and the title.
    public static let bottomMargin = 16.0

    public init(side: Double, top: Double) {
        self.side = side
        self.top = top
    }

    /// The placement in a room `width` by `height` points.
    public static func upright(width: Double, height: Double) -> ArtPlacement {
        let width = max(0, width)
        let height = max(0, height)
        let side = max(0, min(width, height - topMargin - bottomMargin))
        let spare = max(0, height - side - topMargin - bottomMargin)
        return ArtPlacement(side: side, top: min(height, topMargin + spare / 3))
    }
}
