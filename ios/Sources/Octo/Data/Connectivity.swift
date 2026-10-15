import Foundation
import Network
import Observation

/// Whether the phone has a connection now, and whether it is Wi-Fi or a cable rather than
/// mobile data. Parts that wait for a connection hear when one comes back.
@MainActor
@Observable
final class Connectivity {
    private(set) var online = true
    private(set) var onWifi = false
    /// Whether the connection is one the phone is asked to use sparingly (Low Data Mode).
    private(set) var lowData = false

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var listeners: [UUID: @MainActor () -> Void] = [:]

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            // Any Wi-Fi counts, a personal hotspot too; anything else is mobile data.
            let wifi = online && (path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet))
            let lowData = online && path.isConstrained
            Task { @MainActor in self?.update(online: online, wifi: wifi, lowData: lowData) }
        }
        monitor.start(queue: DispatchQueue(label: "app.winters.octo.connectivity"))
    }

    private func update(online: Bool, wifi: Bool, lowData: Bool) {
        let changed = online != self.online || wifi != onWifi || lowData != self.lowData
        let back = online && !self.online
        let wifiBack = wifi && !onWifi
        self.online = online
        onWifi = wifi
        self.lowData = lowData
        if changed || back || wifiBack {
            for listener in listeners.values { listener() }
        }
    }

    /// Calls `listener` whenever the connection changes: one appearing, Wi-Fi coming or going.
    @discardableResult
    func onChange(_ listener: @escaping @MainActor () -> Void) -> UUID {
        let id = UUID()
        listeners[id] = listener
        return id
    }
}
