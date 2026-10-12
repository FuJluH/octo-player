import Foundation

/// A rectangle in points, by its edges.
public struct PopupRect: Sendable, Equatable {
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

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(left: x, top: y, right: x + width, bottom: y + height)
    }

    public var width: Double { right - left }
    public var height: Double { bottom - top }

    public func contains(x: Double, y: Double) -> Bool {
        x >= left && x <= right && y >= top && y <= bottom
    }
}

/// A size in points.
public struct PopupSize: Sendable, Equatable {
    public var width: Double
    public var height: Double

    public init(_ width: Double, _ height: Double) {
        self.width = width
        self.height = height
    }
}

/// Where a pop-up goes. `above` means it flipped over the control that opened it, for want of
/// room below; `fromEnd` means it lines up with the control's end edge instead of its start;
/// `centered` means there was no control, so it sits in the middle of the screen.
public struct PopupSpot: Sendable, Equatable {
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

    /// The point it grows from, as fractions of its size: the corner nearest the control, or
    /// its middle.
    public var origin: (x: Double, y: Double) {
        centered ? (0.5, 0.5) : (fromEnd ? 1 : 0, above ? 1 : 0)
    }
}

/// Places a pop-up of `size` in a window of `window`, keeping `margin` clear of every edge and
/// of the system bars (`top` and `bottom` tall). It goes under the control, `gap` away, when
/// it fits there; over it when only that fits; otherwise on the roomier side, pushed back
/// inside. It lines up with the control's start edge, or its end edge when the control is on
/// the far half of the screen. With no control it sits in the middle. `keepAbove` is the side
/// it took when it opened: while it still fits there it stays.
public func placePopup(anchor: PopupRect?, size: PopupSize, window: PopupSize, margin: Double, gap: Double = 0,
                       top: Double = 0, bottom: Double = 0, keepAbove: Bool? = nil) -> PopupSpot {
    let left = margin
    let right = window.width - margin
    let roof = top + margin
    let floor = window.height - bottom - margin
    // Too big to fit, it keeps to the start and the top.
    func fitX(_ x: Double) -> Double { min(max(x, left), max(left, right - size.width)) }
    func fitY(_ y: Double) -> Double { min(max(y, roof), max(roof, floor - size.height)) }

    guard let anchor else {
        return PopupSpot(x: fitX(left + ((right - left - size.width) / 2).rounded(.down)),
                         y: fitY(roof + ((floor - roof - size.height) / 2).rounded(.down)),
                         centered: true)
    }
    let fromEnd = anchor.left + anchor.right >= window.width
    let x = fitX(fromEnd ? anchor.right - size.width : anchor.left)
    let roomBelow = floor - (anchor.bottom + gap)
    let roomAbove = anchor.top - gap - roof
    let above: Bool
    if keepAbove == true && size.height <= roomAbove {
        above = true
    } else if keepAbove == false && size.height <= roomBelow {
        above = false
    } else if size.height <= roomBelow {
        above = false
    } else if size.height <= roomAbove {
        above = true
    } else {
        above = roomAbove > roomBelow
    }
    let y = fitY(above ? anchor.top - gap - size.height : anchor.bottom + gap)
    return PopupSpot(x: x, y: y, above: above, fromEnd: fromEnd)
}

/// Where a pop-up of `size` goes in a window of `window`, keeping `margin` clear of the
/// edges. At a point it opens down and to the right of it, flipping up or left where it would
/// not fit. Under a control it opens below it, or above when only that fits. With neither it
/// sits in the middle.
public func placePopupAt(point: (x: Double, y: Double)?, anchor: PopupRect?, size: PopupSize, window: PopupSize,
                         margin: Double, gap: Double = 0) -> (x: Double, y: Double) {
    let maxX = max(margin, window.width - margin - size.width)
    let maxY = max(margin, window.height - margin - size.height)
    func fit(_ x: Double, _ y: Double) -> (x: Double, y: Double) { (min(max(x, margin), maxX), min(max(y, margin), maxY)) }
    if let anchor {
        let fromEnd = anchor.left + anchor.right >= window.width
        let x = fromEnd ? anchor.right - size.width : anchor.left
        let below = anchor.bottom + gap
        let above = anchor.top - gap - size.height
        let y = below + size.height <= window.height - margin || above < margin ? below : above
        return fit(x, y)
    }
    if let point {
        let x = point.x + size.width <= window.width - margin ? point.x : point.x - size.width
        let y = point.y + size.height <= window.height - margin ? point.y : point.y - size.height
        return fit(x, y)
    }
    return fit(((window.width - size.width) / 2).rounded(.down), ((window.height - size.height) / 2).rounded(.down))
}

