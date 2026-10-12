import OctoKit
import SwiftUI

/// Another device's queue the server holds, newer than this phone's.
struct ResumeOffer: Equatable, Sendable {
    /// Who saved it: the device's name trimmed, else "another device".
    var device: String
    var title: String
    var artist: String?
    /// When it was saved, as the server says it; answering records it.
    var changedAt: String
}

/// Where the resume card's offer comes from: the server play queue sync.
@MainActor
protocol ResumeOffers: AnyObject {
    var offer: ResumeOffer? { get }
    /// Puts the other device's queue in place of this one, paused where it was. False when none of
    /// its songs could be found.
    func take(_ offer: ResumeOffer) async -> Bool
    /// Records the offer as answered, so the same queue is not offered again.
    func dismiss(_ offer: ResumeOffer)
}

/// A quiet offer at the top of Home to carry on from another device, when the server has a newer
/// queue saved by another app.
struct ResumeCard: View {
    let source: ResumeOffers?
    @State private var loading = false
    /// The last offer, kept while the card folds away.
    @State private var last: ResumeOffer?

    var body: some View {
        let offer = source?.offer
        VStack(spacing: 0) {
            if let shown = offer {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pick up where you left off on \(shown.device)").font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                    Text(shown.title).font(.octoBody).foregroundStyle(.white).lineLimit(1)
                    if let artist = shown.artist, !artist.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(artist).font(.octoBodySmall).foregroundStyle(OctoColor.textSecondary).lineLimit(1)
                    }
                    HStack(spacing: 12) {
                        Button {
                            resume(shown)
                        } label: {
                            if loading { ProgressView().controlSize(.small) } else { Text("Resume") }
                        }
                        .buttonStyle(.glassProminent)
                        Button("Not now") { source?.dismiss(shown) }.buttonStyle(.glass)
                    }
                    .font(DiscoveryStyle.label)
                    .padding(.top, 12)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: offer)
        .onChange(of: offer, initial: true) { _, now in if let now { last = now } }
    }

    /// Ignored while already loading; a failure is only logged.
    private func resume(_ offer: ResumeOffer) {
        guard !loading, let source else { return }
        loading = true
        Task {
            _ = await source.take(offer)
            loading = false
        }
    }
}

/// The release notes in a glass sheet: the version as a big title, then the notes, which scroll.
struct WhatsNewPanel: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("What's new").font(DiscoveryStyle.label).foregroundStyle(OctoColor.textSecondary)
                Text("Octo \(Session.appVersion)")
                    .font(.octoTitle)
                    .foregroundStyle(.white)
                    .padding(.top, 2)
                    .padding(.bottom, 18)
                    .accessibilityAddTraits(.isHeader)
                NotesText(source: whatsNewNotes)
            }
            .frame(maxWidth: 460, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 26)
            .padding(.bottom, 28)
        }
        .presentationDetents([.fraction(0.82)])
        .presentationDragIndicator(.visible)
    }
}

/// The little markdown Octo writes itself: headings, paragraphs, bullet lists and rules, with bold,
/// italic, code and links inside a line.
struct NotesText: View {
    let source: String

