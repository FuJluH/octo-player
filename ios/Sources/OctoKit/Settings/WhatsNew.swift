import Foundation

/// What this update brings: the one line the card on Home shows, and the notes the panel shows,
/// as markdown. Both are rewritten with each update.
public enum WhatsNew {
    /// The one line the card on Home shows. Kept short.
    public static let summary = "A new equalizer, sorting, favorites, downloads and much more"

    /// Whether the card about what is new should show: once after each update, but not on a
    /// fresh install, which has nothing to compare with.
    public static func due(lastSeen: Int?, current: Int, freshInstall: Bool) -> Bool {
        guard let lastSeen else { return !freshInstall }
        return lastSeen < current
    }

    public static let notes = """
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
    - Browse your music **by folder** on your server.
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
    - Play on **AirPlay** speakers and TVs from the player.

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
    - **Home Screen widgets** for what is playing and for quick play.
    - Ask Siri or Shortcuts to play Liked songs, recently added or an album mix, start a radio, or resume.
    - Audio files from the Files app open straight in Octo.
    - Share a song's file, or delete it from the phone.
    - Search remembers your recent searches, and can show only songs, albums, artists or playlists.
    - Bring in playlists from files, and save them out again.

    ## Settings

    - Settings has **a page for each topic**, and a search for any setting.
    - The artwork's colors can glow softly behind the app.
    - Send your plays to **ListenBrainz**, with or without a server.
    - **Back up** your settings, playlists, likes, favorites and more to a file, and bring them back.
    """
}
