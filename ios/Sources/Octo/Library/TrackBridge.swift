import OctoKit
import SwiftUI

// Between the library's rows and what the player and the routes take.

extension LibraryTrack {
    /// The server's own id for this song, when its row is the server's copy.
    var serverSongId: String? {
        if isFind(id) { return nativeId }
        return isServerSource(sourceId) ? nativeId : nil
    }

    /// The song as the queue takes it: by its library id, so the player picks the best copy (a
    /// download, the phone's file, or the server's stream). A find keeps its own id.
    var queueSong: Song {
        var song = asSong
        if !isFind(id) { song.id = id }
        return song
    }

    /// The album's id on the server, from the library's "<source>:<id>".
    var serverAlbumId: String? { serverId(of: albumId, sourceId: sourceId) }

    /// The artist's id on the server, from the library's "<source>:<id>".
    var serverArtistId: String? { serverId(of: artistId, sourceId: sourceId) }

    /// Whether a song row offers the song as found online, not in the library.
    var isFound: Bool { isFind(id) }
}

extension LibraryAlbum {
    /// The release types, one a line as kept.
    var types: [String] { releaseTypes.split(separator: "\n").map(String.init).filter { !$0.isEmpty } }
}


/// A picture from the library's artwork: a server's cover, or the stand-in tile while it loads
/// or when there is none.
struct ArtCover: View {
    let artwork: String?
    var size: CGFloat
    var radius: CGFloat = OctoRadius.artS

    var body: some View { ArtworkView(artwork: artwork, size: size, radius: radius) }
}

extension Library {
    /// The library album a route names: by the library's id, or by the server's own id.
    func resolveAlbum(_ id: String) async -> LibraryAlbum? {
        if let album = await album(id) { return album }
        if let server = serverInUse { return await album("\(server):\(id)") }
        return nil
    }

    /// The library artist a route names: by the library's id, the server's own id, or the name.
    func resolveArtist(_ id: String, name: String) async -> LibraryArtist? {
        if let artist = await artist(id) { return artist }
        if let server = serverInUse, let artist = await artist("\(server):\(id)") { return artist }
        return await artistsWithKeys([searchKey(name)]).first
    }

    /// Library songs for plain songs the server listed, where the library has them.
    func libraryTracks(for songs: [Song]) async -> [LibraryTrack] {
        guard let server = serverInUse else { return [] }
        return await tracks(ids: songs.map { "\(server):\($0.id)" })
    }

    /// The library song a plain song from the server is, when the library has it.
    func libraryTrack(for song: Song) async -> LibraryTrack? {
        if song.isExternal { return nil }
        if let track = await track(song.id) { return track }
        guard let server = serverInUse else { return nil }
        return await track("\(server):\(song.id)")
    }
}
