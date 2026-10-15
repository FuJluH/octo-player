import Foundation
import OctoKit

// The library's rows as the player, the rows and the pages take songs, albums and artists today:
// by their ids on the server in use.

/// The server's id for a library row id made from it ("<source>:<native id>"), or nil for a row the
/// library made itself or one from another source.
func serverId(of catalogId: String, sourceId: String?) -> String? {
    guard let sourceId, catalogId.hasPrefix(sourceId + ":") else { return nil }
    let native = String(catalogId.dropFirst(sourceId.count + 1))
    if native.isEmpty || native.hasPrefix("artist:") || native.hasPrefix("album:") { return nil }
    return native
}

/// What a song or album shown by its server id carries as its cover: the server cover a library
/// picture names, or for a picture from the phone the stored reference itself, which `Cover`
/// draws as it is. Nil when there is no picture.
func coverId(of artwork: String?) -> String? {
    switch ArtworkRef.decode(artwork) {
    case .server(_, let coverId, _, _): coverId
    case .device: artwork
    case nil: nil
    }
}

/// A stored artwork reference from what a song or album carries as its cover: a reference as it
/// is, or a bare cover id of `source`.
func artworkOf(cover: String?, source: String, online: Bool = false) -> String? {
    guard let cover, !cover.isEmpty else { return nil }
    if ArtworkRef.decode(cover) != nil { return cover }
    return ArtworkRef.server(sourceId: source, coverId: cover, online: online).encode()
}

extension LibraryTrack {
    /// The song as the player plays it: a find by its id on the server, a server song by its own.
    var asSong: Song {
        let find = isFind(id)
        var song = Song(id: find || isServerSource(sourceId) ? nativeId : id, title: title, artist: artist, album: album,
                        albumId: serverId(of: albumId, sourceId: sourceId), duration: Int(durationMs / 1_000),
                        coverArt: coverId(of: artwork), isExternal: find)
        song.artistId = serverId(of: artistId, sourceId: sourceId)
        song.year = year
        song.track = trackNo
        song.discNumber = discNo
        song.genre = genre.isEmpty ? nil : genre
        if let explicit { song.explicitStatus = explicit ? "explicit" : "clean" }
        return song
    }
}

extension LibraryAlbum {
    /// The album as its page opens it.
    var asAlbum: Album {
        var album = Album(id: isServerSource(sourceId) ? nativeId : id, name: title, artist: artist, coverArt: coverId(of: artwork))
        album.artistId = serverId(of: artistId, sourceId: sourceId)
        album.songCount = songCount
        album.duration = Int(durationMs / 1_000)
        album.year = year
        return album
    }
}

extension LibraryArtist {
    /// The artist's id on the server, for its page.
    func pageId(_ sourceInUse: String?) -> String { serverId(of: id, sourceId: sourceInUse ?? sourceId) ?? id }
}

extension Station {
    /// A station, a Made for you list or a mix as its page opens it: a read-only list on the
    /// server.
    var asPlaylist: Playlist? {
        var fields: [String: Any] = ["id": id, "name": name, "songCount": songCount ?? 0, "coverArt": coverId(of: artwork) ?? id, "readonly": true]
        if let octoGroup { fields["octoGroup"] = octoGroup }
        let data = try? JSONSerialization.data(withJSONObject: fields)
        return data.flatMap { try? JSONDecoder().decode(Playlist.self, from: $0) }
    }
}

extension PlaylistSummary {
    /// The playlist as its page opens it.
    func asPlaylist(_ sourceInUse: String?) -> Playlist? {
        let data = try? JSONSerialization.data(withJSONObject: [
            "id": serverId(of: id, sourceId: sourceInUse) ?? id, "name": name, "songCount": songCount,
            "duration": Int(durationMs / 1_000), "coverArt": coverId(of: covers.first) ?? "", "octoNotice": octoNotice ?? "",
        ])
        return data.flatMap { try? JSONDecoder().decode(Playlist.self, from: $0) }
    }
}