/// The pop-up's measures, in points.
public enum PopupMeasures {
    /// Kept clear of every edge, the bars and the keyboard.
    public static let edgeMargin = 12.0
    /// Between the control and the card.
    public static let anchorGap = 6.0
    /// The widest a pop-up gets.
    public static let maxWidth = 340.0
    /// The share of the screen's height it may take before it scrolls.
    public static let heightShare = 0.6
    /// Its corners.
    public static let corner = 20.0
    /// A glass menu page's width, so its pages line up as it turns.
    public static let menuWidth = 288.0
    /// A choice list's narrowest and widest.
    public static let choiceMinWidth = 220.0
    public static let choiceMaxWidth = 320.0
}

/// The rectangle a menu opens beside, from what was pressed and where the finger was. A
/// control no wider than half the screen is the rectangle itself. A wide row is narrowed to
/// the finger, keeping the row's top and bottom.
public func menuAnchor(bounds: PopupRect, fingerX: Double, fingerY: Double, windowWidth: Double) -> PopupRect {
    bounds.width * 2 <= windowWidth ? bounds : PopupRect(left: fingerX, top: bounds.top, right: fingerX, bottom: bounds.bottom)
}

/// The last thing pressed, so a menu or a small card can open beside it. Older than two
/// seconds, what opens was not asked for by a finger, so it goes in the middle.
public struct PressMemory: Sendable {
    public static let window = 2.0

    private var spot: PopupRect?
    private var at = -Double.infinity

    public init() {}

    /// A press landed on `anchor` at `time` seconds.
    public mutating func pressed(_ anchor: PopupRect, at time: Double) {
        spot = anchor
        at = time
    }

    /// What was pressed in the last two seconds before `time`, if anything.
    public func recent(at time: Double) -> PopupRect? {
        time - at < Self.window ? spot : nil
    }

    public mutating func forget() { spot = nil }
}

/// Where a pop-up is among its pages: the pages opened, the first at the bottom, and whether
/// the last move went deeper or came back, which sets the way the pages slide. `opening`
/// counts the times the pop-up started over, so a page opened afresh starts fresh.
public struct PageTrail<T: Equatable>: Equatable {
    public let pages: [T]
    public let deeper: Bool
    public let opening: Int

    /// A trail always shows a page; an empty list gives nil.
    public init?(_ pages: [T], deeper: Bool = true, opening: Int = 0) {
        guard !pages.isEmpty else { return nil }
        self.pages = pages
        self.deeper = deeper
        self.opening = opening
    }

    private init(trusted pages: [T], deeper: Bool, opening: Int) {
        self.pages = pages
        self.deeper = deeper
        self.opening = opening
    }

    public static func of(_ first: T) -> PageTrail { PageTrail(trusted: [first], deeper: true, opening: 0) }

    public var current: T { pages[pages.count - 1] }
    public var canGoBack: Bool { pages.count > 1 }

    /// A page opened from this one, with a way back.
    public func open(_ page: T) -> PageTrail { PageTrail(trusted: pages + [page], deeper: true, opening: opening) }

    /// Back to the page before; on the first page nothing changes.
    public func back() -> PageTrail {
        canGoBack ? PageTrail(trusted: Array(pages.dropLast()), deeper: false, opening: opening) : self
    }

    /// This page swapped for another at the same depth.
    public func replace(_ page: T) -> PageTrail { PageTrail(trusted: Array(pages.dropLast()) + [page], deeper: true, opening: opening) }

    /// Back at the start with `first`, as the pop-up opens again.
    public func restart(_ first: T) -> PageTrail { PageTrail(trusted: [first], deeper: true, opening: opening + 1) }
}

/// How each option of a glass menu is drawn: the chosen one in the pill, a line above every
/// other one except where it would touch the pill.
public func menuRowLooks(count: Int, selected: Int) -> [MenuRowLook] {
    MenuRowLook.rows(count: count, selected: selected)
}
