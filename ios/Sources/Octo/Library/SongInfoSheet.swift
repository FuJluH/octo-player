import AVFoundation
import CoreMedia
import OctoKit
import SwiftUI
import UIKit

/// Everything known about a song, as labelled lines on a sheet, read once as it opens.
struct SongInfoSheet: View {
    let subject: SongSubject
    @Environment(LibraryActions.self) private var actions
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var lines: [InfoLine]?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        ArtCover(artwork: subject.track.artwork, size: 56, radius: OctoRadius.artS)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(subject.track.title).font(.headline).lineLimit(2)
                            Text(subject.track.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                if let lines {
                    Section {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in SongInfoRow(line: line) }
                    }
                } else {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Reading the song").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Song info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
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
        // The server names it on the song itself, or radio remembered it when the song came.
        facts.suggestedBy = song.octoSuggestedBy ?? actions.state.data.discovery.suggestedBy(subject.track.id)
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
        // A phone file's missing sound details are read from the file itself.
        if track.onPhone, facts.bitrate == nil || facts.sampleRate == nil || facts.bitDepth == nil,
           let url = (phone?.uri).flatMap(URL.init(string:)) {
            let read = await audioDetails(of: url)
            facts.bitrate = facts.bitrate ?? read.bitrate
            facts.sampleRate = facts.sampleRate ?? read.sampleRate
            facts.bitDepth = facts.bitDepth ?? read.bitDepth
        }
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

/// A sound file's bit rate (bits per second), sample rate (Hz) and bit depth, as far as the file
/// says; a compressed file has no bit depth.
private func audioDetails(of url: URL) async -> (bitrate: Int?, sampleRate: Int?, bitDepth: Int?) {
    let asset = AVURLAsset(url: url)
    guard let track = try? await asset.loadTracks(withMediaType: .audio).first else { return (nil, nil, nil) }
    let rate = try? await track.load(.estimatedDataRate)
    let formats = (try? await track.load(.formatDescriptions)) ?? []
    let basic = formats.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
    let bitrate = rate.flatMap { $0 > 0 ? Int($0.rounded()) : nil }
    let sampleRate = basic.flatMap { $0.mSampleRate > 0 ? Int($0.mSampleRate.rounded()) : nil }
    let bitDepth = basic.flatMap { $0.mBitsPerChannel > 0 ? Int($0.mBitsPerChannel) : nil }
    return (bitrate, sampleRate, bitDepth)
}

/// One line of the info sheet: its label over its value, and a Copy button for copyable ones.
struct SongInfoRow: View {
    let line: InfoLine
    @State private var copied = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.label).font(.footnote).foregroundStyle(.secondary)
                Text(line.value).font(.body).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if line.copyable {
                Button(copied ? "Copied" : "Copy") {
                    UIPasteboard.general.string = line.value
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                }
                .buttonStyle(.borderless)
                .font(.subheadline)
            }
        }
    }
}
