import Observation
import OctoKit
import SwiftUI
import UIKit

/// The cover's flight between the bar's small player and the player's card. While the bar shows
/// the small player, its cover and the card each say where they are on screen; as the player
/// opens or closes, one copy of the cover flies from one to the other in a layer above
/// everything, its corners rounding from one shape to the other, while both real covers wait
/// hidden. Opened with no small player showing, there is nothing to fly from and the card simply
/// comes in with the player.
@MainActor
@Observable
final class CoverFlight {
    static let shared = CoverFlight()

    /// One flight: where it starts and ends on screen, and the corner at each end as a share of
    /// the cover's side.
    struct Trip: Equatable {
        let id = UUID()
        let coverId: String?
        let from: CGRect
        let to: CGRect
        let fromCorner: CGFloat
        let toCorner: CGFloat
        let opening: Bool
        let image: UIImage?

        static func == (a: Trip, b: Trip) -> Bool { a.id == b.id }
    }

    private(set) var trip: Trip?
    /// The player opened from the small player and its card has not been placed yet.
    private(set) var waitingForCard = false

    /// Where the bar's cover is, while the bar shows the small player.
    @ObservationIgnored var barFrame: CGRect?
    /// Where the player's card is, while the player shows.
    @ObservationIgnored private(set) var cardFrame: CGRect?
    /// Where the card was last laid out, kept across closing, since the card can be placed
    /// before the player says it is opening.
    @ObservationIgnored private var lastCard: CGRect?
    @ObservationIgnored private var image: (coverId: String, picture: UIImage)?
    @ObservationIgnored private var coverId: String?

    /// The card waits hidden for its cover while it flies in, or while it flies home.
    var hidesCard: Bool { waitingForCard || trip != nil }
    /// The bar's cover waits hidden while a cover is in the air.
    var hidesBar: Bool { trip != nil }

    /// The cover's picture at the card's size, made ready while the small player shows, so the
    /// flight never starts on an empty tile.
    func prepare(_ coverId: String?, size: Int, client: SubsonicClient?) async {
        guard let coverId else { return }
        if image?.coverId == coverId { return }
        guard let picture = await Covers.shared.image(coverId, size: size, client: client) else { return }
        image = (coverId, picture)
    }

    /// The player has appeared. With the small player showing, the card stays hidden until its
    /// place is known, then the cover flies there.
    func playerOpening(_ coverId: String?) {
        self.coverId = coverId
        cardFrame = nil
        waitingForCard = barFrame != nil
        // The card may already be laid out: then the cover flies at once.
        if waitingForCard, let lastCard { cardPlaced(lastCard) }
        // Never left hidden: whatever happens to the layout, the card shows a moment later.
        if waitingForCard {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                self?.waitingForCard = false
            }
        }
    }

    /// The player's card is laid out here.
    func cardPlaced(_ frame: CGRect) {
        guard frame.width > 1, frame.height > 1 else { return }
        cardFrame = frame
        lastCard = frame
        guard waitingForCard else { return }
        waitingForCard = false
        guard let barFrame else { return }
        trip = Trip(coverId: coverId, from: barFrame, to: frame, fromCorner: 0.5, toCorner: CGFloat(PlayerArtCorner),
                    opening: true, image: picture(coverId))
        endLater(trip)
    }

    /// The player is closing: with the small player showing, the cover flies home to it from
    /// wherever the card is now, pulled down or not.
    func playerClosing(_ coverId: String?) {
        waitingForCard = false
        guard let cardFrame, let barFrame else {
            trip = nil
            return
        }
        trip = Trip(coverId: coverId, from: cardFrame, to: barFrame, fromCorner: CGFloat(PlayerArtCorner), toCorner: 0.5,
                    opening: false, image: picture(coverId))
        endLater(trip)
        self.cardFrame = nil
    }

    func landed(_ id: UUID) {
        if trip?.id == id { trip = nil }
    }

    /// A flight always ends, even when its animation never says it landed.
    private func endLater(_ trip: Trip?) {
        guard let id = trip?.id else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1_200))
            self?.landed(id)
        }
    }

    private func picture(_ coverId: String?) -> UIImage? {
        guard let coverId, let image, image.coverId == coverId else { return nil }
        return image.picture
    }
}

/// The card's corners once the player is open, as a share of its side.
let PlayerArtCorner = 0.03

/// Draws the cover while it flies, above the bar and the player. It never takes a touch.
struct CoverFlightLayer: View {
    @State private var flight = CoverFlight.shared

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let trip = flight.trip {
                FlyingCover(trip: trip) { flight.landed(trip.id) }
                    .id(trip.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One flight: the frame moves on a spring with no bounce (stiffness 400) and the corners on a
/// quicker one (stiffness 1500).
private struct FlyingCover: View {
    let trip: CoverFlight.Trip
    let landed: () -> Void
    @State private var travel = 0.0
    @State private var round = 0.0

    var body: some View {
        FlightCard(trip: trip, travel: travel, round: round)
            .onAppear {
                withAnimation(.octoSpring(1, 400)) {
                    travel = 1
                } completion: {
                    landed()
                }
                withAnimation(.octoSpring(1, 1500)) { round = 1 }
            }
    }
}

private struct FlightCard: View, Animatable {
    let trip: CoverFlight.Trip
    var travel: Double
    var round: Double

    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(travel, round) }
        set {
            travel = newValue.first
            round = newValue.second
        }
    }

    var body: some View {
        let t = CGFloat(travel)
        let rect = CGRect(x: trip.from.minX + (trip.to.minX - trip.from.minX) * t,
                          y: trip.from.minY + (trip.to.minY - trip.from.minY) * t,
                          width: trip.from.width + (trip.to.width - trip.from.width) * t,
                          height: trip.from.height + (trip.to.height - trip.from.height) * t)
        let share = trip.fromCorner + (trip.toCorner - trip.fromCorner) * CGFloat(round)
        let shape = RoundedRectangle(cornerRadius: rect.width * share, style: .continuous)
        // The card's shadow comes in with the card and goes as the cover lands in the bar.
        let lift = trip.opening ? travel : 1 - travel
        ZStack {
            OctoColor.backgroundTertiary
            if let image = trip.image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .frame(width: max(rect.width, 1), height: max(rect.height, 1))
        .clipShape(shape)
        .background {
            shape.fill(Color.black)
                .elevation3()
                .opacity(min(max(lift, 0), 1))
        }
        .offset(x: rect.minX, y: rect.minY)
    }
}
