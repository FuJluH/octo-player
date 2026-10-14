//! Live streams end to end: HLS playlists and live radio, from a local
//! server through the decoder.

use std::io::Write;
use std::net::TcpStream;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::thread;
use std::time::{Duration, Instant};

use crate::deck::{Deck, DeckStatus};
use crate::decode::{Decoder, lc_core_config};
use crate::error::ErrorKind;
use crate::source::{self, http::HttpOptions};
use crate::testing::fixtures::*;
use crate::testing::http_server::ScriptServer;

fn live() -> HttpOptions {
    HttpOptions { live: true, live_backoff: Duration::from_millis(20), ..Default::default() }
}

// The ADTS frames of an AAC file, each whole.
fn adts_frames(bytes: &[u8]) -> Vec<&[u8]> {
    let mut frames = Vec::new();
    let mut at = 0;
    while at + 7 <= bytes.len() {
        assert_eq!(bytes[at], 0xff, "not an ADTS frame at {at}");
        let len = ((bytes[at + 3] as usize & 3) << 11)
            | ((bytes[at + 4] as usize) << 3)
            | (bytes[at + 5] as usize >> 5);
        frames.push(&bytes[at..at + len]);
        at += len;
    }
    frames
}

// The AAC fixture cut into segments of about half a second, each with the
// ID3 tag packed audio segments start with.
fn adts_segments(name: &str) -> Vec<Vec<u8>> {
    let bytes = std::fs::read(fixture(name)).unwrap();
    adts_frames(&bytes)
        .chunks(22)
        .map(|frames| with_id3v2(&frames.concat(), &[("TIT2", "segment")], &[]))
        .collect()
}

fn answer(conn: &mut TcpStream, content_type: &str, body: &[u8]) {
    let head = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        body.len()
    );
    let _ = conn.write_all(head.as_bytes());
    let _ = conn.write_all(body);
}

