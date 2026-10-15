# Parity contract: playback and data

Read from octo-player `origin/main` 0f11df0f (Android app plus the shared Kotlin core). Every line below is a behavior the iPhone app must match exactly. Nothing here is UI.

Path shorthand used in the citations:

- `app:` is `app/src/main/java/app/winters/octo/`
- `shared:` is `shared/core/src/commonMain/kotlin/app/winters/octo/`
- `sharedTest:` is `shared/core/src/commonTest/kotlin/app/winters/octo/`
- `appTest:` is `app/src/test/java/app/winters/octo/`
- `subsonic:` is `subsonic/src/main/kotlin/app/winters/octo/subsonic/`

## 1. Server song addresses in the queue

- [x] A server song sits in the queue under a private address `octo-stream://song/<url-encoded server id>`, never under a signed server URL; the URL is signed fresh at every open and every seek and is never stored (app:playback/StreamRef.kt:9, app:playback/Streams.kt:57-60)
- [x] The address carries query parameters in this order, each left out when unknown: `source=<sourceId>`, `mime=<mime type>`, `bitrate=<bits per second>`, `max=<kbps or raw>` (only once a request is pinned) (app:playback/StreamRef.kt:28-37)
- [x] Encoding is UTF-8 URL encoding with every `+` turned into `%20` (app:playback/StreamRef.kt:101)
- [x] Parsing returns nothing unless the scheme is `octo-stream` and the authority is `song`; the path (after the leading `/`) must be non-empty and contain no `/`; an empty `source` or `mime` reads as absent; a non-numeric `bitrate` reads as absent; `max=raw` pins the raw file, a numeric `max` pins that cap, any other `max` leaves it unpinned (app:playback/StreamRef.kt:41-61)
- [x] A song is "pinned" just before it loads: the exact request (raw or a kbps cap) is fixed into its address, so the saved copy and the signed URL always agree for that load (app:playback/StreamRef.kt:11-14, app:playback/Streams.kt:169-174, 231-234)
- [x] Pinning fills in the source id from the signed-in session when the address has none; with no source known at all the address is left as it is (app:playback/Streams.kt:169-174)
- [x] The saved-copy key of a server song is `<sourceId>|<serverId>|<mime or "unknown">|<maxKbps or "raw">`, never the signed URL (which carries a fresh random part each time) (app:playback/StreamRef.kt:63-67, app:playback/Streams.kt:215-218)
- [x] Any other address (phone file, radio station, opened file) uses its own key or its URI string as the cache key (app:playback/Streams.kt:216-218)

## 2. Stream quality per network

- [x] Stream sizes are `Original` (the file as it is), 320, 256, 192 and 128 kbps (shared:playback/StreamQuality.kt:5-11)
- [x] Defaults on a new install: Wi-Fi `Original`, mobile data `Original`, copy preference `PhoneFirst`, start-after `Short` (1 s); an unknown stored value falls back to the default (app:player/PlayerSettings.kt:111-117, 166-178)
- [x] Mobile data means the active network has neither the Wi-Fi nor the Ethernet transport; with no active network the phone is not "on mobile data" (app:playback/Streams.kt:95-103)
- [x] Online means the active network reports the internet capability; "on Wi-Fi" means online and not on mobile data (app:playback/Streams.kt:88-93) (iPhone: NWPathMonitor: a satisfied path is online, and on Wi-Fi is online and not mobile data)
- [x] The quality used: when the app does not pick (a family account whose device mode is not "Let this app decide"), always `Original`; else the mobile setting on mobile data, else the Wi-Fi setting (app:playback/Streams.kt:105-109, 331-335; shared:ui/family/AudioQuality.kt:88)
- [x] The app picks the quality when there is no family, or when the family device mode is `App` (shared:ui/family/AudioQuality.kt:84-88)
- [x] The request for a quality: `Original` asks for the raw file; a lossy file whose known bitrate in kbps (bits / 1000) is at or under the cap also asks for the raw file (re-encoding would only lose quality); anything else asks for an MP3 capped at the quality (app:playback/Copies.kt:113-119) (iPhone: files Apple's decoder cannot open (Ogg, Opus, WMA, APE, WavPack, DSD) are asked as an MP3 at the cap, or at 320 kbps for Original)
- [x] A raw request sends `format=raw`; a capped request sends `format=mp3`, `maxBitRate=<kbps>`, `estimateContentLength=true` (MP3 because every server offers it and constant-bitrate MP3 can be seeked and blended) (app:playback/Copies.kt:98-107)
- [x] The phone transcodes to MP3, not Opus; the shared `streamParams` Opus helper exists but the Android app never calls it (shared:ui/family/AudioQuality.kt:90-94)
- [x] What the player receives (for the quality badge): the original mime for a raw request, `audio/mpeg` for a capped one (app:playback/Copies.kt:109-110, app:playback/Streams.kt:121-125)
- [x] Lossless mime types: audio/flac, audio/x-flac, audio/alac, audio/wav, audio/x-wav, audio/wave, audio/vnd.wave, audio/aiff, audio/x-aiff, audio/ape, audio/x-ape, audio/wavpack, audio/x-wavpack (case-insensitive) (app:playback/Copies.kt:82-87)
- [x] Choosing the request for a load (in order): a pinned request wins; else the request for this connection when its saved copy is complete; else the first other size (largest first, raw counting as largest) whose saved copy is complete (costs no data, works offline); else this connection's request when partly saved; else the first other size partly saved (so a seek after moving from Wi-Fi to mobile reads the same file); else this connection's request (app:playback/StreamRef.kt:76-97)
- [x] The list of sizes a song could be asked in is every quality's request for it, duplicates removed, largest first (app:playback/StreamRef.kt:69-74)
- [~] Casting to another device always uses the pinned request or the Wi-Fi quality's request (app:playback/Streams.kt:176-179) (not on iPhone: Chromecast and DLNA are dropped; AirPlay carries the sound the phone's own decks make, so no device asks for the song itself)
- [~] A cast URL is signed for the address the phone uses now; none when no server is signed in or the song is another kept server's (app:playback/Streams.kt:181-188) (not on iPhone: with no casting, AirPlay included, no cast address is ever made)

## 3. Opening, signing and retrying a stream

- [x] The app waits up to 3 s for the saved sign-in to come back before deciding there is no server (app:playback/Streams.kt:51-52, 83-86) (iPhone: the saved sign-in comes back from the Keychain as the app starts; a stream request waits for it only within the first 3 s)
- [x] Read chain for a server song: pin the request into the address, then (while saved copies are kept) read through the saved-copy cache filling it from the server as it plays, else straight from the server; the server URL is signed as each read opens; phone files and other addresses open as they are (app:playback/Streams.kt:263-289)
- [x] Signing fails at once with "No connection" when offline, "No server signed in" with no session, "No song id" for an unreadable address (app:playback/Streams.kt:236-242)
- [x] A song whose address names another kept server's source id is never sent to the server in use ("Another server's song"); a song whose source id matches no kept server (an edited server's old address) still plays on the server in use (app:playback/Streams.kt:224-228, 243-246)
- [x] The signed URL is the server client's `stream` endpoint with `id=<serverId>` plus the request parameters (app:playback/Streams.kt:247-248)
- [x] An unreadable saved copy is skipped and the song is read from the server instead (app:playback/Streams.kt:207-213)
- [x] Retries: a load that failed because there is no connection, no server, or another server's song (or while offline) is not retried and fails at once so the song is skipped; any other failure retries on the platform default schedule (Media3: delay min((errors - 1) x 1000, 5000) ms, at least 3 tries; parse and not-found errors are not retried) (app:playback/Streams.kt:251-260)
- [x] Streams use a constant-bitrate seek for files without a seek table (a transcoded MP3) (app:playback/Streams.kt:142-143)
- [x] Downloads read a server song from its saved copy when one exists, otherwise from the server, and never fill the saved copies (app:playback/Streams.kt:159-165) (iPhone: a song saved whole is copied from the saved songs; one saved only in part downloads whole through the system's background transfer)
- [x] Every download request carries `X-Octo-Purpose: offline` on the server's own addresses so an Octo server does not count it as a play; no other host sees the header (app:playback/Streams.kt:198-203) (iPhone: the system's background transfer follows a redirect by itself)

## 4. Which copy of a song plays

- [x] A server copy is any copy whose source id starts with `server:`; every other copy is a file on the phone (app:playback/Copies.kt:10-11)
- [x] Copy choice: copies are ordered phone first; the playable ones are server copies only while the server is reachable and phone copies only while their file still exists; when none is playable all are still considered (so the chosen one fails and is skipped); the best is the highest quality, a tie keeping the earlier (phone); `PhoneFirst` takes the first phone copy in the pool, else the best; `BestQuality` takes the best (app:playback/Copies.kt:13-32)
- [x] Quality comparison, in order: lossless beats lossy; then higher sample rate; then deeper bit depth; then higher bitrate; a fact unknown (null or 0 or less) on either side is skipped (app:playback/Copies.kt:69-80)
- [x] Bitrate of a copy: its stored bitrate when above 0 (a value under 10 000 is kbps and is multiplied by 1000); else file size x 8 / seconds when both are known; else unknown (app:playback/Copies.kt:89-96)
- [x] With a download of the song: unless "stream on Wi-Fi" is on, the phone is on Wi-Fi and the server is reachable, the choice is made among the phone copies plus the download with the server treated as unreachable (a download plays like a phone file) (app:playback/Copies.kt:34-47, app:playback/PlayableSongs.kt:88-90)
- [x] A download as a copy: id `download:<server copy id>`, source `download`, its file URI, its format (or the server's mime when none), its file size (or the server's size when 0); bitrate, sample rate and bit depth are kept only when the format is the server's own (app:playback/Copies.kt:49-67)
- [x] The download is matched to the server copy with the same source id and server id, else to the first server copy (app:playback/PlayableSongs.kt:93-96)
- [x] The server is reachable for copy choice only when some asked song has a server copy, the phone is online, and a signed-in client exists (app:playback/PlayableSongs.kt:82-84)
- [x] Missing phone files are checked only when the server is reachable, by asking the media store for the ids in the file URIs in batches of 900; without permission to read music every phone file counts as missing (app:playback/PlayableSongs.kt:85-86, 108-130)
- [x] A song with no copy plays from the catalog row's own URI and mime (app:playback/PlayableSongs.kt:100-101)
- [x] The tempo (BPM) sent with a song is the playing copy's when above 0, else the first other copy's above 0 (app:playback/Copies.kt:124-127)
- [x] The stored loudness sent with a song is the playing copy's ReplayGain, else the first other copy's (app:playback/Copies.kt:129-132)

## 5. Turning ids into playable queue items

- [x] The app sends only song ids (plus a source word); the service turns them into playable items (app:playback/MediaItems.kt:91-99, app:playback/OctoPlaybackService.kt:585-624) (iPhone: the player runs inside the app, with no separate service; lists still reach it by song id)
- [x] Ids resolve in order, one result per id: a radio id plays its stream; an opened-file id plays its file while readable; a find (song found online) plays as the library song it was adopted as while the library has it, else streams from the server; a library id plays from its chosen copy; an id the app no longer knows yields nothing (app:playback/PlayableSongs.kt:25-27, 51-69)
- [x] A find streams with its own source id, server id and mime, its bitrate (kbps) multiplied by 1000 (app:playback/PlayableSongs.kt:71-74)
- [x] Ids are looked up in batches of 900 (SQLite limit) and returned in the order asked, dropping unknown ones (app:playback/Stores.kt:36-41, app:playback/PlayableSongs.kt:57)
- [x] Starting a list at a chosen song: its place counting only songs still playable; when the chosen song is gone, the first song (app:playback/PlayableSongs.kt:29-34)
- [x] A list played from the app carries its name (or no name) on every song as its queue source; songs added by Play next or Add to queue (from the app or a car) are the listener's own (You); ids the app no longer knows are dropped (app:playback/OctoPlaybackService.kt:577-579, 585-624; app:playback/PlaybackConnection.kt:140-152, 225-229)
- [x] A queue item carries: id, URI, mime, title, artist, album, track number, disc number, year, listed length, artwork reference, album id, artist id, file mime, album order, explicit flag, BPM (only 1 to 999), and stored track/album gain and peak (app:playback/MediaItems.kt:48-89, 131-133)
- [x] Lock screen and notification artwork is drawn from the artwork reference at 512 px (app:playback/MediaItems.kt:101-118) (iPhone: the lock screen's Now Playing artwork (MPNowPlayingInfoCenter), drawn at 512 px)
- [x] A radio station id is `radio:<url-encoded stream URL>:<url-encoded name>` (each trimmed); it plays the URL as is, titled with its name (or the URL when unnamed), artist "Radio"; a live stream never crossfades and never counts as a play (app:playback/RadioItems.kt:8-47)
- [x] An opened file id is `file:<url-encoded URI>:<url-encoded title>:<url-encoded artist>`; before playing, the file is opened to check it can be read (a `file` path must be readable, a `content` URI must open, anything else fails); one that cannot be read is dropped quietly, also from a restored queue; its title falls back to the URI's last path segment, then "Audio file"; it has no listed length, so (despite the source comment saying it never counts) it can count as a play once the player has measured its length, at the moment it moves on (see section 20); such a play is stored locally under its `file:` id (never shown, since no library song has that id), may go to ListenBrainz, and never reaches a server (app:playback/OpenedFileItems.kt:14-74; app:playback/OctoPlaybackService.kt:352-366; app:playback/PlayTracker.kt:60-66)

## 6. Decks, audio focus and volume

- [x] Playback runs on two decks sharing one audio session (so an equalizer app hears both); the deck playing is what everything talks to (app:playback/OctoPlayer.kt:23-43, 73-104) (iPhone: both decks are audio source nodes in one AVAudioEngine under one audio session; iOS lets no other app attach an equalizer)
- [x] Each deck plays as media/music, pauses when the output becomes noisy (headphones unplugged), and holds a CPU wake lock while playing (app:playback/OctoPlayer.kt:30-43) (iPhone: the audio session plays as long-form music; a lost output (headphones out) pauses; the background audio mode keeps it running)
- [x] Audio focus is owned above the decks: playing asks for focus; when refused (a call) playback stays paused (app:playback/OctoPlayer.kt:45-69, 175-183)
- [x] Focus lost for good (another app plays): pause, never resume by itself, give focus back (app:playback/OctoPlayer.kt:155-160) (iPhone: an AVAudioSession interruption that never says to resume (another app took the sound) leaves it paused, and the system takes the session back)
- [x] Focus lost for a moment (a call, a prompt): pause, and resume on focus gain only if it was playing (app:playback/OctoPlayer.kt:161-171) (iPhone: AVAudioSession interruptions: a beginning pauses, an end that says to resume plays again only if it was playing)
- [x] Focus lost with ducking allowed: volume drops to 0.2; focus regained restores it (app:playback/OctoPlayer.kt:71, 166-168) (iPhone: iOS lowers Octo's sound itself when another app asks to duck others, so there is no duck call to answer)
- [x] Pausing by the listener cancels any pending resume-on-focus and ends any blend (app:playback/OctoPlayer.kt:178-181)
- [x] Deck volume is (0.2 when ducked else 1) x the sleep timer's fade, set on the playing deck and on the outgoing deck during a blend; the spare stays at 0 until handed over (app:playback/OctoPlayer.kt:326-333) (iPhone: ducking is the system's (above); the sleep fade sits on the playing and outgoing decks and the spare stays silent)
- [x] Stopping or releasing gives focus back (app:playback/OctoPlayer.kt:291-301) (iPhone: Stop and Close end the audio session and tell other apps they may play; after a pause the sound is let go after 10 minutes (30 with a headphone switch on))
- [x] Speed and pitch are set on both decks, so a blend never jumps in pace (app:playback/OctoPlayer.kt:284-289)
- [x] Skip silence is set on both decks (app:playback/OctoPlayer.kt:133-138)
- [x] Any seek, new queue, add, remove, move, replace, shuffle change, repeat change or stop ends a blend at once first (app:playback/OctoPlayer.kt:185-282)
- [x] Each queue entry gets an entry id `q:<n>` as it goes in (counter from 0 per player), unless it already has one, so the same song twice is two entries (app:playback/OctoPlayer.kt:105-106, 255-257; app:playback/QueueEntries.kt:6-9)

## 7. When a stream starts playing (buffering)

- [x] Phone files start by the platform's default rule; streams start once the buffered audio, in real time at the current speed (buffered / speed, except at speed 1 or 0 and below), reaches the start-after setting (app:playback/OctoLoadControl.kt:11-45) (iPhone: phone files start after 250 ms of sound (2 s after running dry), as iOS has no player default for Octo's own decoder)
- [x] After running dry mid-song, a stream waits for the larger of the start-after setting and the platform's after-rebuffer amount (Media3 2 000 ms) (app:playback/OctoLoadControl.kt:41-45)
- [x] Start-after choices: "As soon as possible" 250 ms, "1 second" 1 000 ms (default), "2.5 seconds" 2 500 ms, "5 seconds" 5 000 ms, "10 seconds" 10 000 ms; label "Start playing after", help "Waits for this much audio before a song starts. Shorter starts faster on a slow connection; longer stutters less." (shared:playback/StartAfter.kt:3-14)
- [x] A change to start-after reaches every deck at once (app:playback/OctoPlaybackService.kt:232-234)

## 8. Gapless and crossfade rules

