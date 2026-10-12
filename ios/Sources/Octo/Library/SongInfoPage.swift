import OctoKit
import SwiftUI
import UIKit

/// Everything known about a song, as plain labelled lines, read once as the page opens.
struct SongInfoPage: View {
    let subject: SongSubject
    let canGoBack: Bool
    let back: () -> Void
    @Environment(LibraryActions.self) private var actions
    @Environment(Session.self) private var session
    @State private var lines: [InfoLine]?

    var body: some View {
        GlassMenuPage(width: 320) {
            if canGoBack { GlassMenuBack(title: "Song info", onBack: back) } else { GlassMenuHeading("Song info") }
        } content: {
            if let lines {
                SongMenuHeader(track: subject.track)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in SongInfoRow(line: line) }
                Color.clear.frame(height: 8)
            } else {
                GlassMenuNote("Reading the song")
            }
        }
        .task { lines = await read() }
    }

    private func read() async -> [InfoLine] {
        let song = subject.song
        var facts = SongInfoFacts(title: song.title, artist: song.artist ?? song.byline, album: song.album ?? "")
        facts.year = song.year
        facts.genre = song.genre ?? ""
        facts.trackNo = song.track
        facts.discNo = song.discNumber
        facts.durationMs = Int64(song.duration) * 1_000
        facts.mimeType = mimeTypeOf(contentType: song.contentType, suffix: song.suffix)
        facts.bitrate = song.bitRate.map { $0 * 1_000 }
        facts.sampleRate = song.samplingRate
        facts.bitDepth = song.bitDepth
        facts.suggestedBy = song.octoSuggestedBy
        facts.explicit = song.explicitStatus.map { $0 == "explicit" }
        if let gain = song.replayGain {
            facts.trackGain = gain.trackGain
            facts.albumGain = gain.albumGain
            facts.trackPeak = gain.trackPeak
            facts.albumPeak = gain.albumPeak
        }
        guard !subject.track.isFound else {
            facts.source = .found
            return infoLines(facts)
        }
        let state = actions.state
        let library = state.library
        let track = await state.resolved(subject.track)
        let copies = await library.copies(track.id)
        let phone = copies.first { !isServerSource($0.sourceId) }
        let server = copies.first { isServerSource($0.sourceId) }
        let described = track.onPhone ? (phone ?? server) : (server ?? phone)
        let details = await library.details(track.id)
        let played = await library.playedTracks().first { $0.track.id == track.id }
        let album = await library.album(track.albumId)
        facts.title = track.title
        facts.artist = track.artist
        facts.album = track.album
        facts.albumArtist = album?.artist
        facts.year = details.year ?? track.year
        facts.originalYear = details.originalYear
        facts.genre = track.genre
        facts.genres = details.genres
        facts.composer = details.composer
        facts.bpm = details.bpm
        facts.comment = details.comment
        facts.explicit = details.explicit ?? track.explicit
        facts.discTitle = details.discTitle
        facts.mbRecordingId = details.mbRecordingId
        facts.mbAlbumId = details.mbAlbumId
        facts.mbReleaseGroupId = details.mbReleaseGroupId
        facts.mbArtistIds = details.mbArtistIds
        facts.trackNo = track.trackNo
        facts.discNo = track.discNo
        facts.durationMs = track.durationMs
        facts.mimeType = described?.mimeType ?? track.mimeType
        facts.sizeBytes = described?.sizeBytes ?? track.sizeBytes
        facts.bitrate = described?.bitrate.map { $0 < 10_000 ? $0 * 1_000 : $0 } ?? facts.bitrate
        facts.sampleRate = described?.sampleRate ?? facts.sampleRate
        facts.bitDepth = described?.bitDepth ?? facts.bitDepth
        if let gains = copies.first(where: { $0.trackGain != nil || $0.albumGain != nil }) {
            facts.trackGain = gains.trackGain.map(Double.init)
            facts.albumGain = gains.albumGain.map(Double.init)
            facts.trackPeak = gains.trackPeak.map(Double.init)
            facts.albumPeak = gains.albumPeak.map(Double.init)
        }
        facts.addedAtSeconds = track.addedAt
        facts.plays = played?.plays ?? 0
        facts.lastPlayedAt = played?.lastPlayedAt ?? 0
        facts.rating = state.rating(of: track)
        if track.onPhone {
            facts.source = .phone(path: phone?.uri.flatMap { URL(string: $0) }.map { $0.isFileURL ? $0.path : $0.absoluteString })
        } else {
            let kept = state.offline.byTrack[track.id]
            facts.source = .server(name: serverName, downloadedTo: kept.flatMap { $0.path.isEmpty ? nil : $0.path })
        }
        return infoLines(facts)
    }

    /// "Octo" for an Octo server, else the server type with its first letter upper-cased, else
    /// the host.
    private var serverName: String? {
        if session.isOcto { return "Octo" }
        if let type = session.profile?.info.type, !type.isEmpty { return type.prefix(1).uppercased() + type.dropFirst() }
        return session.client?.baseURL.host
    }
}

/// One line of the info page: its label, its value, and a Copy button for copyable ones.
struct SongInfoRow: View {
    let line: InfoLine
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(line.label)
                .font(.octoCaption)
                .foregroundStyle(OctoColor.textMuted)
                .frame(width: 92, alignment: .leading)
                .padding(.top, 2)
            Text(line.value)
                .font(.octoBodySmall)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            if line.copyable {
                Button(copied ? "Copied" : "Copy") {
                    UIPasteboard.general.string = line.value
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                }
                .font(.octoLabel)
                .foregroundStyle(.white)
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}