fn not_found(conn: &mut TcpStream) {
    let _ = conn.write_all(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
}

// The number in a path like "/seg/12.aac".
fn number(target: &str) -> Option<u64> {
    target.rsplit('/').next()?.split('.').next()?.parse().ok()
}

// A live media playlist: each time it is asked for it shows one segment
// more, four at a time, with `tag` written before a segment where it says.
fn live_playlist(asked: u64, ext: &str, head: &str, tag: impl Fn(u64) -> Option<&'static str>) -> String {
    let mut text = format!(
        "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-TARGETDURATION:0.3\n#EXT-X-MEDIA-SEQUENCE:{asked}\n{head}"
    );
    for seq in asked..asked + 4 {
        if let Some(tag) = tag(seq) {
            text.push_str(tag);
            text.push('\n');
        }
        text.push_str(&format!("#EXTINF:0.5,\n/seg/{seq}.{ext}\n"));
    }
    text
}

// The tone's frequency in most tenths of a second of `stereo`: the joins
// where a looped fixture starts over are left out that way.
fn steady_frequency(stereo: &[f32], rate: u32) -> f64 {
    let window = rate as usize / 10 * 2;
    let mut each: Vec<f64> = stereo.chunks_exact(window).map(|w| frequency(w, rate)).collect();
    each.sort_by(f64::total_cmp);
    each[each.len() / 2]
}

// Reads `secs` of sound from a deck, failing the test on a failure.
fn read_secs(deck: &Deck, secs: f64) -> Vec<f32> {
    let until = Instant::now() + Duration::from_secs(20);
    let mut all = Vec::new();
    let mut buf = vec![0.0; 4096];
    loop {
        let rate = deck.info().map_or(44_100, |i| i.sample_rate) as f64;
        if all.len() as f64 / 2.0 >= secs * rate {
            return all;
        }
        let r = deck.read(&mut buf);
        if let Some(f) = r.failure {
            panic!("the stream failed: {f}");
        }
        assert!(!r.finished, "a live stream ended after {} frames", all.len() / 2);
        all.extend_from_slice(&buf[..r.frames * 2]);
        if r.frames == 0 {
            assert!(Instant::now() < until, "only {} frames came", all.len() / 2);
            thread::sleep(Duration::from_millis(2));
        }
    }
}

#[test]
fn a_live_hls_playlist_of_adts_segments_plays_on() {
    let segments = adts_segments("tone-440-44k-stereo.aac");
    let polls = Arc::new(AtomicU64::new(0));
    let count = polls.clone();
    let server = ScriptServer::start(move |asked, conn, _| {
        if asked.target.ends_with(".m3u8") {
            let n = count.fetch_add(1, Ordering::SeqCst);
            answer(conn, "application/vnd.apple.mpegurl", live_playlist(n, "aac", "", |_| None).as_bytes());
        } else if let Some(seq) = number(&asked.target) {
            answer(conn, "audio/aac", &segments[seq as usize % segments.len()]);
        } else {
            not_found(conn);
        }
    });
    let deck = Deck::open(1, server.url("/live/radio.m3u8"), 0.0, live());
    let sound = read_secs(&deck, 3.0);
    let info = deck.info().unwrap();
    assert_eq!((info.codec.as_str(), info.sample_rate, info.duration_ms), ("aac", 44_100, None));
    let middle = &sound[sound.len() / 4..];
    assert!((steady_frequency(middle, 44_100) - 440.0).abs() < 3.0, "{}", steady_frequency(middle, 44_100));
    // It went back for newer segments, and started near the newest.
    assert!(polls.load(Ordering::SeqCst) >= 3);
    let first = server
        .asked()
        .iter()
        .find_map(|a| a.target.starts_with("/seg/").then(|| number(&a.target)))
        .flatten();
    assert_eq!(first, Some(1), "{:?}", server.asked());
}

#[test]
fn a_live_hls_playlist_of_fmp4_segments_plays_across_discontinuities() {
    let dir = fixture("hls-fmp4");
    let init = std::fs::read(dir.join("init.mp4")).unwrap();
    let segments: Vec<Vec<u8>> =
        (0..4).map(|i| std::fs::read(dir.join(format!("seg{i}.m4s"))).unwrap()).collect();
    let polls = Arc::new(AtomicU64::new(0));
    let count = polls.clone();
    let server = ScriptServer::start(move |asked, conn, _| {
        let t = asked.target.as_str();
        if t == "/master.m3u8" {
            // A variant in a codec the engine cannot play, at a higher rate.
            let master = "#EXTM3U\n\
                #EXT-X-STREAM-INF:BANDWIDTH=640000,CODECS=\"ec-3\"\nsurround.m3u8\n\
                #EXT-X-STREAM-INF:BANDWIDTH=128000,CODECS=\"mp4a.40.2\"\nstereo.m3u8\n";
            answer(conn, "application/vnd.apple.mpegurl", master.as_bytes());
        } else if t == "/stereo.m3u8" {
            let n = count.fetch_add(1, Ordering::SeqCst);
            // The segments come round again, each time after a discontinuity.
            let text = live_playlist(n, "m4s", "#EXT-X-MAP:URI=\"init.mp4\"\n", |seq| {
                (seq % 4 == 0 && seq > 0).then_some("#EXT-X-DISCONTINUITY")
            });
            answer(conn, "application/vnd.apple.mpegurl", text.as_bytes());
        } else if t == "/init.mp4" {
            answer(conn, "audio/mp4", &init);
        } else if let Some(seq) = number(t).filter(|_| t.starts_with("/seg/")) {
            answer(conn, "audio/mp4", &segments[seq as usize % 4]);
        } else {
            not_found(conn);
        }
    });
    let deck = Deck::open(1, server.url("/master.m3u8"), 0.0, live());
    let sound = read_secs(&deck, 4.0);
    assert_eq!(deck.info().unwrap().sample_rate, 44_100);
    let middle = &sound[sound.len() / 4..];
    assert!((steady_frequency(middle, 44_100) - 440.0).abs() < 3.0, "{}", steady_frequency(middle, 44_100));
    let targets: Vec<String> = server.asked().into_iter().map(|a| a.target).collect();
    assert!(!targets.iter().any(|t| t.contains("surround")), "{targets:?}");
    // Each period starts with the init segment again.
    assert!(targets.iter().filter(|t| *t == "/init.mp4").count() >= 2, "{targets:?}");
}

// A transport stream fixture cut every `packets` packets, wherever that
// falls, and whether any cut fell inside a PES packet of its audio.
fn ts_segments(name: &str, packets: usize) -> (Vec<Vec<u8>>, bool) {
    let bytes = std::fs::read(fixture(name)).unwrap();
    assert_eq!(bytes.len() % 188, 0);
    let segments: Vec<Vec<u8>> = bytes.chunks(188 * packets).map(<[u8]>::to_vec).collect();
    // FFmpeg puts the audio on PID 0x100; a cut before a packet of it that
    // starts no PES packet is a cut inside one.
    let mid_pes = segments[1..]
        .iter()
        .any(|s| s[1] & 0x40 == 0 && (u16::from(s[1] & 0x1f) << 8 | u16::from(s[2])) == 0x100);
    (segments, mid_pes)
}

// A live playlist of `segments` over and over, a discontinuity each time
// they start again.
fn ts_server(segments: Vec<Vec<u8>>) -> ScriptServer {
    let polls = AtomicU64::new(0);
    ScriptServer::start(move |asked, conn, _| {
        let t = asked.target.as_str();
        let count = segments.len() as u64;
        if t == "/live.m3u8" {
            let n = polls.fetch_add(1, Ordering::SeqCst);
            let text = live_playlist(n, "ts", "", |seq| {
                (seq % count == 0 && seq > 0).then_some("#EXT-X-DISCONTINUITY")
            });
            answer(conn, "application/vnd.apple.mpegurl", text.as_bytes());
        } else if let Some(seq) = number(t).filter(|_| t.starts_with("/seg/")) {
            answer(conn, "video/mp2t", &segments[(seq % count) as usize]);
        } else {
            not_found(conn);
        }
    })
}

#[test]
fn hls_in_mpeg_ts_segments_plays_aac_and_mp3() {
    for (name, codec) in [("tone-440-44k-stereo-aac.ts", "aac"), ("tone-440-44k-mono-mp3.ts", "mp3")] {
        let (segments, mid_pes) = ts_segments(name, 29);
        assert!(mid_pes, "{name}: no cut fell inside a PES packet");
        let server = ts_server(segments);
        let deck = Deck::open(1, server.url("/live.m3u8"), 0.0, live());
        // Past the end of the fixture, so across a discontinuity.
        let sound = read_secs(&deck, 3.5);
        let info = deck.info().unwrap();
        assert_eq!(
            (info.codec.as_str(), info.sample_rate, info.duration_ms),
            (codec, 44_100, None),
            "{name}"
        );
        let middle = &sound[sound.len() / 4..];
        assert!(
            (steady_frequency(middle, 44_100) - 440.0).abs() < 3.0,
            "{name}: {}",
            steady_frequency(middle, 44_100)
        );
        let wrapped = server
            .asked()
            .iter()
            .filter_map(|a| number(&a.target).filter(|_| a.target.starts_with("/seg/")))
            .max();
        assert!(wrapped.unwrap() >= 7, "{name}: only up to segment {wrapped:?}");
    }
}

#[test]
fn hls_in_mpeg_ts_with_audio_the_engine_cannot_play_fails_clearly() {
    let (mut segments, _) = ts_segments("tone-440-44k-stereo-aac.ts", 1_000);
    // Every PMT (PID 0x1000) made to call the AAC stream AC-3.
    let pmts = segments[0]
        .chunks_exact_mut(188)
        .filter(|p| (u16::from(p[1] & 0x1f) << 8 | u16::from(p[2])) == 0x1000);
    for packet in pmts {
        let section = 4 + 1 + packet[4] as usize;
        let info = (usize::from(packet[section + 10] & 0x0f) << 8) | usize::from(packet[section + 11]);
        let stream_type = section + 12 + info;
        assert_eq!(packet[stream_type], 0x0f);
        packet[stream_type] = 0x81;
    }
    let server = ts_server(segments);
    let deck = Deck::open(1, server.url("/live.m3u8"), 0.0, live());
    let until = Instant::now() + Duration::from_secs(10);
    let failure = loop {
        if let DeckStatus::Failed(f) = deck.status() {
            break f;
        }
        assert!(Instant::now() < until, "it never failed");
        thread::sleep(Duration::from_millis(5));
    };
    assert_eq!(failure.kind, ErrorKind::Unsupported);
    assert!(failure.message.contains("codec the engine does not play"), "{failure}");
}

// A stream that comes back at another rate after a discontinuity keeps
// sounding at its first rate, and a finished playlist ends.
#[test]
fn a_rate_change_after_a_discontinuity_keeps_the_first_rate() {
    let low = adts_segments("tone-440-44k-stereo.aac");
    let high = std::fs::read(fixture("tone-440-48k-stereo.aac")).unwrap();
    let server = ScriptServer::start(move |asked, conn, _| {
        let t = asked.target.as_str();
        if t == "/vod.m3u8" {
            let text = "#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXT-X-PLAYLIST-TYPE:VOD\n\
                #EXTINF:0.5,\nlow/0.aac\n#EXTINF:0.5,\nlow/1.aac\n\
                #EXT-X-DISCONTINUITY\n#EXTINF:1,\nhigh.aac\n#EXT-X-ENDLIST\n";
            answer(conn, "application/vnd.apple.mpegurl", text.as_bytes());
        } else if t == "/high.aac" {
            answer(conn, "audio/aac", &high);
        } else if let Some(n) = number(t) {
            answer(conn, "audio/aac", &low[n as usize]);
        } else {
            not_found(conn);
        }
    });
    let mut decoder = Decoder::open(source::open(&server.url("/vod.m3u8"), live()).unwrap()).unwrap();
    assert_eq!(decoder.sample_rate(), 44_100);
    let (mut all, mut block) = (Vec::new(), Vec::new());
    while decoder.next_block(&mut block).unwrap() {
        all.extend_from_slice(&block);
    }
    // Two half seconds, then one second made 44.1 kHz.
    let frames = all.len() / 2;
    assert!((frames as i64 - 2 * 44_100).abs() < 6_000, "{frames}");
    // The 48 kHz part, by the 44.1 kHz clock, is still 440 Hz.
    let tail = &all[(frames - 30_000) * 2..(frames - 4_000) * 2];
    assert!((steady_frequency(tail, 44_100) - 440.0).abs() < 3.0, "{}", steady_frequency(tail, 44_100));
}

#[test]
fn he_aac_configs_become_their_aac_lc_core() {
    // Explicit HE-AAC: SBR (5), 22.05 kHz core (7), stereo, 44.1 kHz out (4), then LC.
    let he = [0x2b, 0x92, 0x08, 0x00];
    let core = u16::from_be_bytes(lc_core_config(&he).unwrap());
    assert_eq!((core >> 11, (core >> 7) & 15, (core >> 3) & 15), (2, 7, 2));
    // Backward-compatible signalling: LC first, the SBR extension after.
    assert_eq!(lc_core_config(&[0x13, 0x90, 0x56, 0xe5, 0x00]), Some([0x13, 0x90]));
    // Plain AAC-LC is left alone.
    assert_eq!(lc_core_config(&[0x12, 0x10]), None);
    // And the AAC decoder takes the core.
    use symphonia::core::codecs::audio::well_known::CODEC_ID_AAC;
    use symphonia::core::codecs::audio::{AudioCodecParameters, AudioDecoderOptions};
    let mut params = AudioCodecParameters::new();
    params.for_codec(CODEC_ID_AAC).with_sample_rate(44_100).with_extra_data(Box::new(he));
    let registry = symphonia::default::get_codecs();
    assert!(
        registry.make_audio_decoder(&params, &AudioDecoderOptions::default()).is_err(),
        "HE-AAC as it is"
    );
    params.with_extra_data(Box::new(lc_core_config(&he).unwrap()));
    let decoder = registry.make_audio_decoder(&params, &AudioDecoderOptions::default()).unwrap();
    assert_eq!(decoder.codec_params().sample_rate, Some(22_050));
}

// An endless MP3 radio stream with titles every `METAINT` bytes: the
// fixture over and over, its title changing every three blocks.
const METAINT: usize = 4_000;

pub(super) fn icy_radio(stopped: &AtomicBool, conn: &mut TcpStream) {
    let mp3 = std::fs::read(fixture("tone-440-44k-mono.mp3")).unwrap();
    let head = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: audio/mpeg\r\nicy-name: Test FM\r\nicy-metaint: {METAINT}\r\nConnection: close\r\n\r\n"
    );
    if conn.write_all(head.as_bytes()).is_err() {
        return;
    }
    let endless = mp3.iter().copied().cycle();
    let mut audio = Vec::with_capacity(METAINT);
    for (i, byte) in endless.enumerate() {
        audio.push(byte);
        if audio.len() < METAINT {
            continue;
        }
        let block_index = i / METAINT;
        let song = block_index / 3;
        let text = format!("StreamTitle='Test FM - Song {song}';StreamUrl='https://img.test/{song}.jpg';");
        let mut block = text.into_bytes();
        block.resize(block.len().div_ceil(16) * 16, 0);
        let mut out = std::mem::take(&mut audio);
        out.push((block.len() / 16) as u8);
        out.extend_from_slice(&block);
        if stopped.load(Ordering::Acquire) || conn.write_all(&out).is_err() {
            return;
        }
        if block_index > 2_000 {
            return;
        }
    }
}

