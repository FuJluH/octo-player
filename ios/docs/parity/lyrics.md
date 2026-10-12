# Parity contract: lyrics

Read from octo-player `origin/main` 0f11df0f (Android app, the shared Kotlin core, and the Subsonic client). Every line below is a behavior the iPhone app must match exactly: numbers, strings, states, order and motion. Where the Android code does something that looks odd, it is still listed, because parity means matching it.

Path shorthand used in the citations:

- `app:` is `app/src/main/java/app/winters/octo/`
- `shared:` is `shared/core/src/commonMain/kotlin/app/winters/octo/`
- `sharedTest:` is `shared/core/src/commonTest/kotlin/app/winters/octo/`
- `appTest:` is `app/src/test/java/app/winters/octo/`
- `subsonic:` is `subsonic/src/main/kotlin/app/winters/octo/subsonic/`
- `subsonicTest:` is `subsonic/src/test/kotlin/app/winters/octo/subsonic/`
- `design:` is `design/src/main/java/app/winters/octo/design/`

Units: `dp` is Android density-independent pixels (iOS points), `sp` is a font size in dp scaled by the user's text size, `em` is the main line's font size in pixels as worked out in section 16, `s` is seconds.

## 1. Where lyrics show in the full player

- [x] The player's controls row has a Lyrics action button: icon `Lyrics`, accessibility name "Lyrics", state "Showing" while lyrics are open and "Hidden" otherwise; a tap toggles lyrics mode (app:player/PlayerOverlay.kt:635-641)
- [x] Lyrics mode is one flag in the player model, false at start, flipped by `toggleLyrics()`; lyrics are only looked up while it is on (app:player/PlayerViewModel.kt:207-213)
- [x] Upright: in lyrics mode the artwork folds away (`ArtStage folded = lyricsOpen`) and the controls, volume and switches are replaced by the small lyrics bar, which sits at the bottom with 12dp (`LyricsBarGap`) below it (app:player/PlayerOverlay.kt:381-399, app:player/LyricsBar.kt:58)
- [x] Upright: the lyrics are drawn in a separate layer over the whole player content, filling it with padding top 56dp (the top line's height) and bottom 76dp (bar 64dp plus gap 12dp), laid out at full size from the start so lines settle where they belong while the rest folds away (app:player/PlayerOverlay.kt:401-410, 420) (iPhone: the top line is 40 pt, so the layer starts 40 pt down)
- [x] Upright: inside that layer the lyrics pane has a further 8dp padding top and bottom (app:player/PlayerOverlay.kt:451)
- [x] Upright: the lyrics pane reaches 24dp past each side (`edgeBleed = 24.dp`), cancelling the player's own 24dp side padding, so the flowing lyrics' own margins are measured from the player's full width (the window minus status bar, navigation bar and display cutout insets) (app:player/PlayerOverlay.kt:382, 453, app:player/PlayerOverlay.kt:329-335)
- [x] Upright: the lyrics layer fades with an alpha that animates to 1 over 360ms after a 120ms delay when lyrics open, and to 0 over 360ms with no delay when they close; with reduced motion it snaps; nothing is composed while the alpha is exactly 0 (app:player/PlayerOverlay.kt:438-456)
- [x] Lyrics mode coming or going swaps the controls with a fade in of 240ms after a 120ms delay and a fade out of 160ms; upright the space eases to its new height over 360ms with FastOutSlowIn easing; sideways the size snaps; with reduced motion there is no fade and the size snaps (app:player/PlayerOverlay.kt:423-434)
- [x] Sideways (width greater than height): the row has 24dp side padding and 32dp between the halves; the artwork stays on the left (never folded, max side 420dp); the right half in lyrics mode is a column of the top line, the lyrics pane (weight 1, padding 4dp top and bottom, no edge bleed), then the lyrics bar with 8dp below it (app:player/PlayerOverlay.kt:337-375)
- [x] The lyrics bar reaches 12dp past the player's side padding (`LyricsBarBleed`), so it sits 12dp from the screen edges (app:player/PlayerOverlay.kt:328, 416-418)
- [x] The lyrics chooser panel is owned by the player screen; the bar's menu opens it with `showLyricsChooser = true` and it closes with `false` (app:player/PlayerOverlay.kt:185, 271, 276-282) (iPhone: the chooser is a sheet the player owns)
- [x] The content color for lyrics is the player's ink (`LocalContentColor`): dark on a pale background, white otherwise (app:player/PlayerOverlay.kt:253, app:player/LyricsPane.kt:229-230)
- [x] A vertical drag that starts on the flowing lyrics is consumed by the lyrics scroll (`change.consume()`), so the player's pull-down-to-close (which only acts on an unconsumed drag past touch slop) does not take it (app:player/FlowingLyrics.kt:275-285, app:player/PlayerOverlay.kt:196-230)

## 2. The lyrics pane: states and chrome

- [x] The pane takes a `LyricsState` (Hidden, HiddenForSong, Loading, None, Failed(trackId), Found(trackId, lyrics)) and the player's position, seek and now-playing state (app:player/LyricsPane.kt:181-190, app:player/PlayerViewModel.kt:297-307)
- [x] The screen is kept on (`view.keepScreenOn = true`, cleared when the pane leaves) while the state is Found and the "Keep the screen on" setting is on (default on); this applies to synced, plain and instrumental Found lyrics alike (app:player/LyricsPane.kt:191-194, 251-258, app:lyrics/LyricsTiming.kt:220) (iPhone: the idle timer stays off)
- [x] The output offset used by the pane is the kept output timing (section 33) plus the screen lead `screenLeadMs(display refresh rate)`; the refresh rate is read once per view, 60 Hz when unknown (app:player/LyricsPane.kt:196-202) (iPhone: the screen's maximumFramesPerSecond, 60 when unknown)
- [x] State changes cross-fade over 300ms (a new Found with other lyrics cross-fades too, since the whole state is the key) (app:player/LyricsPane.kt:204)
- [x] Found: the song's own timing offset is read as a live flow for that track id, starting at 0 (app:player/LyricsPane.kt:208)
- [x] Found: "flowing" means synced, not instrumental, and the look's style is Flowing (app:player/LyricsPane.kt:211)
- [x] Found: the content box fills the pane, bleeds by `edgeBleed` only when flowing (0 otherwise), and has faded top and bottom edges (app:player/LyricsPane.kt:212)
- [x] Found and instrumental: shows the quiet text "Instrumental" (app:player/LyricsPane.kt:215)
- [x] Found and synced but the look not read yet: shows nothing at all for that moment (app:player/LyricsPane.kt:216-217) (iPhone: the look is read at once, so there is no blank moment)
- [x] Found, synced, Flowing: the flowing view (section 17) with the song offset, the output offset (with screen lead), the look, reduce motion, seek, and text color = the player's ink (app:player/LyricsPane.kt:218-231)
- [x] Found, synced, Classic: the classic view (section 28) with `totalOffset(songOffset, outputOffset)` (app:player/LyricsPane.kt:232)
- [x] Found, not synced: the plain view (section 29) (app:player/LyricsPane.kt:233)
- [x] None: quiet text "No lyrics for this song" (app:player/LyricsPane.kt:237)
- [x] Failed: quiet text "Couldn't load lyrics, tap to retry"; the text is a button with 24dp padding around it and no ripple; a tap asks the repository to fetch the song's lyrics again (bumps its revision) (app:player/LyricsPane.kt:238-243, 260-270, app:player/LyricsFeed.kt:115-119, app:lyrics/LyricsRepository.kt:223, 451-453)
- [x] HiddenForSong: quiet text "Lyrics are hidden for this song" (app:player/LyricsPane.kt:244)
- [x] Loading and Hidden: an empty box filling the pane, no spinner, no text (app:player/LyricsPane.kt:245)
- [x] Quiet text: centered in the pane, style body (16sp, Medium), color TextMuted (accent #97B1B9 at 80% alpha), centered alignment (app:player/LyricsPane.kt:260-270, design:OctoType.kt:13, design:OctoColors.kt:23-30)
- [x] Edge bleed: the content is measured `2 x bleed` wider than given and placed shifted left by `bleed`, so it overhangs both sides equally; the reported width stays the given width (app:player/LyricsPane.kt:272-287)
- [x] Faded edges: the pane's content is drawn offscreen, then multiplied (DstIn) by a vertical gradient transparent at 0, opaque black at `edge`, opaque at `1 - edge`, transparent at 1, where `edge = min(32dp / pane height, 0.45)`; lines fade out over 32dp at the top and bottom instead of being cut (app:player/LyricsPane.kt:289-303)
- [x] The pane's model reads: keep screen on (default true), output offset (default the automatic timing of the output playing now), look (null until read), reduce motion (the app setting only; the phone setting is added in the view), the player's time-change events, playback speed, and each song's offset (app:player/LyricsPane.kt:143-173) (iPhone: the look is read at once; reduce motion is Octo's or the phone's)

## 3. What the lyrics view is asked to show over time

- [x] The song asked for is the playing track id while lyrics mode is on, else nothing; it changes only when the id or the mode changes (app:player/PlayerViewModel.kt:238-241)
- [x] For a song, the wanted value is `(id, hidden, version)` where hidden is the phone's hide for the song and version is the pair (phone pick, repository revision for the song); any change to these asks again (app:player/PlayerViewModel.kt:243-256, app:player/LyricsFeed.kt:24)
- [x] "Watched" means something is subscribed to the lyrics state (the pane or the lyrics bar is on screen); it turns false only after 5000ms with no subscriber, so rotating the phone does not count as leaving; it starts false (app:player/PlayerViewModel.kt:223-233, 290-291)
- [x] "Away" for saving is read at save time: no subscriber right now (app:player/PlayerViewModel.kt:235-236)
- [x] Each time watched turns true a turn counter goes up; the first lookup in a new turn is `resumed = true`, later ones in the same turn `false` (app:player/LyricsFeed.kt:46-53, 79-81)
- [x] Nothing wanted: state Hidden (app:player/LyricsFeed.kt:74)
- [x] Hidden by the listener: state HiddenForSong, nothing looked up (app:player/LyricsFeed.kt:75)
- [x] Not watched: nothing is looked up; a different song than the one shown shows Loading (never the last song's lyrics, never None); the same song keeps what it shows (app:player/LyricsFeed.kt:76-78, appTest:player/LyricsFeedTest.kt:66-90)
- [x] Watched: Loading is shown first unless the same song already shows Found or None, which stay up while they are checked again (app:player/LyricsFeed.kt:82-85, appTest:player/LyricsFeedTest.kt:197-216)
- [x] A Failed answer is asked again quietly up to 2 more times, 4000ms apart (`QUIET_RETRIES = 2`, `QUIET_RETRY_MS = 4000`), with resumed false, while Loading stays up (app:player/LyricsFeed.kt:26-29, 87-95)
- [x] Still Failed after the quiet retries: shows Failed(trackId), then waits for the network to change (a network back after none, or a switch to another), shows Loading and looks up exactly once more, then shows Found, None or Failed and stays (app:player/LyricsFeed.kt:96-108, app:lyrics/NetworkWatch.kt:33-38)
- [x] A lookup that throws counts as Failed, never None; cancellation from outside propagates (app:player/LyricsFeed.kt:55-62)
- [x] Every new wanted value or watched turn cancels the lookup in flight and starts over (`transformLatest` on distinct (song, turn) pairs) (app:player/LyricsFeed.kt:64-67)
- [x] The network watch follows the phone's default network: the current network on available, cleared to none only if the lost one is the current one (app:lyrics/NetworkWatch.kt:14-31) (iPhone: the network the phone prefers, the first one available)
- [x] A lookup passes the playing song's title, artist, album and listed length when its id still matches; otherwise blanks and 0 (app:player/PlayerViewModel.kt:258-262)
- [x] Neighbor head start: while lyrics are open and watched, once a song has stayed for 1200ms, the next song (`upNext[1]`, since `upNext[0]` is the current one) and the previous song (`played.last`) get their lyrics looked up (title, artist, blank album, listed length), skipping radio entries and the current id; a skip before 1200ms restarts the wait; a neighbor's failure saves nothing (app:player/PlayerViewModel.kt:264-287, 293-294)

## 4. The lyrics data model

- [x] Sources and their menu words: Server "From your server", SongFile "From the song file", LyricsFile "From a .lrc file beside the song", Online "From LRCLIB" (shared:lyrics/Lyrics.kt:6-12)
- [x] Lyrics: `synced`, `lines`, `source`, `instrumental` (default false), `onlineId` (LRCLIB number, nullable), `serverPick` (the server's pinned copy id like "kugou:123", nullable) (shared:lyrics/Lyrics.kt:16-31)
- [x] Lyrics are empty when not instrumental and no line has non-blank text (shared:lyrics/Lyrics.kt:32)
- [x] A line: `startMs` (default 0), `endMs` (nullable: runs until the next line), `text` (empty for a gap), `words`, `backingText` (default ""), `backing` words, `agent` (singer name), `background` (only backing voices), `duet` (second lead voice), `translation`, `romanization` (shared:lyrics/Lyrics.kt:35-57)
- [x] A line is a gap when both its text and its backing text are blank (shared:lyrics/Lyrics.kt:58)
- [x] A word: `startMs`, `endMs` (nullable), `text`, `from` and `to` as character positions in the line's text, `to` exclusive (shared:lyrics/Lyrics.kt:61-70)
- [x] `lineAt(position)`: binary search for the last line whose start is at or before the position; -1 before the first; with two lines at the same time, the later one (shared:lyrics/Lyrics.kt:72-88, sharedTest:lyrics/LyricsTest.kt:15-26)
- [x] `shownLines()` (used by Classic only): for synced lyrics, a gap line at 0 is added when the first line starts at 5000ms or later and is not itself a gap; after any non-gap line with a known end, a gap line at that end is added when the next line starts 5000ms or more later and is not a gap (shared:lyrics/Lyrics.kt:90-109, sharedTest:lyrics/LyricsTest.kt:28-43)
- [x] `endOf(i)`: the line's own end, else the next line's start, else null (shared:lyrics/Lyrics.kt:111-113)

## 5. LRC text parsing

- [x] A UTF-8 byte order mark at the very start is removed; text is split into rows on any line break (`\n`, `\r\n`) and each row is trimmed (shared:lyrics/Lrc.kt:9-10, 21, 29)
- [x] Line stamps: `[m:ss]`, `[m:ss.f]`, `[m:ss:f]` with 1 to 3 minute digits, 1 to 2 second digits, an optional fraction of 1 to 3 digits after `.` or `:` (shared:lyrics/Lrc.kt:3-4)
- [x] A fraction is read as a decimal: 1 digit times 100ms, 2 digits times 10ms, 3 digits as ms; `[01:05:50]` is 65.5 s (shared:lyrics/Lrc.kt:113-124, sharedTest:lyrics/LrcTest.kt:7-21)
- [x] A row may start with several stamps; it becomes one line at each stamp with the same text (shared:lyrics/Lrc.kt:31-41, sharedTest:lyrics/LrcTest.kt:23-32)
- [x] Word stamps `<m:ss.ff>` inside a line time each piece; text before the first word stamp starts at the line's start; a word ends where the next stamp starts, and a stamp with nothing after it ends the word before it; whitespace-only pieces are not words but stay in the text (shared:lyrics/Lrc.kt:6-7, 79-101, sharedTest:lyrics/LrcTest.kt:63-79)
- [x] The line text is trimmed and every word's `from`/`to` is shifted by the leading cut and clamped to the trimmed text; words left empty are dropped (shared:lyrics/Lrc.kt:103-110)
- [x] A timed line's `endMs` is its last word's end when it has words (shared:lyrics/Lrc.kt:39)
- [x] Tag rows `[name:value]` (letters or `#` in the name) are skipped: `[ar:]`, `[ti:]`, `[length:]` and so on (shared:lyrics/Lrc.kt:12-13, 44-55)
- [x] `[offset:+N]` / `[offset:-N]` / `[offset:N]` in ms: above zero the words come sooner; every time (line start, end, word starts and ends, backing) is moved by `-offset` and clamped at 0 (shared:lyrics/Lrc.kt:48, 61-62, 126-136, sharedTest:lyrics/LrcTest.kt:34-50)
- [x] `[bg:...]` adds backing vocals (with their own word stamps) to the line or lines the timed row just before it made (shared:lyrics/Lrc.kt:25-26, 49-52, sharedTest:lyrics/LrcTest.kt:88-93)
- [x] An empty timed line is a gap (shared:lyrics/Lrc.kt:15-19, sharedTest:lyrics/LrcTest.kt:56-61)
- [x] Timed lines are sorted by start, and leading gaps are dropped; if every timed line is a gap the result is null (shared:lyrics/Lrc.kt:59-66, sharedTest:lyrics/LrcTest.kt:115-122)
- [x] Text with no line stamps is plain: tag rows skipped, runs of blank rows folded into one blank row (a verse break), leading blanks dropped, trailing blanks dropped; nothing left is null (shared:lyrics/Lrc.kt:68-76, sharedTest:lyrics/LrcTest.kt:101-106)

## 6. Lyrics in the song file's tags

- [x] Tag names read (case-insensitive): `LYRICS`, `LYRICS:<description>`, `UNSYNCEDLYRICS`, `UNSYNCED LYRICS`, `SYNCEDLYRICS` (synced SYLT frames are not read) (shared:lyrics/SongFileLyrics.kt:3-8)
- [x] Values are ordered by that list (a `LYRICS:` tag ranks as `LYRICS`), blank values dropped; the first value that looks timed wins, else the first value (shared:lyrics/SongFileLyrics.kt:10-22, sharedTest:lyrics/LyricsTest.kt:45-53)
- [x] "Looks timed" means some row starts (after spaces) with `[` + 1 to 3 digits + `:` + 1 to 2 digits (shared:lyrics/SongFileLyrics.kt:24-27)
- [x] The chosen text is parsed by the LRC parser with source SongFile (app:lyrics/LyricsRepository.kt:483-485)

## 7. Lyrics from the server (structured lyrics)

- [x] The main lyrics are entries whose kind is missing or "main" and that have a non-blank line; the best is scored synced 2 plus word cues 1, highest wins (shared:lyrics/ServerLyrics.kt:15-16)
- [x] No main lyrics: null (shared:lyrics/ServerLyrics.kt:16, sharedTest:lyrics/ServerLyricsTest.kt:132-136)
- [x] Not synced: plain lyrics, each line's value trimmed (shared:lyrics/ServerLyrics.kt:17-19)
- [x] Synced: each line's start (missing reads as 0); a line with no cue lines is timed by line with its trimmed value (shared:lyrics/ServerLyrics.kt:23-26)
- [x] Cue lines are matched to lyric lines by `index`; cue lines whose agent's role is "bg" are backing, the rest are leads (shared:lyrics/ServerLyrics.kt:21-27)
- [x] Several leads (or several backings) on one line join into one text with a single space between; each cue line's leading spaces are cut and its words keep their places in the joined text; words wholly inside the cut are dropped (shared:lyrics/ServerLyrics.kt:67-83, sharedTest:lyrics/ServerCuesTest.kt:61-87)
- [x] Only backing voices on a line: the line's text and words are the backing's, `background = true`, end = latest cue-line end (shared:lyrics/ServerLyrics.kt:32-40, sharedTest:lyrics/ServerLyricsTest.kt:105-123)
- [x] With a lead: text and words from the leads, backing text and words from backings, `agent` = the first lead's agent name, `duet = true` when the first lead's agent role is "voice", end = the latest of each cue line's end (or its latest cue end) (shared:lyrics/ServerLyrics.kt:30-31, 41-51)
- [x] Cue positions are UTF-8 byte offsets, both ends inclusive; they are turned into character ranges covering whole letters (an end inside a multi-byte letter takes the whole letter; a 4-byte letter is 2 Java chars); a cue outside the text or backwards is dropped (shared:lyrics/ServerLyrics.kt:85-136, sharedTest:lyrics/ServerLyricsTest.kt:15-50)
- [x] A cue's end is its own end, else the next cue's start, else the cue line's end (shared:lyrics/ServerLyrics.kt:94, sharedTest:lyrics/ServerLyricsTest.kt:52-56)
- [x] The server's `offset` (ms, above zero = sooner) shifts every time by `-round(offset)`, clamped at 0 (shared:lyrics/ServerLyrics.kt:57-61, sharedTest:lyrics/ServerLyricsTest.kt:86-103)
- [x] Translation: only when the phone's language (the device locale's language) is given and is not the song's language; the first entry of kind "translation" in the phone's language; matched line by line when it has the same number of lines, else by identical start times; blank lines skipped, values trimmed (shared:lyrics/ServerLyrics.kt:55, 138-158, sharedTest:lyrics/ServerLyricsTest.kt:99-103)
- [x] Romanization: the first entry of kind "pronunciation" in any language, only when the phone reads another language than the song; matched the same way (shared:lyrics/ServerLyrics.kt:56, 143-158)
- [x] Languages match whether written in 2 or 3 letters ("en" = "eng", "fra" = "fr"), `_` read as `-` (shared:lyrics/ServerLyrics.kt:160-173, sharedTest:lyrics/ServerLyricsTest.kt:139-144)
- [x] The phone language passed is `Locale.getDefault().language` (app:lyrics/LyricsRepository.kt:533) (iPhone: the phone's own first language, whatever languages the app itself is written in)
- [x] Older servers (no `songLyrics` extension) are asked with `getLyrics` by artist and title (the server copy's artist/title when known, else the song's) and the plain text answer is parsed as LRC or plain (app:lyrics/LyricsRepository.kt:530-532, app:lyrics/ServerChoices.kt:47-54) (iPhone: one server in use, so the song's own artist and title are the server copy's)

## 8. The online library (LRCLIB)

- [x] Base address `https://lrclib.net`; requests go through the app's shared HTTP client, which already names the app; no key (shared:lyrics/OnlineLyrics.kt:24-26, 50-52, app:di/LyricsModule.kt:10-17) (iPhone: URLSession with the app's own user agent)
- [x] Exact lookup: `GET /api/get?track_name=<title>&artist_name=<artist>` plus `album_name` only when the album is non-blank and `duration=<round(ms / 1000)>` only when the length is above 0 (shared:lyrics/OnlineLyrics.kt:253-265, sharedTest:lyrics/LyricsTest.kt:55-64)
- [x] Search: `GET /api/search?track_name=<title>&artist_name=<artist>` (no duration) (shared:lyrics/OnlineLyrics.kt:135-141, sharedTest:lyrics/LyricsTest.kt:115-121)
- [x] Free search typed by hand: `GET /api/search?q=<trimmed words>` (shared:lyrics/OnlineLyrics.kt:188-193)
- [x] By number: `GET /api/get/<id>` (shared:lyrics/OnlineLyrics.kt:195-200)
- [x] HTTP 404 means "the library has nothing"; any other non-success throws an I/O error "Lyrics lookup failed: HTTP <code>"; a cancelled lookup cancels its request (shared:lyrics/OnlineLyrics.kt:111-132)
- [x] An answer's lyrics: instrumental gives empty instrumental lyrics (not synced); else the synced text if it parses as synced, else the plain text; the copy's number is kept as `onlineId` (shared:lyrics/OnlineLyrics.kt:244-251, sharedTest:lyrics/LyricsTest.kt:66-76)
- [x] Automatic find: the exact lookup first; if it is synced or instrumental it wins; otherwise the search is asked with up to 3 query variants (from SongIdentity's variants that keep an artist), in order, until one gives a timed match (shared:lyrics/OnlineLyrics.kt:54-75, 143-164, sharedTest:lyrics/LyricsMatchTest.kt:73-97)
- [x] During find, a search that cannot be reached is thrown only when the exact lookup found nothing; with plain lyrics from the exact lookup, they stand; a 404 search moves to the next variant (shared:lyrics/OnlineLyrics.kt:65-73, sharedTest:lyrics/OnlineCopiesTest.kt:43-57)
- [x] Best search match: only copies with non-blank synced lyrics, the same song as lyrics read it (title whole, ignoring case, accents, punctuation, stylized letters, guests and upload noise; a "clean" edit counts as the song; remixes, live takes and other versions never do; the artist must match), and, when the song's length is known, a copy length within 3.0 s; sorted same album (case-insensitive) first, then nearest length; the first that parses as synced (shared:lyrics/OnlineLyrics.kt:43-44, 146-186, sharedTest:lyrics/LyricsTest.kt:78-113, sharedTest:lyrics/LyricsMatchTest.kt:30-62)
- [x] Copies to choose from: the search with each variant in turn (only the first request's failure is thrown; a later failure ends the loop), keeping copies with an id and words whose title and artist are not a different song (live takes and remixes stay), from the first variant that has any; ranked timed first, then same album (album non-blank), then nearest length (unknown length last) (shared:lyrics/OnlineLyrics.kt:83-97, 213-227, sharedTest:lyrics/OnlineCopiesTest.kt:65-77)
- [x] The library's own match for the chooser: the exact lookup as a copy (needs an id and words; length = round(duration x 1000) or 0) (shared:lyrics/OnlineLyrics.kt:77-81, 236-242, sharedTest:lyrics/OnlineCopiesTest.kt:31-41)
- [x] A typed search keeps every copy with words, unfiltered, in the library's order (shared:lyrics/OnlineLyrics.kt:99-103, sharedTest:lyrics/OnlineCopiesTest.kt:79-89)
- [x] The length the library is asked with is the real length learned by playing when it corrected the listing, else the listed length (app:lyrics/LyricsRepository.kt:491-494)

## 9. The lookup order

- [x] Before any source: the phone's choice for the song and the "Find lyrics online" setting are read; failing to read them is Failed; a hidden song answers None (app:lyrics/LyricsRepository.kt:176-187) (iPhone: the choice and the setting are plain reads that cannot fail; a hidden song answers None)
- [x] The song's facts are the library's own (catalog track, or the online find for a found song) with any blank field filled from the player's, and a length of 0 replaced by the player's (app:lyrics/LyricsRepository.kt:496-509)
- [x] The phone file is the first copy of the song on the phone (`DEVICE` source) with a content address; a found song (`find:` id) has no copies (app:lyrics/LyricsRepository.kt:192-194) (iPhone: the first copy on the phone with an address: a Music app song or a file brought in from Files)
- [x] A pick made on this phone is tried first: Online(id) fetches `/api/get/<id>` only when online lookups are on; OnServer and Own(Server) ask the server; Own(SongFile) reads the file's tags; Own(LyricsFile) reads the .lrc; Own(Online) is nothing; non-empty lyrics win at once and are saved as the pick's answer (complete, asked online) (app:lyrics/LyricsRepository.kt:195-206, 425-442)
- [x] A pick whose source no longer has the lyrics (or errors) falls back to the usual order, and the pick is tried again next time (app:lyrics/LyricsRepository.kt:168-175, 195-206)
- [x] The usual order: the server, then the song file's tags, then a .lrc file beside the song, then LRCLIB (only when online lookups are on and title and artist are non-blank) (app:lyrics/LyricsRepository.kt:207-219, app:lyrics/ServerChoices.kt:56-78)
- [x] Each source is asked in turn: the first synced lyrics win at once; plain lyrics are kept while later sources are asked for synced ones, and the first plain ones win if none are synced; empty lyrics count as none (app:lyrics/LyricsRepository.kt:84-116, appTest:lyrics/LyricsSearchTest.kt:30-85)
- [x] A source that throws or is cut off by its own time limit is skipped and marks the search incomplete; a stop from outside stops the whole search (app:lyrics/LyricsRepository.kt:96-107, appTest:lyrics/LyricsSearchTest.kt:87-118)
- [x] `askedOnline` is set once the Online step is reached, whatever it answers (app:lyrics/LyricsRepository.kt:95)
- [x] When the song is on a server that keeps lyrics choices (section 10), the server's answer is final: plain lyrics from it are used as they are; LRCLIB is asked only when the server step did not answer (threw); a server "none" is marked unsure (app:lyrics/ServerChoices.kt:56-78, appTest:lyrics/ServerChoicesTest.kt:255-300, appTest:lyrics/LyricsSearchTest.kt:120-128)
- [x] The server step needs the saved sign-in; it waits up to 3000ms for it to come back at app start, and for a lookup a sign-in still not back is an I/O error (incomplete), not "not on the server" (app:lyrics/LyricsRepository.kt:46-47, 511-520, 544-548) (iPhone: the saved sign-in and the extensions it saved; it waits up to 3 s for the sign-in to come back)
- [x] A song is on the server when it has a copy whose source id is the signed-in server's, or it is a found song (its server id is the `find:` id without the prefix) (app:lyrics/LyricsRepository.kt:514-520)
- [x] Server call by extensions: no `songLyrics:<n>` listed gives the older by-name call; highest version 2 or more gives `getLyricsBySongId` with `enhanced=true`; version 1 gives it without (app:lyrics/ServerChoices.kt:35-54, appTest:lyrics/ServerChoicesTest.kt:56-61)
- [x] Server "not found" is no lyrics; server unreachable is an I/O error "Server unreachable" (app:lyrics/LyricsRepository.kt:535-539)
- [x] Server lyrics carry `serverPick` when this phone has heard the server has a copy pinned for the song (app:lyrics/LyricsRepository.kt:540-541)

## 10. Lyrics choices kept on the server

- [x] A server keeps choices for every app when its extensions list `octoLyrics:1` (app:lyrics/ServerChoices.kt:31-33, subsonic:LyricsPins.kt:8)
- [x] Whether it keeps them is remembered per server for 30 minutes; else it is true when listed at sign-in; else the server is asked (`supportsIfKnown("octoLyrics")`): a yes or no is remembered, no answer (unreachable, busy proxy, refused sign-in) is treated as no and not remembered (app:lyrics/LyricsRepository.kt:49-51, 463-481, subsonic:SubsonicClient.kt:110-127)
- [x] Choice values: "auto" (the server finds them), "none" (hidden), or a copy id like "kugou:123" (subsonic:LyricsPins.kt:10-15)
- [x] A pick or hide made on this phone wins on this phone over whatever the server chose (app:lyrics/ServerChoices.kt:13-15)
- [x] Choosing a server copy or Automatic sends it to the server (`setLyricsChoice`), then forgets the song's saved answer, then clears this phone's pick and hide for the song; a refresh then fetches the song's lyrics again at once (app:lyrics/ServerChoices.kt:16-18, 192-211, app:lyrics/LyricsRepository.kt:242-265)
- [x] Hiding on a server that keeps choices sends "none" and hides on this phone too, keeping the phone's pick; showing again sends "auto" and removes the phone's hide, keeping its pick (app:lyrics/ServerChoices.kt:19-21, 206-210, appTest:lyrics/ServerChoicesTest.kt:208-216)
- [x] When the server refuses a choice, it throws and nothing on the phone changes (no forget, pick kept) (app:lyrics/ServerChoices.kt:192-195, appTest:lyrics/ServerChoicesTest.kt:218-231)
- [x] Hide and show fall back to the phone alone when the song is not on such a server or the server could not take it (app:lyrics/LyricsRepository.kt:267-293)
- [x] The server's answer to setLyricsChoice is remembered as the song's pin ("auto" and "none" clear the pin) (app:lyrics/LyricsRepository.kt:255-259, 455-461)
- [x] A server without the extension changes nothing: every choice stays on the phone (app:lyrics/ServerChoices.kt:28-29)
- [x] A saved answer is stale (forgotten and fetched again) when the server's choice moved elsewhere: never for an answer this phone picked; for "auto", stale when the saved server lyrics carry a pin; for "none", stale when saved lyrics are from the server; for a copy id, stale when saved lyrics are not from the server or carry another pin (app:lyrics/ServerChoices.kt:168-181, appTest:lyrics/ServerChoicesTest.kt:233-253)
- [x] Source names: "kugou" KuGou, "lrclib" LRCLIB, "netease" NetEase, "lyricsovh" Lyrics.ovh, "" or "pinned" "your server", any other the key trimmed with its first letter upper-cased (app:lyrics/ServerChoices.kt:80-88)
- [x] The menu's source line: for server lyrics with a pin, "From <name of the pin's prefix>", else the source label; plus ", word by word" when any line has words ("From KuGou, word by word", "From your server", "From LRCLIB") (app:lyrics/ServerChoices.kt:90-96, appTest:lyrics/ServerChoicesTest.kt:302-315)
- [x] A typed server search "artist - title" (split on the first " - ", both sides non-empty after trimming) asks for that title and artist; anything else is a title by the song's own artist ("- Café" is a title) (app:lyrics/ServerChoices.kt:183-190, appTest:lyrics/ServerChoicesTest.kt:317-322)

## 11. Saved answers and when they are asked again

- [x] Each song's answer is kept in memory (the 32 most recently used) in front of a cache folder `<app cache>/lyrics/`, one JSON file per song named by the SHA-1 hex of the song id plus `.json`; unknown JSON keys are ignored; the system may clear the folder (app:lyrics/LyricsAnswers.kt:26-29, app:lyrics/LyricsCache.kt:80-116, app:lyrics/LyricsRepository.kt:153)
- [x] A cache file is written beside itself as `<name>.tmp` then renamed over the old one (delete and rename again if the rename fails); read and write errors are ignored (app:lyrics/LyricsCache.kt:92-104)
- [x] A saved entry holds: saved time, lyrics or none, asked online, lookup version, the pick it came from, unsure, away (app:lyrics/LyricsCache.kt:34-52)
- [x] A saved answer stands for the current pick when: with a pick, it was saved for that same pick and has lyrics; with no pick, it was saved with no pick and is still good (app:lyrics/LyricsCache.kt:53-57, appTest:lyrics/LyricsChoicesTest.kt:121-135)
- [x] It is not used when the lyrics view has just come back (`resumed`) and it is a "none" saved while away (app:lyrics/LyricsAnswers.kt:45, app:lyrics/LyricsCache.kt:59-61, appTest:lyrics/LyricsAnswersTest.kt:111-129)
- [x] Still good, rule 1: server lyrics (not instrumental) with no word timing on any line are asked again when saved before lookup version 4, or saved 1 hour (3,600,000ms) ago or more (app:lyrics/LyricsCache.kt:20-28, 69-72, appTest:lyrics/LyricsStorageTest.kt:27-41)
- [x] Still good, rule 2: with online lookups on, an answer that never asked online and is not synced lyrics (a none, or plain) is asked again (app:lyrics/LyricsCache.kt:73, appTest:lyrics/LyricsStorageTest.kt:59-65)
- [x] Still good, rule 3: with online lookups on, plain lyrics saved before lookup version 4 are asked again (app:lyrics/LyricsCache.kt:74, appTest:lyrics/LyricsStorageTest.kt:67-71)
- [x] Still good, rule 4: with online lookups on, LRCLIB lyrics saved by lookup version 2 (the loose length-only match) are asked again, even when timed (app:lyrics/LyricsCache.kt:30-32, 75, appTest:lyrics/LyricsStorageTest.kt:73-79)
- [x] Still good, rule 5: otherwise lyrics stand forever (app:lyrics/LyricsCache.kt:76)
- [x] Still good, rule 6: a "none" stands 24 hours (86,400,000ms), or 10 minutes (600,000ms) when unsure (a server that looks lyrics up itself said none) or saved while the lyrics were not on screen (app:lyrics/LyricsCache.kt:8-14, 76, appTest:lyrics/LyricsAnswersTest.kt:73-109)
- [x] The current lookup version is 4 (app:lyrics/LyricsCache.kt:16-18)
- [x] A search that failed outright, or found nothing while a source failed, is Failed and saves nothing (an older answer stays as it was) (app:lyrics/LyricsAnswers.kt:50-61, appTest:lyrics/LyricsAnswersTest.kt:28-71)
- [x] A finished search is saved in memory always and to disk only when every source answered; lyrics found while a source failed are shown but kept in memory only (app:lyrics/LyricsAnswers.kt:63-76)
- [x] The saved entry is unsure only when there are no lyrics and the search was unsure, and away when nothing showed the lyrics at save time (app:lyrics/LyricsAnswers.kt:63-71)
- [x] Picking lyrics on the phone saves them as the song's answer (now, asked online, version 4, the pick) before saving the pick, so the view finds them at once (app:lyrics/LyricsRepository.kt:225-240)

## 12. Choices kept on this phone

- [x] Stored in a preferences store "lyrics_choices" with keys `pick:<trackId>` (string) and `hidden:<trackId>` (boolean), only for songs the listener changed (app:lyrics/LyricsChoices.kt:27-33) (iPhone: a UserDefaults suite named lyrics_choices with the same keys)
- [x] Pick encodings: "own:Server", "own:SongFile", "own:LyricsFile", "online:<number>", "server:<choice>"; anything else (including "own:Online", "online:abc", "server:") reads as no pick (app:lyrics/LyricsChoices.kt:47-64, appTest:lyrics/LyricsChoicesTest.kt:97-107, appTest:lyrics/ServerChoicesTest.kt:324-329)
- [x] Picking replaces the last pick and removes the hide (app:lyrics/LyricsChoices.kt:87-94)
- [x] Hiding keeps the pick for when they are shown again; showing removes only the hide (app:lyrics/LyricsChoices.kt:96-104)
- [x] Clearing removes the pick and the hide (or sets hidden when asked to keep it hidden) (app:lyrics/LyricsChoices.kt:106-114)
- [x] Lyrics name their own pick: LRCLIB lyrics by their number (none when the number was not kept), any other source as Own(source) (app:lyrics/LyricsChoices.kt:66-71)

## 13. A .lrc file beside the song

- [x] Names tried: the song file's name without its last extension plus `.lrc` and `.LRC`; a name without an extension has none (app:lyrics/LyricsFiles.kt:74-80, appTest:lyrics/LyricsStorageTest.kt:14-19)
- [x] The phone's media library is asked first (same relative folder and one of those names), then the file path beside the song (app:lyrics/LyricsFiles.kt:20-32, 51-71) (iPhone: the Music app keeps no folders, so a .lrc file is looked for beside a song file brought in from Files)
- [x] Files over 1 MiB are not lyrics (app:lyrics/LyricsFiles.kt:17-18, 82-93)
- [x] Text is read as strict UTF-8, else as Windows-1252 (app:lyrics/LyricsFiles.kt:95-105, appTest:lyrics/LyricsStorageTest.kt:21-25)
- [x] Parsed with the LRC parser, source LyricsFile (app:lyrics/LyricsRepository.kt:487-489)

## 14. Server API calls and models

- [x] `getLyricsBySongId?id=<id>` plus `enhanced=true` only when asking for word timings; answer key `lyricsList.structuredLyrics` (subsonic:SubsonicClient.kt:510-520, subsonicTest:LyricsClientTest.kt)
- [x] Structured lyrics fields: `lang` (default "und"), `synced`, `line[{start?, value}]`, `displayArtist`, `displayTitle`, `offset` (ms, default 0), `kind` ("main", "translation", "pronunciation"; missing = main), `agents[{id, role ("main", "voice", "bg", "group"), name?}]`, `cueLine[{index, agentId?, start?, end?, value, cue[{start, end?, value, byteStart, byteEnd}]}]` (subsonic:Models.kt:443-500)
- [x] `getLyricsCandidates?id=<id>` plus `title` and `artist` only when non-blank after trimming; answer key `lyricsCandidates` with `id`, `choice` (default "auto"), `candidate[{id, source, title, artist, album?, duration? (s), kind ("word", "line", "plain", "instrumental"), sameSong, chosen, preview[]}]` (subsonic:LyricsPins.kt:17-61, subsonic:SubsonicClient.kt:522-526)
- [x] `setLyricsChoice?id=<id>&candidate=<choice>`; answer key `lyricsChoice.choice` (defaults to what was sent) (subsonic:SubsonicClient.kt:528-539)
- [x] Older `getLyrics?artist=&title=`; answer key `lyrics.value`, blank is none (subsonic:SubsonicClient.kt:541-550)
- [x] A server with lookups switched off answers getLyricsCandidates with a server error ("Lyrics lookups are off on this server"); the phone then remembers the server does not keep choices (30 minutes) and builds the local list (subsonicTest:LyricsPinsTest.kt, app:lyrics/LyricsRepository.kt:334-336)

## 15. Flowing: from lyrics to lines

- [x] Only synced, non-instrumental lyrics map; plain gives no lines and the flowing view draws nothing (shared:lyrics/engine/LyricMapper.kt:30-31, app:player/FlowingLyrics.kt:158-159)
- [x] Lines are sorted by start; credit lines from the source are skipped when they match (case-insensitive) "written by", "lyrics by", "words by", "music by", "composed by", "composer", "lyricist", 作词, 作詞, 作曲, 编曲, 編曲, 词, 詞 or 曲 followed by `:` or `：`, and have no word timings (shared:lyrics/engine/LyricMapper.kt:20-24, 32)
- [x] All times become seconds (ms / 1000.0) (shared:lyrics/engine/LyricMapper.kt:232)
- [x] A lead line: trimmed text; end = its own end, else its last word's end, else the next line's start, else start + 5.0 s (shared:lyrics/engine/LyricMapper.kt:17-18, 94-112, 172-174)
- [x] Words cover a line only when the words' letters (whitespace removed) joined equal the line's letters; otherwise the line is timed by line (shared:lyrics/engine/LyricMapper.kt:151-157, sharedTest:lyrics/engine/LyricMapperTest.kt:110-114)
- [x] Blank word pieces are dropped; each word's end is its own end, else the next piece's start (in the original list), else the line end, never before its start (shared:lyrics/engine/LyricMapper.kt:158-168)
- [x] A word has a trailing space (ends a group that may wrap) when it is the last, its text ends with whitespace, the next starts with whitespace, or the line text between them has whitespace; syllables of one word sit flush (shared:lyrics/engine/LyricMapper.kt:163-168, sharedTest:lyrics/engine/LyricMapperTest.kt:72-99)
- [x] A line timed by line gets one word spanning the whole text, start to end, with a trailing space, and `isLineTimed = true` (no fill word by word, no bloom) (shared:lyrics/engine/LyricMapper.kt:102, 110, sharedTest:lyrics/engine/LyricMapperTest.kt:101-108)
- [x] Right to left comes from the first letter with a strong direction: right-to-left (Hebrew, Arabic, Syriac, Thaana, N'Ko) gives true, left-to-right gives false, none gives false (shared:lyrics/engine/LyricMapper.kt:180-193, sharedTest:lyrics/engine/LyricMapperTest.kt:24-34)
- [x] A line is set against the right edge when `rtl xor duet` (shared:lyrics/engine/SyncLyrics.kt:39-41)
- [x] Translation kept only when non-empty and not the same as the text ignoring whitespace and case; romanization kept only when non-empty and not the same as the text or the translation (shared:lyrics/engine/LyricMapper.kt:106-108, 195-197)
- [x] Translations and romanizations are carried only by lead lines; backing lines and interludes never show them (shared:lyrics/engine/LyricMapper.kt:94-148)
- [x] The singer's name (`agent`) is not shown in the flowing view; only `duet` (which side) and `background` (smaller, quieter) are used (shared:lyrics/engine/LyricMapper.kt:94-133, shared:lyrics/engine/SyncLyrics.kt:15-38)
- [x] A line only backing voices sing (background, or blank text) becomes a background line from its text or its backing text (shared:lyrics/engine/LyricMapper.kt:53-58)
- [x] Background lines lose one pair of wrapping brackets `(` `)` or full-width `（` `）` from the text, and from the first and last words when both carry them; words left empty go; the last kept word gets a trailing space (shared:lyrics/engine/LyricMapper.kt:114-133, 199-226, sharedTest:lyrics/engine/LyricMapperTest.kt:154-172)
- [x] A background line starts at its first word (else the line start) and ends at its latest word end (else the line end) (shared:lyrics/engine/LyricMapper.kt:120-121)
- [x] Backing vocals under a lead line become their own line right after it, on the lead's side (`isDuet` = the lead's), starting no earlier than the lead (shared:lyrics/engine/LyricMapper.kt:72-77)
- [x] Before each sung line (unless an interlude was just added), the wait since the last sung line's end (or since 0 for the first) is checked: 4.0 s or more adds an interlude for it (so a first line at 4 s or later gets dots before it); less stretches the last sung line's end to this line's start (never shortens it) (shared:lyrics/engine/LyricMapper.kt:7-11, 60-68, 176-178, sharedTest:lyrics/engine/LyricMapperTest.kt:116-147)
- [x] An empty source line (a gap marked on purpose) becomes an interlude from its start to the next non-gap line's start when that is 2.0 s or more, after stretching the last sung line to the gap's start; shorter marked gaps add nothing; a gap with no sung line after it adds nothing (shared:lyrics/engine/LyricMapper.kt:13-15, 41-51, sharedTest:lyrics/engine/LyricMapperTest.kt:139-152)
- [x] An interlude has empty text and no words and takes the side (rtl, duet) of the line after it (shared:lyrics/engine/LyricMapper.kt:135-148)
- [x] A "Written by A, B & C" credit line (start = the latest end, never ends) is only added when writers are passed; the Android app never passes writers, so no credit line appears on Android (shared:lyrics/engine/LyricMapper.kt:80-90, 228-230, app:player/FlowingLyrics.kt:158)
- [x] Lines are numbered 0..n-1 in the final order (shared:lyrics/engine/LyricMapper.kt:91)

## 16. Flowing: sizes, margins and wrapping

- [x] Main font size: view width in dp / 13, clamped to 22..36 sp (about 30 sp on a typical phone); em in pixels = size x font scale x density (the clamp is before the user's text scale) (app:player/FlowingLyricsText.kt:18-20, 86-89) (iPhone: points, and Dynamic Type as the font scale)
- [x] Left margin = 6% of the view width clamped to 24..48dp; right margin = 4% clamped to 16..56dp; available text width = width - left - right (at least 1px) (app:player/FlowingLyricsText.kt:90-92)
- [x] Worked example from these rules: a 412dp-wide view gives a 31.69sp line, left 24.72dp, right 16.48dp, 370.8dp of text width; a 393pt-wide iPhone view gives 30.23, left 24, right 16, 353 (app:player/FlowingLyricsText.kt:86-92)
- [x] Font: the default family, ExtraBold (800) for lead and backing lines, SemiBold (600) for the credit and for translations and romanizations (app:player/FlowingLyricsText.kt:93, 136-139, 164-169)
- [x] Backing (background) lines use em = max(0.75 em, 12dp); the credit uses em = max(0.4 em, 13dp); every line's padding, gaps and extras scale from its own em (app:player/FlowingLyricsText.kt:29-32, 94-95, 131-135)
- [x] Row height 1.2 em; padding 0.25 em above the first row and below the last thing in the line; gap after each whole word 0.25 em (app:player/FlowingLyricsText.kt:23-25, 140, 176)
- [x] An interlude is 10dp tall closed and 1.2 em + 2 x 0.25 em = 1.7 em open (app:player/FlowingLyricsText.kt:34-35, 96-97)
- [x] Lines timed by line, the credit, or lines with no words are laid out as one text block exactly `available` wide, soft-wrapped by the text engine, line height 1.2 em, aligned right for right-side lines and left otherwise, text direction RTL for rtl lines; height = padding + block height (app:player/FlowingLyricsText.kt:141-157)
- [x] Word-timed lines: each word measured alone on one line with no wrapping (app:player/FlowingLyricsText.kt:183)
- [x] Words group into whole sung words: a group ends at a word with a trailing space, or at the last word (app:player/FlowingLyricsText.kt:187-195)
- [x] Groups fill rows greedily: a group starts a new row when the row has something and `used + groupWidth > available`, where `used` is the sum of the row's groups plus one 0.25 em gap after each; a group is never broken, so one group wider than the available width sits alone on its row and runs past the right margin (clipped only at the view's edge) (app:player/FlowingLyricsText.kt:196-208)
- [x] A line with no spaces between its timed words (Japanese, Chinese) is one group and never wraps (sharedTest:lyrics/ServerCuesTest.kt:43-47, app:player/FlowingLyricsText.kt:188-195)
- [x] Row r's top is padding + r x 1.2 em; its width is the sum of its words plus a gap between groups (app:player/FlowingLyricsText.kt:211-213)
- [x] A row starts at the left margin, or for right-side lines at left + available - row width (hugging the right edge) (app:player/FlowingLyricsText.kt:214)
- [x] Left-to-right lines place words left to right; rtl lines place them from the row's right end leftward (app:player/FlowingLyricsText.kt:215-225)
- [x] Each word is centered vertically in its row: top = row top + (1.2 em - word height) / 2 (app:player/FlowingLyricsText.kt:221)
- [x] The line's main height is the bottom of its last row (app:player/FlowingLyricsText.kt:159-160)
- [x] Romanization then translation (in that order) follow under the line, each after a 0.1 em gap, at 0.5 em of the line's em, SemiBold, line height 1.3, the line's alignment, soft-wrapped `available` wide at the left margin (app:player/FlowingLyricsText.kt:26-28, 163-175)
- [x] Total line height = bottom of the last part + 0.25 em padding (app:player/FlowingLyricsText.kt:176)
- [x] The line grows and shrinks from its text's start edge: pivot x = left margin, or left + available for right-side lines (app:player/FlowingLyricsText.kt:65-66, 127)
- [x] Held words (1.0 s or longer) of lines near the focus are split into letters by grapheme cluster (accents stay on their letters), blank letters skipped, each letter measured alone and placed at its x inside the laid-out word; rtl words stay one whole piece, since joined letters would break (app:player/FlowingLyricsText.kt:110-123, 230-251)

## 17. Flowing: the view host, measuring and the frame loop

- [x] The view fills its space and clips everything to its bounds (app:player/FlowingLyrics.kt:189)
- [x] Layout is measured off the main pass, in slices of at most 4ms per frame, so opening lyrics never stalls a frame (app:player/FlowingLyrics.kt:110-112, 192-203) (iPhone: measured off the main thread altogether, so no frame stalls)
- [x] After a size or density change, layout waits 150ms of stillness before measuring again (only when already laid out) (app:player/FlowingLyrics.kt:107-108, 193) (iPhone: Dynamic Type changes lay the lines out again)
- [x] Once measured, the engine gets the line heights, the interlude's closed and open heights and the view height; every line then jumps into place (app:player/FlowingLyrics.kt:204-206, shared:lyrics/engine/LyricEngine.kt:97-105)
- [x] The whole view fades from 0 to 1 over 450ms (default easing, ease in-out) the first time it is laid out (app:player/FlowingLyrics.kt:104-105, 185, 207, 274)
- [x] New lyrics (another song, another pick) start from scratch: new lines, a new engine, layout cleared, the fade back at 0 and run again once measured (app:player/FlowingLyrics.kt:158-160, 184-186)
- [x] One frame loop drives everything every display frame; it runs only while the app is in the foreground and restarts fresh (clock reset, everything jumps) when it comes back (app:player/FlowingLyrics.kt:211-231, shared:lyrics/engine/LyricEngine.kt:107-112) (iPhone: a display link; it rests only while the app is in the background)
- [x] When nothing moved last frame, nothing is playing and nothing is scrolling, the loop waits 32ms between frames instead of every frame (app:player/FlowingLyrics.kt:114-116, 229, shared:lyrics/engine/LyricEngine.kt:283) (iPhone: the display link drops to 30 fps while nothing moves)
- [x] The song offset and output offset are read afresh every frame, so a timing step moves the words on the next frame without a restart (app:player/FlowingLyrics.kt:169-174, appTest:lyrics/engine/LyricTimingLiveTest.kt)
- [x] The clock is told to take a fresh anchor whenever the player reports a time change (a seek, a new song, play or pause, a new speed) and when playing state or track changes (app:player/FlowingLyrics.kt:176-179, app:playback/PlaybackConnection.kt:69-99)
- [x] Only lines on screen (by the on-screen test) plus the focus line are built as views; that range changes as lines come and go (shared:lyrics/engine/LyricEngine.kt:313-325, app:player/FlowingLyrics.kt:253-261)
- [x] Every line is placed at the view's top-left with the view's full width and its own height (an interlude at its open height) and moved by its layer (app:player/FlowingLyrics.kt:286-293, 313, 319-322)
- [x] Reduced motion here means the app's Reduce motion setting or the phone's animations being off (animator duration scale 0), re-read when the app resumes (app:player/FlowingLyrics.kt:161-162, app:ui/common/ReduceMotion.kt:21-35) (iPhone: iOS Reduce Motion stands in for the animator scale, followed live)

## 18. Flowing: the lyrics clock

- [x] The player's reported position anchors a clock that runs on from there on the phone's steady clock at the playback speed: shown = anchor + elapsed x rate (shared:lyrics/engine/LyricClock.kt:25-34, 142-149, sharedTest:lyrics/engine/LyricClockTest.kt:9-21)
- [x] The output timing is the clock's latency, subtracted from the time: lyric time = player time - output offset; minus shows words sooner (shared:lyrics/engine/LyricClock.kt:31-35, 123)
- [x] The song's offset is subtracted on top: lyric time `t` = clock time - song offset (shared:lyrics/engine/LyricEngine.kt:143-147, sharedTest:lyrics/engine/LyricEngineTest.kt:63-70)
- [x] Paused (not playing, or the reported position the same for 6 frames in a row): the player's own position minus the latency, not projected, and the anchor dropped (shared:lyrics/engine/LyricClock.kt:13-15, 103-111, sharedTest:lyrics/engine/LyricClockTest.kt:46-60)
- [x] A new anchor is taken when not anchored, when asked, or (carrying on from the projection) when the speed changed (shared:lyrics/engine/LyricClock.kt:113-117)
- [x] When the projection and the player disagree by more than 0.15 s, the player wins (re-anchored, not counted as a seek) (shared:lyrics/engine/LyricClock.kt:6-8, 119-122, sharedTest:lyrics/engine/LyricClockTest.kt:23-33)
- [x] The shown time never goes below 0 (shared:lyrics/engine/LyricClock.kt:126)
- [x] A jump of more than 0.6 s from the last frame's shown time is a seek (shared:lyrics/engine/LyricClock.kt:10-11, 136, sharedTest:lyrics/engine/LyricClockTest.kt:35-44)
- [x] After a tap to seek, the tap's target (the player time) minus latency shows until the player is within 0.5 s of it or 2.5 s have passed (shared:lyrics/engine/LyricClock.kt:17-20, 90-95, 128-134, sharedTest:lyrics/engine/LyricClockTest.kt:62-86)
- [x] The step given to springs is the time since the last frame, clamped to 0..0.05 s; the first frame's step is 0 (shared:lyrics/engine/LyricClock.kt:22-23, 100, sharedTest:lyrics/engine/LyricClockTest.kt:88-96)
- [x] A changed output timing shifts the last time by the difference and takes a fresh anchor, so the change is not a seek and the lines glide instead of jumping; the same value again changes nothing (shared:lyrics/engine/LyricClock.kt:80-88, appTest:lyrics/engine/OutputTimingTest.kt:93-138)
- [x] Reset (the view coming back) drops the anchor, the last reported value, the still count, the last time and the last frame time, so the next frame is not a seek and has step 0 (shared:lyrics/engine/LyricClock.kt:64-72, sharedTest:lyrics/engine/LyricClockTest.kt:98-107)

## 19. Flowing: springs

- [x] Springs are solved in closed form: each target change solves the curve from the current value, velocity and target once; each frame reads the curve at the elapsed time, so motion is identical at 60 and 120 frames per second (shared:lyrics/engine/Spring.kt:16-21, 147-172, sharedTest:lyrics/engine/SpringTest.kt:88-104)
- [x] Line position spring: mass 1, stiffness 200, damping 28; line scale spring: mass 1, stiffness 260, damping 32; scroll offset spring: mass 1, stiffness 240, damping 28 (all just under critical damping) (shared:lyrics/engine/Spring.kt:174-177, sharedTest:lyrics/engine/SpringTest.kt:138-143)
- [x] At rest when within 0.01 of the target and slower than 0.01 per second; resting snaps exactly to the target with zero velocity (shared:lyrics/engine/Spring.kt:9-11, 127-145)
- [x] Velocity is sampled over a 1/240 s window around the current time (shared:lyrics/engine/Spring.kt:13-14, 63-68)
- [x] A target can wait (`delay`) before it takes over; it takes over at the exact moment inside a frame; a new target replaces one still waiting; moving the target keeps a running wait (shared:lyrics/engine/Spring.kt:70-121, sharedTest:lyrics/engine/SpringTest.kt:106-133)
- [x] Jump puts it at a place, still, dropping any waiting target (shared:lyrics/engine/Spring.kt:92-100)
- [x] Speed s (the Motion speed setting as a fraction) scales stiffness by s x s and damping by s, keeping the damping ratio, and restarts the curve from the current value and velocity; speeds of 0 or less are ignored (shared:lyrics/engine/Spring.kt:47-56, sharedTest:lyrics/engine/SpringTest.kt:120-136)
- [x] Under-damped (ratio below 1) swings in; exactly 1 creeps in; over-damped creeps in on two exponentials (shared:lyrics/engine/Spring.kt:151-172)

## 20. Flowing: the engine, every frame

- [x] Nothing happens until heights, a view height above 0 and at least one line are known (shared:lyrics/engine/LyricEngine.kt:59, 141)
- [x] Places are set outright (snap) on the first frame, after a seek, after a resize and after coming back; with reduced motion, positions and sizes always jump (shared:lyrics/engine/LyricEngine.kt:149-153)
- [x] A seek while scrolling by hand ends the scroll at once (offset jumps to 0) (shared:lyrics/engine/LyricEngine.kt:154)
- [x] The Motion speed setting is applied to every position, scale and scroll spring when it changes (shared:lyrics/engine/LyricEngine.kt:156-164)
- [x] Each line's status: Upcoming before its start, Active from its start until before its end, Passed from its end; several lines can be Active at once (shared:lyrics/engine/LyricEngine.kt:168-175)
- [x] Focus anchors: every line except a backing line that starts before the end of the lead line just above it (not a background or interlude line) (shared:lyrics/engine/LyricEngine.kt:41-47)
- [x] Interludes are focus anchors, so while a gap plays its dots take the focus position (shared:lyrics/engine/LyricEngine.kt:43-47)
- [x] Focus = the last anchorable line whose start is at or before t; before any, the first anchorable line (or 0); while scrolling, the focus held when the finger went down (shared:lyrics/engine/LyricEngine.kt:114-125, 194)
- [x] Focus position: the focus line's middle sits at 33% of the view height (`FOCUS_AT = 0.33`; the code comment's "47%" is outdated); every line is stacked on the heights of the lines above it with no extra gap: `y(i) = above(i) - above(focus) + 0.33 x viewHeight - height(focus) / 2` (shared:lyrics/engine/LyricMotion.kt:20-37, sharedTest:lyrics/engine/LyricMotionTest.kt:8-21)
- [x] Stacking uses unscaled heights; shrinking inactive lines does not close up the gaps (shared:lyrics/engine/LyricEngine.kt:196-197, app:player/FlowingLyrics.kt:372-374)
- [x] An interlude's height is its closed height unless Active; Active, it opens and closes (section 24) (shared:lyrics/engine/LyricEngine.kt:176-191)
- [x] The ripple runs when the focus changed from a known focus, nothing jumped, nobody is scrolling and the Ripple setting is above 0 (shared:lyrics/engine/LyricEngine.kt:198-200)
- [x] Ripple delays: walking down the lines whose new target lies inside the view (0..view height), each waits one step longer than the one above, starting at 0 for the top one; the step is 0.05 s x Ripple fraction and from the focus line down it shrinks by dividing by 1.05 per line; lines off screen do not wait and do not push others back (shared:lyrics/engine/LyricMotion.kt:48-71, sharedTest:lyrics/engine/LyricMotionTest.kt:24-48)
- [x] Worked example: six lines on screen with focus 2 wait 0, 0.05, 0.10, 0.150, 0.198, 0.243 s (sharedTest:lyrics/engine/LyricMotionTest.kt:26-35)
- [x] Line position each frame: jump to the target when jumping; else jump when both the current and the target place are off screen; else, if more than 1.5 view heights away, first jump to 1.5 views short of the target on the same side; then head for the target with the ripple delay, or at once when it was far, or by moving the target without restarting a wait (shared:lyrics/engine/LyricEngine.kt:224-241)
- [x] On screen means `y >= -(height + 0.3 x view height)` and `y <= 1.3 x view height`, with the scroll offset added (shared:lyrics/engine/LyricMotion.kt:39-42, shared:lyrics/engine/LyricEngine.kt:229)
- [x] Growth: the scale spring heads for 1 while the line is Active and 0 otherwise (jumps when jumping); 0 means the inactive size, 1 full size; the spring can overshoot slightly (shared:lyrics/engine/LyricEngine.kt:221-222, shared:lyrics/engine/LineState.kt:10-15)
- [x] Opacity target for an Active line: 1.0 (shared:lyrics/engine/LyricMotion.kt:86-88)
- [x] Opacity target for an Upcoming line: 0.55 (shared:lyrics/engine/LyricMotion.kt:77, 89)
- [x] Opacity target for a Passed line: 0.45 when sung lines are kept (the setting on, or while scrolling by hand), else 0.0 (shared:lyrics/engine/LyricMotion.kt:78, 90, shared:lyrics/engine/LyricEngine.kt:207, sharedTest:lyrics/engine/LyricEngineTest.kt:17-31)
- [x] Blur target: Active 0; otherwise `min(3.0, 0.4 + 0.6 x |line index - focus index|)` dp (1.0 next to the focus, 1.6, 2.2, 2.8, then 3.0) (shared:lyrics/engine/LyricMotion.kt:79, 92-95, shared:lyrics/engine/LyricEngine.kt:246)
- [x] Opacity and blur set outright on a snap; otherwise eased each frame by `current + (target - current) x (1 - e^(-dt / 0.12))`, snapping when within 0.002 (opacity) or 0.01 (blur) (shared:lyrics/engine/LyricMotion.kt:81-101, shared:lyrics/engine/LyricEngine.kt:247-253, sharedTest:lyrics/engine/LyricMotionTest.kt:60-75)
- [x] Opacity and blur keep easing even with reduced motion (only positions and sizes jump) (shared:lyrics/engine/LyricEngine.kt:247-253)
- [x] The press (0..1) moves linearly toward 1 while pressed or held, and toward 0 otherwise, at 1 / 0.08 s per second (shared:lyrics/engine/LineState.kt:6-8, shared:lyrics/engine/LyricEngine.kt:255-256)
- [x] Word animation (letter splitting) is prepared for the focus line, then up to 10 lines ahead, then up to 4 behind, within 3ms per frame; it is let go for lines more than 8 behind or 14 ahead (shared:lyrics/engine/LyricEngine.kt:12-21, 287-311, sharedTest:lyrics/engine/LyricEngineTest.kt:84-90)
- [x] Redraws are skipped for lines whose place, size, fade, blur (in quarter steps), press and brightness did not change and whose words or dots are not moving (an implementation detail; motion must look the same) (shared:lyrics/engine/LyricEngine.kt:258-279, shared:lyrics/engine/LineState.kt:34-56)

## 21. Flowing: each line's layer (place, growth, fade, blur, curve)

- [x] Scale = inactive + (1 - inactive) x grown, where inactive is the Inactive line size setting as a fraction (default 0.80) and grown is the scale spring's value (app:player/FlowingLyrics.kt:372-373, shared:lyrics/LyricsLook.kt:18)
- [x] A press shrinks the line further: scale x (1 - 0.03 x press), so fully pressed is 97% (app:player/FlowingLyrics.kt:374, shared:lyrics/engine/LineState.kt:8)
- [x] Vertical place = the position spring's value + the scroll offset (app:player/FlowingLyrics.kt:375-376)
- [x] Alpha = the eased opacity, clamped 0..1 (app:player/FlowingLyrics.kt:377)
- [x] Blur: the eased blur rounded to quarter steps (0 below 0.1), times the screen density, as a Gaussian blur with transparent edges; only on Android 12 and later (app:player/FlowingLyrics.kt:378-379, shared:lyrics/engine/LyricMotion.kt:103-107, sharedTest:lyrics/engine/LyricMotionTest.kt:77-82) (iPhone: each line keeps blurred copies of its picture at whole-point strengths, made off the main thread)
- [x] Scale origin: x at the line's pivot (its text's start edge) and y at the line's vertical middle (app:player/FlowingLyrics.kt:380)
- [x] Curved lyrics (the Arc setting) apply only to lines on screen, using the line's middle (place + scroll + half its current height) (app:player/FlowingLyrics.kt:381-383)
- [x] Arc: drum radius = 0.55 x view height; r = clamp((line middle - 0.33 x view height) / radius, -1, 1); a = 1 - r x r (shared:lyrics/engine/LyricMotion.kt:384-386)
- [x] Arc: forward depth z = 40dp x a (the focus row is 40dp forward) (shared:lyrics/engine/LyricMotion.kt:365-366, 387)
- [x] Arc: sideways move = side x 60dp x (1 - a), side 1 for left-set lines and -1 for right-set lines, so lines away from the focus move inward up to 60dp (shared:lyrics/engine/LyricMotion.kt:365, 389, app:player/FlowingLyrics.kt:385-391)
- [x] Arc: turn about the vertical axis = side x 0.09 x r x a radians (converted to degrees for the layer) (shared:lyrics/engine/LyricMotion.kt:367, 391, app:player/FlowingLyrics.kt:392)
- [x] Arc: camera distance = 1400dp / 72 in the layer's camera units (perspective 1400dp) (app:player/FlowingLyrics.kt:135-136, 393) (iPhone: Core Animation perspective of 1400 pt)
- [x] Arc: the line's scale is multiplied by 1400 / (1400 - z) in dp (1400 / 1360 at the focus) (shared:lyrics/engine/LyricMotion.kt:368, 392, app:player/FlowingLyrics.kt:394, sharedTest:lyrics/engine/LyricMotionTest.kt:318-354)
- [x] With the arc off, or a line off screen, the sideways move and turn are 0 (app:player/FlowingLyrics.kt:395-398)

## 22. Flowing: drawing words (brightness, fill sweep, lift)

- [x] Brightness pair from growth: bright = 0.3 + 0.7 x g, dark = 0.3 + 0.1 x g, with g clamped 0..1 and each rounded to steps of 0.02; full size gives sung words 100% and unsung 40%; other lines are 30% all through (shared:lyrics/engine/LyricMotion.kt:109-126, sharedTest:lyrics/engine/LyricMotionTest.kt:142-157)
- [x] A touched line (pressed, or press above 0.5) is drawn with bright 1.0 and dark 0.85 (shared:lyrics/engine/LyricMotion.kt:114-115, shared:lyrics/engine/LineState.kt:58-59)
- [x] Backing (background) lines draw at 60% of the pair; the credit block at a fixed 75%; translations and romanizations at a fixed 70% (all inside the layer's opacity) (app:player/FlowingLyrics.kt:121-124, 411-418)
- [x] A block line (timed by line) is drawn whole at bright x voice; it has no sweep and no lift (app:player/FlowingLyrics.kt:413-416, app:player/FlowingLyricsText.kt:150-157)
- [x] Words are drawn in the text color (the player's ink), not white (app:player/FlowingLyrics.kt:156, 415-418)
- [x] A word not yet reached is drawn at the dark alpha, a word fully sung at the bright alpha, a word being sung with the fill sweep (app:player/FlowingLyrics.kt:444-448)
- [x] Fill sweep: the word is drawn fully opaque into its own layer covering the word box plus 0.5 em on every side, then multiplied (DstIn) by a horizontal gradient: bright alpha from 0 to the bright stop, a soft ramp to the dark stop, dark alpha to 1 (mirrored for rtl), clamped beyond its ends (app:player/FlowingLyrics.kt:452-483)
- [x] Mask shape: soft edge f = (0.5 x row height x Fill softness) / word width (in word widths; the edge is 0.6 em x softness in pixels whatever the word's width); mask size = 2 + f word widths; bright stop = (1 - f / size) / 2; dark stop = bright stop + f / size (shared:lyrics/engine/LyricMotion.kt:128-143, sharedTest:lyrics/engine/LyricMotionTest.kt:86-101)
- [x] Mask left edge for progress p: left-to-right `wordLeft - (1 - p) x (1 + f) x wordWidth`; right-to-left `wordLeft - p x (1 + f) x wordWidth`; at 0 the dark part covers the word, at 1 the bright part does (shared:lyrics/engine/LyricMotion.kt:145-153, sharedTest:lyrics/engine/LyricMotionTest.kt:103-127)
- [x] Softness 0 gives a hard edge (mask 2 words wide, both stops at 0.5) (sharedTest:lyrics/engine/LyricMotionTest.kt:129-135)
- [x] Progress = (t + lead - start) / (end - start), clamped 0..1, where lead = min(0.25 s, length x f / (2 x (1 + f))) (0 when the length or edge is 0); the middle of the soft edge is on the first letter as the word starts (shared:lyrics/engine/LyricMotion.kt:155-180, sharedTest:lyrics/engine/WordFillTest.kt)
- [x] A Passed line whose word animation has been let go ("cold") draws every word fully sung and fully risen (app:player/FlowingLyrics.kt:425-426, 433-438)
- [x] Lift: each sung word rises by `-(0.05 em, or 0.10 em for backing lines) x Lift fraction x EaseOut(done)` where done = clamp((t - start) / max(1.0, end - start), 0, 1) and EaseOut is cubic-bezier(0, 0, 0.58, 1); it stays up after (shared:lyrics/engine/LyricMotion.kt:243-254, sharedTest:lyrics/engine/LyricMotionTest.kt:161-170)
- [x] The lift moves the word's drawing only; the fill layer and row do not move (app:player/FlowingLyrics.kt:466, 500)
- [x] With reduced motion: no lift and no bloom, but the fill sweep still runs (app:player/FlowingLyrics.kt:427-428)

## 23. Flowing: bloom on long notes

- [x] Only words held 1.0 s or longer, in prepared (live) lines, with reduced motion off, bloom letter by letter (shared:lyrics/engine/LyricMotion.kt:256-259, app:player/FlowingLyrics.kt:428, 439-442, app:player/FlowingLyricsText.kt:116)
- [x] The line's last whole word (every syllable after the last trailing space before the final word) is "last" and blooms harder and longer (app:player/FlowingLyrics.kt:429, 441)
- [x] Bloom strength, raw swell for a word held d seconds: a = d x 1000 / 2000, then sqrt(a) if a > 1 else a cubed, times 0.6 (shared:lyrics/engine/LyricMotion.kt:280-282)
- [x] Bloom strength, raw glow: g = d x 1000 / 3000, then sqrt(g) if g > 1 else g cubed, times 0.5 (shared:lyrics/engine/LyricMotion.kt:283-284)
- [x] Bloom run (each letter's swell length) = d seconds (shared:lyrics/engine/LyricMotion.kt:285)
- [x] The line's last word: a x 1.6, g x 1.5, run x 1.2 (shared:lyrics/engine/LyricMotion.kt:286-290, sharedTest:lyrics/engine/LyricMotionTest.kt:188-202)
- [x] amount = min(1.2, a) x Emphasis fraction (the limit applies before the setting) (shared:lyrics/engine/LyricMotion.kt:291)
- [x] glow = min(0.8, g) x Glow fraction (shared:lyrics/engine/LyricMotion.kt:292)
- [x] glow radius = min(0.3, glow x 0.3) em (shared:lyrics/engine/LyricMotion.kt:293)
- [x] stagger between letters = run / 2.5 / n, n = the word's letters without spaces (shared:lyrics/engine/LyricMotion.kt:275-277, 293)
- [x] Words under 1.0 s, or with no letters, do not bloom (shared:lyrics/engine/LyricMotion.kt:279, sharedTest:lyrics/engine/LyricMotionTest.kt:172-174)
- [x] Letter k starts swelling at word start + stagger x k (shared:lyrics/engine/LyricMotion.kt:296-297, sharedTest:lyrics/engine/LyricMotionTest.kt:204-209)
- [x] Each letter's swell e = upAndBack((t - letter start) / run): 0 outside 0..1; up to 1 at 0.5 along cubic-bezier(0.2, 0.4, 0.58, 1), then back down along 1 - cubic-bezier(0.3, 0, 0.58, 1) (shared:lyrics/engine/LyricMotion.kt:182-231, sharedTest:lyrics/engine/LyricMotionTest.kt:224-235)
- [x] Letter pose scale: 1 + 0.1 x amount x e (growth of a held letter) (shared:lyrics/engine/LyricMotion.kt:310)
- [x] Letter pose across: `-0.03 x amount x (n / 2 - k) x e` em, so letters left of the middle move left and those right of it move right (the word spreads) (shared:lyrics/engine/LyricMotion.kt:311)
- [x] Letter pose up: `-0.025 x amount x e` em (shared:lyrics/engine/LyricMotion.kt:312)
- [x] Letter glow alpha: e x glow (shared:lyrics/engine/LyricMotion.kt:313, sharedTest:lyrics/engine/LyricMotionTest.kt:211-222)
- [x] A letter outside its swell (e = 0) rests at scale 1, no move, no glow (shared:lyrics/engine/LyricMotion.kt:303-308)
- [x] Bob on top: starts 0.4 s before the letter, runs 1.4 x run, `-0.05 x sin(pi x x) x Lift fraction` em, doubled for backing lines (shared:lyrics/engine/LyricMotion.kt:317-325, sharedTest:lyrics/engine/LyricMotionTest.kt:237-246)
- [x] Each letter is drawn at word x + its own x + across, word top + lift + up + bob, scaled about its own center (half its width, half its height) (app:player/FlowingLyrics.kt:503-521)
- [x] Glow is a white text shadow with no offset (white even on a pale background), blur radius = glow radius in pixels, alpha = min(1, glow alpha), drawn only when glow alpha is above 0.01 and the radius above 0.5px (app:player/FlowingLyrics.kt:508-513, 519)
- [x] Letters that bloom keep the word's fill: the sweep mask covers the bloomed letters too (app:player/FlowingLyrics.kt:443-448, 478-482)
- [x] Right-to-left held words swell as one piece (a single "letter") (app:player/FlowingLyricsText.kt:230-234)

## 24. Flowing: interludes (the three dots)

- [x] Dots draw only while the interlude is Active (app:player/FlowingLyrics.kt:524-526)
- [x] Dot diameter 0.34 em, gap 0.22 em, three across (1.46 em), starting at the left margin, or ending at the right margin for right-side interludes; centered on the interlude's current height; in the text color (app:player/FlowingLyrics.kt:126-128, 530-542)
- [x] Each dot's radius = diameter / 2 x pose scale; its alpha = pose opacity x its light, clamped 0..1 (app:player/FlowingLyrics.kt:535-541)
- [x] Pose at p seconds into a gap of f seconds: period = f / ceil(f / 1.5); breathe = sin(1.5 x pi - 2 x p / period) / 20 + 1; scale = breathe, opacity = 1 (shared:lyrics/engine/LyricMotion.kt:327-338)
- [x] Grow-in (not reached by a seek, p < 1): scale = breathe x easeOutExpo(p / 2); opacity 0 before 0.5 s, then (p - 0.5) / 0.5 (shared:lyrics/engine/LyricMotion.kt:339-342, sharedTest:lyrics/engine/LyricMotionTest.kt:257-266)
- [x] Exit: with r = f - p, below 0.75 s the scale is multiplied by 1 - easeInOutBack((0.75 - r) / 0.75 / 2) (a little inhale, then a pop away); below 0.375 s opacity = r / 0.375 (shared:lyrics/engine/LyricMotion.kt:343-345, sharedTest:lyrics/engine/LyricMotionTest.kt:275-286)
- [x] Lights one, two, three: u = max(0.001, f - 0.75); light k = clamp((p - k x u / 3) x 3 / u x 0.75, 0.25, 1) (shared:lyrics/engine/LyricMotion.kt:346-347, sharedTest:lyrics/engine/LyricMotionTest.kt:288-301)
- [x] The final scale is multiplied by 0.7 (shared:lyrics/engine/LyricMotion.kt:348)
- [x] easeOutExpo(x) = 1 for x >= 1, else 1 - 2^(-10 x); easeInOutBack uses c2 = 2.5949095 (shared:lyrics/engine/LyricMotion.kt:233-241)
- [x] Space: the interlude opens over 0.8 s (easeOutExpo(p / 0.8)) and closes over its last 0.6 s (easeOutExpo((f - p) / 0.6)), taking the smaller; 0 outside the gap; height = closed + (open - closed) x that (shared:lyrics/engine/LyricMotion.kt:354-361, shared:lyrics/engine/LyricEngine.kt:182-187, sharedTest:lyrics/engine/LyricMotionTest.kt:310-316)
- [x] An interlude reached by a snap (first frame, seek, resize) shows its dots and space already grown; this resets once it is no longer Active (shared:lyrics/engine/LyricEngine.kt:176-181, shared:lyrics/engine/LineState.kt:31-32, sharedTest:lyrics/engine/LyricMotionTest.kt:303-308)
- [x] Reduced motion: dots held still at scale 0.7, opacity 1, every light 0.85, and the space fully open while Active (shared:lyrics/engine/LyricMotion.kt:351-352, shared:lyrics/engine/LyricEngine.kt:184, app:player/FlowingLyrics.kt:529)

## 25. Flowing: touch, scroll, follow again, long press, accessibility

- [x] Every line except the credit takes taps, presses and long presses (interludes included) (app:player/FlowingLyrics.kt:333-349)
- [x] Finger down on a line presses it in (press toward 1, brightness to the touched pair, scale toward 97%); lifting releases it (app:player/FlowingLyrics.kt:338-343, shared:lyrics/engine/LyricEngine.kt:360-362)
- [x] A tap on a line faded below 5% opacity does nothing (app:player/FlowingLyrics.kt:242-243)
- [x] A tap plays from where the line is heard: target = max(0, round(line start ms) + song offset + output offset (with screen lead)); the line is held pressed for 0.08 s, a hand scroll ends (springing back), the clock shows the target until the player gets there, and the player seeks (app:player/FlowingLyrics.kt:244-248, shared:lyrics/engine/LyricEngine.kt:364-370, appTest:lyrics/engine/OutputTimingTest.kt:59-91)
- [x] After a tap, a polite live announcement says "Playing from m:ss" (the target time) (app:player/FlowingLyrics.kt:249, 263-270)
- [x] A long press shows a time stamp pill for that line for 1500ms, then it goes (app:player/FlowingLyrics.kt:118-119, 233-238, 259)
- [x] Stamp text: the time the line is heard (written start + song offset + output offset with screen lead, never below 0) as m:ss, or h:mm:ss from an hour (app:player/FlowingLyrics.kt:549, 567-568, app:ui/common/Layout.kt:68-74)
- [x] Stamp type: 11.52sp Bold with tabular figures, white (app:player/FlowingLyrics.kt:133, 550-553) (iPhone: 11.52 pt growing with Dynamic Type)
- [x] Stamp pill: fill #121214 at alpha 0x52 (about 32%), full capsule, 0.5dp border in white at 16%, padding 8dp sideways and 3dp up and down (app:player/FlowingLyrics.kt:130-132, 561-563)
- [x] Stamp place: its bottom 4dp above the line's top, following the line's spring and the scroll; x at the left margin, or ending at the right margin for right-set lines; it is not scaled, blurred or faded with the line, and it is drawn above every line (app:player/FlowingLyrics.kt:262, 555-560)
- [x] A vertical drag anywhere on the view scrolls by hand: on start the lyrics stop following the song and hold the current focus; passed lines show at 45% while scrolling even if sung lines are not kept (shared:lyrics/engine/LyricEngine.kt:207, 327-336, sharedTest:lyrics/engine/LyricEngineTest.kt:92-116)
- [x] The finger moves the scroll offset's target by the drag distance; the offset follows on its spring (240, 28), not one to one (shared:lyrics/engine/LyricEngine.kt:338-346)
- [x] The scroll stops with the first line's top no lower than 30% of the view and the last line's bottom no higher than 70%; if the lyrics are too short for both, it sits midway (shared:lyrics/engine/LyricEngine.kt:27-30, 338-346, sharedTest:lyrics/engine/LyricEngineTest.kt:118-126)
- [x] There is no fling: lifting the finger leaves the offset where its spring lands (shared:lyrics/engine/LyricEngine.kt:348-352, app:player/FlowingLyrics.kt:275-285)
- [x] 2.0 s after the finger lifts (and not dragging again), the lyrics follow the song again: the offset springs back to 0 and the focus returns to the line being sung with the ripple (shared:lyrics/engine/LyricEngine.kt:23-25, 165, 348-358, sharedTest:lyrics/engine/LyricEngineTest.kt:110-115)
- [x] No ripple while scrolling (shared:lyrics/engine/LyricEngine.kt:198)
- [x] Each line reads aloud as its text, plus ". " and its translation when it has one; an interlude reads "Instrumental" (app:player/FlowingLyrics.kt:357-361)
- [x] Each tappable line has an accessibility click action labelled "Play from m:ss" with the line's written start (no offsets), which taps it (app:player/FlowingLyrics.kt:316, 324-332)

## 26. Flowing: reduced motion, in one place

- [x] Positions and sizes jump every frame (no springs, no ripple) (shared:lyrics/engine/LyricEngine.kt:151-152, sharedTest:lyrics/engine/LyricEngineTest.kt:72-80)
- [x] No word lift, no bloom, no bob, no glow (app:player/FlowingLyrics.kt:427-428)
- [x] The fill sweep, opacity and blur easing still run (app:player/FlowingLyrics.kt:444-448, shared:lyrics/engine/LyricEngine.kt:247-253)
- [x] Dots still, interludes fully open while active (section 24)
- [x] Triggered by the app's Reduce motion switch ("Backgrounds and lyrics hold still. On by itself when the phone's animations are off.") or the phone's animations being off (app:ui/settings/AppearancePage.kt:123-129, app:player/FlowingLyrics.kt:161-162) (iPhone: Octo's switch with the same helper, or iOS Reduce Motion)

## 27. Look settings

- [x] Styles: Flowing ("Lines ripple into place, words fill with light and long notes bloom.") and Classic ("The line being sung grows and its words brighten in place."); default Flowing (shared:lyrics/LyricsLook.kt:5-10, 26)
- [x] Emphasis: key `lyrics_fx_emphasis`, 0..200%, default 100 (how much long notes swell, spread and rise) (shared:lyrics/LyricsLook.kt:14, 27-28)
- [x] Glow: key `lyrics_fx_glow`, 0..200%, default 100 (shared:lyrics/LyricsLook.kt:15, 29-30)
- [x] Lift: key `lyrics_fx_lift`, 0..200%, default 100 (how far sung words rise and bob) (shared:lyrics/LyricsLook.kt:16, 31-32)
- [x] Motion speed: key `lyrics_fx_speed`, 50..200%, default 100 (spring speed) (shared:lyrics/LyricsLook.kt:17, 33-34)
- [x] Inactive line size: key `lyrics_fx_inactive_scale`, 60..100%, default 80 (shared:lyrics/LyricsLook.kt:18, 35-36)
- [x] Fill softness: key `lyrics_fx_fade`, 0..200%, default 100 (shared:lyrics/LyricsLook.kt:19, 37-38)
- [x] Ripple: key `lyrics_fx_cascade`, 0..200%, default 100; at 0 there is no ripple (shared:lyrics/LyricsLook.kt:20, 39-40, shared:lyrics/engine/LyricEngine.kt:198)
- [x] Keep sung lines visible: key `lyrics_keep_completed`, default on (shared:lyrics/LyricsLook.kt:41-44, app:lyrics/LyricsLookSettings.kt:21, 33)
- [x] Curved lyrics: key `lyrics_arc`, default off (shared:lyrics/LyricsLook.kt:45-46, app:lyrics/LyricsLookSettings.kt:22, 34)
- [x] Style key `lyrics_style` stores the enum name; unknown reads as Flowing (app:lyrics/LyricsLookSettings.kt:20, 32)
- [x] Every slider value is clamped to its range on read and on write; fractions are percent / 100 (shared:lyrics/LyricsLook.kt:58-72, app:lyrics/LyricsLookSettings.kt:36, 43-45)
- [x] The look lives in the same "lyrics" preferences store as the timing (app:lyrics/LyricsLookSettings.kt:26-37, app:lyrics/LyricsTiming.kt:134-135)
- [x] The sliders, Keep and Arc only affect the Flowing style (app:ui/settings/LyricsPage.kt:168)

## 28. Classic style

- [x] Uses `shownLines()` (gap lines for waits of 5 s or more at the start or after a known end) (app:player/LyricsPane.kt:330, shared:lyrics/Lyrics.kt:90-109)
- [x] Runs on the lyrics clock: position - (song offset + output offset with screen lead); the position updates every frame while playing and every 300ms while paused (to catch seeks from elsewhere) (app:player/LyricsPane.kt:331-347, app:player/Position.kt:11-26)
- [x] The current line is `lineAt(position)` (-1 before the first) (app:player/LyricsPane.kt:336)
- [x] A scrolling list with half the view's height as padding above and below (app:player/LyricsPane.kt:388-399)
- [x] Follows the song: the current line (at least line 0) is scrolled so its middle sits at the view's middle; the first time it is put there at once, then it glides with a spring (damping ratio 0.7, stiffness 80); a line not laid out yet is first jumped to (app:player/LyricsPane.kt:138-139, 370-380, 403-413)
- [x] A drag stops following; following resumes 3000ms after the drag ends or is cancelled; a new drag cancels the pending resume (app:player/LyricsPane.kt:131-132, 349-368)
- [x] Each row's emphasis animates 0 to 1 when it becomes current and back, on the same spring (0.7, 80) (app:player/LyricsPane.kt:417)
- [x] Classic type: the default family in Bold, line height 1.2 em, letter spacing -0.2sp (app:player/LyricsPane.kt:134-136)
- [x] Classic size: lerp(20, 28, emphasis) sp, so the current line grows from 20sp to 28sp on the spring (the size, not a scale, so the text rewraps as it grows) (app:player/LyricsPane.kt:117-119, 423)
- [x] Classic alignment: duet lines aligned to the end (right), all others to the start (app:player/LyricsPane.kt:424-428)
- [x] Classic rows: full width, padded 10dp top and bottom, soft wrapping across the pane's whole width (no extra side margins in the pane) (app:player/LyricsPane.kt:425-428)
- [x] Background lines are 0.8 x the size with backing alphas; backing text under a lead line is 0.7 x the size with 2dp above it, backing alphas (app:player/LyricsPane.kt:429-449)
- [x] Alphas: lead sung 0.85, unsung 0.5, resting 0.35; backing sung 0.55, unsung 0.3, resting 0.2 (app:player/LyricsPane.kt:121-129)
- [x] Drawing: base alpha = lerp(resting, unsung (or sung when the line has no words), emphasis); a line with no words, or emphasis at or below 0.01, is drawn whole at base (app:player/LyricsPane.kt:494-498)
- [x] Word-timed lines: the sung part (every word ended, plus the share of the current word's box that has gone by, with a hard edge, from the right for right-to-left text) is drawn at lerp(resting, sung, emphasis); the rest at base (app:player/LyricsPane.kt:499-501, 506-539)
- [x] A word's end for Classic: its own end, else the next word's start, else the line's end, else start + 1000ms (app:player/LyricsPane.kt:514)
- [x] Translation under the line: body style (16sp Medium), the line's alignment, white at lerp(0.3, 0.6, emphasis), 4dp above it; romanization and singer names are not shown (app:player/LyricsPane.kt:450-457)
- [x] All Classic text is white, whatever the player's ink (app:player/LyricsPane.kt:320, 454, 483-501)
- [x] A tap on a word seeks to that word's start; a tap elsewhere on the line to the line's start; the seek goes to where it is heard (+ both offsets, never below 0), the position updates at once and following resumes (app:player/LyricsPane.kt:382-387, 433-446, 486-491)
- [x] Gap lines show three 8dp white dots, 8dp apart, in a row padded 10dp top and bottom whose height is lerp(12, 28, emphasis) dp; a tap seeks to the gap's start (app:player/LyricsPane.kt:541-553)
- [x] Gap dots bounce only while the gap is the current line, on a 1400ms linear loop from 0 to 1 repeating (app:player/LyricsPane.kt:554, 577-587)
- [x] Gap dot bounce: phase = (beat - dot index x 0.15) x 2 pi; lift = -abs(sin(phase)) x 4dp x emphasis (app:player/LyricsPane.kt:560-561)
- [x] Gap dot scale: lerp(0.75, 1, emphasis) (app:player/LyricsPane.kt:562-564)
- [x] Gap dot lighting: a dot (0, 1, 2) is lit once (position - gap start) / (gap end - gap start) reaches (index + 1) / 3; with no known end, none are lit (app:player/LyricsPane.kt:565-568)
- [x] Gap dot alpha: lerp(0.25, 0.85 when lit or 0.5 when not, emphasis) (app:player/LyricsPane.kt:569)
- [x] Classic gap dots keep bouncing with reduced motion on (app:player/LyricsPane.kt:554, 578-587)
- [x] No edge bleed, but faded edges apply (app:player/LyricsPane.kt:212)

## 29. Plain (untimed) lyrics

- [x] A vertically scrolling column with 32dp padding top and bottom (app:player/LyricsPane.kt:305-312)
- [x] An empty line is an 18dp space; any other line is 20sp Bold, line height 1.2 em, letter spacing -0.2sp, white at 0.85, padded 4dp top and bottom, start aligned, wrapping (app:player/LyricsPane.kt:313-325) (iPhone: 20 pt growing with Dynamic Type)
- [x] Not tappable; no following; no edge bleed; faded edges apply (app:player/LyricsPane.kt:212, 305-326)

## 30. The lyrics bar (small player in lyrics mode)

- [x] One glass capsule (floating glaze, full round shape), full width, 64dp tall (app:player/LyricsBar.kt:56-58, 84-88, design:Glaze.kt:193-208) (iPhone: a Liquid Glass capsule)
- [x] Row padding 12dp start and 6dp end, items centered vertically (app:player/LyricsBar.kt:114-117)
- [x] Artwork 40dp with 10dp corners, with the outside-library badge when the song is not in the library (app:player/LyricsBar.kt:118)
- [x] Song column (weight 1, padding 10dp sideways, 8dp up and down): title in label style (13.5sp SemiBold) in the ink, one line, ellipsis; artist in caption style at 11sp, ink at 60%, one line, ellipsis; a tap on it leaves lyrics (accessibility label "Leave lyrics"), no ripple (app:player/LyricsBar.kt:119-139) (iPhone: VoiceOver reads the title and artist with the hint Leave lyrics)
- [x] Buttons 40dp each, no ripple: Previous (icon 24dp, "Previous"), Play/Pause (icon 28dp, "Play" or "Pause"), Next (icon 24dp, "Next") (app:player/LyricsBar.kt:140-142, 201-213)
- [x] Lyrics switch 40dp, glowing lit icon 22dp in the ink, "Lyrics" with state "Showing"; a tap leaves lyrics (app:player/LyricsBar.kt:143-154)
- [x] More button 40dp, icon 22dp in ink at 70%, "Lyrics menu"; a tap opens the lyrics menu anchored to this button's window bounds (app:player/LyricsBar.kt:155-164, 191-198) (iPhone: a system menu on the button)
- [x] Progress line place: inset 32dp from each end (half the bar's height, along the straight part of the capsule), 4dp above the bar's bottom, in a 3dp tall area (app:player/LyricsBar.kt:166-174)
- [x] Progress line look: the track is the ink at 18%, the played part the ink at 70%, both 2dp strokes bottom-aligned in the 3dp area with round caps; the played part is drawn only when above 0 (app:player/LyricsBar.kt:175-188)
- [x] Scrubbing starts only from a touch within the bottom 22dp of the bar, and only when the song's length is known (app:player/LyricsBar.kt:60-61, 89-95)
- [x] Scrubbing waits for a sideways touch slop, so taps and vertical moves still reach the buttons and the player (app:player/LyricsBar.kt:96-98)
- [x] Scrub fraction = (x - 32dp) / (bar width - 64dp), clamped 0..1, following the finger (app:player/LyricsBar.kt:90-92, 99-103)
- [x] While scrubbing the progress stroke is 3dp and the played part is the ink at 95% (app:player/LyricsBar.kt:175-188)
- [x] On release the player seeks to fraction x length and the progress jumps there at once; a cancelled drag seeks nothing (app:player/LyricsBar.kt:104-110)
- [x] The progress position updates every frame while playing (app:player/LyricsBar.kt:76, app:player/Position.kt:11-29)

## 31. The lyrics menu

- [x] A glass popup beside the bar's More button, pane title "Lyrics", its content 280dp wide with 6dp padding; it reopens on its first page each time; back goes back a page before closing (app:player/LyricsMenu.kt:243-289) (iPhone: a system menu that always opens at its root; timing is a popover of its own)
- [x] Nothing shows inside without a track id (app:player/LyricsMenu.kt:266)
- [x] Top line (quiet heading: label style 13.5sp SemiBold, accent color, padding 14dp sideways, 10dp top, 6dp bottom): Found gives the lyrics' source line (section 10); hidden "Lyrics are hidden for this song"; none "No lyrics found for this song"; failed "Couldn't load lyrics"; loading or closed "Looking for lyrics" (app:player/LyricsMenu.kt:291-298, 338, app:ui/common/GlassMenu.kt:87-95) (iPhone: the menu's section heading)
- [x] Hidden for the song: "Show lyrics again" (shows them, on the server too when it keeps choices, and closes the menu), then "Choose other lyrics" (closes the menu and opens the chooser) (app:player/LyricsMenu.kt:314-321)
- [x] Otherwise: "Find lyrics" when there are no Found lyrics, else "Choose other lyrics", with the detail "Every copy that can be found for this song" (closes the menu and opens the chooser) (app:player/LyricsMenu.kt:323)
- [x] Found, synced and not instrumental: "Adjust timing" with the detail = the timing summary (section 33), or "Move the words earlier or later" when nothing was moved; opens the timing page (app:player/LyricsMenu.kt:324-327) (iPhone: the row opens the timing popover)
- [x] Found: "Hide lyrics for this song" (hides them, on the server too when it keeps choices, and closes the menu) (app:player/LyricsMenu.kt:328-335)
- [x] Options are action rows (none selected): min height 40dp, padding 14dp sideways and 10dp up and down, label 14sp Normal white, detail caption (12sp) muted, 1dp hairlines between rows at white 8%, a quiet accent pill under the finger, no ripple (app:player/LyricsMenu.kt:339, app:ui/common/GlassMenu.kt:63-160, design:OctoTokens.kt:91-94) (iPhone: system menu rows with their subtitles)

## 32. The timing page (in the lyrics menu)

- [x] Header: a back row with a chevron and "Lyrics timing"; back returns to the options (app:player/LyricsMenu.kt:281-284, app:ui/common/GlassMenu.kt:278-302) (iPhone: a popover headed Lyrics timing; closing it and opening the menu again goes back)
- [x] Hint: "If the words light up late, tap Earlier. If early, tap Later." in caption style, muted, centered, padding 14dp sideways, 2dp top, 12dp bottom (app:player/LyricsMenu.kt:350-356)
- [x] First control: title "This song", about "For this song only, on every output.", limit 10 s either way, Reset clears the song's offset (app:player/LyricsMenu.kt:357-364)
- [x] A 1dp divider at white 8% with 14dp side and 6dp vertical padding, then 8dp space (app:player/LyricsMenu.kt:365-366, 380)
- [x] Second control: title = the output's name ("Phone speaker", "Headphones", a Bluetooth device's name or "Bluetooth", a USB device's name or "USB audio"), about = the output timing text, limit 2 s either way, reset labelled "Use automatic", enabled only when the output's timing was set by the listener (app:player/LyricsMenu.kt:367-376, app:sound/SoundEngine.kt:40, 55-71) (iPhone: the iPhone's own output names: iPhone speaker, Headphones, the Bluetooth or USB name, AirPlay, CarPlay)
- [x] A timing control: title (label style, white, one line, ellipsis) with the signed value on the right (18sp Bold, tabular figures, 12dp before it; read aloud "<title>: <In time / 0.25 s later / ...>" politely when it changes); the about line under it (caption, muted, padding 14dp sideways, 2dp top, 10dp bottom) (app:ui/common/TimingAdjuster.kt:31-75) (iPhone: a VoiceOver announcement as the value changes)
- [x] Earlier and Later glaze buttons side by side (8dp apart, 8dp side padding, equal widths); Earlier steps -1 and is disabled at the lower limit, Later steps +1 and is disabled at the upper limit (app:ui/common/TimingAdjuster.kt:77-93)
- [x] The reset text under them in a box at least 44dp tall, centered, label style in the accent color, full opacity when it can reset and 40% otherwise, clickable only when it can (circle clip, padding 14dp sideways and 8dp up and down) (app:ui/common/TimingAdjuster.kt:94-108)
- [x] The lyrics keep playing behind the menu and move with each step on the next frame (app:player/LyricsMenu.kt:342-344, app:player/FlowingLyrics.kt:169-174)

## 33. Timing math, offsets, outputs and the screen lead

- [x] One step is 50ms; a song's offset is limited to -10000..10000ms, an output's to -2000..2000ms (app:lyrics/LyricsTiming.kt:23-29, appTest:lyrics/LyricsTimingTest.kt:44-53)
- [x] An offset says how much later than written the words are heard: lyrics clock = position - offset; a line is heard at max(0, line time + offset) (app:lyrics/LyricsTiming.kt:35-49, appTest:lyrics/LyricsTimingTest.kt:18-42)
- [x] The song's and the output's offsets add up (app:lyrics/LyricsTiming.kt:40-52, appTest:lyrics/LyricsTimingTest.kt:110-118)
- [x] Earlier is -1 step (words sooner), Later is +1 step (app:ui/common/TimingAdjuster.kt:77-93)
- [x] A song's offset is stored as `offset:<trackId>` in the "lyrics" store and removed when it returns to 0; it reads 0 when absent (app:lyrics/LyricsTiming.kt:139-167)
- [x] An output's offset is stored as `lyrics_output_offset:<outputKey>`, kept even at 0 (so it stays off automatic); a step starts from the output's current timing (its automatic one at first, or one saved under a key it had before), removes the former keys and writes under the current key (app:lyrics/LyricsTiming.kt:141-145, 183-202)
- [x] "Use automatic" removes the output's offset under its current key and every former key (app:lyrics/LyricsTiming.kt:204-207)
- [x] Automatic output timing (never set by the listener): -500ms for a Bluetooth output (key starts with `bluetooth:`), -300ms for everything else (speaker, cable, USB) (app:lyrics/LyricsTiming.kt:66-74, appTest:lyrics/LyricsTimingTest.kt:55-79)
- [x] An output's saved timing is looked up under its key, then under each former key in order (app:lyrics/LyricsTiming.kt:97-102, app:sound/SoundEngine.kt:73-75, appTest:lyrics/LyricsTimingTest.kt:94-108)
- [x] Output keys: "speaker"; "wired"; "usb:<name>"; "bluetooth:<device name>" (or the first address when nameless), with the device's addresses as former keys; Bluetooth outranks USB, which outranks a cable (app:sound/SoundEngine.kt:31-71) (iPhone: the audio route's ports: Bluetooth, hands-free included, then USB, then a cable, keyed and ranked the same way, with AirPlay and CarPlay besides)
- [x] The output timing follows the output playing now as earbuds or a cable come and go (app:lyrics/LyricsTiming.kt:183-191, app:player/LyricsPane.kt:153-156)
- [x] Screen lead: -round(2 x 1000 / refresh Hz) ms, with Hz taken as 60 when not finite or below 30 (60 Hz -33, 90 Hz -22, 120 Hz -17); added to every output's timing for the views, never shown or stored (app:lyrics/LyricsTiming.kt:31-33, 58-64, app:player/LyricsPane.kt:196-202, appTest:lyrics/LyricsTimingTest.kt:120-128)
- [x] Output timing text: automatic "Every song on this output. Automatic: 0.5 s earlier, the usual for Bluetooth." or "Every song on this output. Automatic: 0.3 s earlier, the usual for a speaker or a cable."; set by the listener "Every song on this output." (app:lyrics/LyricsTiming.kt:87-95, appTest:lyrics/LyricsTimingTest.kt:86-92)
- [x] Timing summary for the menu: "This song <signed>" when the song's offset is not 0, "<output name> <signed>" when the output's is not 0 and not automatic, joined by " · "; nothing when neither (app:lyrics/LyricsTiming.kt:112-117, appTest:lyrics/LyricsTimingTest.kt:130-139)
- [x] Timing in words: 0 is "In time", else "<seconds> s later" or "<seconds> s earlier" with trailing zeros stripped ("0.25 s later", "1 s later", "1.75 s earlier") (app:lyrics/LyricsTiming.kt:119-124, appTest:lyrics/LyricsTimingTest.kt:141-149)
- [x] Signed timing: "0 s", "+0.75 s", "-1.5 s", "+1 s" (app:lyrics/LyricsTiming.kt:126-132, appTest:lyrics/LyricsTimingTest.kt:151-158)
- [x] Picking other lyrics resets the song's timing (an offset for other lyrics would be wrong) (app:player/LyricsMenu.kt:197-224)

## 34. The lyrics chooser panel

- [x] A large glass popup centered on screen (no anchor), pane title "Choose lyrics", at most 440dp wide and 80% of the screen tall; it rises above the keyboard while typing; its content scrolls inside it with 18dp padding top and 6dp bottom (app:player/LyricsMenu.kt:496-515, design:GlassPopup.kt:143-161) (iPhone: a sheet with detents and its grabber; the keyboard pushes it up)
- [x] Opening it (or a new track) starts a fresh look: cancels any look and search, clears search results and the "not taken" note, shows "Looking for lyrics", then the found list (app:player/LyricsMenu.kt:158-173, 393-395)
- [x] A look that fails shows an empty list with online lookups treated as off (so the online-off note shows and the search box is hidden) (app:player/LyricsMenu.kt:169-171, 430-474)
- [x] Heading "Choose lyrics" in section style (18sp Bold) white, 24dp from the sides (app:player/LyricsMenu.kt:405, 412)
- [x] Under it "<title> by <artist>" (blank parts left out) in caption style, muted, one line, ellipsis, 2dp below when the server keeps choices else 12dp (app:player/LyricsMenu.kt:413-420)
- [x] When the server keeps choices: "Lyrics picked from your server show on all your devices and apps." caption, muted, 12dp below (app:player/LyricsMenu.kt:421-428)
- [x] The search box shows when the server keeps choices or online lookups are on (assumed on until the look finishes): placeholder "Search by title, or artist - title" (server) or "Search LRCLIB by title or artist"; the keyboard's action is Search; a trailing 40dp search button (icon 20dp, accent color, "Search"); both clear the keyboard focus and search (app:player/LyricsMenu.kt:430-457)
- [x] The typed text is kept per track across recompositions and rotation (app:player/LyricsMenu.kt:399)
- [x] Searching trims the words; empty clears the results; a new search cancels the last; it asks the server's sources when the server keeps choices for the song, else LRCLIB (app:player/LyricsMenu.kt:175-195)
- [x] Search states: searching "Searching your server" / "Searching LRCLIB"; failed "Could not reach your server" / "Could not reach LRCLIB"; done: section "Search results", "Nothing found for that" when empty, then rows (marked showing when the pick is the one showing), hairlines always drawn (app:player/LyricsMenu.kt:458-471)
- [x] A server search sends the split title and artist to getLyricsCandidates and keeps only copies with a non-blank id; any server error is a failed search (app:lyrics/LyricsRepository.kt:410-423)
- [x] An answer for a different track than the one playing is ignored (app:player/LyricsMenu.kt:407, 481)
- [x] With the server not keeping choices and online off: "Online lyrics are off in Settings, so only your server and this phone are searched." (app:player/LyricsMenu.kt:472-474)
- [x] Section "For this song"; if the server refused the last choice: "Your server could not use those lyrics this time. Try again, or pick others."; while looking: "Looking for lyrics" (app:player/LyricsMenu.kt:476-479)
- [x] The list (section 35); empty gives "No lyrics found for this song"; a 1dp hairline before every row but the first, left undrawn right below the showing row so no line touches the darker pill; then "Could not reach <your server / LRCLIB / the song's files, joined by " or "> this time." when sources failed; 8dp space at the end (app:player/LyricsMenu.kt:480-494, 517-525, 624-635)
- [x] Section titles: label style, accent color, padding 14dp sideways, 16dp top, 6dp bottom; quiet lines: caption, muted, padding 14dp sideways and 10dp up and down; everything else 16dp from the panel's sides (app:player/LyricsMenu.kt:405, 604-622)
- [x] A row: at least 56dp tall, 14dp corners, with a press ripple, accessibility action "Keep these lyrics" when showing else "Use these lyrics", state "Showing now" when showing; padding 14dp sideways and 10dp up and down, 12dp between text and check (app:player/LyricsMenu.kt:527-553) (iPhone: a pressed pill in place of a ripple; VoiceOver hint and value)
- [x] The showing row sits on the darker selected pill with a white 18dp check on the right (app:player/LyricsMenu.kt:548, 571-573)
- [x] Row text: the label (14sp, white), then the detail (caption, muted, at most 2 lines, ellipsis), then the preview (caption, accent color, at most 2 lines, ellipsis, 4dp above): the first two non-empty lines joined by a line break, or "Instrumental" for instrumental copies (app:player/LyricsMenu.kt:554-569)
- [x] Labels: "Automatic" for the server's auto entry; "From <source name>" for a server copy; else "From your server", "From the song file", "From a .lrc file beside the song", "From LRCLIB" by where it was found (app:lyrics/ServerChoices.kt:98-112, appTest:lyrics/ServerChoicesTest.kt:63-84)
- [x] Details, joined by " · ": for the auto entry "Let your server find the best match" (no lyrics carried) or "Found by your server"; for LRCLIB copies and server copies: "<title> by <artist>" (or the title) when found by a typed search or the title's match key differs from the playing song's, then the album when known, then the length as m:ss when at least 1 s; then the timing kind when the row carries lyrics or is a server copy: "Word by word", "Timed" or "Not timed" (instrumental adds nothing) (app:player/LyricsMenu.kt:578-602, app:lyrics/LyricsCandidates.kt:17-23)
- [x] Picking the row already showing just closes the panel (app:player/LyricsMenu.kt:402-404)
- [x] Picking a phone-side entry (server answer, song file, .lrc, LRCLIB) resets the song's timing, keeps the lyrics as the song's answer, saves the pick, and closes the panel at once (app:player/LyricsMenu.kt:202-211, app:lyrics/LyricsRepository.kt:225-240)
- [x] Picking a server entry (a server copy or Automatic) sends it to the server; on success it resets the song's timing and closes; on failure the panel stays open with the refusal note (app:player/LyricsMenu.kt:212-224)

## 35. Candidate list rules

- [x] Origins in list order: Server, ServerCopy, SongFile, LyricsFile, OnlineMatch, OnlineSearch (app:lyrics/LyricsCandidates.kt:3-7)
- [x] Kinds: Words ("Word by word") when any line has words, Lines ("Timed") when synced, Plain ("Not timed"), Instrumental (""); a server copy's kind comes from the server: "word", "line", "instrumental", anything else Plain (app:lyrics/LyricsCandidates.kt:17-30, app:lyrics/ServerChoices.kt:114-120)
- [x] With every choice on the phone, sources are asked all at once: the server's answer, the song file's, the .lrc's, LRCLIB's exact match and LRCLIB's search copies (the last two only with online on and a title and artist) (app:lyrics/LyricsRepository.kt:368-403)
- [x] With the server keeping choices: the server's copies list; in parallel the server's own answer (only when the list came back and the choice is "auto"), the song file's and the .lrc's; the list is Automatic (when the list came back or there is an answer; carrying the answer only while the choice is "auto" and it is not empty), then the server copies with a non-blank id, then the phone's own; LRCLIB is not asked directly (app:lyrics/LyricsRepository.kt:314-366, app:lyrics/ServerChoices.kt:136-155, appTest:lyrics/ServerChoicesTest.kt:86-97)
- [x] An unreachable server in that mode notes "your server" as missed and still shows the phone's own, with the server choice taken as "auto" (so the panel stays in server mode) (app:lyrics/LyricsRepository.kt:331-340, appTest:lyrics/ServerChoicesTest.kt:99-102)
- [x] A server error from getLyricsCandidates (lookups off) or any other error building the server list falls back to the phone-side list (app:lyrics/LyricsRepository.kt:334-339, 309-311)
- [x] When listing shows the server's choice moved since this phone saved its answer, the saved answer is forgotten and fetched again (app:lyrics/LyricsRepository.kt:341-349)
- [x] Which entry is showing: with the server keeping choices and the showing lyrics from the server, the server's choice ("none" means none showing); otherwise the showing lyrics' own pick (app:lyrics/ServerChoices.kt:157-166)
- [x] The showing entry comes first; then by origin order; then in the order found (app:lyrics/LyricsCandidates.kt:90-92, appTest:lyrics/LyricsCandidatesTest.kt:23-35)
- [x] With no known pick, the showing lyrics are recognized by their words and timing (app:lyrics/LyricsCandidates.kt:78-83, appTest:lyrics/LyricsCandidatesTest.kt:37-44)
- [x] The showing lyrics are added as an entry when no source offered them this time (origin from their source; LRCLIB counts as the match) (app:lyrics/LyricsCandidates.kt:84-89, appTest:lyrics/LyricsCandidatesTest.kt:60-67)
- [x] Each pick shows once, and lyrics with the same words and timing as one above are left out (server copies carry no lyrics, so are never merged that way); empty lyrics are left out (app:lyrics/LyricsCandidates.kt:93-98, appTest:lyrics/LyricsCandidatesTest.kt:46-58, 69-73)
- [x] Words and timing compare as: kind word ("instrumental", "timed", "plain"), then per line the start (when timed) and the trimmed text (app:lyrics/LyricsCandidates.kt:102-110)
- [x] Preview: the first two non-empty trimmed lines of the lyrics, or of the server's preview (app:lyrics/LyricsCandidates.kt:54-57, appTest:lyrics/LyricsCandidatesTest.kt:75-83)
- [x] A server copy: pick OnServer(id), no lyrics, title, artist, album (or ""), length = seconds x 1000 (unknown 0), source (or the id's prefix) (app:lyrics/ServerChoices.kt:122-134)

## 36. Settings: the Lyrics page

- [x] In the settings index under the group "Lyrics and history": row "Lyrics" with the Lyrics icon and the summary "Found online" or "From your music only", plus "Screen stays on" when on, joined by " · " (app:ui/settings/SettingsScreen.kt:320-321, app:ui/settings/SettingsSummaries.kt:19-27, 99-102)
- [x] Page title "Lyrics" (app:ui/settings/LyricsPage.kt:121)
- [x] First group: switch "Find lyrics online" with helper "From LRCLIB when your music has none. Sends only the title, artist, album and length." (default on); switch "Keep the screen on" (default on) (app:ui/settings/LyricsPage.kt:122-134, app:ui/settings/SettingsIndex.kt:417-424, app:player/PlayerSettings.kt:54-55)
- [x] Group "Synced lyrics" (Lyrics icon): choice row "Lyrics style" showing the style's label; it opens a choice sheet titled "Lyrics style" with "Flowing" and "Classic", each with its description, the current one selected (app:ui/settings/LyricsPage.kt:135-146, app:ui/settings/SettingsIndex.kt:425-428) (iPhone: a system menu titled Lyrics style)
- [x] Group "Timing" (Timer icon) with footer "Words late? Tap Earlier. Early? Tap Later. One song is set from the player's lyrics menu.": an info row titled with the output's name, value = the signed timing, helper = the output timing text; then Earlier, Later and "Use automatic" (12dp top, 8dp sides) for the output playing now (app:ui/settings/LyricsPage.kt:147-167)
- [x] Group "Look" (Appearance icon) with footer "For the Flowing style.": seven sliders in order Emphasis, Glow, Lift, Motion speed, Inactive line size, Fill softness, Ripple, each showing "<n>%", moving in steps of 5% within its range; then switch "Keep sung lines visible" (helper "Sung lines stay faintly above.") and switch "Curved lyrics" (helper "Lines bend round a drum.") (app:ui/settings/LyricsPage.kt:45-46, 168-203)
- [x] Settings search entries: Emphasis "How much long notes swell letter by letter"; Glow "How strongly long notes glow"; Lift "How far sung words rise and bob"; Motion speed "How quickly lines move into place"; Inactive line size "How big the lines not being sung are"; Fill softness "How soft the edge of the word fill is"; Ripple "How far apart lines start moving"; Keep sung lines visible "Lines already sung stay faintly on screen"; Curved lyrics "The lines bend around a drum"; Lyrics timing on this output "Words earlier or later on this speaker or headphones"; with their keywords (app:ui/settings/SettingsIndex.kt:416-468)

## 37. Backup of lyrics settings

- [x] A backup holds keep screen on (default true), each song's moved timing (by song key), the whole look (missing in older backups), and each output's timing by output key (missing in older backups) (app:backup/Backup.kt:74-88)
- [x] Restoring a song's timing clamps it to the song limit and removes it at 0; restoring an output's clamps it to the output limit and keeps 0 (app:lyrics/LyricsTiming.kt:177-181, 212-217)
- [x] The restore summary says "Lyrics timing for N song(s)" and "Lyrics timing for N sound output(s)" (app:backup/Backup.kt:366-367)

## 38. Android behaviors that look like quirks (match them)

- [x] The flowing focus sits at 33% of the view height, not the 47% a code comment states (shared:lyrics/engine/LyricMotion.kt:20-30)
- [x] The flowing font size is width / 13, not the "width over 20" a code comment states (app:player/FlowingLyricsText.kt:18, 88)
- [x] An unbreakable group wider than the text width (a very long word, or a whole unspaced CJK line) overflows the right margin and is clipped by the view's edge (app:player/FlowingLyricsText.kt:196-208, app:player/FlowingLyrics.kt:189)
- [x] Glow is always white, even when the words are dark on a pale background (app:player/FlowingLyrics.kt:510)
- [x] Classic and Plain text is always white, even on a pale background (app:player/LyricsPane.kt:320, 454, 483)
- [x] With "Keep sung lines visible" off, passed lines fade to 0 and cannot be tapped (below 5%) (shared:lyrics/engine/LyricMotion.kt:86-90, app:player/FlowingLyrics.kt:243)
- [x] A failed chooser look shows the "Online lyrics are off" note (app:player/LyricsMenu.kt:169-171, 472-474)
- [x] Classic gap dots bounce even with reduced motion (app:player/LyricsPane.kt:554)
- [x] No credit line is ever shown on Android (no writers are passed) (app:player/FlowingLyrics.kt:158)

## Shared logic to port line for line

Port in this order; each file is plain logic with no drawing, and its tests should be ported with it and pass unchanged. Files marked JVM use Java or OkHttp calls that need a Swift equivalent with identical results (UTF-8 code points, `Character.getDirectionality`, `Locale` ISO-3 language codes, `MessageDigest` SHA-1, HTTP).

1. `shared:lyrics/Lyrics.kt`: the lyrics model, `isEmpty`, `isGap`, `lineAt`, `shownLines`, `endOf`. Tests: `sharedTest:lyrics/LyricsTest.kt`.
2. `shared:lyrics/Lrc.kt`: LRC and plain text parsing, word stamps, `[bg:]`, `[offset:]`, `shifted`. Tests: `sharedTest:lyrics/LrcTest.kt`.
3. `shared:lyrics/SongFileLyrics.kt`: picking the lyrics tag and `looksTimed`. Tests: `sharedTest:lyrics/LyricsTest.kt` (songFileLyricsPreferTimedText).
4. `shared:lyrics/LyricsLook.kt`: styles, dials with ranges and defaults, `percent`, `with`, `fraction`. Tests: covered through the engine tests.
5. `subsonic:Models.kt` (StructuredLyrics, LyricsLine, LyricsAgent, CueLine, Cue, LyricsList, PlainLyrics) and `subsonic:LyricsPins.kt` (constants, LyricsCandidates, ServerLyricsCandidate, LyricsChoiceAnswer, `lyricsCandidatesParams`). Tests: `subsonicTest:LyricsClientTest.kt`, `subsonicTest:LyricsPinsTest.kt` with fixtures `subsonic/src/test/resources/fixtures/getLyrics*.json`, `setLyricsChoice.json`, `lyricsLookupsOff.json`, `getOpenSubsonicExtensionsOctoLyrics.json`.
6. `shared:lyrics/ServerLyrics.kt` (JVM: code points, Locale): `serverLyrics`, `joinLayers`, `cueWords`, `Utf8Positions`, companions, `sameLanguage`. Tests: `sharedTest:lyrics/ServerLyricsTest.kt`, `sharedTest:lyrics/ServerCuesTest.kt`, `appTest:lyrics/ServerCueKindsTest.kt`.
7. `shared:lyrics/OnlineLyrics.kt` (JVM: OkHttp; needs `shared:catalog/SongIdentity.kt` query variants and `same` verdicts from the catalog area): LRCLIB URLs, `find`, `exact`, `copiesOf`, `search`, `byId`, `bestSearchMatch`, `rankCopies`, `sameLyricsSong`, `sameTitleAndArtist`, `lyricsSearches`. Tests: `sharedTest:lyrics/LyricsTest.kt` (online parts), `sharedTest:lyrics/OnlineCopiesTest.kt`, `sharedTest:lyrics/LyricsMatchTest.kt`.
8. `shared:lyrics/engine/SyncLyrics.kt`: SyncWord, SyncLine, `alignRight`. Tests: `sharedTest:lyrics/engine/LyricMapperTest.kt` (rightToLeftAndDuetDecideTheSide).
9. `shared:lyrics/engine/Spring.kt`: closed-form spring, waits, speed, `springOffset`, the three lyric springs. Tests: `sharedTest:lyrics/engine/SpringTest.kt`.
10. `shared:lyrics/engine/LyricMotion.kt`: focus and stacking, on-screen test, ripple delays, opacity and blur targets, settle, blur steps, brightness, mask shape and slide, fill lead and progress, cubic bezier and easings, lift, emphasis, glyph pose, bob, dots, interlude open, arc pose. Tests: `sharedTest:lyrics/engine/LyricMotionTest.kt`, `sharedTest:lyrics/engine/WordFillTest.kt`.
11. `shared:lyrics/engine/LyricClock.kt`: projected, drift-corrected, seek-detecting clock with latency and tap hold. Tests: `sharedTest:lyrics/engine/LyricClockTest.kt`.
12. `shared:lyrics/engine/LineState.kt`: per-line springs, fades, press, motion window, brightness choice (the Compose version counters become whatever invalidation iOS uses). Tests: through `LyricEngineTest.kt`.
13. `shared:lyrics/engine/LyricMapper.kt` (JVM: `Character.getDirectionality`): lyrics to SyncLines, interludes, stretching, backing lines, brackets, credit skip, `timedWords`, `isRtl`, `sameText`. Tests: `sharedTest:lyrics/engine/LyricMapperTest.kt`, `sharedTest:lyrics/ServerCuesTest.kt`.
14. `shared:lyrics/engine/LyricEngine.kt`: the per-frame engine (status, heights, focus, targets, ripple, springs, fades, press, prepare and release, shown range, drag, follow again, tap). Tests: `sharedTest:lyrics/engine/LyricEngineTest.kt`, `appTest:lyrics/engine/LyricTimingLiveTest.kt`, `appTest:lyrics/engine/OutputTimingTest.kt`.
15. `app:lyrics/LyricsTiming.kt` (pure functions only: `lyricsClock`, `heardAt`, `totalOffset`, `stepTiming`, `screenLeadMs`, `automaticOutputTiming`, `outputTimingIn`, `outputOffsetIn`, `outputOffsetsIn`, `outputTimingAbout`, `automaticTimingNote`, `timingSummary`, `timingLabel`, `signedTiming`; plus storage key rules) with `app:sound/SoundEngine.kt` `AudioOutput`, `outputFor`, `savedFor`. Tests: `appTest:lyrics/LyricsTimingTest.kt`.
16. `app:lyrics/LyricsChoices.kt` (pick model, `encoded`, `decodePick`, `pickOf`, store rules). Tests: `appTest:lyrics/LyricsChoicesTest.kt`.
17. `app:lyrics/LyricsCandidates.kt` (origins, kinds, `kindOf`, candidate, preview, `candidateList`, `wordsOf`). Tests: `appTest:lyrics/LyricsCandidatesTest.kt`.
18. `app:lyrics/LyricsCache.kt` (`CachedLyrics.standsFor`, `recheckOnReturn`, `stillGood`, constants, file naming by SHA-1) and `app:lyrics/LyricsAnswers.kt` (memory LRU of 32, what a search may save). Tests: `appTest:lyrics/LyricsAnswersTest.kt`, `appTest:lyrics/LyricsStorageTest.kt`.
19. `app:lyrics/ServerChoices.kt` (`offersLyricsChoices`, `serverLyricsCall`, `lyricsSteps`, `lyricsSourceName`, `sourceLine`, `candidateLabel`, `serverKindOf`, `asCandidate`, `automaticCandidate`, `serverCandidates`, `showingPick`, `servedStale`, `splitLyricsSearch`, `sendServerChoice`). Tests: `appTest:lyrics/ServerChoicesTest.kt`.
20. `app:lyrics/LyricsRepository.kt` `searchInOrder`, `LyricsStep`, `LyricsSearch`, `CandidateSearch` (pure), then the repository's lookup, pick, choose, hide, show and candidate flows as described in sections 9 to 11 and 35. Tests: `appTest:lyrics/LyricsSearchTest.kt`.
21. `app:lyrics/LyricsFiles.kt` `lyricsFileNames` and `decodeText` (pure); the media lookup becomes the iOS file access equivalent. Tests: `appTest:lyrics/LyricsStorageTest.kt`.
22. `app:player/LyricsFeed.kt` `lyricsStates` (state machine with quiet retries, network wait, watched turns) and `LyricsWanted`. Tests: `appTest:player/LyricsFeedTest.kt`.
