import Foundation
import OctoKit

/// What the settings pages show of the data parts: the phone's music as the library scans it, and
/// how copying the server's library is going.
@MainActor
final class SettingsLinks {
    private var watches: [AnyObject] = []

    private struct PhoneState: Equatable {
        var access: PhoneAccess
        var songCount: Int
        var scanning: Bool
        var folders: [MusicFolder]
    }

    private struct SyncState: Equatable {
        var syncing: Bool
        var problem: String?
        var last: LastSync?
    }

    init(device: DeviceLibrary, sync: ServerSync) {
        let phone = PhoneMusic.shared
        phone.work = PhoneMusic.Work(
            requestAccess: { [weak device] in
                guard let device else { return }
                if device.access == .deniedForever { device.openSettings() } else { device.requestAccess() }
            },
            rescan: { [weak device] in await device?.rescan() }
        )
        let readPhone: @MainActor () -> PhoneState? = { [weak device] in
            guard let device else { return nil }
            return PhoneState(access: Self.phoneAccess(device.access), songCount: device.songCount, scanning: device.scanning,
                              folders: device.folders)
        }
        let showPhone: @MainActor (PhoneState?) -> Void = { state in
            guard let state else { return }
            phone.show(access: state.access, songCount: state.songCount, scanning: state.scanning, folders: state.folders)
        }
        showPhone(readPhone())
        watches.append(Watch(readPhone, changed: showPhone))

        let feeds = SettingsFeeds.shared
        let readSync: @MainActor () -> SyncState? = { [weak sync] in
            guard let sync else { return nil }
            return SyncState(syncing: sync.syncing, problem: sync.problem, last: sync.last)
        }
        let showSync: @MainActor (SyncState?) -> Void = { state in
            guard let state else { return }
            if feeds.syncing != state.syncing { feeds.syncing = state.syncing }
            if feeds.syncProblem != state.problem { feeds.syncProblem = state.problem }
            let last = state.last.map { SettingsFeeds.LastSync(serverId: $0.accountId, at: Date(timeIntervalSince1970: Double($0.at) / 1000)) }
            if feeds.lastSync != last { feeds.lastSync = last }
        }
        showSync(readSync())
        watches.append(Watch(readSync, changed: showSync))
    }

    private static func phoneAccess(_ access: DeviceAccess) -> PhoneAccess {
        switch access {
        case .granted: .granted
        case .notAsked: .notAsked
        case .denied: .denied
        case .deniedForever: .deniedForever
        }
    }
}