#[test]
fn an_icy_radio_stream_decodes_and_hands_on_titles_as_heard() {
    let server = ScriptServer::start(|_, conn, stopped| icy_radio(stopped, conn));
    let deck = Deck::open(1, server.url("/stream"), 0.0, live());
    // 4 000 bytes at 96 kbps is a third of a second: past 3 s, the third
    // title (from block 6) has been reached, and nothing past block 9.
    let mut titles = Vec::new();
    let mut sound = Vec::new();
    let until = Instant::now() + Duration::from_secs(20);
    let mut buf = vec![0.0; 2048];
    while sound.len() / 2 < 44_100 * 3 + 22_050 {
        let r = deck.read(&mut buf);
        assert!(r.failure.is_none() && !r.finished, "{r:?}");
        sound.extend_from_slice(&buf[..r.frames * 2]);
        titles.extend(deck.take_title(r.start_secs + r.frames as f64 / 44_100.0).map(|meta| meta.title));
        if r.frames == 0 {
            assert!(Instant::now() < until);
            thread::sleep(Duration::from_millis(1));
        }
    }
    assert_eq!(titles[..3], ["Test FM - Song 0", "Test FM - Song 1", "Test FM - Song 2"], "{titles:?}");
    assert!(titles.len() <= 4, "titles ran ahead of the sound: {titles:?}");
    let middle = &sound[sound.len() / 4..];
    assert!((steady_frequency(middle, 44_100) - 440.0).abs() < 3.0, "{}", steady_frequency(middle, 44_100));
    // Seeking a live stream does nothing.
    deck.seek(30.0);
    let r = deck.read(&mut buf);
    assert!(r.start_secs < 5.0, "{r:?}");
    assert_eq!(server.asked().len(), 1);
}

