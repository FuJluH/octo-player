import Observation
import OctoKit
import QuartzCore
import SwiftUI
import UIKit

/// The cover's flight between the bar's small player and the player's card. While the bar shows
/// the small player, its cover and the card each say where they are on screen; as the player
/// opens or closes, one copy of the cover flies from one to the other in a layer above
/// everything, its corners rounding from one shape to the other, while both real covers wait
/// hidden. The flight is Core Animation's, so it keeps moving while the main thread is busy
/// building or taking down the player. Opening from the small player with the card's place known
/// from before, the cover takes off before the player is built (`launch`). Opened with no small
/// player showing, there is nothing to fly from and the card simply comes in with the player.
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
    /// Where the flight under way is headed now.
    @ObservationIgnored private var headed: CGRect?
    @ObservationIgnored private var image: (coverId: String, picture: UIImage)?
    @ObservationIgnored private var coverId: String?
    /// The layer the cover flies in.
    @ObservationIgnored weak var view: FlightView?

    /// The card waits hidden for its cover while it flies in, or while it flies home.
    var hidesCard: Bool { waitingForCard || trip != nil }
    /// The bar's cover waits hidden while a cover is in the air.
    var hidesBar: Bool { trip != nil }

    /// The cover's picture at the card's size, made ready while the small player shows and
    /// decoded off the main thread, so the flight never starts on an empty tile or stops to
    /// decode it.
    func prepare(_ coverId: String?, size: Int, client: SubsonicClient?) async {
        guard let coverId else { return }
        if image?.coverId == coverId { return }
        guard let picture = await Covers.shared.image(coverId, size: size, client: client) else { return }
        let ready = await picture.byPreparingForDisplay() ?? picture
        image = (coverId, ready)
    }

    /// The same for a live station, in the order its cover takes them, kept under `flightKey`:
    /// the tile Octo draws for it at once, then the best picture that loads.
    func prepare(live shown: LiveShown, coverArt: String?, size: Int, client: SubsonicClient?) async {
        let key = liveFlightKey(shown)
        if image?.coverId == key { return }
        image = (key, drawnStationTile(shown.station, pixels: size))
        let sources = liveCoverSources(octo: LiveLookup.shared.cover(shown.onAir), shown: shown, serverCover: coverArt)
        guard let found = await loadFirstLiveCover(sources, pixels: size, client: client), image?.coverId == key else { return }
        let ready = await found.1.byPreparingForDisplay() ?? found.1
        guard image?.coverId == key else { return }
        image = (key, ready)
    }

    /// The player is about to open from the small player. When the card's place is known from
    /// before, the cover takes off now and true is answered: the player is then built a frame
    /// later, under the flight.
    func launch(_ coverId: String?) -> Bool {
        guard trip == nil, view?.window != nil,
              case .now(let to) = coverFlightStart(bar: barFrame, lastCard: lastCard), let barFrame else { return false }
        self.coverId = coverId
        waitingForCard = false
        cardFrame = nil
        fly(Trip(coverId: coverId, from: barFrame, to: to, fromCorner: 0.5, toCorner: CGFloat(PlayerArtCorner),
                 opening: true, image: picture(coverId)))
        return true
    }

    /// The player has appeared. A cover already on its way in carries on. Otherwise, with the
    /// small player showing, the card stays hidden until its place is known, then the cover
    /// flies there.
    func playerOpening(_ coverId: String?) {
        #if DEBUG
        FlightProbe.note("opening bar=\(String(describing: barFrame)) last=\(String(describing: lastCard)) flying=\(trip?.opening == true)")
        #endif
        self.coverId = coverId
        cardFrame = nil
        if trip?.opening == true {
            waitingForCard = false
            return
        }
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

    /// The player's card is laid out here. A cover flying in turns toward a place that moved.
    func cardPlaced(_ frame: CGRect) {
        guard frame.width > 1, frame.height > 1 else { return }
        #if DEBUG
        FlightProbe.note("card placed \(frame) waiting=\(waitingForCard) flying=\(trip != nil)")
        #endif
        cardFrame = frame
        lastCard = frame
        if let trip, trip.opening, let headed, flightNeedsRetarget(headed: headed, placed: frame) {
            self.headed = frame
            view?.retarget(to: frame)
            return
        }
        guard waitingForCard else { return }
        waitingForCard = false
        guard let barFrame else { return }
        fly(Trip(coverId: coverId, from: barFrame, to: frame, fromCorner: 0.5, toCorner: CGFloat(PlayerArtCorner),
                 opening: true, image: picture(coverId)))
    }

    /// The player is closing: with the small player showing, the cover flies home to it from
    /// wherever the card is now, pulled down or not.
    func playerClosing(_ coverId: String?) {
        waitingForCard = false
        guard let cardFrame, let barFrame else {
            land()
            return
        }
        fly(Trip(coverId: coverId, from: cardFrame, to: barFrame, fromCorner: CGFloat(PlayerArtCorner), toCorner: 0.5,
                 opening: false, image: picture(coverId)))
        self.cardFrame = nil
    }

    func landed(_ id: UUID) {
        guard trip?.id == id else { return }
        #if DEBUG
        FlightProbe.note("landed")
        #endif
        land()
    }

    private func land() {
        trip = nil
        headed = nil
        view?.clear()
    }

    private func fly(_ next: Trip) {
        trip = next
        headed = next.to
        #if DEBUG
        FlightProbe.note("trip \(next.opening ? "open" : "close") from \(next.from) to \(next.to) image=\(next.image != nil)")
        #endif
        let id = next.id
        view?.fly(next) { [weak self] in self?.landed(id) }
        // A flight always ends, even when its animation never says it landed.
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

/// What the flying cover of `song` is kept under: its cover id, or, for a live station, what its
/// cover shows now.
@MainActor
func flightKey(_ song: Song?) -> String? {
    guard let song else { return nil }
    if isRadio(song.id), let shown = LiveTitleBoard.shared.shown(song.id) { return liveFlightKey(shown) }
    return song.coverArt
}

@MainActor
private func liveFlightKey(_ shown: LiveShown) -> String {
    "live|\(LiveLookup.shared.cover(shown.onAir)?.coverArt ?? "")|\(shown.cover)|\(shown.station)"
}

/// The layer the cover flies in, above the bar and the player. It never takes a touch.
struct CoverFlightLayer: UIViewRepresentable {
    func makeUIView(context: Context) -> FlightView {
        let view = FlightView()
        CoverFlight.shared.view = view
        return view
    }

    func updateUIView(_ view: FlightView, context: Context) {}
}

/// The flying cover drawn by Core Animation: the picture with its rounding corners, and under
/// it the card's three shadows, which come in with the card and go as it lands in the bar. The
/// frame moves on a spring with no bounce (stiffness 400) and the corners on a quicker one
/// (stiffness 1500).
final class FlightView: UIView {
    private let card = CALayer()
    /// The card's shadows as `elevation3` draws them: opacity, blur and drop.
    private static let shadowLooks: [(opacity: Float, radius: CGFloat, y: CGFloat)] = [
        (0.25, shadowRadius(4), 2), (0.20, shadowRadius(16), 8), (0.15, shadowRadius(32), 16),
    ]
    private let shadows: [CALayer] = shadowLooks.map { _ in CALayer() }
    /// Bumped by every flight and turn, so only the last one's end lands it.
    private var generation = 0
    private var corner: (from: CGFloat, to: CGFloat) = (0, 0)
    private var landed: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear
        for (shadow, look) in zip(shadows, Self.shadowLooks) {
            shadow.backgroundColor = UIColor.black.cgColor
            shadow.shadowColor = UIColor.black.cgColor
            shadow.shadowOpacity = look.opacity
            shadow.shadowRadius = look.radius
            shadow.shadowOffset = CGSize(width: 0, height: look.y)
            shadow.cornerCurve = .continuous
            layer.addSublayer(shadow)
        }
        card.masksToBounds = true
        card.cornerCurve = .continuous
        card.contentsGravity = .resizeAspectFill
        card.backgroundColor = UIColor(OctoColor.backgroundTertiary).cgColor
        layer.addSublayer(card)
        clear()
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

    /// Starts a flight, handing it to the screen at once so it moves on its own from here.
    func fly(_ trip: CoverFlight.Trip, landed: @escaping () -> Void) {
        generation += 1
        let mine = generation
        self.landed = landed
        let from = convert(trip.from, from: nil)
        let to = convert(trip.to, from: nil)
        corner = (trip.fromCorner, trip.toCorner)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        card.contents = trip.image?.cgImage
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.generation == mine else { return }
            self.landed?()
        }
        let lift: (from: Float, to: Float) = trip.opening ? (0, 1) : (1, 0)
        for target in [card] + shadows {
            target.isHidden = false
            move(target, from: from, to: to, cornerFrom: from.width * trip.fromCorner, cornerTo: to.width * trip.toCorner)
        }
        for shadow in shadows {
            shadow.opacity = lift.to
            shadow.add(spring("opacity", from: lift.from, to: lift.to, stiffness: 400), forKey: "opacity")
        }
        CATransaction.commit()
        CATransaction.flush()
        #if DEBUG
        sample()
        #endif
    }

    #if DEBUG
    private var sampler: CADisplayLink?

    /// Logs where the screen shows the flying cover each frame the main thread gets, so a stall
    /// of the main thread can be seen not to stop it.
    private func sample() {
        guard FlightProbe.on, sampler == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(sampled))
        link.add(to: .main, forMode: .common)
        sampler = link
    }

    @objc private func sampled() {
        guard !card.isHidden, let now = card.presentation() else {
            sampler?.invalidate()
            sampler = nil
            return
        }
        FlightProbe.note("shown y=\(Int(now.position.y - now.bounds.height / 2)) w=\(Int(now.bounds.width))")
    }
    #endif

    /// The flight under way turns toward a new place from wherever it is now.
    func retarget(to global: CGRect) {
        guard !card.isHidden else { return }
        generation += 1
        let mine = generation
        let to = convert(global, from: nil)
        let now = card.presentation() ?? card
        let from = CGRect(x: now.position.x - now.bounds.width / 2, y: now.position.y - now.bounds.height / 2,
                          width: now.bounds.width, height: now.bounds.height)
        let cornerNow = now.cornerRadius
        #if DEBUG
        FlightProbe.note("retarget from \(from) to \(to)")
        #endif
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.generation == mine else { return }
            self.landed?()
        }
        for target in [card] + shadows {
            target.removeAnimation(forKey: "position")
            target.removeAnimation(forKey: "bounds.size")
            target.removeAnimation(forKey: "cornerRadius")
            move(target, from: from, to: to, cornerFrom: cornerNow, cornerTo: to.width * corner.to)
        }
        CATransaction.commit()
        CATransaction.flush()
    }

    /// Takes the flying cover away, in the same frame the real cover shows.
    func clear() {
        generation += 1
        landed = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for target in [card] + shadows {
            target.removeAllAnimations()
            target.isHidden = true
        }
        card.contents = nil
        CATransaction.commit()
    }

    private func move(_ target: CALayer, from: CGRect, to: CGRect, cornerFrom: CGFloat, cornerTo: CGFloat) {
        target.position = CGPoint(x: to.midX, y: to.midY)
        target.bounds = CGRect(origin: .zero, size: to.size)
        target.cornerRadius = cornerTo
        target.add(spring("position", from: CGPoint(x: from.midX, y: from.midY), to: target.position, stiffness: 400), forKey: "position")
        target.add(spring("bounds.size", from: from.size, to: to.size, stiffness: 400), forKey: "bounds.size")
        target.add(spring("cornerRadius", from: cornerFrom, to: cornerTo, stiffness: 1500), forKey: "cornerRadius")
    }

    private func spring(_ keyPath: String, from: Any, to: Any, stiffness: Double) -> CASpringAnimation {
        let spring = CASpringAnimation(keyPath: keyPath)
        spring.mass = 1
        spring.stiffness = stiffness
        spring.damping = springDamping(ratio: 1, stiffness: stiffness)
        spring.initialVelocity = 0
        spring.fromValue = from
        spring.toValue = to
        // Ends once within a thousandth of the way, where the spring's tail is no longer seen.
        spring.duration = min(spring.settlingDuration, criticalSpringSeconds(stiffness: stiffness))
        return spring
    }
}
