import Foundation
import OctoKit

/// The queue in use, kept as a file in the app's own folder.
struct QueueFile: QueueRows {
    let url: URL

    static var standard: QueueFile {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("playback", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return QueueFile(url: folder.appendingPathComponent("queue.json"))
    }

    func read() async -> QueueSnapshot? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return savedQueueRead(text)
    }

    func write(_ snapshot: QueueSnapshot) async {
        try? encodeQueue(snapshot).write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Small texts kept by key in the player's own preferences, such as the queues waiting for
/// other accounts.
final class PlayerTexts: KeyedText, @unchecked Sendable {
    private let defaults = UserDefaults(suiteName: "playback") ?? .standard

    func text(_ key: String) -> String? { defaults.string(forKey: key) }

    func setText(_ text: String?, for key: String) {
        if let text { defaults.set(text, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}