// Waits for a deck to fail, reading what it gives meanwhile.
fn read_to_failure(deck: &Deck) -> crate::error::Failure {
    let until = Instant::now() + Duration::from_secs(20);
    let mut buf = vec![0.0; 4096];
    loop {
        let r = deck.read(&mut buf);
        if let Some(f) = r.failure {
            return f;
        }
        assert!(!r.finished, "it ended without a failure");
        if r.frames == 0 {
            assert!(Instant::now() < until, "it never failed");
            thread::sleep(Duration::from_millis(2));
        }
    }
}

#[test]
fn empty_segments_are_passed_over_and_the_stream_plays_on() {
    let segments = adts_segments("tone-440-44k-stereo.aac");
    let polls = AtomicU64::new(0);
    let server = ScriptServer::start(move |asked, conn, _| {
        let t = asked.target.as_str();
        if t.ends_with(".m3u8") {
            let n = polls.fetch_add(1, Ordering::SeqCst);
            answer(conn, "application/vnd.apple.mpegurl", live_playlist(n, "aac", "", |_| None).as_bytes());
        } else if let Some(seq) = number(t) {
            match seq % 3 {
                // Nothing at all, and only the timing tag.
                0 => {
                    let _ = conn.write_all(
                        b"HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
                    );
                }
                1 => answer(conn, "audio/aac", &with_id3v2(&[], &[("TIT2", "timing")], &[])),
                _ => answer(conn, "audio/aac", &segments[seq as usize % segments.len()]),
            }
        } else {
            not_found(conn);
        }
    });
    let deck = Deck::open(1, server.url("/live/radio.m3u8"), 0.0, live());
    let sound = read_secs(&deck, 2.0);
    let middle = &sound[sound.len() / 4..];
    assert!((steady_frequency(middle, 44_100) - 440.0).abs() < 3.0, "{}", steady_frequency(middle, 44_100));
}

