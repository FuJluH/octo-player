import Foundation
import Observation
import OctoKit

/// Small per-store values kept on the phone, under "<store>.<name>" and, for one account's values,
/// "<store>.<name>@<account>".
struct Prefs: @unchecked Sendable {
    let store: String
    private let defaults = UserDefaults.standard

    init(_ store: String) { self.store = store }

    func key(_ name: String, _ account: String? = nil) -> String { storeKey(store, name, account: account) }

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

/// The values in their first order, each once.
func distinct(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
}

/// Work that runs one piece at a time, each after the one before it ends.
@MainActor
final class SerialWork {
    private var last: Task<Void, Never>?

    /// Runs `work` once everything handed in before has ended, and waits for it.
    func run(_ work: @escaping @MainActor () async -> Void) async {
        let before = last
        let task = Task { @MainActor in
            await before?.value
            await work()
        }
        last = task
        await task.value
    }
}

/// A value handed across threads where its owner keeps it to one at a time.
struct Unchecked<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
