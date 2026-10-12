# Parity contract: widgets, voice and the ways in from the system

Read from octo-player `origin/main` 0f11df0f (the Android app). Every line is a behavior the iPhone app must match. On iPhone the look is the system's: home screen widgets drawn the way good iOS widgets are, with SF Symbols, not Android's layouts copied; what each widget shows, its sizes, taps, updates and states follow Android.

Path shorthand used in the citations:

- `app:` is `app/src/main/java/app/winters/octo/`
- `res:` is `app/src/main/res/`
- `appTest:` is `app/src/test/java/app/winters/octo/`
- `manifest` is `app/src/main/AndroidManifest.xml`

## 1. The widgets Android has

- [x] Two home screen widgets, and no others: Now playing (label "Now playing") and Quick play (label "Quick play") (manifest:177-199, res:values/widget.xml:33, app/src/main/res/values/strings.xml:7) (iPhone: two WidgetKit widgets)
- [x] Both are home screen only (`widgetCategory="home_screen"`), never on the lock screen (res:xml/widget_now_playing.xml:12, res:xml/widget_quick_play.xml:12) (iPhone: home screen sizes only, no Lock Screen families)
- [x] Neither asks the system for timed updates (`updatePeriodMillis="0"`): Now playing is redrawn only when the player tells it to, Quick play never changes (res:xml/widget_now_playing.xml:2-3, 11, res:xml/widget_quick_play.xml:2-3, 11) (iPhone: timeline policy never; the app reloads Now playing when it changes)
- [x] Picker descriptions: Now playing "The song that is on, with play, pause and skip."; Quick play "Liked songs, the newest albums, an album mix or the last queue, in one tap." (res:values/widget.xml:32-34, res:xml-v31/widget_now_playing.xml:5, res:xml-v31/widget_quick_play.xml:5)

## 2. Now playing: what it shows

- [x] It shows whatever the player last told it; with the player not running that is "Nothing playing" and a play button that picks up the saved queue (app:widget/NowPlayingWidget.kt:16-18, 30-42)
- [x] What the player tells it: the song's title, its artist, and whether it plays; nothing at all while no song is loaded (app:widget/WidgetFaces.kt:3-9, app:widget/WidgetUpdates.kt:28-38)
- [x] "Plays" counts buffering after a press of play, so the button already shows pause then (Media3 `!shouldShowPlayButton`) (app:widget/WidgetUpdates.kt:35-36)
- [x] Nothing loaded, at every size: title "Nothing playing", no artist, the play button only (no skips), and the empty cover (app:widget/WidgetFaces.kt:47-50, appTest:widget/WidgetFacesTest.kt:64-74)
- [x] A song with a blank title reads "Unknown song"; a blank artist is hidden (app:widget/WidgetFaces.kt:40-41, 51-52, appTest:widget/WidgetFacesTest.kt:76-82)
- [x] Text is trimmed and every run of whitespace becomes one space; blank text counts as missing (app:widget/WidgetFaces.kt:62-66, appTest:widget/WidgetFacesTest.kt:84-89)
- [x] Text longer than 80 characters is cut to 79 with trailing spaces removed and "…" added (so at most 80); exactly 80 stays whole (app:widget/WidgetFaces.kt:43-45, 63-67, appTest:widget/WidgetFacesTest.kt:91-104)
- [x] The play button shows pause while playing and play otherwise; its spoken label is "Pause" or "Play" to match (app:widget/NowPlayingWidget.kt:99-100, res:values/widget.xml:37-38)
- [x] The cover is the song's artwork; with none, or nothing loaded, an empty cover: a dark tile (#1A1A1B) with a music note in the middle (app:widget/NowPlayingWidget.kt:89-93, res:drawable/widget_art_empty.xml:2-15, res:values/widget.xml:8) (iPhone: SF Symbol music.note on a #1A1A1B tile)
- [x] The cover is a center square crop of the artwork, at most 300 px across, read once per song (app:widget/WidgetArt.kt:14-41)
- [x] The cover's spoken label is "Open the player" (res:layout/widget_now_playing_large.xml:17, res:values/widget.xml:36)
- [x] Spoken labels of the skip buttons: "Previous" and "Next" (res:layout/widget_now_playing_large.xml:69, 88, res:values/widget.xml:39-40)

