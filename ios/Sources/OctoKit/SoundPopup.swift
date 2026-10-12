import Foundation

/// Where the Sound page's glass pop-ups go: beside what was pressed, or in the middle when
/// nothing was.
public enum SoundPopup {
    /// A rectangle in whole points, as left, top, right and bottom edges.
    public struct Box: Sendable, Equatable {
        public var left: Int
        public var top: Int
        public var right: Int
        public var bottom: Int

        public init(_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) {
            self.left = left
            self.top = top
            self.right = right
            self.bottom = bottom
        }

        public var width: Int { right - left }
    }

    /// Where a pop-up landed. `above` means it flipped over the control that opened it, for
    /// want of room below; `fromEnd` means it lines up with the control's end edge; `centered`
    /// means there was no control.
    public struct Spot: Sendable, Equatable {
        public var x: Int
        public var y: Int
        public var above = false
        public var fromEnd = false
        public var centered = false

        public init(x: Int, y: Int, above: Bool = false, fromEnd: Bool = false, centered: Bool = false) {
            self.x = x
            self.y = y
            self.above = above
            self.fromEnd = fromEnd
            self.centered = centered
        }

        /// The corner it grows from, as fractions of its size: the one nearest the control, or
        /// its middle.
        public var origin: (x: Double, y: Double) {
            centered ? (0.5, 0.5) : (fromEnd ? 1 : 0, above ? 1 : 0)
        }
    }

    /// How far a pop-up keeps from the screen's edges, and from the control.
    public static let edgeMargin = 12
    public static let anchorGap = 6
    /// How long a press counts as what opened a pop-up.
    public static let pressSeconds = 2.0

    /// The rectangle a pop-up opens beside: a control narrower than half the screen is the
    /// rectangle itself; a wide row is narrowed to the finger, keeping its top and bottom.
    public static func anchor(bounds: Box, fingerX: Int, windowWidth: Int) -> Box {
        bounds.width * 2 <= windowWidth ? bounds : Box(fingerX, bounds.top, fingerX, bounds.bottom)
    }

    /// Places a pop-up of `width` by `height` in a window `windowWidth` by `windowHeight`,
    /// keeping `margin` clear of every edge and of the system bars (`top` and `bottom` tall).
    /// It goes under the control, `gap` away, when it fits there; over it when only that fits;
    /// otherwise on the roomier side, pushed back inside. It lines up with the control's start
    /// edge, or its end edge when the control is on the far half of the screen. With no control
    /// it sits in the middle. `keepAbove` is the side it took when it opened: while it still
    /// fits there it stays.
    public static func place(anchor: Box?, width: Int, height: Int, windowWidth: Int, windowHeight: Int, margin: Int,
                             gap: Int = 0, top: Int = 0, bottom: Int = 0, keepAbove: Bool? = nil) -> Spot {
        let left = margin
        let right = windowWidth - margin
        let roof = top + margin
        let floor = windowHeight - bottom - margin
        func fitX(_ x: Int) -> Int { min(max(x, left), max(left, right - width)) }
        func fitY(_ y: Int) -> Int { min(max(y, roof), max(roof, floor - height)) }

        guard let anchor else {
            return Spot(x: fitX(left + (right - left - width) / 2), y: fitY(roof + (floor - roof - height) / 2), centered: true)
        }
        let fromEnd = anchor.left + anchor.right >= windowWidth
        let x = fitX(fromEnd ? anchor.right - width : anchor.left)
        let roomBelow = floor - (anchor.bottom + gap)
        let roomAbove = anchor.top - gap - roof
        let above: Bool
        if keepAbove == true && height <= roomAbove {
            above = true
        } else if keepAbove == false && height <= roomBelow {
            above = false
        } else if height <= roomBelow {
            above = false
        } else if height <= roomAbove {
            above = true
        } else {
            above = roomAbove > roomBelow
        }
        let y = fitY(above ? anchor.top - gap - height : anchor.bottom + gap)
        return Spot(x: x, y: y, above: above, fromEnd: fromEnd)
    }
}