    private enum Part: Hashable {
        case heading(String)
        case paragraph(String)
        case bullets([String])
        case rule
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                switch part {
                case .heading(let text):
                    inline(text).font(.octoSection).foregroundStyle(.white).padding(.top, 6).accessibilityAddTraits(.isHeader)
                case .paragraph(let text):
                    inline(text).font(.octoBodySmall).foregroundStyle(.white.opacity(0.9))
                case .bullets(let items):
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•").foregroundStyle(OctoColor.textSecondary)
                                inline(item).foregroundStyle(.white.opacity(0.9))
                            }
                            .font(.octoBodySmall)
                        }
                    }
                case .rule:
                    Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
                }
            }
        }
    }

    private func inline(_ text: String) -> Text {
        let styled = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        return Text(styled)
    }

    private var parts: [Part] {
        var parts: [Part] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        func endParagraph() {
            if !paragraph.isEmpty { parts.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }
        func endList() {
            if !bullets.isEmpty { parts.append(.bullets(bullets)) }
            bullets = []
        }
        for raw in source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                endParagraph()
                endList()
            } else if line.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" || $0 == " " }) && line.filter({ $0 != " " }).count >= 3 {
                endParagraph()
                endList()
                parts.append(.rule)
            } else if line.hasPrefix("#") {
                endParagraph()
                endList()
                parts.append(.heading(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                endParagraph()
                bullets.append(String(line.dropFirst(2)))
            } else if !bullets.isEmpty && raw.hasPrefix(" ") {
                bullets[bullets.count - 1] += " " + line
            } else {
                endList()
                paragraph.append(line)
            }
        }
        endParagraph()
        endList()
        return parts
    }
}

/// What this update brings, part by part. Rewritten with each update.
let whatsNewNotes = """
A big update: a new **equalizer**, **sorting** for every list, **favorites**, **downloads**, lyrics that follow the song, and much more.

## Sound

- An **equalizer** with a live curve, presets, and room for your own.
- **Loudness** evens out the volume from song to song.
- **Headphone correction**, and balance between left and right.
- Headphones and speakers can each keep their own sound.

## Library

- **Sort any list**, and each list remembers its order.
- **Favorites** in one place: your liked songs, albums and artists, with a shelf on Home.
- **Pin** albums, artists and playlists to the top of Home.
- Browse your music **by folder**, on the phone or your server.
- **History** shows what you played lately and what you play most.
- Rate songs with stars.
- Play and Shuffle at the top of your lists, and a random album.
- Pull down on a list to look for new music.

## Playback

- Play next and Add to queue keep their place while shuffling.
- The **queue** shows what already played. It can clear itself, save as a playlist, or stop after a song.
- **Autoplay** keeps similar songs coming when the queue runs out.
- Change the **speed and pitch**, and skip the quiet parts.
- The **sleep timer** can add a few minutes, or stop after a few songs.
- Songs can **fade into each other**, and music can carry on when headphones reconnect.
- Swipe the artwork to skip.
- Play in the car with **CarPlay**, or ask Siri to play something.

## Server

- **Discover** finds songs, albums and artists beyond your library, and plays them.
- Stations on Home, and a **radio** from a song or an artist.
- Play your server's internet radio stations.
- Playlists stay the same on the phone and your server, both ways.
- **Share links** to songs and albums.
- Pick up the queue where another device left off.
- Artist pages show top songs, a biography and similar artists.
- Scan your server for new music, and see who else is listening.
- If your server is Octo, Settings shows what it is doing.

## Lyrics

- **Lyrics** in the player, from your server, the song's files or online.
- Lyrics that follow the song light up as they are sung. Tap a line to play from there.
- Move a song's lyrics earlier or later when they are out of time.
- The screen stays on while lyrics show.

## Offline

- **Download** songs, albums and playlists.
- Keep Liked songs and chosen playlists downloaded as they change.
- Songs you stream are kept for a while, so they play again without a connection.
- The next few songs load ahead while one plays.
- With no connection, songs that cannot play are dimmed.

## Everyday touches

- **Undo** when you remove something, and a short note when something does not work.
- **Pick several songs** at once to play, queue, add to a playlist, download or like.
- **Song info** shows everything known about a song.
- Swipe a song to the right to play it next.
- Search remembers your recent searches, and can show only songs, albums, artists or playlists.
- Bring in playlists from files, and save them out again.

## Settings

- Settings has **a page for each topic**, and a search for any setting.
- The artwork's colors can glow softly behind the app.
- Send your plays to **ListenBrainz**, with or without a server.
- **Back up** your settings, playlists, likes, favorites and more to a file, and bring them back.
"""
