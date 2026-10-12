import Foundation

/// One folder in a tree of songs: the folders inside it, then its own songs, both already in the
/// order they are shown.
public final class FolderNode<T>: @unchecked Sendable {
    public let name: String
    public let folders: [FolderNode<T>]
    public let songs: [T]
    /// Every song in this folder and the folders inside it.
    public let songCount: Int

    public init(name: String, folders: [FolderNode<T>], songs: [T]) {
        self.name = name
        self.folders = folders
        self.songs = songs
        songCount = songs.count + folders.reduce(0) { $0 + $1.songCount }
    }

    /// Every song under this folder, in the order the folder shows them: each inside folder in
    /// turn, then the folder's own songs.
    public func allSongs() -> [T] {
        var out: [T] = []
        out.reserveCapacity(songCount)
        collect(into: &out)
        return out
    }

    private func collect(into out: inout [T]) {
        for folder in folders { folder.collect(into: &out) }
        out += songs
    }

    /// The folder at this path of names below this one, or nil when there is none by now.
    public func at(_ path: [String]) -> FolderNode<T>? {
        var node: FolderNode<T>? = self
        for name in path { node = node?.folders.first { $0.name == name } }
        return node
    }
}

/// The names in a folder path, like "Music/Kavinsky/Nightcall/".
public func pathNames(_ path: String?) -> [String] {
    (path ?? "").split(separator: "/").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
}

/// Builds a folder tree from where each song sits. Folders sort by name the way people count
/// (2 before 10); songs within a folder by `songOrder`.
private final class FolderBuilding<T> {
    var order: [String] = []
    var folders: [String: FolderBuilding<T>] = [:]
    var songs: [T] = []
}

public func buildFolderTree<T>(_ items: [T], pathOf: (T) -> [String], songOrder: (T, T) -> Bool) -> FolderNode<T> {
    typealias Building = FolderBuilding<T>
    let root = Building()
    for item in items {
        var node = root
        for name in pathOf(item) {
            if let next = node.folders[name] {
                node = next
            } else {
                let next = Building()
                node.folders[name] = next
                node.order.append(name)
                node = next
            }
        }
        node.songs.append(item)
    }
    func finish(_ name: String, _ node: Building) -> FolderNode<T> {
        FolderNode(
            name: name,
            folders: node.order.sorted { naturalOrder($0, $1) < 0 }.map { finish($0, node.folders[$0]!) },
            songs: node.songs.sorted(by: songOrder))
    }
    return finish("", root)
}

/// A tree whose top was skipped to where the music actually is, and the names skipped on the way.
public struct Collapsed<T> {
    public var skipped: [String]
    public var root: FolderNode<T>

    /// The name to call the top by: the last folder skipped into, or empty when nothing was skipped.
    public var name: String { skipped.last ?? "" }
}

extension FolderNode {
    /// Skips down through folders that hold nothing but one other folder, so a library kept
    /// wholly inside "Music" starts at "Music".
    public func collapsed() -> Collapsed<T> {
        var node = self
        var skipped: [String] = []
        while node.songs.isEmpty, node.folders.count == 1 {
            node = node.folders[0]
            skipped.append(node.name)
        }
        return Collapsed(skipped: skipped, root: node)
    }
}

/// Compares names the way people count: "Disc 2" before "Disc 10", and case only breaks ties.
public func naturalOrder(_ a: String, _ b: String) -> Int {
    let x = Array(a), y = Array(b)
    var i = 0, j = 0
    func digitsEnd(_ s: [Character], _ from: Int) -> Int {
        var end = from
        while end < s.count, s[end].isASCII, s[end].isNumber { end += 1 }
        return end
    }
    while i < x.count, j < y.count {
        let ca = x[i], cb = y[j]
        if ca.isASCII, ca.isNumber, cb.isASCII, cb.isNumber {
            let endA = digitsEnd(x, i), endB = digitsEnd(y, j)
            let numA = String(x[i..<endA]).drop { $0 == "0" }
            let numB = String(y[j..<endB]).drop { $0 == "0" }
            if numA.count != numB.count { return numA.count - numB.count }
            if numA != numB { return numA < numB ? -1 : 1 }
            i = endA
            j = endB
        } else {
            let la = String(ca).lowercased(), lb = String(cb).lowercased()
            if la != lb { return la < lb ? -1 : 1 }
            i += 1
            j += 1
        }
    }
    let rest = (x.count - i) - (y.count - j)
    if rest != 0 { return rest < 0 ? -1 : 1 }
    return a == b ? 0 : (a < b ? -1 : 1)
}

/// What one folder holds, as far as gathering songs needs: the ids of the folders inside it and
/// its own songs, in the order shown.
public struct FolderContents<S> {
    public var folders: [String]
    public var songs: [S]

    public init(folders: [String], songs: [S]) {
        self.folders = folders
        self.songs = songs
    }
}

/// The songs gathered under a folder, and whether there were more than the limit allowed.
public struct Gathered<S> {
    public var songs: [S]
    public var limitReached: Bool
}

/// Most songs one Play or Shuffle gathers from under a server folder.
public let serverSongLimit = 2_000

/// Most folders one Play or Shuffle opens on the way.
public let serverFolderLimit = 400

/// Collects every song under a folder, in the order the folders show them: each inside folder in
/// turn, then the folder's own songs. Stops at `limit` songs, or after opening `maxFolders`
/// folders. A folder seen twice is opened once.
public func gatherSongs<S>(_ start: FolderContents<S>, limit: Int, maxFolders: Int, isolation: isolated (any Actor)? = #isolation,
                           open: (String) async throws -> FolderContents<S>) async rethrows -> Gathered<S> {
    var out: [S] = []
    var seen = Set<String>()
    var opened = 0
    var cut = false
    var stack: [(contents: FolderContents<S>, next: Int)] = [(start, 0)]
    while let top = stack.last, !cut {
        if top.next < top.contents.folders.count {
            let id = top.contents.folders[top.next]
            stack[stack.count - 1].next += 1
            guard seen.insert(id).inserted else { continue }
            if out.count >= limit || opened >= maxFolders {
                cut = true
                break
            }
            opened += 1
            stack.append((try await open(id), 0))
        } else {
            let songs = top.contents.songs
            let room = limit - out.count
            if songs.count > room {
                out += songs.prefix(room)
                cut = true
            } else {
                out += songs
            }
            stack.removeLast()
        }
    }
    return Gathered(songs: out, limitReached: cut)
}

/// A name for the server that people would recognize: Octo, the kind of server it says it is, or
/// failing both its address.
public func serverName(isOcto: Bool, type: String?, host: String) -> String {
    if isOcto { return "Octo" }
    if let type = type?.trimmingCharacters(in: .whitespaces), !type.isEmpty { return type.prefix(1).uppercased() + type.dropFirst() }
    return host
}