#[test]
fn a_stream_whose_numbers_start_again_is_joined_again() {
    let segments = adts_segments("tone-440-44k-stereo.aac");
    let polls = AtomicU64::new(0);
    let server = ScriptServer::start(move |asked, conn, _| {
        let t = asked.target.as_str();
        if t.ends_with(".m3u8") {
            let n = polls.fetch_add(1, Ordering::SeqCst);
            // The encoder starts over after four polls, numbering from 0.
            let first = if n < 4 { 1_000 + n } else { n - 4 };
            answer(
                conn,
                "application/vnd.apple.mpegurl",
                live_playlist(first, "aac", "", |_| None).as_bytes(),
            );
        } else if let Some(seq) = number(t) {
            answer(conn, "audio/aac", &segments[seq as usize % segments.len()]);
        } else {
            not_found(conn);
        }
    });
    let deck = Deck::open(1, server.url("/live/radio.m3u8"), 0.0, live());
    let sound = read_secs(&deck, 4.0);
    let middle = &sound[sound.len() / 4..];
    assert!((steady_frequency(middle, 44_100) - 440.0).abs() < 3.0, "{}", steady_frequency(middle, 44_100));
    let fetched: Vec<u64> = server.asked().iter().filter_map(|a| number(&a.target)).collect();
    let restart = fetched.iter().position(|&n| n < 1_000).expect("never joined again after the restart");
    assert!(fetched[..restart].iter().all(|&n| n >= 1_000), "{fetched:?}");
}

