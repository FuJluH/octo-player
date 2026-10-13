#if DEBUG
import os

/// Marks in the device log, for lining a drive step up with the frame probe.
@MainActor
enum BodyTrace {
    private static let log = Logger(subsystem: "app.winters.octo", category: "frames")

    static func mark(_ words: String) {
        log.notice("app mark \(words, privacy: .public)")
    }
}
#endif