## 3. Now playing: sizes and shapes

- [x] Three shapes: Small, Medium and Large; the widget takes the largest that fits its size as it is resized (app:widget/WidgetFaces.kt:11-12, app:widget/NowPlayingWidget.kt:53-62) (iPhone: small, medium and large widget sizes; the face is picked from the size it is drawn at)
- [x] The shape rule: narrower than 200 is Small (even when tall, since three buttons need the width); else lower than 100 is Medium; else Large. No size known yet counts as the smallest (app:widget/WidgetFaces.kt:14-25, appTest:widget/WidgetFacesTest.kt:12-30)
- [x] Small shows the cover, the title on one line and play or pause; no artist and no skips (app:widget/WidgetFaces.kt:54-55, res:layout/widget_now_playing_small.xml:1-78, appTest:widget/WidgetFacesTest.kt:32-41)
- [x] Medium adds the artist on one line and the previous and next buttons; the title stays on one line (app:widget/WidgetFaces.kt:56, res:layout/widget_now_playing_medium.xml:1-78, appTest:widget/WidgetFacesTest.kt:43-49) (iPhone: drawn where a slot is wide and short)
- [x] Large gives the title a second line, with the artist and the three buttons under the words, and a bigger cover (app:widget/WidgetFaces.kt:57-58, res:layout/widget_now_playing_large.xml:1-93, appTest:widget/WidgetFacesTest.kt:51-57) (iPhone: medium puts the cover beside the words and buttons; large puts a bigger cover above them)
- [~] Placed at 4x1 by default, resizable from 2x1 up to as large as the home screen allows (res:xml-v31/widget_now_playing.xml:7-14, res:xml/widget_now_playing.xml:2-3) (not on iPhone: WidgetKit has fixed widget sizes, with no 4x1 slot and no free resizing)
- [x] Whatever does not fit is cut with an ellipsis at the end (res:layout/widget_now_playing_large.xml:38-40, 50-51)

## 4. Now playing: taps

