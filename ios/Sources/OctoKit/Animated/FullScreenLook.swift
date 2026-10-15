import Foundation

/// How a tall loop fills the player in Full screen, the same numbers on every app: drawn `zoom`
/// times the screen's width, centered, its top `top` of the screen's height from the top edge
/// (above it when negative), whole down to `meltStart` of the screen's height and gone by
/// `meltEnd` (or by its own bottom, when that is higher), eased by `melt` between, over the
/// player's own background made `backgroundGain` times brighter.
public enum FullScreenLook {
    public static let zoom = 1.10
    public static let top = -0.005
    public static let meltStart = 0.505
    public static let meltEnd = 0.68
    /// How far in from each side the loop fades out, as a share of its width.
    public static let sideFeather = 0.0
    /// Black laid over the loop, from 0 to 1.
    public static let darkening = 0.0
    /// How much brighter the background under the loop is drawn than without one.
    public static let backgroundGain = 0.80 / 0.62

    /// How much of the loop is gone at `t` of the way through its melt: smoothstep.
    public static func melt(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }

    /// Where the loop goes on a screen `width` by `height` points, for a loop `shape` tall per
    /// point of width: its size, its top, and where its melt starts and ends, in points from the
    /// screen's top. The melt always ends by the loop's own bottom, so no edge can show.
    public static func place(width: Double, height: Double, shape: Double)
        -> (width: Double, height: Double, top: Double, meltFrom: Double, meltTo: Double) {
        let loopWidth = width * zoom
        let loopHeight = loopWidth * shape
        let loopTop = top * height
        let to = min(meltEnd * height, loopTop + loopHeight)
        let from = min(meltStart * height, to - 1)
        return (loopWidth, loopHeight, loopTop, from, to)
    }
}
