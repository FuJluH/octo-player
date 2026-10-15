import Foundation

/// How long the press on a tapped line takes to go in.
public let PRESS_S = 0.08
public let PRESSED_SCALE = 0.97

/// One line's moving parts: where it is (a spring), how big (a spring from 0 at the other lines'
/// size to 1 at full size), how clear and how sharp, whether it is being sung, and whether its
/// word animation is ready.
public final class LineState {
    public let line: SyncLine
    public let y = linePositionSpring()
    public let grown = lineScaleSpring()
    public var opacity = 0.0
    public var blur = 0.0
    public var status = LineStatus.upcoming

    /// Its height now; an interlude's changes as its dots open and close.
    public var height = 0.0

    /// Its word animation is prepared, near the focus.
    public var live = false

    /// Pressed by a finger, and how far the press has gone in (0 to 1).
    public var pressed = false
    public var pressHeldUntil = 0
    public var press = 0.0

    /// An interlude reached by a seek shows its dots already grown.
    public var grownIn = false

    /// Bumped when its place, size, opacity or blur changes, and when what it draws changes. Its
    /// layer and its drawing read one each, so a line that did not change this frame is not
    /// touched.
    public var layerVersion = 0
    public var drawVersion = 0

    /// What it last drew with, to tell when that changes.
    public var drawnBrightness: Brightness?

    /// From when to when its words move: bobs start 0.4 s before a letter, and a held word's last
    /// letter (with the last word's longer swell and its bob) settles about 2.2 lengths after the
    /// word starts. Lines not timed word by word have no moving words.
    public let motionFrom: Double
    public let motionUntil: Double

    public init(_ line: SyncLine) {
        self.line = line
        let wordTimed = !line.isLineTimed && !line.isInterlude && !line.isCredit && !line.words.isEmpty
        motionFrom = wordTimed ? line.start - 0.5 : Double.infinity
        motionUntil = !wordTimed
            ? -Double.infinity
            : line.words.map { word in
                let length = word.end - word.start
                return max(word.start + max(1.0, length), word.start + 2.2 * length)
            }.max()!
    }

    /// The brightness pair it is drawn with now.
    public func brightness() -> Brightness { pressed || press > 0.5 ? TouchedBrightness : OctoKit.brightness(grown.value()) }
}
