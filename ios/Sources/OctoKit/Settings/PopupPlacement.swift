import Foundation

/// Where a popup goes. `above` means it flipped over the control that opened it, for want of
/// room below; `fromEnd` means it lines up with the control's end edge instead of its start;
/// `centered` means there was no control, so it sits in the middle of the screen.
public struct PopupSpot: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var above = false
    public var fromEnd = false
    public var centered = false

    public init(x: Double, y: Double, above: Bool = false, fromEnd: Bool = false, centered: Bool = false) {
        self.x = x
        self.y = y
        self.above = above
        self.fromEnd = fromEnd
        self.centered = centered
    }

    /// The corner it grows from, as fractions of its size: the one nearest the control, or its
    /// middle.
    public var origin: (x: Double, y: Double) {
        centered ? (0.5, 0.5) : (fromEnd ? 1 : 0, above ? 1 : 0)
    }
}

/// A rectangle in screen points.
public struct PopupRect: Equatable, Sendable {
    public var left: Double
    public var top: Double
    public var right: Double
    public var bottom: Double

    public init(left: Double, top: Double, right: Double, bottom: Double) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }
}

public enum PopupPlacement {
    /// Kept clear of every screen edge.
    public static let margin = 12.0
    /// Between the popup and the control that opened it.
    public static let gap = 6.0
    /// The widest a popup gets.
    public static let maxWidth = 340.0
    /// The share of the screen's height a popup may take before it scrolls.
    public static let heightShare = 0.6

    /// Places a popup of `width` by `height` on a screen `screenWidth` by `screenHeight`, keeping
    /// `margin` clear of every edge and of the system bars (`top` and `bottom` tall). It goes
    /// under the control, `gap` away, when it fits there; over it when only that fits; otherwise
    /// on the roomier side, pushed back inside. It lines up with the control's start edge, or its
    /// end edge when the control is on the far half of the screen. With no control it sits in
    /// the middle. `keepAbove` is the side it took when it opened: while it still fits there it
    /// stays.
    public static func place(anchor: PopupRect?, width: Double, height: Double, screenWidth: Double, screenHeight: Double,
                             margin: Double = margin, gap: Double = 0, top: Double = 0, bottom: Double = 0,
                             keepAbove: Bool? = nil) -> PopupSpot {
        let left = margin
        let right = screenWidth - margin
        let roof = top + margin
        let floor = screenHeight - bottom - margin
        // Too big to fit, it keeps to the start and the top.
        func fitX(_ x: Double) -> Double { min(max(x, left), max(left, right - width)) }
        func fitY(_ y: Double) -> Double { min(max(y, roof), max(roof, floor - height)) }

        guard let anchor else {
            return PopupSpot(x: fitX(left + ((right - left - width) / 2).rounded(.down)),
                             y: fitY(roof + ((floor - roof - height) / 2).rounded(.down)), centered: true)
        }
        let fromEnd = anchor.left + anchor.right >= screenWidth
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
        return PopupSpot(x: x, y: y, above: above, fromEnd: fromEnd)
    }
}