- [x] Crossfade settings: off by default; longest blend 8 s by default, range 2 to 16 s; smart transitions on; filter sweeps on; match tempo off (app:player/PlayerSettings.kt:45-53, 119-120)
- [x] The longest blend used is crossfadeSeconds x 1000 when crossfade is on, else 0 (off) (app:player/PlayerSettings.kt:90-95)
- [x] No crossfade (plain gapless) when: crossfade off, nothing next, repeat one, the player stops at the end of the song (sleep timer), or either length is unknown (0 or less) (shared:playback/Crossfade.kt:17-25)
- [x] An album played in order stays gapless: same album id and the next song's album order is exactly this one's plus 1 (shared:playback/Crossfade.kt:26-32)
- [x] The plain blend length is min(longest blend, half the shorter song); under 500 ms it is no blend at all (shared:playback/Crossfade.kt:11-12, 33-34)
- [x] The plain equal-power fade: out = cos(p x pi / 2), in = sin(p x pi / 2), p clamped 0 to 1 (shared:playback/Crossfade.kt:37-41)
- [x] When the next song's length is unknown but any length would blend, the next song is opened early on the spare deck (from its start) once the real time left is at most the longest blend + 15 s, and the blend is decided once it reports its length (app:playback/BlendTiming.kt:6-28, app:playback/Crossfader.kt:223-232)
- [x] The spare loads a song with a known length 5 s ahead of the blend in the timing helper (SPARE_LOAD_AHEAD_MS) and 15 s ahead when the length is unknown (app:playback/BlendTiming.kt:3-9, 24-28)
- [x] Songs played gaplessly are left to the player's own gapless handling; the spare is emptied (app:playback/Crossfader.kt:233-239)
- [x] The next song's length for blending is what the spare measured once it holds that song at that index, else its listed length corrected by what earlier plays learned (app:playback/Crossfader.kt:307-313, app:playback/BlendTiming.kt:11-14)
- [x] The playing song's length is the deck's measured length when believable, else the listed (corrected) length (app:playback/Crossfader.kt:299-305)
- [x] All blend timing is in real time: time left = (length - position) / speed (app:playback/Crossfader.kt:220-221)
- [x] The longest blend is in song time, scaled by the speed: at 1.5x an 8 s setting covers 12 s of song and still lasts 8 s (app:playback/AutomixTiming.kt:44-48)
- [x] A song whose audio path was set up before crossfade came on cannot be shaped and plays out without a blend (logged "this song started before crossfade was on, so it plays out") (app:playback/Crossfader.kt:480-488) (iPhone: every deck always runs through Octo's sound processor, so no song can start before crossfade could shape it)
- [x] Turning crossfade on or off is read before the saved queue is restored at start, because it decides how each deck's audio path is built; while on, each deck's sound processor stays in the path even when nothing else is shaped (app:playback/OctoPlaybackService.kt:134-135, 163-173, 203-212; app:sound/OctoDspProcessor.kt:200-205, 254-259)
- [x] A change to any automix setting ends a blend under way (app:playback/Crossfader.kt:60-66)

## 9. Crossfader: when the next song is prepared and the blend runs

- [x] The crossfader checks the playing song every 1 000 ms while the end is far off and every 40 ms near it and during the blend (app:playback/Crossfader.kt:21-24)
- [x] While a tempo-matched song eases back to its own speed, checks run at least every 200 ms (40 x 5) (app:playback/Crossfader.kt:679-683)
- [x] Playing starts the checks at once; a pause (by the listener, a call, unplugged headphones) finishes any blend at once, drops the run-up and stops checking, except when a blend is under way and the incoming deck is only rebuffering (playWhenReady true, buffering, not suppressed): then the blend rides it out, checking every 40 ms (app:playback/Crossfader.kt:140-156; app:playback/AutomixTiming.kt:38-42)
- [x] A song change that is not the blend's own (skip, new queue) drops the plan and empties the spare (app:playback/Crossfader.kt:158-164)
- [x] Not playing but wanting to (loading after a seek): keep checking every 40 ms; truly paused: stop until playing again (app:playback/Crossfader.kt:191-198)
- [x] With the longest blend 0, nothing next, or no current song: no plan, spare emptied, check again in 1 s (app:playback/Crossfader.kt:199-206)
- [x] A position more than 2 000 ms away from where it should be since the last check (last position + elapsed x speed) counts as a jump (a seek): the run-up and plan are dropped and made again (app:playback/Crossfader.kt:209-212, 315-323; app:playback/AutomixTiming.kt:34-36)
- [x] A plan is made once the end of the playing song, the start of the next and the live reading of the playing song are all in, or without waiting when smart transitions are off or there is no scout, or once the real time left is at most longest blend + 15 000 + 3 000 + 1 000 ms (app:playback/Crossfader.kt:443-449)
- [x] A plan is made again whenever any of these change: current entry, next entry, either length, the settings, repeat one, stop at end of song, speed, skip silence, or whether the tail, head or reading became ready (app:playback/Crossfader.kt:124-138, 415-441)
- [x] Waiting on the scouts: check every 1 s while time left exceeds longest blend + 30 000 ms, else every 40 ms (app:playback/Crossfader.kt:247-252)
- [x] A gapless plan empties the spare and checks every 1 s (app:playback/Crossfader.kt:253-257)
- [x] The spare loads the next song once the real time to the blend's start is at most 15 000 ms (PLAN_LOAD_LEAD_MS) (app:playback/Crossfader.kt:258-259; app:playback/AutomixTiming.kt:12-14)
- [x] Loading the spare: it gets the whole queue, positioned on the next song at the run-up start (0 with no plan), the same shuffle order and shuffle mode, the same repeat mode, the same speed and pitch (the beat-match rate replaces the speed when the plan has one, pitch kept), the same skip-silence, volume 0, not playing, armed with the incoming side of the plan, then prepared (app:playback/Crossfader.kt:499-521, 536-539)
- [x] A new plan for a song already loaded re-arms it and re-paces it, and moves it only if it is more than 40 ms from the new run-up start (a move would reload it) (app:playback/Crossfader.kt:523-534; app:playback/AutomixTiming.kt:66-71)
- [x] The run-up starts 40 ms before the run-up point in the playing song, only if the spare is ready; if it is not ready the plan is dropped (logged once per next song "the next song was not ready for its run-up") and a later plan is made (app:playback/Crossfader.kt:261-275)
- [x] Run-up start: the playing deck is armed with the outgoing side of the plan and its silence gate; the spare seeks to where the next song should be now if that is more than 40 ms ahead of where it is, then plays (still silent) (app:playback/Crossfader.kt:545-555)
- [x] During the run-up the two decks are lined up (see Aligner); once the playing song reaches the blend start the hand-over happens (app:playback/Crossfader.kt:276-283, 557-565)
- [x] Next check after a step: 1 s when the blend start is more than 16 000 ms of real time away, else 40 ms (app:playback/Crossfader.kt:285)
- [x] When the alignment did not lock to the beat on a bar-locked plan, the outgoing low-pass is re-armed to sweep smoothly instead of stepping on beats (app:playback/Crossfader.kt:567-575)
- [x] Hand-over: the alignment is settled with what was measured last; the old deck is told to stop at the end of its song; the incoming deck becomes the one everyone talks to (volume set, playing); the old deck becomes the next spare; the plan is logged with its reason and alignment ("aligned to N ms", ", on the beat") (app:playback/Crossfader.kt:577-597; app:playback/OctoPlayer.kt:303-314)
- [x] During the blend the old deck plays out until its position reaches blend start + overlap, it ends, or it is paused; then it is stopped, emptied and its stop-at-end cleared, both decks are disarmed, and a blend under 95 % finished is logged as cut short (app:playback/Crossfader.kt:599-606, 632-649)
- [x] A tempo-matched incoming song eases back to its own speed after the blend: the rate follows the plan's curve and is only changed in steps of at least 0.0025, landing exactly on the listener's speed when done; the listener changing speed, or the deck changing, stops the easing; an interruption restores the listener's speed at once (app:playback/Crossfader.kt:34-35, 608-630)
- [x] Releasing the player cancels all scouting, releases the scout and the spare (app:playback/Crossfader.kt:175-183) (iPhone: the player lives as long as the app, so its scout and spare go with it)
- [x] A song change during a blend counts as the song ending on its own (for the sleep timer) (app:playback/OctoPlayer.kt:114-116; app:playback/SleepTimer.kt:36-41)

## 10. Lining the decks up (Aligner)

- [x] The incoming song starts playing silently 2 500 ms (in the playing song's time, x the incoming rate) before its entry point, never before 0; with no overlap the run-up starts at 0 (app:playback/AutomixTiming.kt:8-10, 73-75)
- [x] The run-up point in the playing song is blend start - (entry - run-up start) / incoming rate (app:playback/AutomixTiming.kt:77-78)
- [x] Where the incoming song should be when the playing song is at x: entry + (x - start) x incoming rate; the incoming rate is the beat-match rate or 1 (app:playback/AutomixTiming.kt:57-58, 80-81)
- [x] The offset is (incoming - entry) / rate - (outgoing - start), positive when the incoming song runs ahead (app:playback/AutomixTiming.kt:83-86)
- [x] The decks are first measured 1 000 ms after the incoming song starts playing, and 400 ms after it plays again following a correction (app:playback/AutomixTiming.kt:16-19)
- [x] An offset of 10 ms or less is left alone; at most 3 corrections are tried; no correction is tried with under 400 ms left before the blend (app:playback/AutomixTiming.kt:21-32, 129)
- [x] Each correction seeks the incoming song to where it should be at (outgoing position + measured lag), never below 0; the lag after each correction (minus the error seen) is added to the next (app:playback/AutomixTiming.kt:88-135)
- [x] With the incoming deck not playing, the aligner waits, or settles once the blend start is reached (app:playback/AutomixTiming.kt:117-125)
- [x] Settled: carries the last measured offset (or none) and "locked" when that offset is under 15 ms (filters step on the beat only then) (app:playback/AutomixTiming.kt:24-25, 140-143)

## 11. Reading ahead (scout) and server transition profiles

- [x] Scouting runs only with smart transitions on and a scout available (app:playback/Crossfader.kt:329-331)
- [x] The end of the playing song is read once per queue entry, after it has played 1 000 ms and only if it is at least 35 000 ms long: the last 60 000 ms (from max(0, length - 60 000) to length) (app:playback/Crossfader.kt:26-28, 333-353; app:playback/Scout.kt:23-26)
- [x] The start of the next song is read once per queue entry as soon as it is known: its first 30 000 ms (app:playback/Crossfader.kt:354-375)
- [x] Each part comes from the server's transition profile when the server has one, else from scouting the file; a song with no address is marked done with no analysis (app:playback/Crossfader.kt:393-413)
- [x] Once both parts are in, the playing deck's live reading of the song (heard time, body level, tempo) is taken once per entry, off the main thread (app:playback/Crossfader.kt:376-390)
- [x] The scout decodes on 2 low-priority background threads (so the next song's start never waits on the playing song's end), each stretch cancellable, each giving up after 20 000 ms; answers come back on the main thread unless cancelled (app:playback/Scout.kt:20-21, 31-97)
- [x] Decoding seeks to the sync point before the start, skips frames before it, stops at the end time or end of stream, gives up on a stretch whose format changes part way (keeping what it has), and returns nothing when cancelled or empty (app:playback/Scout.kt:99-191) (iPhone: Apple's file reader seeks to the exact frame and hands out one fixed format, so there is no sync point to skip from and no change of format part way)
- [x] The scout reads through the same chain as playback (pin, saved copies, signing), so what it reads is saved for playing too, and always names the unsigned address so a reopen goes through the whole chain again (app:playback/Streams.kt:133-140; app:playback/ScoutSources.kt:49-78)
- [x] Before reading a server song over HTTP the scout asks for its first byte alone and needs a non-blank `Content-Range` answer; a server that sends the whole song every time is not scouted ("the server sends this song only whole"); a saved copy never asks the server (app:playback/ScoutSources.kt:11-47)
- [x] Profiles are asked only when the session's saved `isOcto` flag is set (the Octo status page `api/admin/status` answered with an `octo` key at sign-in, which only happens on the home network; not the broader "runs Octo" test), and only for songs whose address is from the server in use (or names no server) (app:playback/ServerProfiles.kt:24-29, 61-77; app:data/OctoProbe.kt:13-35; app:data/SessionRepository.kt:306-322)
- [x] The server is taken to offer profiles when its extensions list `octoTransitions` version 1; otherwise it is asked once whether it supports them and a definite answer is remembered; a server that says no is never asked for profiles and the songs are scouted (app:playback/ServerProfiles.kt:44-59, 71)
- [x] The kept profiles start over whenever the server in use changes (app:playback/ServerProfiles.kt:43-51; shared:playback/AutomixProfile.kt:145-149)
- [x] The 64 most recently used profiles are kept (shared:playback/AutomixProfile.kt:99-111)
- [x] A "not ready" or failed answer is believed for 60 000 ms before the song is asked about again; the list of such songs is cleared once it passes 256 (shared:playback/AutomixProfile.kt:94-97, 113-143)
- [x] A profile is used only when ready, of version 1, with a length above 0, and with both a head and a tail whose hop is above 0 and whose levels decode from base64; levels are byte codes meaning -100 + code x 0.5 dB; a tempo needs bpm and beat length above 0 (shared:playback/AutomixProfile.kt:8-16, 48-91)
- [x] With a profile's tail, no heard level goes to the planner (the profile is already measured against the whole song) and the tempo is the profile's trusted whole-song tempo, else the heard one; without a profile, the heard body level is used only after 20 000 ms has been heard (app:playback/Crossfader.kt:30-32, 462-464; app:playback/AutomixTiming.kt:50-55)
- [x] The played time told to the planner is the time heard x speed when a reading exists, else the position (app:playback/Crossfader.kt:467)
- [x] The outgoing silence gate armed at the run-up: the tail's gate (re-measured against the heard body level when there is one), else max(-60, heard body level - 45) dB (app:playback/Crossfader.kt:492-496)
- [x] Scouted analysis uses the song's tag BPM (1 to 999) to pick the tempo's octave (app:playback/AutomixTiming.kt:60-64; app:playback/MediaItems.kt:128-133)

## 12. Planning a transition (shared AutomixPlan)

- [x] Kinds: GAPLESS (no overlap), CROSSFADE (fixed equal-power at the end), CUT (short planned swap), LIFT (planned blend into a louder song), BLEND (planned blend) (shared:playback/AutomixPlan.kt:44-60)
- [x] When the plain crossfade length is 0 (or nothing next) the plan is gapless, starting at the song's length, with reason "gapless: " + one of: "crossfade off", "nothing next", "repeat one", "stopping at the end of the song", "a song's length is unknown", "the album plays in order", "a song too short to blend" (shared:playback/AutomixPlan.kt:175-178, 396-409, 446-454)
- [x] Smart transitions off: the fixed equal-power crossfade at the end (start = length - plain, entry 0, curve 0, no filters, no headroom, reason "smart transitions off") (shared:playback/AutomixPlan.kt:181, 411-429)
- [x] A genre on either song matching classical, opera, spoken, audiobook, podcast or comedy (case-insensitive, anywhere in the text): the end crossfade with curve 0.4, 1 dB headroom, no filters, reason "genre <genre>" (shared:playback/AutomixPlan.kt:41-42, 182-184, 431-444)
- [x] Either song under 35 000 ms: the same end crossfade, reason "a song under 35 s" (shared:playback/AutomixPlan.kt:9-10, 185-187)
- [x] Planned blends are capped at min(longest blend, half the shorter song) (shared:playback/AutomixPlan.kt:189)
- [x] Filter strength is 0.7 with filter sweeps on, else 0 (shared:playback/AutomixPlan.kt:190; shared:playback/AutomixCurves.kt:19-20)
- [x] The next song's entry is its sound start from the head analysis (0 without one) (shared:playback/AutomixPlan.kt:191-192)
- [x] Bar lock and tempo match are possible only at speed 1 with skip silence off (shared:playback/AutomixPlan.kt:193)
- [x] The latest a blend may end is 250 ms before the song's end (shared:playback/AutomixPlan.kt:16-17, 194)
- [x] Without a tail analysis, or when the tail's sound end or outro is unknown (silent), a late plan is made: reason "no analysis of this song's end" or "this song's end is silent" (shared:playback/AutomixPlan.kt:196-205)
- [x] Late plan: ends at the latest end; starts at the later of now and latest end - overlap; under 500 ms long it is gapless ("too late to blend: <why>"); else CUT/LIFT/BLEND by the usual kind rule, with the curve and filters but no bar lock, no tempo match, `late` set, 1 dB headroom, reason "late <kind> at <s> over <s>, next song from <s>: <why>" (shared:playback/AutomixPlan.kt:361-394)
- [x] With a heard body level, the tail is re-measured against it before planning (shared:playback/AutomixPlan.kt:199)
- [x] Latest end = min(sound end, length - 250); outro start = min(outro, latest end) (shared:playback/AutomixPlan.kt:207-208)
- [x] The tail's tempo counts only when trusted; with a whole-song tempo it is moved to that tempo's octave and dropped if then more than 4 % away from it (shared:playback/AutomixPlan.kt:209-215)
- [x] Bar lock needs a trusted tail tempo and a trusted head tempo (and lock allowed); the tempo ratio is folded by halving or doubling into 0.707 to 1.414 (shared:playback/AutomixPlan.kt:216-219, 336-344)
- [x] With bar lock, the entry snaps to the next song's nearest beat when within 300 ms (never below 0) (shared:playback/AutomixPlan.kt:34-35, 221-226)
- [x] Overlap with bar lock: 4 bars of the playing song, or 2 bars when the tempo ratio is more than 8 % off; without: latest end - outro start (shared:playback/AutomixPlan.kt:228-234)
- [x] When the next song's quiet start (its intro end - entry) is longer than the overlap, the overlap grows to cover it, in whole bars (rounded up) under bar lock (shared:playback/AutomixPlan.kt:235-246)
- [x] The overlap is then held between 1 800 ms and the cap; under bar lock, if that cut it below whole bars, it becomes the most whole bars that fit (if at least 1 bar and at least 1 800 ms), else bar lock is given up for the length; then rounded to whole ms (shared:playback/AutomixPlan.kt:12-14, 247-254)
- [x] Earliest start: the largest of 50 % of the song, 30 000 ms, the point where the song will count as played (now + max(0, min(length / 2, 240 000) - played)), latest end - 45 000 ms, the start of the tail analysis, and now + 3 000 ms (pre-roll) (shared:playback/AutomixPlan.kt:19-29, 256-263)
- [x] Latest start = latest end - overlap; when it is before the earliest start, a late plan ("no start left before <s>") (shared:playback/AutomixPlan.kt:264-267)
- [x] Candidate starts: the bar lines between earliest and latest under bar lock; else every 250 ms back from the latest start (shared:playback/AutomixPlan.kt:31-32, 269-275)
- [x] Scoring each candidate: -0.08 per second the blend ends before the latest end; -0.15 per second away from the outro start when the outro starts more than 1 s before the latest end; +1.0 when within 250 ms of a section boundary; under bar lock +0.6, plus +0.8 when a whole multiple of 8 bars back from the phrase anchor (the bar line nearest the outro start); -1.5 x the share of the overlap at or above body level - 3 dB; the highest score wins, a tie going to the later candidate (shared:playback/AutomixPlan.kt:276-295)
- [x] Tempo match (setting on, bar lock): only when the folded ratio is 0.5 % to 4 % off 1; the rate is the ratio held to 0.94 to 1.06, and the entry moves to the next song's first bar line at or after sound start - 300 ms (shared:playback/AutomixPlan.kt:297-304)
- [x] Kind: overlap of 2 400 ms or less is a CUT; a LIFT when the next song's first 8 s from entry are at least 3 dB louder than this song over the overlap; else a BLEND (shared:playback/AutomixPlan.kt:346-352)
- [x] Curve weights: CUT 0.75, LIFT 0.55, BLEND 0.2, CROSSFADE 0.4 (shared:playback/AutomixPlan.kt:354-359; shared:playback/AutomixCurves.kt:11-17)
- [x] Planned blends play both songs 1 dB quieter through the overlap (shared:playback/AutomixPlan.kt:37-39)
- [x] Start and entry are rounded half up to whole ms; the reason reads "<kind> at <s> over <s> (<n> bars of <bpm> BPM), next song from <s> (full from <s>), outro at <s>, latest end <s>, no analysis of the next song's start, rate <x.xxx>", times as seconds with two decimals (shared:playback/AutomixPlan.kt:306-333, 456-470)
- [x] The plan's beats inside the blend (outgoing tempo grid) leave out any beat within a twentieth of a beat of either end (shared:playback/AutomixPlan.kt:126-138)
- [x] The outgoing low-pass steps on the beat when bar-locked, gliding over an eighth of a bar (shared:playback/AutomixPlan.kt:140-146)

## 13. Transition curves and filters (shared AutomixCurves, AutomixFilters)

- [x] Out volume at t: cos(t x pi / 2) x (1 - k) + (1 - S(t)) x k, clamped 0 to 1, where S is the logistic curve 1 / (1 + e^(-12 (t - 0.5))) rescaled to run exactly 0 to 1 (shared:playback/AutomixCurves.kt:43-56)
- [x] In volume keeps the squares summing to 1: sqrt(1 - out^2) (shared:playback/AutomixCurves.kt:58-62)
- [x] Outgoing low-pass falls on a log scale from 18 000 Hz toward 18 000 x (450 / 18 000)^strength (shared:playback/AutomixCurves.kt:22-25, 64-71)
- [x] Stepped low-pass: holds each beat's cutoff until `glide` before the next beat, then glides to it (shared:playback/AutomixCurves.kt:73-89)
- [x] Outgoing bass cut (high-pass) rises on a log scale from 10 Hz to max(10, 300 x strength) Hz by the middle of the blend and holds (shared:playback/AutomixCurves.kt:27-31, 91-96)
- [x] Incoming high-pass starts at max(20, 675 x strength) Hz and opens to 20 Hz by 60 % through the blend (shared:playback/AutomixCurves.kt:33-37, 98-103)
- [x] A tempo-matched song plays at its rate through the blend, then eases back to 1 over 5 000 ms on a half-cosine (shared:playback/AutomixCurves.kt:39-41, 105-112)
- [x] Filters are Butterworth second-order sections (Q 0.7071), cookbook low-pass and high-pass, cutoff held between 1 Hz and 45 % of the sample rate (shared:playback/AutomixFilters.kt:8-61)

## 14. Running the transition on the sound

- [x] Each deck's sound processor runs its side of the plan on that deck's own song time (stream start + frames x 1000 x speed / rate), so both reach the same place in the blend together (app:sound/OctoDspProcessor.kt:335-348; app:sound/TransitionShaper.kt:36-51) (iPhone: the sound processor sits before Apple's time-pitch unit, so each deck's frames are already the song's own time)
- [x] An armed transition applies only to its own queue entry; a stream whose entry is unknown takes it too (app:sound/OctoDspProcessor.kt:344-346)
- [x] Outgoing progress = (song time - start) / overlap; incoming progress = (song time - entry) / beat rate / overlap (app:sound/TransitionShaper.kt:60-67)
- [x] Gain: incoming 0 before, full after, in-curve x headroom inside; outgoing full before, 0 after, out-curve x headroom inside (app:sound/TransitionShaper.kt:69-77)
- [x] Headroom (1 dB) ramps in over the first 15 % of the blend and out over the last 15 % (app:sound/TransitionShaper.kt:32-34, 79-84)
- [x] Filters run only inside the blend and only with a filter strength above 0; the low-pass is outgoing only; the high-pass is the bass swap going out and the thin start coming in (app:sound/TransitionShaper.kt:86-95)
- [x] The volume never moves faster than silence-to-full in 30 ms, so arming or dropping never clicks (app:sound/TransitionShaper.kt:16-18, 230)
- [x] Filters fade in and out over 10 ms, mixed with the dry sound (app:sound/TransitionShaper.kt:20-23, 231-241)
- [x] Volume and cutoffs are recomputed every 32 frames; a cutoff change under 0.1 % is ignored (app:sound/TransitionShaper.kt:25-26, 137-142)
- [x] Early fade: through the blend the outgoing song is measured in 10 ms blocks before any volume change; once below its silence gate for 300 ms it fades out (at the slew limit) for good (app:sound/TransitionShaper.kt:28-30, 258-280)
- [x] An incoming song armed fresh starts at its curve's volume at once (silent), never fading down; an outgoing song armed late glides to the curve (app:sound/TransitionShaper.kt:187-200)
- [x] An outgoing song before its blend passes through untouched; an incoming song past its blend at full volume with filters off is released (app:sound/TransitionShaper.kt:205-210, 252-255)
- [x] The live reading: while crossfade is on, every sample the listener hears is copied to a ring of 2^18 samples (dropped when full) and fed to a per-song tap every 100 ms on a low-priority worker; a new song starts a new tap at its first sample (app:sound/LiveTapFeed.kt:10-105; app:sound/OctoDspProcessor.kt:310-311)
- [x] The reading answers only for the entry the deck is playing: heard ms, body level of all heard, and the trusted tempo of all heard with the tag BPM picking the octave (app:sound/LiveTapFeed.kt:107-115; shared:playback/AutomixFeatures.kt:629-650)

## 15. Song analysis for transitions (shared AutomixEnvelope, AutomixFeatures)

- [x] The envelope has one value per 10 ms hop: whole-band RMS level in dBFS, bass level below 150 Hz (second-order low-pass), spectral-flux onset (three bands: below 150 Hz, 150 to 2 500 Hz, above 2 500 Hz; mean rise of ln(1 + 100 x magnitude x 4 / 1024) per band, rises only, summed), and the bass band's onset alone (shared:playback/AutomixEnvelope.kt:12-63)
- [x] Samples are summed to mono per frame (16-bit read as / 32 768); each hop's onset uses a Hann-windowed 1 024-sample FFT of the last 1 024 mono samples (zeros before the first); the first hop's onset is 0; a hop with mean square at or under 1e-10 reads -100 dB, never below -100 (shared:playback/AutomixEnvelope.kt:65-214)
- [x] Hop k covers frames k x rate x 10 / 1000 up to (k + 1) x rate x 10 / 1000; a last partial hop is left out (shared:playback/AutomixEnvelope.kt:89-93, 122, 203-209)
- [x] Levels are smoothed (power averaged) over 400 ms (body), 50 ms (sound) and 1 000 ms (outro) windows centred on each hop, fewer hops at the edges (shared:playback/AutomixFeatures.kt:73-76, 335-345)
- [x] Body level: the 75th percentile (head, or a whole song) or 90th percentile (tail) of the 400 ms level over hops above the gate, taking the lower neighbour; measured twice, first above -60 dB, then above its own gate (shared:playback/AutomixFeatures.kt:24-29, 278-289, 347-353)
- [x] Silence gate = max(-60, body - 45) dB; sound start/end are the first/last hop whose 50 ms level is above the gate (end = the hop after) (shared:playback/AutomixFeatures.kt:11-15, 301-312)
- [x] Outro start: after the last hop whose 1 000 ms level is at or above body - 6 dB (capped at the sound end); intro end: the first such hop (shared:playback/AutomixFeatures.kt:17-18, 313-321)
- [x] Section boundaries: hops where the mean 400 ms level of the 2 s after differs from the 2 s before by 4 dB or more, keeping only the strongest change within 2 s either way, earlier winning a tie, none within 2 s of another (shared:playback/AutomixFeatures.kt:20-22, 355-383)
- [x] Tempo search: 70 to 180 BPM, periods tried every 0.1 hop; onsets lose their mean over 1 000 ms around each hop (rises only) and then their overall mean; the score is the normalized autocorrelation at 1, 2, 4 and 8 periods plus 0.5 x at half a period; the first best period wins; no tempo when the onsets hardly move (lag-0 value under 1e-4), nothing scores above 0, or there are fewer than 2 x (longest period + 1) hops (shared:playback/AutomixFeatures.kt:31-67, 469-528)
- [x] A tempo is trusted when its score is at least 0.4 and each half of the sounding hops picks the same period within 2 % (after halving or doubling) (shared:playback/AutomixFeatures.kt:35-39, 395-406)
- [x] The beat grid: the phase with the largest mean onset along it, then fitted three times by least squares to onset peaks (first within a quarter beat, then twice within 35 ms), a fit needing at least 8 beats and half of them on a peak; the downbeat is the beat of four with the most bass onset (shared:playback/AutomixFeatures.kt:417-467, 554-594)
- [x] Onset peaks: above the hop before, at least the hop after, and at least max(0.05, mean + one standard deviation) of the sounding hops (shared:playback/AutomixFeatures.kt:69-71, 530-552)
- [x] A tag BPM picks the octave: when the found tempo is within 2 % of the tag it stays; when half or double it is within 2 %, the grid is redone at that octave; any other tag is ignored (shared:playback/AutomixFeatures.kt:41-43, 407-414)
- [x] Display tempo is halved or doubled into 81 to 162 BPM (shared:playback/AutomixFeatures.kt:56-57, 94-102)
- [x] Rounding is half up everywhere (floor(x + 0.5)), the same in every language (shared:playback/AutomixFeatures.kt:626-627)

## 16. Song length

- [x] A length the player measured is believed only between 1 s and 24 h, and only when the song has not already played more than 1 s past it (a stream that measured only its first part) (shared:playback/SongLength.kt:9-26)
- [x] The playing length: the believable measure, else the listed length (0 when unknown), stretched to the position when it has played past the listing; the scrub bar, time left, song end, blending and play counting all use it (shared:playback/SongLength.kt:28-37)
- [x] A listing is corrected when a believable measure is more than 1 s (LENGTH_SLACK_MS) from it, or when none was listed (shared:playback/SongLength.kt:14-16, 39-46)
- [x] Corrected lengths are kept in memory by song id for as long as the app runs; rows, the queue and the next play read through them; a corrected song's listing is rounded to whole seconds ((ms + 500) / 1000) (shared:playback/SongLength.kt:48-77)
- [x] The phone's own player teaches lengths when a song becomes ready and when the timeline changes; a TV or speaker's length and live streams are never trusted (app:playback/OctoPlaybackService.kt:346-366, 496-517)
- [x] The play counter takes the playing length as soon as it is known (app:playback/OctoPlaybackService.kt:357; app:playback/PlayTracker.kt:60-66)
- [x] For a song found online, a corrected length is also stored with the find (once per value), so it shows next time; a failed store is retried next time (app:discovery/FindLengths.kt:10-48)
- [x] A row shows the learned length, else the listed one, never below 0 (app:discovery/FindLengths.kt:10-12)

## 17. Queue editing and shuffle order

- [x] Shuffle keeps two lists: songs in queue order, and the play order (queue positions in the order they play); a song put in never lands at a random spot (shared:playback/ShuffleQueue.kt:3-7; app:playback/QueueShuffleOrder.kt:24-61)
- [x] Only a queue built from nothing is shuffled at random; the shuffle-play of a list sets items with shuffle on (app:playback/QueueShuffleOrder.kt:45-52; app:playback/PlaybackConnection.kt:140-152)
- [x] Songs inserted at position `at` play after the first `rank` entries of the play order; every song at `at` or later moves along (shared:playback/ShuffleQueue.kt:9-16)
- [x] Rank rules, first that applies: Play next: right after the current song; added at the end ("Add to queue"): last; inserted right after the current song in the queue: right after it; inserted just before an Autoplay song: just before it; inserted at 0: first; else right after the song before them in the queue (shared:playback/ShuffleQueue.kt:18-36)
- [x] Songs the listener adds at the end go before the first Autoplay song still to come (in play order); Autoplay's own additions and Play next are not moved (shared:playback/ShuffleQueue.kt:38-45; app:playback/OctoPlayer.kt:197-218)
- [x] Removing songs keeps the rest in the same play order; moving songs keeps each one's place in the play order (shared:playback/ShuffleQueue.kt:47-65)
- [x] "Play next" puts songs right after the current one in the queue and in the play order, told apart from "Add to queue" even when the last song is on (app:playback/OctoPlayer.kt:220-233; app:playback/OctoPlaybackService.kt:577-579)
- [x] Moving a song already queued to play next: removed from its place, put next; nothing when it is the current song or gone (app:playback/QueueEditor.kt:72-82)
- [x] Undoable edits: remove one song by its key; clear all but the current song; remove given song ids wherever they are (files about to be deleted; when the current one goes the next plays); remove the songs already played (in play order before the current) (app:playback/QueueEditor.kt:36-70)
- [x] An edit keeps the queue as it was, its play order and the keys left after the edit; songs are removed as runs, last run first (shared:playback/QueueRuns.kt:25-34; app:playback/QueueEditor.kt:94-103)
- [x] Undo puts each song back at its old position, entry ids and all, and restores the old play order; it refuses when the queue has changed any other way since (shared:playback/QueueRuns.kt:6-23; app:playback/QueueEditor.kt:84-92; app:playback/OctoPlayer.kt:240-247)
- [x] Play next with an undo (a swipe): undo finds the run of those song ids nearest where they went in and removes it (shared:playback/QueueUndo.kt:3-12; app:playback/PlaybackConnection.kt:241-261)
- [x] Each queue entry has a source: You (Play next, Add to queue, dropped in), Played(list name or none), or Autoplay; saved as "you", "autoplay", "list" or "list:<name>"; unknown words read as an unnamed list (shared:playback/QueueSources.kt:7-73)
- [x] Songs added from a car, from Play next, or from the app's add go in as the listener's own (You); a list played carries its name (shared:playback/QueueSources.kt; app:playback/OctoPlaybackService.kt:577-578, 590-593, 618-620; app:playback/PlaybackConnection.kt:144)
- [x] Headings over runs of one source: "Next from you", "Next from Autoplay", "Next from <name>", "Up next" for an unnamed list; songs of one source that are apart stay in separate runs (shared:playback/QueueSources.kt:23-40)
- [x] A song moved among the songs to come joins the run it lands inside; at the edge between two runs it keeps its own; it never becomes Autoplay's (shared:playback/QueueSources.kt:42-56)
- [x] The key a queue row is drawn under: its entry id, else `<id>#<times seen before>` (app:playback/UpNext.kt:23-36)
- [x] Up next is the current song and everything after it in play order (repeat ignored); played is everything before it in play order, oldest first; neither list is ever longer than the queue (app:playback/UpNext.kt:38-62; app:playback/PlaybackConnection.kt:303-332)

## 18. Queue saved on the phone, and restore at start

- [x] Saved: the song ids in queue order, each song's place in the play order, the current index, the position, repeat mode and shuffle flag (app:playback/Stores.kt:88-105) (iPhone: the queue is kept as a JSON file in the app's own folder, with the same fields)
- [x] Reading back: rows sorted by position; the play order rebuilt from each row's shuffled place; the index held inside the queue; the position never below 0; nothing when there are no rows or no state (app:playback/Stores.kt:107-118)
- [x] Saved when the song changes, when playing stops or pauses, every 15 s while playing, 500 ms after the queue stops changing, when the app's task is removed, at Close and when the service ends (app:playback/OctoPlaybackService.kt:245-246, 268-276, 333-334, 463-466, 511-513, 524-542)
- [x] Saves and reads run one at a time in order on their own background queue, so they finish even as the service stops, and a save asked before a server hand-over lands before it (app:playback/Stores.kt:139-202)
- [x] At start, the service reads the crossfade setting, then brings back the saved queue paused at the saved song and place, with repeat, the saved play order (songs that are gone left out) and shuffle; only if the player is still empty (app:playback/OctoPlaybackService.kt:203-212, 377-393)
- [x] Songs gone from the library are dropped; when the saved current song is gone the queue starts at the first song from 0 (app:playback/Stores.kt:120-127)
- [x] The saved play order is used only when it is a full permutation of the saved queue; the gone songs are left out and the rest renumbered (app:playback/Stores.kt:129-137)
- [x] Apps connecting to the service (and widget commands) wait until the saved queue is back, so nobody mistakes a restoring player for an empty one (app:playback/OctoPlaybackService.kt:148-149, 253-266, 553-564)
- [x] The restored queue is told to the server queue sync as a baseline, so restoring is not a change and is not saved over a newer queue from elsewhere (app:playback/OctoPlaybackService.kt:392; app:server/QueueSync.kt:121-125)
- [x] System "resume playback" (a headset button or the system's media resumption with the app closed): the saved queue at the saved song and place; for display only, just that one song; nothing to resume raises an error (app:playback/OctoPlaybackService.kt:626-643) (iPhone: the lock screen's and headphones' play buttons (MPRemoteCommandCenter) bring the kept queue back, waiting for it as the app starts, and say there is nothing to resume when nothing was kept; iOS never starts an app that is not running for a headset button)
- [x] Each account keeps its own queue: the one in use is the saved queue; each other account's waits in a separate store (`queue@<account>`, JSON with trackIds, shuffleOrder, index, positionMs, repeatMode, shuffle; unknown keys ignored); an empty queue is never stored there (app:playback/Stores.kt:204-261)
- [x] Hand-over between accounts: the waiting queue of the account arriving is taken out of the store; when there is none and "keep when none" is asked, nothing changes; else the leaving account's queue (as left, else as saved) waits, and the arriving one's (or an empty one) becomes the saved queue (app:playback/Stores.kt:175-186)
- [x] Removing a server with "forget here" drops its waiting queue (app:playback/Stores.kt:188-189; app:playback/ServerSwitch.kt:184-200)

## 19. Playback service events and errors

- [x] On every song change: the current id is published, the queue is saved, widgets refresh, the server queue sync hears of it, Autoplay checks, and the length is learned (app:playback/OctoPlaybackService.kt:463-470)
- [x] Repeat change, shuffle change, playing change and playback state change make Autoplay check again (app:playback/OctoPlaybackService.kt:472-474, 496-509, 524-528)
- [x] A queue change saves 500 ms after it settles, tells the server queue sync, makes Autoplay check and learns the length (app:playback/OctoPlaybackService.kt:511-517)
- [x] A pause sends the exact queue to the server queue sync (app:playback/OctoPlaybackService.kt:519-522)
- [x] A song that fails while music should play is skipped with one line "Skipped <title>. <why>"; once as many songs have failed in a row as the queue holds, or there is nothing next, it stops with "Couldn't play <title>. <why>"; the count of failures in a row resets when a song becomes ready; an untitled song is called "a song"; an error while not meant to be playing is ignored (app:playback/OctoPlaybackService.kt:459-494; shared:playback/PlayFailures.kt:14-18)
- [x] Failure reasons: HTTP 404 or 410 for a library song: "That song isn't on the server any more."; any other bad HTTP status, or 404/410 for a song found online: "The server wouldn't send that song."; file not found: missing; network connection failed or timed out, or a timeout: "Couldn't reach the server to play that song."; unsupported format, exceeds capabilities, unsupported container or manifest: "Octo can't play that kind of file."; malformed container or manifest, decoding failed: "That song's file is damaged."; audio output init or write failed: "The sound device stopped working. Pick another output."; anything else: "That song couldn't play." (app:playback/PlayFailureWords.kt:6-33; shared:playback/PlayFailures.kt:3-12)
- [x] Close: saves the queue, cancels the sleep timer, ends casting, hides the notification even for a stopped player, pauses, stops and lets the service end; playing again afterwards brings the notification back for stops and errors (app:playback/OctoPlaybackService.kt:331-344, 503-507) (iPhone: Close clears the lock screen's Now Playing (MPNowPlayingInfoCenter), which comes back on the next play; the AirPlay route stays the listener's)
- [x] The heart in the notification: nothing for no song or a radio station; a like toggle for a library song; for a song found online, "Add to your library" (asks the server to download it) while no download has been asked for, else nothing; the heart goes first, Close second (app:playback/NotificationHeart.kt:6-20; app:playback/OctoPlaybackService.kt:293-329, 368-375) (iPhone: the heart, or Add to your library for a find, sits beside the song on CarPlay's Now Playing screen; the lock screen has no room for one; Close is the stop command)
- [x] Liking from the notification ignores songs found online (app:playback/OctoPlaybackService.kt:574)
- [~] An equalizer app may attach while music plays on the phone; the session is closed once the music stops (idle or ended) or while casting, not at a pause (app:playback/OctoPlaybackService.kt:501-502, 528-531) (not on iPhone: iOS lets no other app attach an equalizer to Octo's sound)
- [x] While "resume on headphones" (wired or Bluetooth) is on, the service stays in the foreground for 30 minutes after a pause instead of the platform default (app:playback/OctoPlaybackService.kt:235-244) (iPhone: while either headphone switch is on, the silent sound is kept 30 minutes after a pause instead of 10, which keeps the app alive to hear the headphones)
- [x] Untrusted apps keep read-only access; cars and the voice assistant (Android Auto, car assistant, Google app) get full control (app:playback/OctoPlaybackService.kt:91-97, 545-565) (iPhone: iOS has no per-controller trust: CarPlay, Siri and Shortcuts get full control through the system)

## 20. Counting a play (on the phone)

- [x] A play counts only for songs of at least 30 s, once min(half the song, 240 000 ms) has been heard (shared:playback/PlayRules.kt:3-11)
- [x] Heard time excludes pauses; the clock keeps running across a song change while music plays (app:playback/PlayTracker.kt:9-58)
- [x] The play is recorded the moment it counts (a timer set for the time still needed, at least 1 ms, re-checked when it fires), or at the song change or service end if that moment was missed; a song is recorded at most once per play-through (app:playback/PlayTracker.kt:68-103)
- [x] "Now playing" is announced once per song, the first time it actually plays (app:playback/PlayTracker.kt:68-73; app:playback/Stores.kt:272-276)
- [x] A play is recorded with the song id, its wall-clock start time (when the song came on), the heard time and the playing length; it is dropped unless it counts (app:playback/Stores.kt:278-286)
- [x] The play is stored locally with the song's relink key, and handed to the server listening sync and to ListenBrainz (app:playback/Stores.kt:278-286)
- [x] A radio station has no length (the player never measures one for a live stream) and never counts (app:playback/RadioItems.kt:15)
- [x] The count timer is only armed when playing starts or the song changes, or re-armed when a measured length arrives while a timer is already running; a song that started with no known length (a find without one, an opened file) gets no timer, so once its measured length arrives it is counted only when it moves on (or after a pause and play again re-arms the timer) (app:playback/PlayTracker.kt:35-66, 87-93)
- [x] A recorded play uses the measured length for the counting rule when the player reported one, otherwise the listed (corrected) length (app:playback/PlayTracker.kt:60-66; app:playback/OctoPlaybackService.kt:357)
- [x] On a server switch or service end, the last song is flushed (counted if it qualifies) for the server it played from (app:playback/OctoPlaybackService.kt:277, 438; app:playback/ServerSwitch.kt:204-209)

## 21. Autoplay

- [x] On by default; turning it off stops it adding (app:player/PlayerSettings.kt:63-64; app:playback/Autoplay.kt:69-78)
- [x] It watches only when: on, the current song has an entry id not already handled, it is not a radio station, repeat is off, nothing comes after it, and it is playing or the queue has ended (app:playback/Autoplay.kt:87-103)
- [x] It adds once the real time left in the last song is at most max(20 000, longest blend + early-exit + 15 000) ms, where early-exit is 45 000 ms when crossfade is on (a planned blend may start that early), checking every 1 000 ms (app:playback/Autoplay.kt:26-40, 111-117)
- [x] Time left uses the player's length, else the listed length, at the current speed (app:playback/Autoplay.kt:169-173)
- [x] It tries once per song, whatever comes of it (app:playback/Autoplay.kt:66-67, 123-128)
- [x] Seeds: the last song, then up to 10 of the listener's own songs (not Autoplay's, not the seed) from the last 30 queue entries, most recent first (app:playback/Autoplay.kt:118-122, 144-150)
- [x] Excluded: everything queued, the 50 most recently played songs, and the seed (app:playback/Autoplay.kt:26-27, 146-147)
- [x] It asks Octo's radio for 10 songs like the seeds, spaced on from the last 30 queued songs (app:playback/Autoplay.kt:150; shared:playback/AutoplayPicks.kt:6-7)
- [x] When the radio gives nothing: the library's songs by the seed's artist (a find's artist matched by name key), shuffled, then the seed's genre, shuffled, without excluded songs or repeats, up to 10 (app:playback/Autoplay.kt:151-167; shared:playback/AutoplayPicks.kt:9-23)
- [x] Songs are added at the end marked as Autoplay's, only if the setting is still on, the same song is still last and nothing was added meanwhile; when the queue already ended while waiting, playback jumps to the first added song and plays (app:playback/Autoplay.kt:122, 129-138)

## 22. Radio (Start radio and Autoplay)

- [x] A radio plays 50 songs after the one it started from (app:playback/LibraryRadio.kt:23-24)
- [x] It mixes the library with the server's suggestions for the first seed (asked for 100 songs when the outside share is over half, else 50); a server error only loses the suggestions; the seed itself is dropped from suggestions (app:playback/LibraryRadio.kt:48-55; shared:radio/RadioTuning.kt:14-16)
- [x] With "Library songs only" on, suggestions found online are left out (app:playback/LibraryRadio.kt:56, 67)
- [x] Each phone song is seen with its artist (or artist id), album id, genre, year, length, liked, rating, play count and last played time (app:playback/LibraryRadio.kt:82-95)
- [x] Tuning defaults: discovery Balanced (0.35), adventure Balanced (reach 0.5, keep 1.0), variety Normal (1.0), favorites off (shared:radio/RadioTuning.kt:8-17; app:player/PlayerSettings.kt:65-69)
- [x] Discovery shares: Only my library 0.0, A little 0.15, Balanced 0.35, Lots 0.6, Mostly new 0.85 (shared:radio/RadioTuning.kt:21-27)
- [x] Adventure: Focused reach 0.2 keep 0.5; Balanced 0.5 / 1.0; Wander 1.0 / 2.0 (shared:radio/RadioTuning.kt:31-35)
- [x] Variety scale: Tight 0.5, Normal 1.0, Wide 1.6 (shared:radio/RadioTuning.kt:40-44)
- [x] Features per song: each genre (weighted by its rarity ln(1 + albums / albums with the genre), shared across the song's genres), each genre in its era (the year spread over 7 either side on a cosine shape of unit length), the year (weight 0.5), each artist (0.6 shared), each composer (0.4 shared) (shared:radio/RadioMix.kt:24-38, 313-356)
- [x] Likeness is the cosine with the seeds' combined features, but 0 unless they share a genre or genre-in-era (shared:radio/RadioMix.kt:358-371)
- [x] A server suggestion adds 0.5 / (1 + rank / 20) (shared:radio/RadioMix.kt:35-38, 129)
- [x] Nudges, each x 0.9: not liked and rated under 4; played more than 4 times; played in the last 15 days; x 0.5 for an artist with any song rated 1 star; x 1.15 for a favorite (liked or 4+ stars) when favorites is on (shared:radio/RadioMix.kt:40-67, 373-381)
- [x] Never picked: the first seed, excluded songs, any song rated 1 star, radio filler, and anything scoring 0 or less (shared:radio/RadioMix.kt:113-133)
- [x] Radio filler: shorter than 45 s or longer than 45 min (0 = unknown is allowed), a title with the whole word "interview" or "podcast", a podcast/audiobook genre, or an intro, introduction, skit or interlude of 4 min or less (shared:radio/RadioFilter.kt:5-24)
- [x] Library candidates share a genre or an artist with the seeds; over 4 000 are sampled at random down to 4 000 (shared:radio/RadioMix.kt:69-72, 119-122)
- [x] Library songs and outside songs are drawn apart; outside songs are dropped entirely for "Only my library" (shared:radio/RadioMix.kt:134-138)
- [x] Library songs played in the last 8 days wait until nothing else will do; the rest keep the top max(200, count x 8 x adventure keep) (shared:radio/RadioMix.kt:40-41, 139-146)
- [x] Spacing: an album or title waits int(6.7 + library size / 6 000) clamped 8 to 30 picks; the album/artist gap is that x variety scale (at least 2); a title always waits the base spacing (shared:radio/RadioMix.kt:147-150, 181-183)
- [x] Too soon: same album within gap + random(gap) picks (capped by albums - 1 and history); same title within its own drawn distance; same artist or composer within gap/2 + random(gap/2 + 1) (capped by artists - 1); distances drawn fresh each time (shared:radio/RadioMix.kt:287-311)
- [x] Outside songs are placed by a draw at the share (paced so it can be reached: at most outside / slots, at least 1 - library / slots; with fewer songs than slots, outside / total), pulled back when more than 1.5 songs off the share, and never more than 2 of the rarer kind in a row (shared:radio/RadioMix.kt:52-62, 167-200)
- [x] The run of one kind carries on from the songs already queued (for the phone, which of the last 30 queued are finds) (shared:radio/RadioMix.kt:159-165; app:playback/LibraryRadio.kt:72-74)
- [x] Each draw lands at random within `reach` of the list's total weight, then takes the first free song from there that spacing allows; songs held back by spacing are remembered; at most count x 100 tries (shared:radio/RadioMix.kt:202-270)
- [x] When spacing leaves it short: the best of what was held back, then songs heard lately, never the same artist twice in a row unless nothing else is left (shared:radio/RadioMix.kt:271-284)
- [x] Artist keys are the main artist of a credit, lowercase, accents gone; genre keys by search key; title key is the core title (versions stripped) (shared:radio/RadioSong.kt:27-36)
- [x] A server's song as a radio song: artists from its artist list, else artist or display artist, else artist id; album id else name; genres list else genre; composers split on `,` `;` `/`; liked = starred; plays and last played from the server (shared:radio/RadioSong.kt:38-55)

## 23. Sleep timer

- [x] Choices: 5, 15, 30, 45, 60 minutes; extend by 5 or 10; stop after 1, 2, 3 or 5 songs; custom up to 720 minutes; after a chosen song in the queue (shared:playback/SleepPlan.kt:21-31)
- [x] The last 30 s fade out by the square of the share left; full volume before (shared:playback/SleepPlan.kt:33-41)
- [x] The countdown ticks on each whole second, and 10 times a second through the fade (shared:playback/SleepPlan.kt:43-48)
- [x] At 0 it pauses and turns off; cancelling restores full volume and stops pausing at the end of the song (app:playback/SleepTimer.kt:140-167)
- [x] Extending a running countdown lifts any fade already begun (app:playback/SleepTimer.kt:117-122)
- [x] "After N songs" counts songs that end on their own (end, repeat, or a crossfade hand-over), becoming "end of this song" at the last; 1 song is "end of this song" (app:playback/SleepTimer.kt:36-41, 63-76, 124-130)
- [x] End of song: the player pauses at the end of the current song; once it does, the timer turns off (app:playback/SleepTimer.kt:63-67, 169-173)
- [x] After a chosen song: it waits until that entry is current, then stops at its end; it turns off when that entry leaves the queue; choosing the current song is "end of this song" (app:playback/SleepTimer.kt:132-138, 73-81)
- [x] Stopping at the end of the song turns crossfade off for that song (shared:playback/Crossfade.kt:24)
- [x] The timer goes when the service ends, and a server switch or Close cancels it (app:playback/SleepTimer.kt:90-95; app:playback/OctoPlaybackService.kt:335, 440)
- [x] Words: "Off", "<n> min left" (rounded up), "At the end of this song", "After 1 song" / "After <n> songs", "After <title>" (shared:playback/SleepPlan.kt:50-57)

## 24. Headphones bring the music back

- [x] Off by default for wired and for Bluetooth; "always play on connect" off (app:player/PlayerSettings.kt:70-75)
- [x] Wired: wired headphones, wired headset, USB headset; Bluetooth: A2DP, BLE headset, BLE speaker (app:playback/HeadsetResume.kt:18-32) (iPhone: wired: the Headphones and USB audio ports; Bluetooth: A2DP and Bluetooth LE outputs)
- [x] It resumes when that kind is switched on, nothing is playing, there is a queue, and either "always" is on or the music was paused by the output going away within the last 30 minutes (app:playback/HeadsetResume.kt:14-16, 34-53)
- [x] It waits 500 ms after a wired connection and 1 500 ms after Bluetooth for the sound to move, and checks the device is still there (app:playback/HeadsetResume.kt:55-59, 84-93)
- [x] Only outputs not seen before count as new; any other pause or playing again forgets the output-lost time (app:playback/HeadsetResume.kt:77-121)
- [x] It brings back only the phone's own player, never a TV, and only while the service is alive (app:playback/HeadsetResume.kt:61-65; app:playback/OctoPlaybackService.kt:238-239) (iPhone: route changes are heard while the app is alive (kept so by the silent wait); an AirPlay route never brings music back)

## 25. Speed and pitch

- [x] Speed 0.5x to 2.0x; detents 0.75, 1, 1.25, 1.5 catch within 0.04; otherwise steps of 0.05, rounded to two places (shared:playback/Pace.kt:7-31)
- [x] Pitch shift -6 to +6 semitones; with "keep pitch" on the pitch is 1 x 2^(st / 12), off it is speed x 2^(st / 12) (shared:playback/Pace.kt:20-58) (iPhone: AVAudioUnitTimePitch: the rate is the speed, and the pitch moves in cents (1200 x log2 of the pitch))
- [x] Defaults: speed 1, keep pitch on, 0 semitones; reset removes all three (app:player/PlayerSettings.kt:56-60, 277-284)
- [x] Labels: "1.25x", "2x", "1.5x"; "+2 st", "0 st", "-3 st" (shared:playback/Pace.kt:60-74)
- [x] Speed, pitch and skip silence reach the phone's player only when they change, so a blend is not cut short (app:playback/OctoPlaybackService.kt:218-231)

## 26. Changing server (ServerSwitch)

- [x] Before the server in use changes: what plays stops, the last song counts for the old server, casting ends, the player empties; the listening sync notes the last play; the queue left goes to the old server (exactly, at most 3 s wait) and waits on the phone; the next account's waiting queue becomes the saved queue (app:playback/ServerSwitch.kt:202-217; app:playback/OctoPlaybackService.kt:400-446)
- [x] The new queue comes back paused once the new server's library is copied, waiting at most 30 000 ms; then a car's tabs are read again (app:playback/ServerSwitch.kt:41-43, 230-240)
- [x] When a server is signed in with none in use before, the phone's queue keeps playing unless that server had a queue waiting here (app:playback/ServerSwitch.kt:219-228)
- [x] The phone library with no server is the account `phone` (app:server/ServerSync.kt:75; app:playback/ServerSwitch.kt:117-126)
- [x] One switch at a time ("Still switching. Try again in a moment."); a switch runs to the end even if its page closes (app:playback/ServerSwitch.kt:139-154)
- [x] Notice after a switch: none when nothing was in use; "Now on <to>. The music from <from> stopped, and its queue is kept for when you come back." when music was stopped; else "Now on <to>." (shared:server/ServerList.kt:59-65)
- [x] Signing out of the server in use disconnects it; signing out of another just signs it out; it stays listed (app:playback/ServerSwitch.kt:172-177)
- [x] Removing a server always removes its library copy; with "forget here" also its waiting queue, waiting plays, favorite sync state, playlist sync state, recent playlists, live lists, server queue notes and admin addresses, and its downloads unless another kept account uses the same address (app:playback/ServerSwitch.kt:179-200)

## 27. Server play queue sync and the Resume offer

- [x] "Sync play queue with the server" is on unless switched off; switching it off cancels a pending save and the offer (app:server/QueueSync.kt:105-119)
- [x] The phone's queue as a server queue: only songs the server has (a library song's copy on this server, the lowest server id when several; a find's own id without its prefix; radio stations never); under shuffle (with a full permutation) in play order; the current song's place, or when it is not on the server the next one that is, from 0 (the last one when none follows) (app:server/QueueSync.kt:57-75, 278-288)
- [x] At most 400 songs are saved (about 11 KB of address): a longer queue keeps 50 before the current song and the rest after (shared:server/ServerQueues.kt:12-29)
- [x] A change saves 10 000 ms after the queue or song stops changing; a pause saves at once with the exact position; leaving a server saves exactly and waits at most 3 000 ms (app:server/QueueSync.kt:48-55, 127-164)
- [x] Each save goes to the server that was in use when the change or pause happened, even if it lands after a switch; saves run one at a time (app:server/QueueSync.kt:127-150, 250)
- [x] The save sends every `id` in order, then `currentIndex` (index-based) or `current` (the current song's id), then `position` in ms (never below 0); index and position are left out when the index is outside the list (subsonic:Models.kt:638-644)
- [x] The desktop's ServerQueueSync is the desktop counterpart; the phone's rules are the ones above (desktop/src/main/kotlin/app/winters/octo/desktop/queue/ServerQueueSync.kt)
- [x] A save after a change is skipped when only the position moved since the last send; a save at a pause is skipped only when nothing changed; nothing is sent while the queue is the restored baseline (app:server/QueueSync.kt:248-255, 127-140)
- [x] Saves use the index-based call when the server lists the `indexBasedQueue` extension, else the id-based call; after saving, the server's own stamp for the save is read back and kept per account, with the local save time (app:server/QueueSync.kt:256-275)
- [x] The offer is looked for when the app comes to the front (at most once per 30 000 ms) and at once when another server comes into use; failures are silent (app:server/QueueSync.kt:51-52, 171-193)
- [x] The offer shows when: syncing is on, signed in, the server's queue has a current song, a readable saved time, that time is not this phone's own last stamp, and it is later than both this phone's last save and the last offer answered (shared:server/ServerQueues.kt:70-79; app:server/QueueSync.kt:218-246)
- [x] The offer names the device that saved it (its client name trimmed, else "another device"), the current song's title and its display artist (else artist) (app:server/QueueSync.kt:241-243)
- [x] Older per-address keys are read when the per-account keys are missing (app:server/QueueSync.kt:236-239, 311-314)
- [x] Taking the offer resolves the songs from the server into library songs or finds; nothing when none resolves; the current song's place (or the first, from 0 when the current is not found) and the saved position; it loads paused with shuffle off (app:server/QueueSync.kt:195-204; app:playback/PlaybackConnection.kt:154-164)
- [x] Taking or dismissing records the offer's time as answered, so the same queue is not offered again (app:server/QueueSync.kt:206-216)
- [x] A remote queue's index (index-based) is held inside the list; an id-based queue's position counts only when its current id is found (shared:server/ServerQueues.kt:43-61)
- [x] Server times are read as an instant, else as a date-time with offset (shared:server/ServerQueues.kt:63-68)
- [x] The app names itself `Octo` to servers (app:server/QueueSync.kt:44-46)
- [x] Removing a server with "forget here" forgets its saved, answered and stamp times (app:server/QueueSync.kt:166-169)

## 28. Likes, ratings and playlists (local stores)

- [x] Liking stores the song with its relink key and the time; unliking deletes it; either is handed to the listening sync (app:playback/Stores.kt:43-86)
- [x] Only a song the library has can be liked (a find cannot, since it is not in the catalog); a like toggle on a missing song does nothing (app:playback/Stores.kt:56-67)
- [x] An unlike with undo restores the like with its original time, so it keeps its place (app:playback/Stores.kt:69-85)
- [x] Ratings are 1 to 5 stars, 0 for none; a song found online cannot be rated; the rating shows at once, the server copies are marked rated (so a rebuild before the next sync still shows it), and the listening sync is told (app:playback/RatingStore.kt:17-41)
- [x] Playlists shown are the phone's own and the server-in-use's; another kept server's wait for it (app:playback/PlaylistStore.kt:35-41)
- [x] Playlist changes run on their own scope so they finish if the page closes; a playlist kept with the server sends each change there (create, rename, delete, add, remove, remove many, restore, restore many in reverse, take back an add, move onto a target) (app:playback/PlaylistStore.kt:23-139)
- [x] A new playlist gets a random UUID, its name trimmed (app:playback/PlaylistStore.kt:43-54)

## 29. Car browsing and voice (Android Auto; CarPlay counterpart)

- [x] Root tabs: Recent, Playlists, Albums (grid), Artists (app:playback/CarLibrary.kt:36-46) (iPhone: CarPlay tabs Recent, Playlists, Albums and Artists, as system lists (CarPlay gives audio apps lists, not grids))
- [x] Recent: the 20 albums played most recently (group "Recently played"), then the 20 most played songs (group "Most played"; choosing one plays that list from it) (app:playback/CarLibrary.kt:47-52) (iPhone: each section is held to half of CarPlay's list limit)
- [x] Playlists: "Liked songs" ("<n> songs") when there are likes, then each playlist with its song count and first cover (app:playback/CarLibrary.kt:53-58) (iPhone: one song reads "1 song")
- [x] Albums: all albums; Artists: all artists (grid), each opening its albums (app:playback/CarLibrary.kt:59-62) (iPhone: the Albums and Artists lists are held to CarPlay's list limit; an artist opens their albums)
- [x] Choosing an album, playlist or liked plays it from the top; choosing a song plays the list it was found in from that song (the top when gone) (app:playback/CarLibrary.kt:68-76; app:playback/CarIds.kt:61-64) (iPhone: an album, a playlist or Liked songs opens its songs with Play first, which plays it from the top; choosing a song plays the list from it)
- [~] Search: up to 30 songs, 15 albums, 10 artists (app:playback/CarLibrary.kt:78-85) (not on iPhone: CarPlay gives audio apps no search screen; searching in the car goes through Siri (next line))
- [x] Voice: empty request shuffles everything; an album named exactly (case, accents and punctuation aside) plays in order; else an artist with the same name plays all their albums shuffled; else up to 50 matching songs in order; a shuffled voice request starts at a random song (app:playback/CarLibrary.kt:87-102; app:playback/OctoPlaybackService.kt:604-611) (iPhone: Siri's play media requests (INPlayMediaIntent) follow these rules)
- [x] Car ids: `root`, `tab:recent`, `tab:playlists`, `tab:albums`, `tab:artists`, `liked`, `mostplayed`, `album:<id>`, `artist:<id>`, `playlist:<id>`, `song:<id>` with `|in:<list id>` (app:playback/CarIds.kt:19-59) (iPhone: CarPlay screens carry their own actions, so the ids are kept for the rules but never handed to the car)
- [x] Covers for a car are 320 px JPEGs (quality 88) cached by SHA-1 of the reference, written aside then renamed, readable only with a grant (app:playback/ArtworkProvider.kt:15-66) (iPhone: CarPlay rows take a picture, drawn at 320 px through the artwork cache, so there is no file to grant)
- [x] After a server switch every car tab is told it changed (app:playback/OctoPlaybackService.kt:424-433)

## 30. The app's line to the player

- [x] Requests made before the connection is up run as soon as it is (app:playback/PlaybackConnection.kt:52-56, 265-271)
- [x] Playing a list: shuffle on sets the items for a random start; off starts at the chosen index from 0; then prepare and play (app:playback/PlaybackConnection.kt:140-152)
- [x] With nothing queued, play shuffles the whole library; from idle it prepares first (app:playback/PlaybackConnection.kt:170-180)
- [x] Repeat cycles off, all, one (app:playback/PlaybackConnection.kt:210-217)
- [x] Previous and next use the player's own rules (previous restarts the song when past its start) (app:playback/PlaybackConnection.kt:219-221)
- [x] Add to queue appends songs (as requests) (app:playback/PlaybackConnection.kt:229)
- [x] Now playing shows the measured length when known, else the corrected listed length; the quality badge from the decoder's format, else the file mime; the output rate when not casting (app:playback/PlaybackConnection.kt:273-294, 334-341) (iPhone: the output rate is the audio session's; AirPlay is a route, not a cast, so it never changes what plays)
- [x] Quality badge: Hi-Res for lossless above 48 kHz, Lossless, else the codec; details "24-bit · 48 kHz" or "128 kbps", and "plays at <rate> kHz" when resampled; 44100 reads 44.1 (app:playback/Quality.kt:10-100)
- [x] A seek, song change, play/pause or speed change counts as a time event (lyrics re-anchor) (app:playback/PlaybackConnection.kt:69-73, 88-104) (iPhone: lyrics re-anchor on play and pause, the song, the speed, and any jump the lyrics clock sees (over 0.6 s, or drifting over 0.15 s))

## 31. Server listening sync: now playing, plays, likes, ratings

- [x] Nothing in the listening sync ever holds up playback or shows an error; what fails is tried again later (app:listening/ListeningSync.kt:31-37)
- [x] Each change is for the server in use when it was made, even when sent after a switch: a play counts for the server it was played from (app:listening/ListeningSync.kt:36-37, 108-118)
- [x] A song's server ids: for a song found online, its own id without the find prefix; for a library song, its copies' native ids on the server in use, sorted, so the same one is first every time; none for a phone-only song (app:listening/ListeningSync.kt:184-191)
- [x] Now playing: `scrobble` with the first server id, the current time in ms and `submission=false`; failures ignored (app:listening/ListeningSync.kt:99-106; subsonic:SubsonicClient.kt:505-508)
- [x] A counted play is queued for its server as (first server id, start time) and the queue is sent at once (app:listening/ListeningSync.kt:108-118)
- [x] A play, now-playing, like or rating made while no server is in use is never sent to a server later (only likes and ratings catch up through the next reconciliation); a phone-only song sends nothing (app:listening/ListeningSync.kt:70-118, 181-191)
- [x] Waiting plays per account: deduplicated, oldest first, at most 500 (oldest let go); stored one per line `<start ms> <server id>` (shared:listening/Scrobbles.kt:5-29)
- [x] Sending waiting plays: oldest first with `scrobble` (`time` = start in ms, `submission=true`); it stops at the first failure worth retrying (server unreachable, not answering like Subsonic, or refusing the login); any other refusal drops that play for good; a play sent is moved to the "sent" record (shared:listening/Scrobbles.kt:15-19; app:listening/ListeningSync.kt:166-174; app:listening/ListeningStore.kt:87-91)
- [x] Before a server switch, the switch waits for every counted play to be noted for its server (app:listening/ListeningSync.kt:120-124; app:playback/ServerSwitch.kt:208-209)
- [x] After every library sync with the server: reconcile likes with stars, reconcile ratings, fold sent plays into the server's counts, then send waiting plays; skipped when the server has no copies (app:listening/ListeningSync.kt:57-68)
- [x] Liking or unliking on the phone stars or unstars all the song's server ids at once; on success they join or leave the agreed record (app:listening/ListeningSync.kt:70-81)
- [x] Star and unstar calls carry at most 50 ids each, sorted; ids in a failed batch count as failed (app:listening/ListeningSync.kt:28-29, 176-178)
- [x] Star reconciliation compares each side with the last agreed record (server ids): both liked: agreed; liked here and was agreed before but not starred there now: unliked here (removed on the server); liked here only: star it there; starred there and agreed before but not liked here: unstar there; starred there only: like it here; a song that lost its server copy keeps its record in case it returns (app:listening/Stars.kt:6-62)
- [x] Reconciliation needs the server's current stars; without them nothing is decided (app:listening/ListeningSync.kt:126-132)
- [x] A like brought from the server keeps the earliest time any of its copies was starred there, else now (app:listening/ListeningSync.kt:137-143)
- [x] The record after reconciling leaves out stars that failed (tried again next sync) and keeps unstars that failed (app:listening/Stars.kt:64-68)
- [x] Server times like `2026-09-19T01:44:59.636933547Z` are read as instants (app:listening/Stars.kt:70-72)
- [x] A rating change sends the song's current rating (so quick changes end on the last) to every server copy (`setRating`, 0 to 5, 0 removes); only when all succeed is the record updated; a song found online is never rated (app:listening/ListeningSync.kt:83-97; subsonic:SubsonicClient.kt:491-493)
- [x] Rating reconciliation per song, copies sorted by server id: before = first agreed record among its ids (0 none); there = the first copy whose rating moved from before, else before; target = the phone's rating when it changed from before, else the server's; the phone wins when both changed; copies not at target are sent; the phone adopts target when different; the record holds target for each id when above 0 (app:listening/Ratings.kt:5-45)
- [x] A song whose server copies were not all set keeps its old record, so the next sync sends the phone's change again (a rating made offline waits) (app:listening/Ratings.kt:47-59)
- [x] After rating sync, sent ratings are written onto the server copies locally, adopted ratings are stored (0 removes), and the library shows the agreed rating at once (app:listening/ListeningSync.kt:148-164)
- [x] Ratings stored per account one per line `<rating> <server id>`, only 1 to 5; a rating outside 1 to 5 is none (app:listening/Ratings.kt:61-73)
- [x] Per-account stores (`synced_stars@`, `pending_plays@`, `sent_plays@`, `synced_ratings@` + account): a switch away and back loses nothing; an older single-server store moves to its account once; removing a server with "forget here" forgets all of it (app:listening/ListeningStore.kt:31-122)

## 32. Play counts merged with the server's

- [x] The phone records every play and also sends plays of songs with a server copy; to avoid counting twice, it remembers per server song the plays it sent (a folded count the server is known to hold, plus start times of newer ones) (app:listening/ServerPlays.kt:7-19)
- [x] A sent play counts as held by the server when it started no later than the server's last-played time + 999 ms (servers may keep whole seconds) (app:listening/ServerPlays.kt:21-29)
- [x] After each sync, sent plays the server now holds fold into the count; songs the server no longer has are forgotten (app:listening/ServerPlays.kt:36-42; app:listening/ListeningSync.kt:66)
- [x] Merged plays per song: phone plays + (server plays - Octo's sent plays it holds, never below 0); last played is the later of the two; a song played only on the server joins; songs with 0 plays are dropped (app:listening/ServerPlays.kt:44-64)
- [x] Albums: each once, at the later of its last play on the phone and on the server (app:listening/ServerPlays.kt:66-68)
- [x] Sent records stored one per line `<folded> <start>,<start> <server id>` (app:listening/ServerPlays.kt:70-81)
- [x] History (newest first): every phone play plus the server's last play of each song, unless that is one of the phone's own plays (within the song's length + 1 000 ms of a phone play of it) or older than the oldest phone play loaded (when the phone list filled the limit); duplicates by song and time dropped; ties by song id (app:listening/History.kt:22-44)
- [x] Day headings: "Today", "Yesterday", the weekday name within the last 7 days, then "MMMM d", and "MMMM d, yyyy" in another year; items keep their order (shared:listening/PlayDays.kt:9-41)
- [x] Most played ranges: "Last 4 weeks" (28 days), "Last 6 months" (calendar months), "All time" (app:listening/History.kt:55-67)
- [x] Most played: by plays, then most recent, then song id; all time merges the server's counts as above; within a range, a song played elsewhere counts one more play only when the server's last play falls in the range, the server holds plays that are not Octo's, and it is not the phone's own latest play (within 1 000 ms) (app:listening/History.kt:69-116)

## 33. Favorite albums and artists with server stars

- [x] Favorite albums and artists follow server stars exactly as liked songs do (the same three-way comparison), using `star`/`unstar` with `albumId` or `artistId`, at most 50 per call (app:listening/FavouriteSync.kt:22-31, 102-127; subsonic:SubsonicClient.kt:495-503)
- [x] A library album's server copy: grouped by server album, the library album that took most of its songs, then the one that kept the server album's own id; ids the library made up (`album:`/`artist:`) are never starred; a server album never counts for two library albums (app:listening/FavouriteStars.kt:12-24)
- [x] A change made on the phone is sent at once and tried again after 5 s, 30 s and 120 s, then left to the next sync; signed out means nothing to send; a newer change that undid it sends nothing (app:listening/FavouriteStars.kt:30-49; app:listening/FavouriteSync.kt:72-93)
- [x] A favorite brought from the server keeps the earliest starred time; the agreed records are per account and kind (`synced_albums@`, `synced_artists@`) (app:listening/FavouriteSync.kt:113-126; app:listening/FavouriteSyncStore.kt:29-71)

## 34. ListenBrainz scrobbling (plays queued offline)

- [x] Off by default; connecting turns it on; "send plays" defaults to All; now playing on by default (app:listening/ListenBrainzStore.kt:40-56, 83-94)
- [x] Plays are kept while switched on and connected, even while the token needs attention; they are sent only when that is not the case (app:listening/ListenBrainzStore.kt:51-55)
- [x] The token is checked with `GET 1/validate-token` (header `Authorization: Token <t>`): 200 with valid and a user name is valid; 400/401 invalid; anything else unreachable; a token must be 8 to 128 ASCII letters, digits or dashes (app:listening/ListenBrainz.kt:244-259, 322-324)
- [x] The token is sealed with its own key (separate from the server password), never logged or put in an address; a token that can no longer be opened (backup on another phone) marks "needs attention" (app:listening/ListenBrainzStore.kt:36-38, 77-79; app:listening/ListenBrainzSync.kt:143-148) (iPhone: the token is a Keychain item of its own, kept on this device only; one that can no longer be read marks needs attention)
- [x] Connecting a different user drops the waiting plays; disconnecting drops them and turns it off (app:listening/ListenBrainzStore.kt:81-105)
- [x] Only plays with a title and artist go; radio stations never; an opened file goes with its title and artist only, as never reaching the server; a find reaches the server; a library song reaches it when it has a server copy (app:listening/ListenBrainz.kt:77-110; app:listening/ListenBrainzSync.kt:202-222)
- [x] "Phone only" mode sends only plays the server never hears, so a server passing its own plays on does not count them twice (app:listening/ListenBrainz.kt:101-110)
- [x] A listen: start time in seconds, title, artist, album trimmed; length (the corrected one) only when above 0; track number only when above 0; MusicBrainz recording, release, release-group and artist ids only when well-formed (lowercase UUID shape) (app:listening/ListenBrainz.kt:45-99; app:listening/ListenBrainzSync.kt:204)
- [x] The queue: deduplicated by start time, title and artist, oldest first, at most 5 000 (oldest let go), saved atomically in a JSON file (app:listening/ListenBrainz.kt:42-43, 112-116; app:listening/ListenBrainzStore.kt:58-163)
- [x] Batches of at most 1 000; one play is sent as `single`, more as `import`, now playing as `playing_now` without a time (app:listening/ListenBrainz.kt:39-40, 118-148)
- [x] Each listen's metadata: artist_name, track_name, release_name (when not blank), and additional_info with media_player "Octo", media_player_version, submission_client "Octo", submission_client_version, duration_ms, tracknumber, recording_mbid, release_mbid, release_group_mbid, artist_mbids (app:listening/ListenBrainz.kt:150-169)
- [x] Answers: 2xx sent; 401 needs attention (stop); 400 or 413 rejected; 429 rate limited; else failed (app:listening/ListenBrainz.kt:274-289)
- [x] A rejected batch is split in halves and each sent on its own; a single rejected play is dropped (app:listening/ListenBrainzSync.kt:174-191)
- [x] After failures, the next try waits 30 s doubling each time, at most 6 h; rate limited waits what the server said; a new play while waiting does not send early; app start and any connection coming back send at once (app:listening/ListenBrainz.kt:124-130; app:listening/ListenBrainzSync.kt:60-76, 138-200)
- [x] At most one call a second; `X-RateLimit-Remaining` 0 with `X-RateLimit-Reset-In` blocks until the window ends; a 429 blocks for Reset-In (default 10 s, clamped 1 s to 1 h); now playing is skipped instead of waiting while blocked (app:listening/ListenBrainz.kt:171-208, 267-272, 293-312)
- [x] Now playing is sent when the song starts (sends on, now playing on); a 401 there marks needs attention; other failures do not matter (app:listening/ListenBrainzSync.kt:91-103)
- [x] The ListenBrainz client never carries the server's headers, certificates or client certificate, uses the platform's trust store, follows no redirects, refuses any host other than api.listenbrainz.org, and sends `User-Agent: Octo/<version> (Android)` (iPhone: its own platform name) (app:listening/ListenBrainz.kt:326-357; app:listening/ListenBrainzSync.kt:47) (iPhone: its User-Agent names iOS: "Octo/<version> (iOS)")

## 35. Server library copy (ServerSync)

- [x] Each kept server's library is copied beside the phone's music: after signing in, at app start when the last copy is stale, and when asked; only the server in use joins the library (app:server/ServerSync.kt:80-85)
- [x] A copy is stale when never made, made by an older rows version (current version 6), older than 6 hours, or made for another account on the same address (app:server/ServerSync.kt:57-71, 156-164)
- [x] When the server in use changes (or none): a running copy is stopped, servers no longer kept lose their rows (and their playlists stay, only on the phone), the library is rebuilt if the merged server changed, the library is marked ready for that account (or `phone`), and a stale copy is started (app:server/ServerSync.kt:141-154, 296-306)
- [x] A signed-out server is still kept, so signing in again needs no new copy (app:server/ServerSync.kt:296-306)
- [x] Only one copy runs at a time; "sync again" stops the running one first (for a changed music folder) (app:server/ServerSync.kt:166-189)
- [x] Reading the library: albums (alphabetical pages of 500), artists, and songs (empty-query search pages of 500, read until a page comes back short) are read side by side; a server that answers an empty search with nothing has its songs read album by album, 4 albums at a time, skipping albums gone since (subsonic:Library.kt:7-58)
- [x] Songs the server marks as outside the library (`isExternal`) are never kept; anything listed twice is kept once (subsonic:Library.kt:16-33; app:server/ServerCatalog.kt:50-53)
- [x] After a copy, in order: the source's rows are replaced in one transaction, the library rebuilt, then likes/stars/ratings/plays sync, favorite albums/artists sync, finds that arrived are adopted, playlists sync, and downloads follow their songs; then the copy's time, counts, rows version and owner are saved (app:server/ServerSync.kt:250-285)
- [x] A failed copy keeps the error in words for the UI ("Couldn't reach the server. Check the address, and that you're on the right network.", etc.); a cancelled one says nothing (app:server/ServerSync.kt:286-293; app:data/UserMessages.kt:5-19)
- [x] One song can be taken in at once after a download finishes: the song and its album as the server has it now; only rows the library lacks are inserted, then the library is rebuilt; answers the library song it became (app:server/ServerSync.kt:213-248)
- [x] Removing a server forgets its copy record, and its rows unless another kept account shares the address (app:server/ServerSync.kt:200-211)
- [x] An older single-server record is moved to the kept account on that address once (app:server/ServerSync.kt:308-331) (iPhone: the iPhone kept every server's record per account from the start, so there is no older record to move)
- [x] The source id of a server is `server:<host>` plus `:<port>` when not the scheme default, always from the main address, so home and away share one library (app:server/ServerCatalog.kt:26-34)

## 36. How server rows are built (ServerCatalog)

- [x] Row ids are `<sourceId>:<server id>` (app:server/ServerCatalog.kt:46)
- [x] A song whose album is missing from the album list gets an album made from its songs (key: its album id, else `album:<search key of album name>`; artist from display album artist, album artists joined ", ", or artist; year the first known; created the latest) (app:server/ServerCatalog.kt:55-59, 185-203)
- [x] Album title falls back to "Unknown album", artist to "Unknown artist"; album artist id is the server's, else `artist:<search key of name>`; album year is the first edition's year when known (original release date not after this edition), else this edition's (year, else release date); added time in seconds from `created` (app:server/ServerCatalog.kt:70-90, 213-221)
- [x] An album's cover is its own, with its first song's (in album order) cover as the fallback for when the server answers with a stand-in picture (app:server/ServerCatalog.kt:65-68, 87)
- [x] Songs in album order: disc (1 when unknown), then track (unknown last), then title sort key; album order is the index in that order (app:server/ServerCatalog.kt:92-96, 205-211)
- [x] Song title falls back to "Untitled"; artist is display artist, else artist, else the album's artist; the song's artist id is its album artist's (app:server/ServerCatalog.kt:97-109)
- [x] Song added time is its `created` in seconds, else the album's (the merge later takes the earliest of any copy) (app:server/ServerCatalog.kt:116-122)
- [x] Mime from the file suffix (flac, mp3, m4a/m4b/mp4/alac as audio/mp4, aac, ogg/oga/opus as audio/ogg, wav, aif/aiff, wv, ape, dsf), else the server's content type (app:server/ServerCatalog.kt:123, 233-246)
- [x] Bitrate in bits/s (server kbps x 1000), sample rate, bit depth, play count, last played, starred time, ReplayGain (gains when finite, peaks only above 0), rating 0 to 5, BPM, comment, composer, disc title, MusicBrainz recording and album ids, artists' MusicBrainz ids, credited artists, genres (the list, else the genre string split), explicit from the song's own `explicitStatus` only, and the family "personal" mark are kept per copy (app:server/ServerCatalog.kt:130-158)
- [x] A song's year is its own (above 0), else the album's edition year; its original year is the album's first-edition year when not after the song's year (app:server/ServerCatalog.kt:99, 144-145)
- [x] The relink key is built from album artist, album title, disc, track, title and length (app:server/ServerCatalog.kt:129; shared:catalog/Keys.kt:12-16)
- [x] Servers send 0 for unknown numbers; 0 is read as unknown everywhere (app:server/ServerCatalog.kt:228-229)
- [x] Times with no zone are read as UTC (app:server/ServerCatalog.kt:248-255)
- [x] Artists are the album artists, named as the server's artist list names them, with album count, song count and the cover of their newest added album (else the listed artist's cover) (app:server/ServerCatalog.kt:163-180)

## 37. Server covers

- [x] Covers are fetched at 150, 300, 600 or 1 200 px (the smallest at least the size wanted; 600 when no size is given), signed afresh each time, and cached under what the picture is, never the URL (app:server/ServerArtwork.kt:20-23, 44-84)
- [x] Cache keys: `server-art:<source>|<cover id>`, `online-art:v3:<source>|<cover id>` for things found online, `drawn-art:v1:<UTC day>:<source>|<cover id>` for covers Octo paints (a cover id of 22 base-62 characters starting `or` or `og`), so those refresh daily; each downloaded size is stored under key + `|<px>` (app:server/ServerArtwork.kt:24-42; shared:catalog/DrawnCovers.kt:1-29)
- [x] Covers wait for the saved sign-in; a cover from another server than the one in use is not drawn (app:server/ServerArtwork.kt:60-65)
- [x] A server's stand-in picture (Navidrome's placeholder: exactly 69 228 bytes with a known SHA-256) is detected, removed from the disk cache, remembered for the run, and the fallback cover is drawn instead; with no fallback the cover fails and the app's empty tile shows (app:server/ServerArtwork.kt:49-117; shared:catalog/StandInCovers.kt:5-41)
- [x] Artwork references are stored as `device:<key>|<uri>`, `server:<source>|<cover>[|<fallback>]` or `online:<source>|<cover>[|<fallback>]`; a fallback equal to the cover is not written (shared:catalog/ArtworkRef.kt:1-60)
- [x] Phone covers come from the media store's thumbnail at the requested width held to 96 to 1 024 px (512 when unknown), one cached picture per album (`device-art:<album key>`) (app:device/DeviceArtworkFetcher.kt:19-43) (iPhone: a Music app song's cover comes from its media library item and a Files song's from the file's own picture, at 96 to 1 024 px (512 when unknown), kept in memory)

## 38. Other server controls

- [x] Whether the user is an admin is asked once per server in use (`getUser`), false on failure (app:server/ServerControls.kt:118-135)
- [x] A library scan: start, then poll status every 2 s; until it has been seen running, "not scanning" is believed only on the second answer; when done, the library is copied again; error 50 says "Only an admin can scan this server.", others "The scan could not start just now." (app:server/ServerControls.kt:194-230, 268-270)
- [x] Shares: expiry Never, 1 day, 1 week, 1 month (30 days); a server that answers error 50 or 70, not found, or HTTP 501 is remembered for the run as not sharing (app:server/ServerControls.kt:34-53, 169-192)
- [x] The server song id used for sharing is the lowest server id among the song's copies on the server in use; an album's is the server album most of its songs came from (`<source>:<id>` rows, ignoring made-up `album:` ids) (app:server/ServerControls.kt:55-59, 139-167)
- [x] Who else is listening leaves out this account's own Octo players (player name starting "Octo", case-insensitive) (app:server/ServerControls.kt:69-72, 232-236)
- [x] Radio stations: Octo's own generated stations (cover id equals station id, on an Octo server) are read-only; a station the server refuses to change (not found or error 50) is marked read-only for the run, per account (app:server/ServerControls.kt:74-77, 238-266)

## 39. Discovery calls (beyond the library)

- [x] Search asks for 10 artists, 20 albums and 40 songs (Octo holds back found songs when 12 or fewer are asked for); songs listed are only finds; albums are those not in the library (not known from this server and not the same title and artist by match key from anywhere), with albums the library holds wholly dropped and partly-held ones kept apart; artists likewise (app:discovery/Discovery.kt:31-33, 120-135, 287-304; shared:discovery/AlbumShare.kt:5-31)
- [x] Server radio for a song: the seed first, then up to 50 similar songs (`getSimilarSongs2` with `octoMix=client`), duplicates removed (app:discovery/Discovery.kt:35-36, 137-143; subsonic:SubsonicClient.kt:421-432)
- [x] The seed's server id: a find's own; else a server copy's; else (phone-only song) a server search for "<artist> <title>" (40 songs) taking the same recording, else the same song in any version; none on failure (app:discovery/Discovery.kt:270-285)
- [x] Stations and Made for you lists exist only for a server that runs Octo (status page, server type "octo", or any extension starting "octo"); Made for you lists are playlists with an `octoList` mark, ordered by Octo's list kinds (app:discovery/Discovery.kt:57-63, 145-168; app:data/OctoProbe.kt:13-19)
- [x] Songs from the server resolve in order: a song linked to a library copy from this server is that library song unless the server now marks it outside the library; else a library song with the same title and artist (same recording, lengths within 10 s when both known, lookup by title keys) is that song (so a phone copy plays instead of a stream); else it is a find (`find:<server id>`), stored with what the app already knew (download asked, adopted song, a learned length when the server sends none) (app:discovery/LibraryMatching.kt:93-112; app:discovery/Discovery.kt:234-268; app:catalog/Online.kt:115-122)
- [x] A find already downloaded shows as the library song it became, while the library has it (app:discovery/LibraryMatching.kt:39-43)
- [x] A song Octo lists as exactly 180 s (or 0) has an unknown length (shared:discovery/Matching.kt:10-25)
- [x] Which Octo radio source suggested a song (`octoSuggestedBy`) is remembered for the song info, at most 5 000 entries, each for 12 hours (app:discovery/Discovery.kt:84-88, 228-232, 317-346; app:discovery/LibraryMatching.kt:15-22)
- [x] A library album as the server lists it now (Octo only): found from the server album most of its songs came from; songs the library lacks come as finds in the server's order (app:discovery/Discovery.kt:180-194)
- [x] Finds not seen for 30 days are let go, unless a download was asked for or they are in the saved queue or a playlist; finds from servers no longer kept are let go at once (app:discovery/Downloads.kt:70-71, 259-265; app:catalog/Online.kt:97-109)
- [x] After each library copy, finds asked for that have not arrived are matched to library songs (same song, same kind of recording, same artist, lengths within 10 s when known) and linked; the song is not liked by this (app:discovery/Downloads.kt:259-276, 427-435)
- [x] Asking for a find to be downloaded stars it on the server; a whole album is starred with `albumId`; asked songs are followed: by polling the server's downloads list every 2 s (a downloading song on screen), 5 s (in front) or 30 s (in the background) on servers that list `octoAcquisitions`, bringing a finished song in up to 3 times 20 s apart; otherwise by watching Octo's admin pages every 20 s for 30 min (copying the library up to 3 times per finished song), or by copying the library 2 and 8 minutes later; a find not arrived after 24 h can be asked for again; support for the list is rechecked after 10 min (app:discovery/Downloads.kt:55-75, 210-337; app:discovery/DownloadProgress.kt:21-34, 106-111, 149-344)

## 40. Phone music (DeviceLibrary, DeviceScanner)

- [x] The phone's music is scanned at start (with access), when access is granted, when the media library changes (after 2 s of quiet), when a folder is switched on or off (at once), and when Octo itself changed files (app:device/DeviceLibrary.kt:97-142) (iPhone: the media library's change notice (after 2 s of quiet), and Octo's Files folder looked at again when the app comes back to the front)
- [x] Only files the media library marks as music are listed, with id, URI, file name, folder, modified time, size, length, added time, mime, volume, and the media library's own reading of title, artist (not "<unknown>"), album artist, album, track, disc, year and genre as a fallback (app:device/DeviceScanner.kt:13-89) (iPhone: the Music app's songs (MPMediaQuery; protected Apple Music songs left out and counted) and audio files in Octo's own Files folder)
- [x] Older phones pack the disc into the track number: a track of 1 000 or more is disc track / 1000, track track % 1000 (app:device/DeviceScanner.kt:53-56, 78)
- [x] A file's added time is the earliest real time among modified, added and taken (ms / 1000), ignoring times before 1 January 1990 or more than a day in the future; with none, the media library's added time (app:device/DeviceRow.kt:71-89)
- [x] The file's own tags win over the media library's for every field; genres from the file when it has any (app:device/DeviceRow.kt:47-69)
- [x] Tags are read only for files new or changed (modified time or size) or read by an older tags version (current 2), 4 readers at a time; tags of files gone are forgotten; a file that cannot be read uses the media library's reading (app:device/DeviceLibrary.kt:40-47, 185-208)
- [x] Folders are grouped by their top level ("Music", "Download"); switched-off folders are left out of the library but still listed with their song counts, most songs first; new folders are always in (app:device/Folders.kt:14-79) (iPhone: the folders are the Music app, Octo's own Files folder, and the folders inside it)
- [x] Each phone song's folder path and relative file path are kept from the last scan (storage name first only when music is on more than one storage: "Internal storage", "SD card", or "SD card <ID>" when several) (app:device/DeviceLibrary.kt:83-93, 167-168; app:device/Folders.kt:33-58) (iPhone: an iPhone has one storage, so no storage name is ever added)
- [x] After a scan the phone source's rows are replaced and the library rebuilt (app:device/DeviceLibrary.kt:157-166)

## 41. Reading tags (TagParsing)

- [x] Tag names are compared upper-case without BOM, spaces or punctuation, with `----:com.apple.iTunes:` and `TXXX:` prefixes removed, keeping © (app:device/TagParsing.kt:84-92)
- [x] Every name each field goes by (ID3, Vorbis, MP4 atoms, free-form) is accepted; for lists the more specific tag wins (ARTISTS over ARTIST) (app:device/TagParsing.kt:42-82, 94-151)
- [x] Several values (or one value joined by NUL) are kept in order, deduplicated; artist and album artist lists are joined with ", " (app:device/TagParsing.kt:104-122)
- [x] Track and disc read "3", "03", "3/12", "3 of 12", "(3)"; 0 is unset; "A1" is not a number (app:device/TagParsing.kt:156-169)
- [x] Year from any date form (leading 4 digits, else any standalone 4 digits), 1000 to 2999 only; an original year after the edition's year is dropped (app:device/TagParsing.kt:130-132, 171-181)
- [x] Compilation is "1", "true" or "yes"; BPM rounds the first number, 1 to 999 only; explicit: 1, 4, explicit, e, true, yes are explicit; 2, clean, c are clean (app:device/TagParsing.kt:183-197)
- [x] MusicBrainz ids are any UUID found in the values, lower-cased (app:device/TagParsing.kt:199-203)
- [x] Genres split on `;` `/` `,` (never `&`), keeping "Folk, World, & Country", "Hip-Hop/Rap", "R&B/Soul", "Singer/Songwriter" whole; ID3 numbers 0 to 191 and (RX) Remix, (CR) Cover are named; "(17)Rock and Roll" keeps the words; duplicates differing only in case dropped (app:device/TagParsing.kt:205-282)
- [x] One genre key folds spellings: lowercase, `&` as and, letters and digits only; families: hip hop (hiphoprap, raphiphop, rap, ...), r and b (rnb, rhythmandblues, ...), electronic (electronica, électronique), alternative (alternativeandindie, ...); the library uses the most common spelling (app:device/TagParsing.kt:284-298; app:device/DeviceCatalogBuilder.kt:163-166)
- [x] The album artist sort falls back to the artist sort only when there is no album artist tag (app:device/TagParsing.kt:144-145)

## 42. Building phone albums (DeviceCatalogBuilder)

- [x] Albums are grouped by album name (search key), the folder name when untagged, "Unknown album" otherwise; a same-named group is split only when every file has a MusicBrainz album id (split by it) or every file has an album artist (split by it) (app:device/DeviceCatalogBuilder.kt:29-50, 138-150)
- [x] Album ids are `device:album:<first 8 bytes of SHA-1 of "<name key>|<split key>" in hex>`, stable across scans; song ids `device:<media id>`; artist ids `device:artist:<search key>` (app:device/DeviceCatalogBuilder.kt:46, 56-58, 168, 188-191)
- [x] Album title is the most common spelling (ties to the longer); album artist: the most common album-artist tag, "Various Artists" for a compilation, else the most common track artist, else "Unknown artist" (app:device/DeviceCatalogBuilder.kt:47-49, 152-161, 185-186)
- [x] Order: disc (1 when unknown), track, then file name; when no tags give track numbers, leading numbers in file names are used only if every file has one and all differ (and more than one file) (app:device/DeviceCatalogBuilder.kt:170-183)
- [x] Song title falls back to the file name without extension, else "Untitled"; sort key uses the title sort tag (app:device/DeviceCatalogBuilder.kt:54, 62)
- [x] Album year is the latest of the songs' original-or-edition years; added time is the latest song's; artwork is the first file's embedded art; sort uses the album sort tag (app:device/DeviceCatalogBuilder.kt:98-113)
- [x] Artists: the most common name; sort from the album artist sort tag; album and song counts; artwork from the newest album (app:device/DeviceCatalogBuilder.kt:116-133)
- [x] Phone files that can be deleted, shared or used as sounds are only media-store URIs of merged phone copies; deleting a song removes every phone file it has (app:device/PhoneFiles.kt:6-58) (iPhone: songs in Octo's Files folder can be deleted and shared, Music app songs shared (as an export) but removed only in the Music app; iOS lets no app set a ringtone, notification sound or alarm)

## 43. Merging phone and server into one library (CatalogMerge, CatalogMerger)

- [x] The library is rebuilt from the sources after any source changes, one rebuild at a time, the phone first so its songs keep their ids; only the phone and the server in use join (app:catalog/CatalogMerge.kt:15-67)
- [x] Copies of sources left out of the library lose their merged id, so nothing that looks up a song's copies finds them (app:catalog/CatalogMerge.kt:19-23, 43; app:catalog/SourceDao.kt:85-87)
- [x] Artists match across sources by match key of the name; albums by match key of album artist + title; the match key ignores case, accents, punctuation, spacing, lookalike letters and bracketed extras ("(Deluxe)"), with "&" as "and"; two things one source keeps apart stay apart; the first source's item is the base (app:catalog/CatalogMerger.kt:58-63, 170-204, 277-284)
- [x] Songs match a copy from another source when not already taken from that source, the title keys (with version markers) agree, and lengths differ by at most 3 000 ms; first within the matched album, else the same artist and title anywhere (match key) (app:catalog/CatalogMerger.kt:24-26, 65-101)
- [x] A song matches at most one copy from each source (app:catalog/CatalogMerger.kt:77-78)
- [x] Merged song fields: added is the earliest real time of any copy; year is the first copy's original year, else the first year; genre the first non-empty; artist the credit naming the most artists (ties keep the first); track, disc and rating (1 to 5) the first known; explicit the first that says; on-phone when any copy is (app:catalog/CatalogMerger.kt:28-56, 206-272)
- [x] Album order: an album filled from more than one source is ordered by disc and track when every song has a track number, otherwise kept in arrival order; single-source albums keep their order (app:catalog/CatalogMerger.kt:103-117)
- [x] An album left with no songs is dropped; album counts and length are recounted only for albums from several sources or with songs moved away; album year, artwork and release types fall back to other copies; added is the earliest (app:catalog/CatalogMerger.kt:120-144)
- [x] Artists from a later source with no albums and no songs left are dropped; the phone's artists always stay; counts recounted for merged or later artists (app:catalog/CatalogMerger.kt:146-165)
- [x] After a rebuild: each copy records its library song; likes, plays, playlist entries and ratings follow (first by the copy that merged, then by relink key); favorite albums/artists and Home pins follow; songs with no server rating show the phone's rating (app:catalog/CatalogMerge.kt:41-53; app:catalog/UserDao.kt:438-536)
- [x] Relinking by key only moves rows whose song id vanished, to the first song with the same non-empty relink key; likes and ratings never duplicate (app:catalog/UserDao.kt:438-478)
- [x] Favorite albums/artists and pins whose id vanished follow the library album/artist that took most of their songs (first by id on a tie), else the first id with the same search key that is not already held (app:catalog/Favourites.kt:64-105; app:catalog/FavouritesDao.kt:183-214)
- [x] Song details (info sheet, ListenBrainz) gather from all copies, phone first: each field from the first copy that has it; genres from every copy, one per genre key; artists the fullest credit (app:catalog/SongDetails.kt:25-61)
- [x] The library rebuild is swapped in at once (delete and insert in one transaction), never half-written; inserts in chunks of 500 (app:catalog/CatalogDao.kt:169-179)

## 44. Song identity (shared SongIdentity, used by merge, matching, downloads)

- [x] Folding: NFKC; curly quotes, primes and backtick to `'`/`"`; all dash kinds and minus to `-`; CJK brackets to `[`/`]`/`(`/`)`; underscores to spaces; whitespace collapsed; Cyrillic/Greek lookalike letters read as Latin inside a word that also has Latin letters (shared:catalog/SongIdentity.kt:185-303)
- [x] Key: lowercase per character (dotted capital I kept), ß→ss, æ→ae, œ→oe, ø→o, đ/ð→d, ł→l, þ→th, ı→i, `&` and a spaced `+` read as "and", only Latin/Greek/Cyrillic accents stripped (kana voicing kept), then only letters, digits and combining marks; a title of only symbols keeps its symbols (shared:catalog/SongIdentity.kt:219-234, 305-325)
- [x] Loose key reads `$` as s and `@` as a beside a letter, `!` as i between letters, `0` as o and `3` as e beside a letter and not beside a digit (shared:catalog/SongIdentity.kt:236-264)
- [x] Titles: a leading track number ("01 - ", "01. ", "1-01 ", "2) ") is dropped when letters follow; a leading "Artist - " is dropped when it names the artist (or when the song has no artist); brackets are read as guests, upload noise, part numbers (kept in the key as "pt N", "vol N", "ch N", "book N", Roman numerals read as numbers), version markers, or subtitles; a trailing " - <version or noise>" tail, trailing "feat. X", and trailing remix/sped-up style words are taken off (shared:catalog/SongIdentity.kt:327-610)
- [x] Neutral version markers (same recording): remaster, explicit, original, album version, single version, mono, stereo; all others (radio edit, extended, live, unplugged, acoustic, instrumental, acapella, demo, sped up, slowed, reverb, nightcore, drumless, 8d, piano, orchestral, lofi, bass boosted, mashup, medley, megamix, blend, remix, vip, bootleg, rework, dub, clean, karaoke, cover, reprise, session, mix, edit, version) make another recording (shared:catalog/SongIdentity.kt:175-179, 400-453)
- [x] Artists split on , ; / 、 × & " + " " • " " x " and with/and/feat/ft/featuring/vs/pres./presents, keeping 42 known names whole ("Tyler, The Creator", "Simon & Garfunkel", ...), keeping "X & The Y" whole, dropping channel suffixes (" - Topic", "VEVO") and every bracket (guests kept as featured); aliases: Ye/Kanye→Kanye West, Tupac/Makaveli→2Pac, Puff Daddy/P. Diddy/Sean Combs→Diddy, Snoop Lion→Snoop Dogg, Yasiin Bey→Mos Def, Biggie→Notorious B.I.G., Donald Glover→Childish Gambino, Prince variants→Prince; a leading "The" is optional (shared:catalog/SongIdentity.kt:656-800)
- [x] Same song verdict: a shared valid ISRC (12 chars after removing dashes, dots and spaces, shape AA XXX 0000000) is the same recording at once; else titles must agree (exact key, loose key, or the same letters with overlapping number sets); different distinct versions are "same song, different version"; remixes credited to different people likewise; different subtitles are different songs (and a subtitle on one side only when extras must agree); artists must share one (exact or loose) and not each name a guest the other lacks; lengths more than 3 s apart (by default) are another version; an unknown length costs 0.05 confidence (shared:catalog/SongIdentity.kt:872-1048)
- [x] Match key for dedup and memory: alias-resolved primary artist key + `|` + title key + (`|` + distinct versions joined with `+` when any) (shared:catalog/SongIdentity.kt:1066-1088)
- [x] Search query variants, in order, duplicates dropped: as given; clean title with credit; the same with stylized characters read as letters; clean title with primary artist; clean title alone (shared:catalog/SongIdentity.kt:1112-1153)
- [x] Confidence rounds to two places half-to-even; the server runs the same rules from the shared case file (shared:catalog/SongIdentity.kt:141-146, 1225-1226)

## 45. Things the listener made (local store)

- [x] Likes, ratings, plays, playlists and the saved queue never point at the catalog with a foreign key (the catalog is rebuilt on every scan); each row keeps a relink key to find its song again (app:catalog/UserData.kt:8-13)
- [x] A play row: song id, relink key, start time, heard ms, length (app:catalog/UserData.kt:32-40)
- [x] Played songs (count and latest start) and played albums (latest start) only include songs the library still has (app:catalog/UserDao.kt:344-411)
- [x] A server's play record per copy (play count, last played) joins only for songs with plays or a last-played time (app:catalog/UserDao.kt:392-411)
- [x] Liked songs list newest like first (app:catalog/UserDao.kt:33-35)
- [x] Playlist changes always move the playlist's updated time forward (max(now, updated + 1)) so a clock going back never makes a change look old (app:catalog/UserDao.kt:169-175)
- [x] Playlist rows: add appends after the last position; removing renumbers and returns the row with its old place for undo; restoring puts it back at its place (past the end goes last); moving drops onto the target's place; only changed rows are written (app:catalog/UserDao.kt:287-342, 539-543; app:catalog/Playlists.kt:73-99)
- [x] A playlist's cover mosaic is up to 4 covers, one per album, in song order, skipping songs without art (app:catalog/Playlists.kt:40-47)
- [x] Home pins: at most 12 shown; pinning something already pinned changes nothing; pins renumber from 0 (app:catalog/Favourites.kt:61-132)
- [x] Most played songs order: plays, then latest play, then id; recently played albums: latest play then id (Car "Recent" uses 20 of each) (app:catalog/Plays.kt:24-41)
- [x] An artist's songs: once any were played, the most played first (then the latest played), the rest in album order (app:catalog/Plays.kt:43-53)

## 46. Songs found online (finds)

- [x] A find's id is `find:<server id>`; it is stored with its source, title, artist, album, album/artist ids, known length (0 when the server only guessed 180 s), cover id, mime (content type, else by suffix), bitrate kbps, when seen, when a download was asked, the library song it became, and explicit (app:catalog/Online.kt:14-51; app:discovery/LibraryMatching.kt:50-65; shared:discovery/Matching.kt:123-132)
- [x] A find shown as a song has no album or artist to open, no track number, added 0, an `online:` cover, and is not on the phone (app:discovery/LibraryMatching.kt:67-91)
- [x] A learned length is stored with a find (app:catalog/Online.kt:81-84; app:discovery/FindLengths.kt:34-48)

## 47. Recently played songs kept on the phone (StreamCache)

- [x] Server songs played lately are kept in a rolling store that lets the least recently played go once full; downloads are separate and stay (app:offline/StreamCache.kt:27-29, 95-125) (iPhone: kept in the app's Caches folder, one file per song with its saved pieces listed beside it; a song is let go whole)
- [x] Sizes: Off, 1 GB, 2 GB (default), 5 GB, 10 GB (binary GB, 1 << 30) (app:offline/OfflineSettings.kt:18-46)
- [x] Off clears everything at once; a new size applies at once, evicting oldest first; nothing is evicted before the saved size is known; keeping is off until the setting is read (app:offline/StreamCache.kt:39-66, 100-112)
- [x] A song counts as fully saved when its content length is known and the whole range is cached; partly saved when any span exists (app:offline/StreamCache.kt:68-79)
- [x] Saved under the stable key from section 1 (source, server id, mime, request), never the URL (app:playback/StreamRef.kt:63-67)

## 48. Fetching ahead (Prefetcher)

- [x] While music plays, the next server songs of the queue (in play order, repeat one treated as off, stopping at the current song) are fetched whole into the saved songs, 5 s after a song starts, one after another; finds are never fetched ahead, only saved as they play (app:offline/Prefetcher.kt:27-139)
- [x] How many ahead: 3 on Wi-Fi and 1 on mobile data by default (each 0 to 10); none while offline or while saved songs are off (app:offline/OfflineSettings.kt:28-37; app:offline/Prefetcher.kt:114-119)
- [x] Any change to what comes next (song change, queue change, playing change, shuffle, repeat) or to the settings starts it over; pausing stops it (app:offline/Prefetcher.kt:55-112)
- [x] Each song is pinned to the request it will play with, skipped when already saved whole; a fetch error stops the run (app:offline/Prefetcher.kt:141-160)
- [x] Fetching ahead is only for the phone's own playing, not while casting (app:playback/OctoPlaybackService.kt:182-183) (iPhone: AirPlay plays from the phone's own decks, so fetching ahead goes on while the sound is on another speaker)

## 49. Downloads kept on the phone (OfflineDownloads)

- [x] Defaults: download quality Original (the server's file), Wi-Fi only on, stream on Wi-Fi off, keep Liked songs off, no kept playlists (app:offline/OfflineSettings.kt:31-46)
- [x] Downloads are real files kept for reasons: by hand (`manual`), Liked songs (`liked`), a kept playlist (`playlist:<id>`); stored sorted, comma separated; a file goes once no reason is left (app:offline/DownloadPlan.kt:3-19; app:offline/DownloadDao.kt:12-41)
- [x] Only library songs on a server and not on the phone can be downloaded (app:offline/DownloadDao.kt:152-159)
- [x] Each download comes from the best-quality server copy (same comparison as copy choice), keyed by the server song (source, server id), which never changes; its library song id follows after each rebuild (app:offline/OfflineDownloads.kt:353-380; app:offline/DownloadDao.kt:120-130)
- [x] Rules are re-applied 1 500 ms after likes, kept playlists or their songs settle, never during a rebuild; a rule's reason goes only when the rule no longer wants the song (a song briefly missing during a sync is not deleted); a download by hand stays until removed by hand (app:offline/OfflineDownloads.kt:306-337; app:offline/DownloadPlan.kt:44-66)
- [x] Downloads run one at a time, oldest asked first (then title), only for the server in use, only while signed in, and only on Wi-Fi when "Wi-Fi only" is on (else whenever online); a connection appearing, a setting change or a sign-in wakes the queue (app:offline/OfflineDownloads.kt:138-164, 400-419; app:offline/DownloadDao.kt:89-91)
- [x] The request uses the download quality (raw, or an MP3 cap; a lossy file already under the cap downloads raw); the file type recorded is the server's mime or audio/mpeg (app:offline/OfflineDownloads.kt:428-433)
- [x] Files: `<Artist> - <Title> [<first 4 bytes of SHA-1 of "source|serverId">].<ext>` (readable part at most 80 characters; characters `\ / : * ? " < > |` and control characters become spaces), in an "Octo" folder the media library does not scan (`.nomedia`), written as `.part` then renamed (app:offline/DownloadFiles.kt:1-44; app:offline/OfflineDownloads.kt:431-446, 503-512) (iPhone: kept in the app's own Application Support folder, which the Files app and the phone's music scan never see and backups skip; written as .part, then renamed)
- [x] Progress is written every 500 ms (held at most 0.99 until done); leaving Wi-Fi mid-download (Wi-Fi only on) pauses it back to the queue (app:offline/OfflineDownloads.kt:62-63, 472-501)
- [x] Failures: no connection or no server puts it back in the queue to wait however long; an HTTP refusal fails at once; other errors retry up to 3 tries 5 000 ms apart, then fail; a failed one can be retried by hand (app:offline/OfflineDownloads.kt:68-71, 447-469, 259-268)
- [x] A download interrupted by the app closing waits again at next start; a download removed while running is stopped and its partial file deleted (app:offline/OfflineDownloads.kt:138-148, 238-247; app:offline/DownloadDao.kt:113-115)
- [x] Removing a download by hand keeps it if a rule still wants it; otherwise its finished file is set aside for 10 s for undo (undo moves it back; unfinished ones re-queue; failed ones come back failed), then deleted; set-aside files left from a closed app are deleted at start (app:offline/OfflineDownloads.kt:73-78, 189-236)
- [x] "Remove all" switches off every rule and deletes every download; removing a server with "forget here" deletes its downloads unless another account uses the address (app:offline/OfflineDownloads.kt:249-273; app:playback/ServerSwitch.kt:196-198)
- [x] A finished download whose file has gone goes back to the queue; playable downloads are only those whose file exists (app:offline/OfflineDownloads.kt:290-300)
- [x] Another kept server's downloads stay untouched until it is in use again (app:offline/OfflineDownloads.kt:339-345)
- [x] A family account with offline copies off gets no new downloads from that server ("Offline copies are off for this account"); files already on the phone stay (app:offline/OfflineDownloads.kt:101-104, 377-388)
- [x] The downloads list orders downloading, queued, failed, done, then newest asked, then title (app:offline/DownloadDao.kt:72-80)

## 50. Offline marks on songs

- [x] A song is out of reach only with no connection and when it is not on the phone, not downloaded, and not saved whole from an earlier play (app:offline/OfflineMarks.kt:29-49)
- [x] The saved songs are only looked through once the connection is gone (app:offline/OfflineMarks.kt:83-94)

## 51. Session state beyond sign-in (SessionRepository)

- [x] States: Loading, SignedOut, SignedIn; everything waiting on the saved sign-in waits for it to leave Loading (app:data/SessionRepository.kt:83-91) (iPhone: the saved sign-in comes back from the Keychain as the app starts, and stream requests wait up to 3 s for it)
- [x] At start the saved server in use is restored; when its sealed secret or connection can no longer be opened (keystore lost, e.g. backup on a new phone) it stays listed, signed out (app:data/SessionRepository.kt:192-197, 513-528)
- [x] Each start re-reads the server's extensions and keeps them when they changed and the server answered with some (an Octo signed in before it listed its extensions becomes known as Octo) (app:data/SessionRepository.kt:199-217)
- [x] Extensions are stored as `<name>:<version>` for every version listed (app:data/SessionRepository.kt:304-305)
- [x] Switching to a kept server: asks it first with its own client and a 6 s timeout, so one out of reach changes nothing; wrong password asks for the password ("<name> didn't take the saved password. It may have been changed."); other failures "Couldn't switch to <name>. <why>"; a signed-out server or one without a saved secret asks for the password (app:data/SessionRepository.kt:56-57, 346-379; shared:server/ServerList.kt:67-69)
- [x] Before the session changes, the old one's things are put away (play counted, queue handed over) (app:data/SessionRepository.kt:337, 374, 415, 428; app:data/SessionHandoff.kt:6-22)
- [x] Signing out keeps the server listed without its password; removing the last kept server forgets the sealing key (app:data/SessionRepository.kt:404-436) (iPhone: each server's secret is its own Keychain item, removed with the server, so there is no sealing key to forget)
- [x] Calls go to the home address while it answers within 2 s, otherwise the main address; the library stays under the main address (app:data/SessionRepository.kt:53-54, 530-548, 585-602)
- [x] A music folder can be chosen to limit the library; the library is copied again afterwards (app:data/SessionRepository.kt:480-490; app:server/ServerSync.kt:182-189)
- [x] Per-account small stores use `<name>@<account>` keys; an older single-account store's values move to their account once, never over existing ones; forgetting an account removes every key ending `@<account>` (app:data/AccountPrefs.kt:11-40) (iPhone: the iPhone app never kept single-account stores; the key rules, the move and the forget are ported)
- [x] The server's playlists list is fetched once per sign-in unless refreshed (Octo sets things up the first time) (app:data/LibraryRepository.kt:27-37) (iPhone: as on Android, where that once-per-sign-in list is never used, the server's playlists are read where they are needed: Made for you and playlist sync)

## 52. Pull to refresh (LibraryRefresh)

- [x] A pull rescans the phone and, when signed in, copies the server's library, both at once, and asks how downloads on their way are going; it returns the server copy's error in words, or nothing (app:data/LibraryRefresh.kt:12-33)

## 53. Rediscovery shelves (data)

- [x] Each album's listening on the phone: songs = album song count; played songs = its songs with plays; plays = their sum; last played = latest play (above 0); added = album added time (above 0) (app:ui/home/Rediscovery.kt:12-28)
- [x] Not played lately: played before but not in the last 180 days, most plays first, then the older last play, then id (shared:home/Rediscovery.kt:28-42)
- [x] Never finished: some songs played and some not, most recently played first, then id; an album already on "not played lately" is left out (shared:home/Rediscovery.kt:44-51, 85-93)
- [x] Never played: no plays and no date, newest added first, then id (shared:home/Rediscovery.kt:53-59)
- [x] Each shelf holds at most 20 albums (app:ui/home/Rediscovery.kt:9-10)
- [x] Most played albums: by plays, then latest play, then id; never-played albums left out (shared:home/Rediscovery.kt:61-72)
- [x] From a Subsonic library (desktop form): album plays are the larger of its songs' total and the album's own count; last played the latest of songs' and album's (shared:home/Rediscovery.kt:95-116)

## Shared logic to port line for line

Platform-independent Kotlin, in porting order (each file only needs the ones above it). Port each one exactly, then port its tests and make them pass unchanged. The JSON resources live in `shared/core/src/commonTest/resources/` and are shared with the server; they are the contract.

### Shared core (`shared:`)

1. `shared:catalog/Keys.kt`: search key (lowercase, accents gone), sort key (leading article dropped), natural sort key, relink key. Tests: `sharedTest:catalog/KeysTest.kt`
2. `shared:catalog/SongIdentity.kt`: folding, title and artist parsing, version markers, aliases, ISRCs, the same-song verdict, match keys, query variants. Tests: `sharedTest:catalog/SongIdentityCasesTest.kt` (with `song-identity-cases.json`), `sharedTest:catalog/SongIdentityIsrcTest.kt`, `sharedTest:catalog/SongIdentityStripFeaturesTest.kt`
3. `shared:catalog/ArtworkRef.kt`: the stored artwork reference and its encoding. Tests: `sharedTest:catalog/ArtworkRefTest.kt`
4. `shared:catalog/DrawnCovers.kt`: Octo's painted cover ids and their daily cache stamp. Tests: `sharedTest:catalog/DrawnCoversTest.kt`
5. `shared:catalog/StandInCovers.kt`: detecting a server's stand-in picture by length and SHA-256. Tests: `sharedTest:catalog/StandInCoversTest.kt`
6. `shared:catalog/Explicit.kt`: the server's explicit mark. Tests: `sharedTest:catalog/ExplicitTest.kt`
7. `shared:catalog/ReleaseGroups.kt`: release shelves from release types. Tests: `sharedTest:catalog/ReleaseGroupsTest.kt`
8. `shared:server/ServerQueues.kt`: the server play queue (400-song trim, remote queue reading, server times, the Resume offer rule). Tests: `appTest:server/QueueSyncTest.kt`
9. `shared:server/ServerList.kt`: server names, status lines and the switch notice wording. Tests: `sharedTest:server/ServerListTest.kt`
10. `shared:ui/family/AudioQuality.kt` (only `appPicksQuality` is used by playback; `streamParams` is not used by the phone): whether this app picks the stream quality. Tests: `sharedTest:ui/family/AudioQualityTest.kt`, `sharedTest:ui/family/FamilyRulesTest.kt`, `appTest:playback/StreamQualityForTest.kt`
11. `shared:playback/StreamQuality.kt`: the stream sizes. Tests: `appTest:playback/StreamQualityForTest.kt`
12. `shared:playback/StartAfter.kt`: how much audio is ready before a stream starts. Tests: `sharedTest:playback/StartAfterTest.kt`
13. `shared:playback/PlayRules.kt`: when a play counts. Tests: `sharedTest:playback/PlayRulesTest.kt`
14. `shared:playback/SongLength.kt`: believable measured lengths, playing length, corrections, RealLengths. Tests: `sharedTest:playback/SongLengthTest.kt`, `appTest:playback/SongLengthsTest.kt`
15. `shared:playback/Crossfade.kt`: gapless rules, plain fade length, equal-power fade. Tests: `sharedTest:playback/CrossfadeTest.kt`
16. `shared:playback/AutomixFilters.kt`: Butterworth biquads and the real FFT. Tests: `sharedTest:playback/AutomixTest.kt`, `sharedTest:playback/AutomixVectorsTest.kt`
17. `shared:playback/AutomixEnvelope.kt`: the 10 ms envelope builder (levels, bass, onsets). Tests: `sharedTest:playback/AutomixTest.kt`, `sharedTest:playback/AutomixVectorsTest.kt`, helper `sharedTest:playback/SyntheticSong.kt`
18. `shared:playback/AutomixFeatures.kt`: body level, gate, sound start/end, outro, intro, boundaries, tempo and beat grid, LiveTap. Tests: `sharedTest:playback/AutomixTest.kt`, `sharedTest:playback/AutomixVectorsTest.kt`
19. `shared:playback/AutomixCurves.kt`: gain curves, filter sweeps, tempo-match easing. Tests: `sharedTest:playback/AutomixTest.kt`, `sharedTest:playback/AutomixVectorsTest.kt`
20. `shared:playback/AutomixPlan.kt`: the transition planner. Tests: `sharedTest:playback/AutomixTest.kt`, `sharedTest:playback/AutomixVectorsTest.kt` (with `automix-vectors.json`), cases `sharedTest:playback/AutomixCases.kt`
21. `shared:playback/AutomixProfile.kt`: reading the server's transition profiles and keeping them (64 kept, 60 s retry). Tests: `sharedTest:playback/AutomixProfileTest.kt` (with `transition-profile.json`)
22. `shared:playback/Pace.kt`: speed and pitch. Tests: `sharedTest:playback/PaceTest.kt`
23. `shared:playback/SleepPlan.kt`: sleep timer choices, fade and ticks. Tests: `sharedTest:playback/SleepPlanTest.kt`
24. `shared:playback/ShuffleQueue.kt`: keeping the shuffle play order through inserts, removals and moves. Tests: `sharedTest:playback/ShuffleQueueTest.kt`
25. `shared:playback/QueueRuns.kt`: undo arithmetic. Tests: `sharedTest:playback/QueueRunsTest.kt`
26. `shared:playback/QueueUndo.kt`: finding songs put in, to take them back out. Tests: `sharedTest:playback/QueueUndoTest.kt`
27. `shared:playback/QueueSources.kt`: where each queue song came from, runs and headings. Tests: `sharedTest:playback/QueueSourcesTest.kt`
28. `shared:playback/PlayFailures.kt`: failure words and the skipped/stopped lines. Tests: `appTest:playback/PlayFailureWordsTest.kt`
29. `shared:playback/AutoplayPicks.kt`: Autoplay's batch size and fallback picks. Tests: `sharedTest:playback/AutoplayPicksTest.kt`
30. `shared:radio/RadioTuning.kt`: radio tuning choices. Tests: `sharedTest:radio/RadioMixTest.kt`
31. `shared:radio/RadioSong.kt`: a song as the radio sees it. Tests: `sharedTest:radio/RadioMixTest.kt`
32. `shared:radio/RadioFilter.kt`: what a radio leaves out. Tests: `sharedTest:radio/RadioFilterTest.kt`
33. `shared:radio/RadioMix.kt`: Octo's radio. Tests: `sharedTest:radio/RadioMixTest.kt`
34. `shared:listening/Scrobbles.kt`: waiting plays, retry rule, storage form. Tests: `appTest:listening/ScrobblesTest.kt`
35. `shared:listening/PlayDays.kt`: day headings. Tests: `sharedTest:listening/PlayDaysTest.kt`
36. `shared:discovery/Matching.kt`: known lengths, title keys, same song / recording / any version, title and ISRC indexes, mime of a server song. Tests: `sharedTest:discovery/MatchingTest.kt`
37. `shared:discovery/AlbumShare.kt`: how much of a found album the library holds. Tests: `sharedTest:discovery/AlbumShareTest.kt`
38. `shared:discovery/LibraryOnly.kt`: "Library songs only". Tests: `sharedTest:discovery/LibraryOnlyTest.kt`
39. `shared:home/Rediscovery.kt`: rediscovery shelves. Tests: `sharedTest:home/RediscoveryTest.kt`, `appTest:ui/home/RediscoveryTest.kt`
40. `shared:offline/OfflineKeeping.kt`: the desktop's keep rules and file paths (not used by the Android app, which uses `app:offline/DownloadPlan.kt`; port only if the iPhone keeps files the desktop way). Tests: `sharedTest:offline/OfflineKeepingTest.kt`

### Pure logic in the Android app (no platform API in the rules), also to port line for line

41. `app:playback/Copies.kt`: copy choice, quality comparison, bitrate, stream request, download as a copy. Tests: `appTest:playback/CopiesTest.kt`
42. `app:playback/StreamRef.kt`: queue addresses, cache keys, request choice. Tests: `appTest:playback/StreamRefTest.kt`
43. `app:playback/Streams.kt` (`streamQualityFor` only): quality per network. Tests: `appTest:playback/StreamQualityForTest.kt`
44. `app:playback/OctoLoadControl.kt` (`hasEnoughToStart`): start-after rule. Tests: `appTest:playback/OctoLoadControlTest.kt`
45. `app:playback/BlendTiming.kt`: spare load lead and waiting on an unknown length. Tests: `appTest:playback/BlendTimingTest.kt`
46. `app:playback/AutomixTiming.kt`: run-up geometry, Aligner, rebuffer rule, speed scaling. Tests: `appTest:playback/AutomixTimingTest.kt`
47. `app:playback/ScoutSources.kt` (`answersRanges`): range support check. Tests: `appTest:playback/ScoutSourcesTest.kt`
48. `app:playback/ServerProfiles.kt` (`serverSongOf` and the offer rule). Tests: `appTest:playback/ServerProfilesTest.kt`
49. `app:sound/TransitionShaper.kt`: per-deck gain, headroom, filters, early fade. Tests: `appTest:sound/TransitionShaperTest.kt`
50. `app:sound/LiveTapFeed.kt`: the live reading ring. Tests: `appTest:sound/LiveTapFeedTest.kt`
51. `app:playback/MediaItems.kt` (`tagBpm`, `songLengthMs`). Tests: `appTest:playback/SongLengthsTest.kt`, `appTest:playback/CopiesTest.kt`
52. `app:playback/Quality.kt`: the quality badge. Tests: `appTest:playback/QualityTest.kt`
53. `app:playback/PlayableSongs.kt` (`playsAs`, `chosenStart`). Tests: `appTest:playback/TappedFindTest.kt`
54. `app:playback/RadioItems.kt`: radio station ids. Tests: `appTest:playback/RadioItemsTest.kt`
55. `app:playback/OpenedFileItems.kt` (id format): opened file ids. Tests: `appTest:playback/OpenedFileItemsTest.kt`
56. `app:playback/QueueEntries.kt` and `app:playback/UpNext.kt`: entry ids, keys, up next and played order. Tests: `appTest:playback/UpNextTest.kt`, `appTest:playback/QueueEditorTest.kt`
57. `app:playback/QueueShuffleOrder.kt`: the shuffle order object. Tests: `appTest:playback/QueueShuffleOrderTest.kt`
58. `app:playback/QueueEditor.kt`: undoable queue edits. Tests: `appTest:playback/QueueEditorTest.kt`
59. `app:playback/Stores.kt` (queue snapshot rows, restore point, restored shuffle, parked queues, hand-over, encode/decode). Tests: `appTest:playback/StoresTest.kt`, `appTest:playback/QueueRestoreTest.kt`, `appTest:playback/QueueHandOverTest.kt`
60. `app:playback/PlayTracker.kt`: heard time and the moment a play counts. Tests: `appTest:playback/PlayTrackerTest.kt`
61. `app:playback/Autoplay.kt` (`autoplayDue`). Tests: `appTest:playback/AutoplayTest.kt`
62. `app:playback/LibraryRadio.kt` (`radioSong`). Tests: `appTest:playback/LibraryRadioTest.kt`
63. `app:playback/SleepTimer.kt`: the timer state machine. Tests: `appTest:playback/SleepTimerTest.kt`
64. `app:playback/HeadsetResume.kt` (`headsetKind`, `shouldResumeOnConnect`). Tests: `appTest:playback/HeadsetResumeTest.kt`
65. `app:playback/NotificationHeart.kt`: the notification's heart. Tests: `appTest:playback/NotificationHeartTest.kt`
66. `app:playback/PlayFailureWords.kt`: error code to reason. Tests: `appTest:playback/PlayFailureWordsTest.kt`
67. `app:playback/CarIds.kt`: car ids. Tests: `appTest:playback/CarIdsTest.kt`
68. `app:listening/Stars.kt`: like/star reconciliation. Tests: `appTest:listening/StarsTest.kt`
69. `app:listening/Ratings.kt`: rating reconciliation. Tests: `appTest:listening/RatingsTest.kt`
70. `app:listening/ServerPlays.kt`: phone and server play counts together. Tests: `appTest:listening/ServerPlaysTest.kt`
71. `app:listening/History.kt`: recent history and most played. Tests: `appTest:listening/HistoryTest.kt`
72. `app:listening/FavouriteStars.kt`: favorite album/artist copies and retries. Tests: `appTest:listening/FavouriteStarsTest.kt`, `appTest:listening/FavouriteSendTest.kt`
73. `app:listening/ListenBrainz.kt` (listens, queue, batches, backoff, rate limits, JSON, token shape). Tests: `appTest:listening/ListenBrainzTest.kt`, `appTest:listening/ListenBrainzApiTest.kt`
74. `app:server/QueueSync.kt` (`serverQueueOf`). Tests: `appTest:server/QueueSyncTest.kt`
75. `app:server/ServerCatalog.kt`: server rows, source id, mime by suffix, times. Tests: `appTest:server/ServerCatalogTest.kt`
76. `app:server/ServerArtwork.kt` (cover keys, stand-in check). Tests: `appTest:server/ServerArtworkTest.kt`
77. `app:server/ServerControls.kt` (share expiry, sharing unavailable, album id, others listening, generated stations). Tests: `appTest:server/ServerControlsTest.kt`
78. `app:catalog/CatalogMerger.kt` and `app:catalog/CatalogMerge.kt` (`inLibrary`): the merge. Tests: `appTest:catalog/CatalogMergerTest.kt`, `appTest:catalog/MergeRulesTest.kt`, `appTest:catalog/LibrarySourcesTest.kt`
79. `app:catalog/SongDetails.kt`: details from every copy. Tests: `appTest:catalog/MergeRulesTest.kt`
80. `app:catalog/Favourites.kt`: relinks, merged-into, pins. Tests: `appTest:catalog/FavouritesTest.kt`
81. `app:catalog/Plays.kt`: play orders. Tests: `appTest:catalog/PlaysTest.kt`
82. `app:catalog/Playlists.kt`: summaries, mosaic, row numbering. Tests: `appTest:catalog/PlaylistsTest.kt`
83. `app:catalog/Places.kt`: songs in group order. Tests: `appTest:catalog/PlacesTest.kt`
84. `app:catalog/Online.kt` (`keptFind`) and `app:discovery/FindLengths.kt`. Tests: `appTest:discovery/FindLengthsTest.kt`
85. `app:discovery/LibraryMatching.kt`: resolving server songs, finds as songs. Tests: `appTest:discovery/LibraryMatchingTest.kt`
86. `app:discovery/Discovery.kt` (`madeForYouLists`, `Suggestions`). Tests: `appTest:discovery/MadeForYouTest.kt`, `appTest:discovery/LibraryMatchingTest.kt`
87. `app:discovery/DownloadProgress.kt` and `app:discovery/Downloads.kt` (phases, adoptions, asked songs). Tests: `appTest:discovery/DownloadProgressTest.kt`, `appTest:discovery/LibraryMatchingTest.kt`, `appTest:ui/downloads/DownloadsPillTest.kt`
88. `app:device/TagParsing.kt` and `app:device/SavedTags.kt`: tag reading and storage. Tests: `appTest:device/TagParsingTest.kt`, `appTest:device/TagFormsTest.kt`, `appTest:device/FileDetailsTest.kt`
89. `app:device/DeviceRow.kt` (`toRow`, `fileAddedAt`). Tests: `appTest:device/FileDetailsTest.kt`
90. `app:device/DeviceCatalogBuilder.kt`: phone albums and artists. Tests: `appTest:device/DeviceCatalogBuilderTest.kt`
91. `app:device/Folders.kt`: folder rules and paths. Tests: `appTest:device/FoldersTest.kt`
92. `app:device/PhoneFiles.kt`: phone files, delete plan, share type. Tests: `appTest:device/PhoneFilesTest.kt`
93. `app:offline/DownloadPlan.kt`: download reasons and plans. Tests: `appTest:offline/DownloadPlanTest.kt`
94. `app:offline/DownloadFiles.kt`: download file names. Tests: `appTest:offline/DownloadFilesTest.kt`
95. `app:offline/OfflineDownloads.kt` (`canRestore`). Tests: `appTest:offline/DownloadUndoTest.kt`
96. `app:offline/OfflineMarks.kt`: out-of-reach marks. Tests: `appTest:offline/OfflineMarksTest.kt`
97. `app:data/AccountPrefs.kt`: per-account keys. Tests: `appTest:data/AccountStoresTest.kt`
98. `app:ui/home/Rediscovery.kt`: phone album listening for the shelves. Tests: `appTest:ui/home/RediscoveryTest.kt`, `appTest:sort/PlayedListeningTest.kt`
