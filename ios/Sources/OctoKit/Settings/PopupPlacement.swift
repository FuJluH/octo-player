import Foundation

/// The measures of a choice popup beside its row, and where it goes (see `placePopup`).
public enum PopupPlacement {
    /// Kept clear of every screen edge.
    public static let margin = PopupMeasures.edgeMargin
    /// Between the popup and the control that opened it.
    public static let gap = PopupMeasures.anchorGap
    /// The widest a popup gets.
    public static let maxWidth = PopupMeasures.maxWidth
    /// The share of the screen's height a popup may take before it scrolls.
    public static let heightShare = PopupMeasures.heightShare

    /// Places a popup of `width` by `height` on a screen `screenWidth` by `screenHeight`; see
    /// `placePopup` for the rules.
    public static func place(anchor: PopupRect?, width: Double, height: Double, screenWidth: Double, screenHeight: Double,
                             margin: Double = margin, gap: Double = 0, top: Double = 0, bottom: Double = 0,
                             keepAbove: Bool? = nil) -> PopupSpot {
        placePopup(anchor: anchor, size: PopupSize(width, height), window: PopupSize(screenWidth, screenHeight), margin: margin,
                   gap: gap, top: top, bottom: bottom, keepAbove: keepAbove)
    }
}
