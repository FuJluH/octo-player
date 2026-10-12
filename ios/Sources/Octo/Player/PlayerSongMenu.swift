import OctoKit
import SwiftUI

/// The rating under the song's title: one small star a point, nothing when unrated.
struct RatingStars: View {
    let rating: Int

    var body: some View {
        if rating > 0 {
            HStack(spacing: 2) {
                ForEach(0..<min(rating, 5), id: \.self) { _ in
                    IconView(.starFilled, size: 12, color: OctoColor.textMuted)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(rating == 1 ? "Rated 1 star" : "Rated \(rating) stars")
        }
    }
}
