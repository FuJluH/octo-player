import Foundation
import Observation
import OctoKit

/// Small per-store values kept on the phone, under "<store>.<name>" and, for one account's values,
/// "<store>.<name>@<account>".
struct Prefs: @unchecked Sendable {
    let store: String
    private let defaults = UserDefaults.standard

    init(_ store: String) { self.store = store }

    func key(_ name: String, _ account: String? = nil) -> String {
        "\(store).\(account.map { accountKey(name, $0) } ?? name)"
    }

    func string(_ name: String, _ account: String? = nil) -> String? { defaults.string(forKey: key(name, account)) }
    func int(_ name: String, _ account: String? = nil) -> Int? { defaults.object(forKey: key(name, account)) as? Int }
    func int64(_ name: String, _ account: String? = nil) -> Int64? {
        (defaults.object(forKey: key(name, account)) as? NSNumber)?.int64Value
    }
    func bool(_ name: String, _ account: String? = nil) -> Bool? { defaults.object(forKey: key(name, account)) as? Bool }
    func strings(_ name: String, _ account: String? = nil) -> Set<String> {
        Set(defaults.stringArray(forKey: key(name, account)) ?? [])
    }

    func set(_ value: Any?, _ name: String, _ account: String? = nil) {
        if let value { defaults.set(value, forKey: key(name, account)) } else { defaults.removeObject(forKey: key(name, account)) }
    }

    func set(strings: Set<String>, _ name: String, _ account: String? = nil) {
        defaults.set(strings.sorted(), forKey: key(name, account))
    }

    func remove(_ name: String, _ account: String? = nil) { defaults.removeObject(forKey: key(name, account)) }

    /// Forgets every value this store keeps for one account.
    func forgetAccount(_ account: String) {
        let mine = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(store + ".") }
        for key in accountKeys(mine, of: account) { defaults.removeObject(forKey: key) }
    }
}

/// Calls `changed` on the main actor each time what `read` answers changes, for as long as the
/// returned watch is kept.
@MainActor
final class Watch<T: Equatable> {
    private let read: @MainActor () -> T
    private let changed: @MainActor (T) -> Void
    private var last: T
    private var live = true

    init(_ read: @escaping @MainActor () -> T, changed: @escaping @MainActor (T) -> Void) {
        self.read = read
        self.changed = changed
        last = read()
        arm()
    }

    func stop() { live = false }

    private func arm() {
        guard live else { return }
        _ = withObservationTracking { read() } onChange: { [weak self] in
            Task { @MainActor in self?.fire() }
        }
    }

    private func fire() {
        guard live else { return }
        let now = read()
        arm()
        if now != last {
            last = now
            changed(now)
        }
    }
}

/// Milliseconds since 1970, now.
func epochNowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