#[test]
fn a_live_playlist_that_stops_growing_fails() {
    let segments = adts_segments("tone-440-44k-stereo.aac");
    let server = ScriptServer::start(move |asked, conn, _| {
        let t = asked.target.as_str();
        if t.ends_with(".m3u8") {
            answer(conn, "application/vnd.apple.mpegurl", live_playlist(0, "aac", "", |_| None).as_bytes());
        } else if let Some(seq) = number(t) {
            answer(conn, "audio/aac", &segments[seq as usize % segments.len()]);
        } else {
            not_found(conn);
        }
    });
    let started = Instant::now();
    let deck = Deck::open(1, server.url("/live/radio.m3u8"), 0.0, live());
    let failure = read_to_failure(&deck);
    assert_eq!(failure.kind, ErrorKind::Network);
    assert!(failure.message.contains("stopped adding"), "{failure}");
    // Three target durations of 0.3 s at least.
    assert!(started.elapsed() >= Duration::from_millis(900));
}

#[test]
fn segments_the_server_keeps_saying_are_missing_end_the_stream() {
    let polls = AtomicU64::new(0);
    let server = ScriptServer::start(move |asked, conn, _| {
        if asked.target.ends_with(".m3u8") {
            let n = polls.fetch_add(1, Ordering::SeqCst);
            answer(conn, "application/vnd.apple.mpegurl", live_playlist(n, "aac", "", |_| None).as_bytes());
        } else {
            not_found(conn);
        }
    });
    let deck = Deck::open(1, server.url("/live/radio.m3u8"), 0.0, live());
    let failure = read_to_failure(&deck);
    assert_eq!(failure.kind, ErrorKind::NotFound, "{failure}");
    let missing = server.asked().iter().filter(|a| a.target.starts_with("/seg/")).count();
    assert_eq!(missing, 8);
}

