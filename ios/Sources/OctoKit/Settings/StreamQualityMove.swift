import Foundation

/// The size the first builds' one stream size becomes for Wi-Fi and mobile data, or nil when
/// nothing moves: it moves once ever (`alreadyMoved`), only when one was kept (`oldKbps`, 0 for
/// the file as it is), and never once a Wi-Fi or mobile data size has been chosen
/// (`sizesChosen`), since the first builds kept neither.
public func movedStreamQuality(oldKbps: Int?, alreadyMoved: Bool, sizesChosen: Bool) -> StreamQuality? {
    guard !alreadyMoved, !sizesChosen, let oldKbps else { return nil }
    return oldKbps > 0 ? .mp3(kbps: oldKbps) : .original
}
