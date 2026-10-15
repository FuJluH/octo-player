# octo-audio

The audio engine for the Octo desktop app (Windows, macOS, Linux). A Rust
library driven from Kotlin on the JVM through generated UniFFI bindings. It
plays local files and server streams with gapless joins, crossfades, the
same sound shaping as the Android app, and a sample-accurate clock.

## Layout

<!-- markdownlint-disable MD013 -->

| Path | What it holds |
| --- | --- |
| `src/api.rs` | The `Engine` object, records, events and listener |
| `src/player.rs` | The player thread: queue, device, events |
| `src/mixer.rs` | Lanes, crossfade (curve, filter sweeps, tempo match), speed, shaping, live tap, clock markers |
| `src/automix.rs` | Transition plans, gain curve and sweep math, the planner and settings |
| `src/scout.rs` | Decodes the end or start of a queued song for the planner, off the audio path |
| `src/lane.rs` | Gapless chains of songs through one resampler |
| `src/deck.rs` | One song decoding ahead on its own thread |
| `src/decode.rs` | symphonia decoding, gapless trims, seeking, tags |
| `src/opus.rs` | Opus through a pure Rust decoder |
| `src/source/` | Files, HTTP(S) streams with read-ahead and pinned certificates, live streams with ICY titles, HLS |
| `src/sound/` | EQ, presets, crossfeed, limiter, balance, mono, ReplayGain |
| `src/pace.rs` | Speed (pitch kept) and pitch shift |
| `src/output/` | Device callback, audio clock, cpal and silent drivers |
| `src/timeline.rs` | Which song and second each ring frame holds |
| `src/video/` | Animated covers: muted video loops decoded by the system (Media Foundation, AVFoundation, GStreamer) |
| `bindings/kotlin/` | Generated Kotlin bindings |
| `examples/` | `play` (manual testing), `bench` (CPU), `render_transition` (blends to WAVs, with checks), `bpm_check` (tempo against tags), `loop_video` (a video loop's decode speed and pace) |
| `tools/make-fixtures/` | Makes the small mp3 and opus test files |

<!-- markdownlint-enable MD013 -->

## Architecture

```text
 deck thread (per song)   player thread                  device callback
 source -> decode ------> lane: RG gain -> resample      (cpal thread)
 (file or HTTP fetch        mix (crossfade, per sample)  ring -> volume,
  thread with               speed -> EQ -> limiter  ---> pause/seek fades
  read-ahead)               markers -> timeline    ring  -> device
                                                          clock atomics
 event thread: calls the app's listener, never on the audio path
```

- **Threads.** The app's calls send commands and return at once. The player
  thread owns the queue, mixer and device. Each song decodes on its own
  thread into a 0.75 s buffer, so opening and network waits never stall
  mixing. HTTP streams fetch on another thread into a 4 MB window.
- **Ring.** The player keeps about 120 ms in a lock-free SPSC ring (`rtrb`).
  The callback never locks, allocates or waits: it copies, applies volume
  and the 10 ms fades for pause, resume and jumps, and records timing.
- **Gapless.** A lane runs consecutive songs through one resampler, so a
  join at the same source rate is exact to the sample, even when the device
  rate differs. Encoder delay and padding are trimmed where symphonia
  exposes them: the LAME header for MP3, pre-skip and granule end for Opus.
  AAC in MP4 (`iTunSMPB`) is not trimmed by symphonia 0.6.
- **Clock.** The callback notes which ring frame it played last and when
  that buffer is heard (cpal's playback timestamp, which includes device
  latency). The mixer tags ring frames with song and second. Position is
  interpolated between callbacks and never runs backwards within a song.

## Coverage against Android

<!-- markdownlint-disable MD013 -->

| Feature | Status |
| --- | --- |
| Gapless | Sample-exact, pre-decoded next song, delay/padding trimmed |
| Crossfade 0 to 16 s | Equal power, per sample; Android's rules, albums in order stay gapless; decided once the next song's real length is known |
| Smart transitions | Planned start, entry and overlap, S-curve, filter sweeps, tempo match; the planner itself is still the plain crossfade |
| Volume | Linear and dB, mute, click-free ramps |
| ReplayGain | Off, track, album, smart; preamp, fallback, clipping prevention, R128 tags, stored server values |
| EQ | Graphic 10 bands and presets, parametric peak and shelves, headphone correction, auto preamp, 30 ms glides |
| Balance, mono, limiter | Same numbers (-1 dB ceiling, 1.5 ms look-ahead, 100 ms release) |
| Speed 0.5 to 2x | Pitch kept (overlap-add, as Android's player), pitch shift in semitones |
| Seek | Sample-accurate, with a fade |
| Pause and resume | 10 ms fade |
| Per-output profiles | The app keeps them: it gets `DeviceChanged` and calls `set_eq` and `set_dsp` |
| Trusted self-signed certificates | `set_trusted_certificates`: the system's check first, then a SHA-256 pin for that host only |
| Live streams | Live radio (`live` items): reconnects, ICY titles as `StreamTitle`, old SHOUTcast `ICY 200 OK` servers, HLS with MPEG-TS, AAC, MP3 or fMP4 segments |
| Skip silence | Not ported |

<!-- markdownlint-enable MD013 -->

## Crates

All newest stable, checked with `python scripts/check-deps.py`.

<!-- markdownlint-disable MD013 -->

| Crate | Version | Why |
| --- | --- | --- |
| symphonia | 0.6.1 | FLAC, MP3, AAC/M4A, ALAC, Vorbis, WAV, AIFF; gapless trims |
| opus-decoder | 0.1.1 | Pure Rust Opus, passes all 12 RFC 8251 vectors |
| cpal | 0.18.2 | WASAPI, Core Audio, ALSA; default-device events |
| rubato | 5.0.0 | FFT resampler to the device rate |
| rtrb | 0.4.0 | Wait-free ring to the callback |
| ureq | 3.4.2 | Small blocking HTTP client, rustls with the OS trust store |
| rustls, rustls-platform-verifier, ring | 0.23.45, 0.7.1, 0.17.14 | ureq's own TLS, named to add pinned certificates to the OS check |
| uniffi | 0.32.2 | Kotlin bindings |
| crossbeam-channel, thiserror, log | 0.5.17, 2.0.21, 0.4.34 | Commands, errors, logs |
| windows (Windows only) | 0.62.2 | Media Foundation and Direct3D 11 for video loops (already in the tree through cpal) |
| objc2-av-foundation, objc2-core-media, objc2-core-video (macOS only) | 0.3.2 | AVFoundation for video loops |
| libloading (Linux only) | 0.9.0 | Loads GStreamer when a video loop is opened, so the engine needs none |
| flacenc (tests only) | 0.5.1 | FLAC files made while testing |
| rcgen (tests only) | 0.14.10 | Self-signed certificates for the HTTPS test server |

<!-- markdownlint-enable MD013 -->

**Opus.** symphonia 0.6 has no Opus decoder. The libopus bindings
(`opusic-sys`, `audiopus_sys`, `libopus_sys`) all build libopus with CMake,
and some need libclang, so they fail on a plain machine. `opus-decoder` is
safe pure Rust and conformance-tested. It is slower than libopus, which is
still well inside budget for music. `opus-rs` is faster but has no
conformance vectors in its tests.

**Speed.** No mature pure Rust time-stretch crate exists. `timestretch`
(0.15) is capable but young, single-author and aimed at DJ decks;
`signalsmith-stretch` needs libclang; the WSOLA crates are weeks old. So
speed uses pitch-synchronous overlap-add written here, the same family as
the Sonic method the Android player uses, with a cubic rate change for
pitch shifts.

## Building

Rust 1.88 or newer (tested with 1.91.1), no toolchain file needed.

- **Windows:** MSVC build tools.
- **macOS:** Xcode command line tools.
- **Linux:** `sudo apt install libasound2-dev pkg-config` (Fedora:
  `alsa-lib-devel`). Output goes through ALSA; with `pipewire-alsa` or the
  PulseAudio ALSA plugin installed, the ALSA `default` device plays through
  PipeWire or PulseAudio and follows its default sink.

```sh
cargo build --release
cargo test
cargo clippy --all-targets -- -D warnings
```

`.github-workflow-example.yml` is a matrix build for all three systems, to
copy into `.github/workflows/` later.

## Kotlin bindings

```sh
sh scripts/gen-kotlin.sh        # or scripts/gen-kotlin.ps1 on Windows
```

This builds the release library and writes
`bindings/kotlin/app/winters/octo/audio/octo_audio.kt`. The JVM side needs
JNA 5.12 or newer (tested with 5.17) and the native library on
`jna.library.path` or bundled as a JNA resource.

```kotlin
val engine = Engine()                  // Engine.newSilent() for tests
engine.setListener(object : EngineListener {
    override fun onEvent(event: EngineEvent) { /* on the engine's thread */ }
})
engine.load(listOf(QueueItem(id = "q:1", source = url)), 0u, 0uL, true)
engine.setCrossfade(6000u)
engine.position().positionMs          // audio clock, fractional ms
```

- **Queue:** `load`, `playNext`, `enqueue`, `replaceUpcoming`,
  `replaceQueue`, `skipTo`, `skipNext`, `setRepeat`, `setStopAfterCurrent`,
  `queue`.
- **Transport:** `play`, `pause`, `stop`, `seek`.
- **Sound:** `setVolume`, `setVolumeDb`, `setMuted`, `setCrossfade`,
  `setAutomix` (smart transitions, filter sweeps, match tempo, longest
  blend), `setEq`, `setReplaygain`, `setDsp`, `setSpeed(speed, pitch)`.
- **Devices:** `devices`, `currentDevice`, `setOutputDevice(id or null)`,
  `outputFormat` (the rate, channels and sample format the device's stream
  was opened with).
- **State:** `position`, `state`, `nowPlaying`, `underruns`,
  `setPositionInterval`, `shutdown`.
- **Also:** `equalizerPresets()`, `graphicBands()`.
- **Events:** `TrackStarted`, `TrackEnded` (with a reason),
  `GaplessTransition`, `CrossfadeStarted`, `TransitionPlanned` (how the
  next song will follow, with an `automix:` line for the log), `Buffering`, `Ready`,
  `StateChanged`, `QueueEnded`, `Error` (with a kind), `DeviceChanged`
  (with the device's format), `Position`, `StreamTitle` (a live stream's
  title, as it is heard). `TrackStarted` carries the song's own format as
  decoded (codec, lossless, rate, channels, bits).

Server streams arrive as signed addresses from the app, as on Android, with
optional extra headers per item. The engine reuses the address for range
requests and reconnects.

## Live streams

A `QueueItem` with `live = true` is live radio. It has no length and
ignores seeks and start positions, and nothing is opened behind it until
it fails or the listener moves on. Paused for 30 s or more, it starts again
where its station is now. `hls = true` opens an address as HLS whatever it
looks like.

- **HTTP.** Requests carry `Icy-MetaData: 1` and no range. A dropped or
  ended connection is made again after 1, 2, 4 and 8 s, carrying on from
  wherever the server is; then the stream fails as gone. A connection
  counts as working only after 64 KB or 10 s, so a server that hangs up
  after a few bytes each time is gone too. The metadata
  blocks an `icy-metaint` server puts in the audio are taken out, and each
  new `StreamTitle` is sent as an event once the sound it starts with is
  heard; an empty one says the station names nothing now. Old SHOUTcast servers answer `ICY 200 OK`; a link in the client's
  connection chain reads that as `HTTP/1.0 200 OK`.
- **Types.** `audio/aac`, `audio/aacp` and `audio/x-aac` are ADTS AAC,
  `audio/mpeg` MP3 and `audio/ogg` Ogg; the bytes have the last word. A
  codec that starts over (a new Ogg stream, say) gets a new decoder, and
  one that comes back at another sample rate is changed back to the first.
- **HLS.** An `.m3u8` address, or a playlist content type, opens as HLS.
  A master playlist's best variant the engine decodes is played (sound
  only first, then the highest bit rate). Segments are fetched in order
  and joined; a live playlist is fetched again every target duration,
  starting three segments from the newest. Numbers that start again (an
  encoder restart) are joined again at the newest; a playlist that adds
  nothing for three target durations (at least 20 s) fails, as do eight
  segments in a row the server says are missing. Empty segments are passed
  over. MPEG-TS, ADTS AAC, MP3 and
  fragmented MP4 (init segment, then segments) play; a discontinuity or a
  new init segment opens a fresh decoder. MPEG-TS is cut down to its first
  audio stream (AAC in ADTS, or MPEG audio) by `source/ts.rs`, which keeps
  its place across segments, so a packet cut between two joins up; timed
  ID3 and other streams are passed over. Encrypted streams are refused
  with a clear error. A live answer whose first bytes (after a byte order
  mark and white space) are `#EXTM3U` is a playlist whatever its address
  and type say; one with no target duration or variants, such as a
  station's `#EXTINF:-1` list, opens its first entry, following at most
  three playlists in a row.
- **HE-AAC.** symphonia's AAC decoder has no SBR or PS, so HE-AAC plays its
  AAC-LC core: half the sample rate, no rebuilt high band, and for HE-AAC
  v2 its mono core. In ADTS that happens by itself; an MP4 config that
  names SBR or PS is turned into its core's.

## Video loops

Animated album covers are short muted H.264 loops in fragmented MP4 (as
Apple keeps them). The app fetches one file and opens a `LoopVideo` on it:

```kotlin
val video = LoopVideo.open(path, widthPx, heightPx)   // scaled down to cover it
video.play()
val n = video.waitFrame(have, 500u)                     // blocks until a newer frame
have = video.copyFrame(pixmap.addr.toULong(), rowBytes, length, have)
video.hold()                                            // decodes nothing until play
video.stop()
```

- **Thread.** Each loop decodes on its own thread, one frame ahead, and
  shows each at its timestamp. At the end it goes back to the first frame
  and carries on, so a round follows the last by one frame's length. Held,
  the thread waits and decodes nothing. A frame more than 250 ms late
  (after sleep, say) restarts the clock from it rather than rushing.
- **Frames.** BGRA, top row first, alpha 255. `copyFrame` copies the
  newest frame into memory the app owns (a bitmap's pixels) only when it
  is newer than the one the app has, so no frame crosses as a new array.
  It refuses memory too small for a frame.
- **Windows.** A Media Foundation Source Reader with advanced video
  processing gives RGB32 at the size asked for. It decodes on the graphics
  card through a Direct3D 11 device when one opens and decodes the first
  frame, else on the processor. `OCTO_VIDEO_SOFTWARE=1` forces the
  processor, for comparing.
- **macOS.** An `AVAssetReader` on the video track gives 32BGRA pixel
  buffers (VideoToolbox decodes). A reader cannot go back, so each round
  has a new one.
- **Linux.** GStreamer (`libgstreamer-1.0.so.0` and `libgstapp-1.0.so.0`)
  is loaded the first time a loop opens: `filesrc ! qtdemux ! decodebin !
  videoconvert ! videoscale ! appsink` in BGRA. H.264 needs
  `gstreamer1.0-libav` (or another H.264 decoder). Without GStreamer,
  `loopVideoAvailable()` is false, opening fails with `Unsupported`, and
  the app shows the still; the engine links neither GStreamer nor GLib.
- **Measured (Windows 11, RTX 3080 Ti, Apple's Short n' Sweet loops, 24
  frames a second, 24 s):** on the graphics card, 486x486 takes 1.6 % of
  one core while playing and 1078x1438 6.9 %; on the processor 2.8 % and
  32.5 % (its decoder spreads each frame over many threads: 0.3 ms and 1.6
  ms a frame of wall time, about 3 and 16 ms of processor time). Held, 0 %.
  Linux (WSL, `avdec_h264`): 486x486 decodes in 1.9 ms a frame and plays
  at about 5 % of one core.

```sh
cargo run --release --example loop_video -- loop.mp4 --seconds 20 --size 486 --hold-after 10
```

## Transitions

When the next song is close, the player opens it and decides how it
follows: gapless, or a blend. A song with no length in the queue (outside
songs on radio) is decided once its decoder reports the length, at the
latest just before the crossfade would have to start. With smart
transitions on, the end of the playing song (60 s) and the start of the
next (30 s) are decoded on a scout thread (a stream's end only when its
server answers ranges) into envelopes: level, bass level and a 3-band
spectral flux every 10 ms. From those `automix::plan` finds each song's
body level, sound start and end, outro, section boundaries and beat grid,
and chooses a `TransitionPlan`: when the blend starts (on a bar line when
both tempos are trusted, scored against the outro and the boundaries),
where the next song comes in, how long both sound, the curve, the filter
sweeps and an optional rate. The mixer runs it; the outgoing song stops
when the blend ends, and finishes early when it falls silent. Without the
end's analysis, or with no start left at least 3 s ahead, the plan is a
late one at the end of the song. The live tap keeps the playing song's
envelope as it is mixed, for its whole-song level and tempo. Genres such as
classical or podcast get the plain crossfade.

The analysis and planner are the same as the app's Kotlin copy in
`shared/core`: `automix::vectors` runs every case in
`shared/core/src/commonTest/resources/automix-vectors.json`.

```sh
cargo run --release --example render_transition -- a.flac b.flac out.wav --filters 0.7
cargo run --release --example render_transition -- --batch pairs.txt out/
cargo run --release --example bpm_check -- ~/Music/some-folder --limit 60
```

`render_transition` prints each plan and checks the rendered blend: its
momentary loudness against the two songs' bodies (3 dB under the quieter,
2 dB over the louder), samples above -0.1 dBFS, and clicks near the blend.
A pairs file holds one pair a line, split by a tab or ` | `. `bpm_check`
finds every song's tempo over the whole song, its first 30 s and its last
60 s, and gives the share within 2 % of the tag tempo after halving or
doubling. MP3 tags are not read: the engine builds symphonia without its
ID3 support.

## Tests

`cargo test` needs no sound device: engine tests play through the silent
driver. WAV and FLAC files are made while the tests run; the MP3 and Opus
fixtures are tones made by `tools/make-fixtures`, the AAC ones by FFmpeg
(see `tests/fixtures/README.md`). Live streams and HLS play from servers
the tests run on the spot.

## Performance

`cargo run --release --example bench`, on this machine (Windows 11):

<!-- markdownlint-disable MD013 -->

| Stage, 44.1 kHz 16-bit FLAC to a 48 kHz device | Per second of audio |
| --- | --- |
| FLAC decode | 0.78 ms |
| EQ (10 bands) + preamp + limiter | 2.2 ms |
| Whole chain (decode, resample, EQ, limiter) | about 3 ms |

<!-- markdownlint-enable MD013 -->

Real-time playback on WASAPI with the Rock preset and the limiter, measured
from outside the process: 0.63 % of one core and a 13.5 MB working set
(3.3 MB private), no underruns.

## Needs real hardware

- Clock accuracy against what is heard (latency figures from each backend).
- Default-device following: unplugging USB and Bluetooth, and Windows,
  macOS and PipeWire default changes.
- Long pauses stopping the stream, and resuming after sleep.
- macOS and Linux builds and playback.
- Long runs over flaky networks.