#[test]
fn an_hls_station_with_a_plain_address_opens_as_hls() {
    let segments = adts_segments("tone-440-44k-stereo.aac");
    let polls = AtomicU64::new(0);
    let server = ScriptServer::start(move |asked, conn, _| {
        let t = asked.target.as_str();
        if t == "/stream" {
            let n = polls.fetch_add(1, Ordering::SeqCst);
            answer(conn, "application/octet-stream", live_playlist(n, "aac", "", |_| None).as_bytes());
        } else if let Some(seq) = number(t).filter(|_| t.starts_with("/seg/")) {
            answer(conn, "audio/aac", &segments[seq as usize % segments.len()]);
        } else {
            not_found(conn);
        }
    });
    let marked = Deck::open(1, server.url("/stream"), 0.0, HttpOptions { hls: true, ..live() });
    read_secs(&marked, 1.5);
    // Unmarked, its first bytes say what it is.
    let unmarked = Deck::open(2, server.url("/stream"), 0.0, live());
    read_secs(&unmarked, 1.5);
}

#[test]
fn a_playlist_behind_a_plain_address_is_known_by_its_first_bytes() {
    let segments = adts_segments("tone-440-44k-stereo.aac");
    let polls = AtomicU64::new(0);
    let server = ScriptServer::start(move |asked, conn, _| {
        let t = asked.target.as_str();
        if t == "/listen" {
            // A byte order mark and blank lines first, and a type that says sound.
            let n = polls.fetch_add(1, Ordering::SeqCst);
            let mut body = vec![0xef, 0xbb, 0xbf];
            body.extend_from_slice(b"\r\n \n");
            body.extend_from_slice(live_playlist(n, "aac", "", |_| None).as_bytes());
            answer(conn, "audio/mpeg", &body);
        } else if let Some(seq) = number(t).filter(|_| t.starts_with("/seg/")) {
            answer(conn, "audio/aac", &segments[seq as usize % segments.len()]);
        } else {
            not_found(conn);
        }
    });
    let deck = Deck::open(1, server.url("/listen"), 0.0, live());
    let sound = read_secs(&deck, 2.0);
    let middle = &sound[sound.len() / 4..];
    assert!((steady_frequency(middle, 44_100) - 440.0).abs() < 3.0, "{}", steady_frequency(middle, 44_100));
    assert_eq!(deck.info().unwrap().codec, "aac");
}

#[test]
fn a_plain_m3u_opens_its_first_station_and_a_looping_one_fails() {
    let server = ScriptServer::start(|asked, conn, stopped| {
        let host = asked.header("host").unwrap_or_default().to_string();
        match asked.target.as_str() {
            "/station.m3u" => {
                let text = format!("#EXTM3U\n#EXTINF:-1,Test FM\nhttp://{host}/radio\nhttp://{host}/other\n");
                answer(conn, "application/octet-stream", text.as_bytes());
            }
            "/loop.m3u" => {
                let text = format!("#EXTM3U\n#EXTINF:-1,Again\nhttp://{host}/loop.m3u\n");
                answer(conn, "text/plain", text.as_bytes());
            }
            "/radio" => icy_radio(stopped, conn),
            _ => not_found(conn),
        }
    });
    let deck = Deck::open(1, server.url("/station.m3u"), 0.0, live());
    let mut titles = Vec::new();
    let until = Instant::now() + Duration::from_secs(20);
    let mut buf = vec![0.0; 2048];
    let mut heard = 0.0;
    while heard < 2.0 {
        let r = deck.read(&mut buf);
        assert!(r.failure.is_none() && !r.finished, "{r:?}");
        heard = r.start_secs + r.frames as f64 / 44_100.0;
        titles.extend(deck.take_title(heard).map(|meta| meta.title));
        if r.frames == 0 {
            assert!(Instant::now() < until);
            thread::sleep(Duration::from_millis(1));
        }
    }
    assert_eq!(deck.info().unwrap().codec, "mp3");
    assert!(titles.first().is_some_and(|t| t == "Test FM - Song 0"), "{titles:?}");
    assert!(server.asked().iter().all(|a| a.target != "/other"));
    // Pointing at itself, it is followed three times and then given up.
    let err = source::open(&server.url("/loop.m3u"), live()).err().unwrap();
    assert_eq!(err.kind, ErrorKind::Unsupported);
    assert!(err.message.contains("too many"), "{err}");
}
