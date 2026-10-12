import Foundation
import Observation
import OctoKit

/// The live lists of the account signed in, kept as the shared lists value. Each account's are under
/// its own key, so signing in elsewhere shows that account's and keeps these for when it comes back.
@MainActor
@Observable
final class LiveListStore {
    /// The lists of the account in use, in the order they were made.
    private(set) var lists: [LiveList] = []

    @ObservationIgnored private let session: Session
    @ObservationIgnored private var account = ""

    /// The lists kept while no server is signed in.
    static let phoneAccount = "phone"

    /// The one in use, for steps run from outside the pages.
    static weak var current: LiveListStore?

    init(session: Session) {
        self.session = session
        accountChanged()
        Self.current = self
    }

    /// Whose lists these are: the signed-in account's, or the phone's own when no server is signed in.
    private var accountInUse: String {
        guard let client = session.client else { return Self.phoneAccount }
        if let id = session.activeId, !id.isEmpty { return id }
        return liveListAccountKey(username: client.credentials.username, address: client.baseURL.absoluteString)
    }

    private func key(_ account: String) -> String { Self.listsKey(account) }

    private static func listsKey(_ account: String) -> String { "live_lists.lists:\(account)" }

    /// Forgets the live lists of a server taken off the list.
    static func forget(_ account: String) {
        UserDefaults.standard.removeObject(forKey: listsKey(account))
    }

    /// Another account in use shows its own lists.
    func accountChanged() {
        account = accountInUse
        lists = decodeLiveLists(UserDefaults.standard.string(forKey: key(account)))
    }

    func byId(_ id: String) -> LiveList? { lists.first { $0.id == id } }

    /// Saves a new list or a changed one, stamped as changed now.
    @discardableResult
    func save(_ list: LiveList) -> LiveList {
        let now = msSince1970()
        var stamped = list
        stamped.name = list.name.trimmingCharacters(in: .whitespacesAndNewlines)
        stamped.changed = now
        if stamped.created == 0 { stamped.created = now }
        change { $0.saving(stamped) }
        return stamped
    }

    func remove(_ id: String) { change { $0.removing(id) } }

    /// Ignores a blank name or the same name.
    func rename(_ id: String, to name: String) {
        guard var list = byId(id) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == list.name { return }
        list.name = trimmed
        save(list)
    }

    /// A copy just after the list, named "<name> (copy)".
    @discardableResult
    func duplicate(_ list: LiveList) -> LiveList {
        let (next, copy) = lists.duplicating(list, now: msSince1970())
        write(next)
        return copy
    }

    private func change(_ edit: ([LiveList]) -> [LiveList]) {
        write(edit(decodeLiveLists(UserDefaults.standard.string(forKey: key(account)))))
    }

    private func write(_ next: [LiveList]) {
        UserDefaults.standard.set(encodeLiveLists(next), forKey: key(account))
        lists = next
    }
}

/// The library as a live list reads it: every song, with its likes and its listening (the phone's
/// plays and the server's).
@MainActor
@Observable
final class LiveLibrary {
    private(set) var tracks: [LibraryTrack] = []
    private(set) var fields = LibraryTrackFields(liked: [], listening: [:])
    /// Goes up each time the library is read again.
    private(set) var version = 0

    @ObservationIgnored private let library: Library

    init(library: Library) { self.library = library }

    /// Reads the library, likes and plays again.
    func read() async {
        let tracks = await library.tracks()
        let liked = await library.likedIds()
        let played = await library.playedTracks()
        self.tracks = tracks
        fields = LibraryTrackFields(liked: liked, listening: libraryListening(played))
        version += 1
    }

    /// The songs each query picked, for the library as last read.
    private(set) var picked: [LibraryQuery: [LibraryTrack]] = [:]
    @ObservationIgnored private var pickedFor = -1

    /// The songs `query` picks, as last worked out; nil until it has been.
    func songs(_ query: LibraryQuery) -> [LibraryTrack]? { pickedFor == version ? picked[query] : nil }

    /// Works out the songs `query` picks, away from the main thread.
    func pick(_ query: LibraryQuery) async {
        if pickedFor != version {
            picked = [:]
            pickedFor = version
        }
        if picked[query] != nil { return }
        let tracks = tracks
        let fields = fields
        let readVersion = version
        let songs = await Task.detached(priority: .userInitiated) {
            query.select(tracks, now: msSince1970(), fields: fields)
        }.value
        guard readVersion == version else { return }
        picked[query] = songs
    }
}