- [x] The cover and the words open the app; with a song loaded they open it on the full player, with nothing loaded just the app (app:widget/NowPlayingWidget.kt:94-97, app:widget/WidgetIntents.kt:39-50) (iPhone: the widget opens octo://player with a song loaded, octo://open with none)
- [x] Opening the full player from a widget happens once per tap; coming back to the app later is not a new tap (app:MainActivity.kt:106-113) (iPhone: each link is delivered once; coming back to the app delivers nothing)
- [x] Play and Pause are separate commands, chosen by what the button shows, so a widget still showing an old state can never do the opposite of what it shows (app:widget/WidgetCommand.kt:3-5, app:widget/NowPlayingWidget.kt:101)
- [x] Previous and Next show only where the shape shows skips, and only then answer taps (app:widget/NowPlayingWidget.kt:103-109)
- [x] The buttons act without opening the app (app:widget/WidgetIntents.kt:19-33) (iPhone: App Intents run in the app; builds without App Intents metadata use octo:// links, which open Octo)

## 5. Now playing: keeping it up to date

- [x] It is redrawn when the song changes and when the music starts or stops playing, never while music simply plays (app:widget/WidgetUpdates.kt:16-18, app:playback/OctoPlaybackService.kt:466, 526)
- [x] The cover is read once per song, and only while a Now playing widget is placed (app:widget/WidgetUpdates.kt:39-48)
- [x] While the new song's cover is being read, the words wait for it so the two change together; once read, the newest words and the cover show (app:widget/WidgetUpdates.kt:49-58)
- [x] A cover that cannot be read leaves the empty cover, and is not tried again for that song (app:widget/WidgetUpdates.kt:24-25, 51-52)
- [x] When the player goes away it goes back to "Nothing playing" (app:widget/WidgetUpdates.kt:61-70, app:playback/OctoPlaybackService.kt:276) (iPhone: cleared when the app ends or the lock screen's Close is used; iOS gives no call when it ends a suspended app)

## 6. Quick play

- [x] Four squares that each start music without opening the app, in this order: Liked songs, Recently added, Album mix, Resume (app:widget/QuickPlayWidget.kt:9-24, res:layout/widget_quick_play.xml:1-60) (iPhone: App Intents, or octo:// links in builds without their metadata)
- [x] Each square is an icon over its name: a filled heart, an album, shuffle, a queue (res:layout/widget_quick_play.xml:26, 34, 49, 57) (iPhone: SF Symbols heart.fill, square.stack.fill, shuffle and music.note.list)
- [x] Names: "Liked songs", "Recently added", "Album mix", "Resume"; at most two lines, cut with an ellipsis (res:values/widget.xml:17-30, 41-44)
- [x] Placed at 2x2, resizable from 2x2 (res:xml-v31/widget_quick_play.xml:7-14) (iPhone: small (2x2) and medium (one row of four))
- [x] Nothing on it changes, so it is drawn once when placed (app:widget/QuickPlayWidget.kt:9-17)
- [x] Liked songs: every liked song, shuffled (app:widget/QuickPicks.kt:20)
- [x] Recently added: the songs of the 10 albums added last, newest album first, each album in its own order, not shuffled (app:widget/QuickPicks.kt:8-9, 21-22)
- [x] Album mix: the songs of 8 random albums, shuffled together (app:widget/QuickPicks.kt:10, 23)
- [x] Resume: exactly the play button: carries on with the queue, or with none, shuffles everything (app:widget/QuickPicks.kt:24, app:widget/WidgetRemote.kt:39-41, 50-58)
- [x] A shuffled start begins at a random song of the list with shuffle on; an unshuffled one at the first song with shuffle off (app:widget/WidgetRemote.kt:60-66)
- [x] A square with no songs behind it (no liked songs, an empty library) does nothing (app:widget/WidgetRemote.kt:60-61) (iPhone: the intent answers that there is nothing to play)

## 7. What the buttons do

- [x] Commands: play, pause, next, previous, and quick play with its pick; each travels as text: "play", "pause", "next", "previous", "quick:<Pick>" with the pick's name (Liked, RecentlyAdded, AlbumMix, Resume); anything else is no command (app:widget/WidgetCommand.kt:6-33, appTest:widget/WidgetFacesTest.kt:106-116)
- [x] Every button is its own request, told apart from the others (app:widget/WidgetCommand.kt:35-43, appTest:widget/WidgetFacesTest.kt:111-112) (iPhone: each its own link and its own intent)
- [x] A command waits until the saved queue is back from the last session before it acts (app:playback/OctoPlaybackService.kt:253-266)
- [x] Play: with nothing queued, shuffles the whole library; else carries on (Media3 `handlePlayButtonAction`: prepares when idle, starts again from the top after the end) (app:widget/WidgetRemote.kt:35, 50-58)
- [x] Pause pauses; Next goes to the next song; Previous goes back (Media3 `seekToPrevious`: to the start of the song, or to the song before near its start) (app:widget/WidgetRemote.kt:36-38)
- [x] A button that ends with nothing playing leaves no notice behind (app:widget/WidgetRemote.kt:46-47, 68-89) (iPhone: iOS has no playback notice to leave)

## 8. Launcher shortcuts use the same lists

- [x] The icon's long-press shortcuts, in order: Shuffle all, Liked songs, Recently added, Resume; the last three share their names with Quick play (app:system/LauncherShortcuts.kt:18-24, res:values/shortcuts.xml:1-8) (iPhone: Home Screen quick actions)
- [x] Shuffle all shuffles every library song; Liked songs and Recently added play Quick play's lists; each says "No songs in your library yet" or "No liked songs yet" when there is nothing (app:system/SystemEntries.kt:47-54, 67-74)
- [x] Resume is exactly the widget's Play command (app:system/SystemEntries.kt:55-63)
- [x] A shortcut that started music opens the full player (app:system/SystemEntries.kt:34-45)

## 9. Voice

- [x] "Play something on Octo" asked of the voice assistant opens Octo with what was said, and plays it (manifest:66-70, app:MainActivity.kt:115-118) (iPhone: Siri's media intent, handled in the app, and App Shortcuts)
- [x] What was said goes to the player as a search request; the player works out what it means (app:playback/PlaybackConnection.kt:182-189, app:playback/OctoPlaybackService.kt:603-611) (iPhone: Siri's media intent goes to the player's search)
- [x] Saying nothing in particular shuffles the whole library (app:playback/CarLibrary.kt:90-92)
- [x] An album named exactly (case, accents and punctuation aside) among the first 5 album matches wins and plays in album order, not shuffled (app:playback/CarLibrary.kt:93-95)
- [x] Else an artist named exactly (by the same-artist rule) among the first 5 artist matches plays all their albums' songs, shuffled (app:playback/CarLibrary.kt:96-100)
- [x] Else up to 50 songs that match play in order, from the first (app:playback/CarLibrary.kt:101)
- [x] A shuffled voice request starts at a random song with shuffle on (app:playback/OctoPlaybackService.kt:607-610)
- [x] Only the library is searched; nothing matching leaves nothing playing (app:playback/CarLibrary.kt:87-102)

## 10. In the car

- [x] The same spoken requests work from the car ("play Drake on Octo" through the car's assistant) (app:playback/OctoPlaybackService.kt:603-611) (iPhone: Siri in CarPlay sends the same media intent)
- [~] Search typed or said in the car lists up to 30 songs, 15 albums and 10 artists that match; empty text finds nothing (app:playback/CarLibrary.kt:78-85, app:playback/OctoPlaybackService.kt:665-686) (not on iPhone: CarPlay audio apps have no search field; Siri in the car takes the same spoken requests)

## 11. Quick settings tiles

- [x] Android has no quick settings tile (no TileService in the manifest), so there is nothing to match in Control Center (manifest:1-215) (iPhone: no Control Center control; play and pause there come from Now Playing)

## iPhone counterparts

- Widgets: a WidgetKit extension, `OctoWidgets` (`app.winters.octo.widgets`). Now playing comes in the small, medium and large sizes; the shape rule above picks the face from the size the widget is drawn at (small is Small; medium and large are Large; iPhone has no 4x1 slot, so Medium shows only where a slot is wide and short). Quick play is small (2x2, the same squares) and medium (one row of four).
- What a widget shows: the app writes the song, its artist, whether it plays and a 300 px cover into the App Group folder and asks WidgetKit to reload, only when the song or play state changes.
- Widget buttons: App Intents that run in the app (`AudioPlaybackIntent`) when the build carries App Intents metadata; a build without it (xtool cannot make `Metadata.appintents`) uses `octo://` links that open Octo and do the same (`octo://player`, `octo://widget?command=play`, `pause`, `next`, `previous`, `quick:Liked`, `quick:RecentlyAdded`, `quick:AlbumMix`, `quick:Resume`).
- Voice: SiriKit's media intent (`INPlayMediaIntent`, handled in the app) for "Play Drake in Octo" in Siri and CarPlay, routed to the player's `playFromSearch`; App Intents with App Shortcuts ("Play <item> in Octo", "Play music in Octo", "Resume Octo", "Play my Liked songs in Octo", "Play recently added in Octo", "Play an album mix in Octo", "Start radio from <item> in Octo") for Siri, Spotlight and Shortcuts.
- Control Center: none, as Android has no quick settings tile; play and pause there come from Now Playing, which the playback engine already fills.
- Car search: CarPlay audio apps have no search field; Siri in the car takes the same media intent.
