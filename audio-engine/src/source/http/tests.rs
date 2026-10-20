use super::*;
use crate::source::trust::Trust;
use crate::testing::http_server::{Behaviour, SelfSigned, TestServer};
use std::io::{Read, Seek, SeekFrom, Write};

fn data(len: usize) -> Vec<u8> {
    (0..len).map(|i| (i * 7 + i / 251) as u8).collect()
}

// Small buffers; a stall timeout no pause of a busy machine reaches.
fn quick() -> HttpOptions {
    HttpOptions {
        stall_timeout: Duration::from_secs(60),
        read_ahead: 256 << 10,
        keep_behind: 64 << 10,
        ..Default::default()
    }
}

fn read_all(source: &mut HttpSource) -> Vec<u8> {
    let mut out = Vec::new();
    source.read_to_end(&mut out).unwrap();
    out
}

#[test]
fn reads_a_whole_stream() {
    let body = data(3_000_000);
    let server = TestServer::start(body.clone(), Behaviour::default());
    let mut source = HttpSource::open(&server.url(), quick()).unwrap();
    assert!(source.supports_ranges());
    assert_eq!(source.byte_len(), Some(body.len() as u64));
    assert_eq!(source.content_type(), Some("audio/flac"));
    assert_eq!(read_all(&mut source), body);
}

#[test]
fn seeks_with_ranges() {
    let body = data(4_000_000);
    let server = TestServer::start(body.clone(), Behaviour::default());
    let mut source = HttpSource::open(&server.url(), quick()).unwrap();
    let mut buf = vec![0u8; 1000];

    // Far ahead: a new range request.
    source.seek(SeekFrom::Start(3_000_000)).unwrap();
    source.read_exact(&mut buf).unwrap();
    assert_eq!(buf, body[3_000_000..3_001_000]);
    assert!(server.ranges_asked().contains(&3_000_000), "{:?}", server.ranges_asked());

    // Back to the start, long dropped from memory: another range.
    source.seek(SeekFrom::Start(10)).unwrap();
    source.read_exact(&mut buf).unwrap();
    assert_eq!(buf, body[10..1010]);

    // From the end.
    source.seek(SeekFrom::End(-500)).unwrap();
    let mut tail = Vec::new();
    source.read_to_end(&mut tail).unwrap();
    assert_eq!(tail, body[body.len() - 500..]);
}

#[test]
fn seeks_on_a_server_without_ranges() {
    let body = data(2_000_000);
    let server = TestServer::start(body.clone(), Behaviour { ranges: false, ..Default::default() });
    let mut source = HttpSource::open(&server.url(), quick()).unwrap();
    assert!(!source.supports_ranges());
    let mut buf = vec![0u8; 1000];
    source.seek(SeekFrom::Start(1_500_000)).unwrap();
    source.read_exact(&mut buf).unwrap();
    assert_eq!(buf, body[1_500_000..1_501_000]);
    // Back again: fetched from the start and skipped.
    source.seek(SeekFrom::Start(100)).unwrap();
    source.read_exact(&mut buf).unwrap();
    assert_eq!(buf, body[100..1100]);
    assert!(server.requests() >= 2);
}

#[test]
fn picks_up_after_a_dropped_connection() {
    let body = data(2_000_000);
    let server =
        TestServer::start(body.clone(), Behaviour { drop_after: Some(700_000), ..Default::default() });
    let mut source = HttpSource::open(&server.url(), quick()).unwrap();
    assert_eq!(read_all(&mut source), body);
    // The second request carried on from where the first broke off.
    assert!(server.ranges_asked().iter().any(|&r| r > 0), "{:?}", server.ranges_asked());
}

#[test]
fn picks_up_after_a_drop_without_ranges() {
    let body = data(1_000_000);
    let server = TestServer::start(
        body.clone(),
        Behaviour { ranges: false, drop_after: Some(300_000), ..Default::default() },
    );
    let mut source = HttpSource::open(&server.url(), quick()).unwrap();
    assert_eq!(read_all(&mut source), body);
    assert_eq!(server.requests(), 2);
}

#[test]
fn replaces_a_connection_that_goes_quiet() {
    let body = data(1_000_000);
    let server =
        TestServer::start(body.clone(), Behaviour { stall_after: Some(200_000), ..Default::default() });
    // A pause of a busy machine can look like a stall too: that only costs
    // another request, never the stream.
    let opts = HttpOptions { stall_timeout: Duration::from_millis(600), max_retries: 1_000, ..quick() };
    let mut source = HttpSource::open(&server.url(), opts).unwrap();
    // The quiet connection stays quiet for as long as the server runs, so
    // the stream only ends whole over a new one.
    assert_eq!(read_all(&mut source), body);
    assert!(server.requests() >= 2);
}

#[test]
fn a_quiet_connection_lets_go_of_the_stream_once_replaced() {
    let body = data(1_000_000);
    let server =
        TestServer::start(body.clone(), Behaviour { stall_after: Some(200_000), ..Default::default() });
    let opts = HttpOptions {
        agent: agent_with_idle_limit(Arc::new(Trust::default()), Duration::from_millis(800)),
        stall_timeout: Duration::from_millis(400),
        max_retries: 1_000,
        ..quick()
    };
    let mut source = HttpSource::open(&server.url(), opts).unwrap();
    assert_eq!(read_all(&mut source), body);
    // The fetch threads hold the stream's memory; the one on the quiet
    // connection gives up its read and ends, as do the rest.
    let held = Arc::downgrade(&source.shared);
    drop(source);
    let until = Instant::now() + Duration::from_secs(10);
    while held.strong_count() > 0 && Instant::now() < until {
        thread::sleep(Duration::from_millis(50));
    }
    assert_eq!(held.strong_count(), 0, "a fetch thread still holds the stream");
}

#[test]
fn a_wait_for_input_is_limited_and_a_shorter_one_kept() {
    use ureq::unversioned::transport::time::Duration as Wait;
    let limit = Duration::from_secs(30);
    let endless = NextTimeout { after: Wait::NotHappening, reason: ureq::Timeout::RecvBody };
    assert_eq!(*idle_limited(endless, limit).after, limit);
    let long = NextTimeout { after: Wait::Exact(Duration::from_secs(90)), reason: ureq::Timeout::RecvBody };
    assert_eq!(*idle_limited(long, limit).after, limit);
    let short = NextTimeout { after: Wait::Exact(Duration::from_secs(5)), reason: ureq::Timeout::RecvResponse };
    let kept = idle_limited(short, limit);
    assert_eq!(*kept.after, Duration::from_secs(5));
    assert_eq!(kept.reason, ureq::Timeout::RecvResponse);
}

#[test]
fn missing_song_fails_at_once() {
    let server = TestServer::start(Vec::new(), Behaviour { status: Some(404), ..Default::default() });
    let err = HttpSource::open(&server.url(), quick()).err().unwrap();
    assert_eq!(err.kind, ErrorKind::NotFound);
    assert_eq!(err.status, Some(404));
}

#[test]
fn no_server_is_a_network_failure() {
    // A port nothing listens on.
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    drop(listener);
    let err = HttpSource::open(&format!("http://127.0.0.1:{port}/x"), quick()).err().unwrap();
    assert_eq!(err.kind, ErrorKind::Network);
}

// Options fetching with its own client, trusting these pins.
fn trusting(pins: &[(&str, &str)]) -> HttpOptions {
    let trust = Arc::new(Trust::default());
    trust.replace(pins.iter().map(|(host, sha)| (host.to_string(), sha.to_string())));
    HttpOptions { agent: agent(trust), ..quick() }
}

#[test]
fn a_self_signed_certificate_is_refused_without_a_pin() {
    let certificate = SelfSigned::new(&["127.0.0.1"]);
    let server = TestServer::start_tls(data(10_000), Behaviour::default(), &certificate);
    let err = HttpSource::open(&server.url(), trusting(&[])).err().unwrap();
    assert_eq!(err.kind, ErrorKind::Network);
    assert!(err.message.to_lowercase().contains("certificate"), "{err}");
    assert_eq!(server.requests(), 0, "nothing was asked over the refused connection");
}

#[test]
fn a_pinned_certificate_streams_for_its_host() {
    let body = data(3_000_000);
    let certificate = SelfSigned::new(&["127.0.0.1"]);
    let server = TestServer::start_tls(body.clone(), Behaviour::default(), &certificate);
    // Marked up the way people read it, as the app may pass it on.
    let shown: String = certificate
        .fingerprint()
        .to_uppercase()
        .as_bytes()
        .chunks(2)
        .map(|pair| std::str::from_utf8(pair).unwrap())
        .collect::<Vec<_>>()
        .join(":");
    let mut source = HttpSource::open(&server.url(), trusting(&[("127.0.0.1", &shown)])).unwrap();
    assert_eq!(read_all(&mut source), body);
    // Seeking makes new connections, each checked the same way.
    source.seek(SeekFrom::Start(100)).unwrap();
    let mut buf = vec![0u8; 1000];
    source.read_exact(&mut buf).unwrap();
    assert_eq!(buf, body[100..1100]);
}

#[test]
fn a_pin_passes_a_certificate_naming_another_host() {
    // Self-made certificates often name something else; the pin is the
    // host's identity by itself.
    let body = data(100_000);
    let certificate = SelfSigned::new(&["octo.test"]);
    let server = TestServer::start_tls(body.clone(), Behaviour::default(), &certificate);
    let mut source =
        HttpSource::open(&server.url(), trusting(&[("127.0.0.1", &certificate.fingerprint())])).unwrap();
    assert_eq!(read_all(&mut source), body);
}

#[test]
fn a_pin_for_another_host_or_certificate_is_no_use() {
    let certificate = SelfSigned::new(&["127.0.0.1"]);
    let other = SelfSigned::new(&["127.0.0.1"]);
    let server = TestServer::start_tls(data(10_000), Behaviour::default(), &certificate);
    let elsewhere =
        trusting(&[("localhost", &certificate.fingerprint()), ("127.0.0.2", &certificate.fingerprint())]);
    let err = HttpSource::open(&server.url(), elsewhere).err().unwrap();
    assert_eq!(err.kind, ErrorKind::Network);
    let wrong = trusting(&[("127.0.0.1", &other.fingerprint())]);
    let err = HttpSource::open(&server.url(), wrong).err().unwrap();
    assert_eq!(err.kind, ErrorKind::Network);
}

#[test]
fn a_pin_given_later_applies_to_the_next_connection() {
    let body = data(10_000);
    let certificate = SelfSigned::new(&["127.0.0.1"]);
    let server = TestServer::start_tls(body.clone(), Behaviour::default(), &certificate);
    let trust = Arc::new(Trust::default());
    let opts = HttpOptions { agent: agent(trust.clone()), ..quick() };
    assert!(HttpSource::open(&server.url(), opts.clone()).is_err());
    trust.replace([("127.0.0.1".to_string(), certificate.fingerprint())]);
    let mut source = HttpSource::open(&server.url(), opts.clone()).unwrap();
    assert_eq!(read_all(&mut source), body);
    // Taken away again, it no longer lets a new connection in.
    trust.replace([]);
    assert!(HttpSource::open(&server.url(), opts).is_err());
}

#[test]
fn content_range_parsing() {
    assert_eq!(range_total("bytes 0-99/1234"), Some(1234));
    assert_eq!(range_start("bytes 100-199/1234"), Some(100));
    assert_eq!(range_total("bytes 0-99/*"), None);
}

// Byte `p` of an endless broadcast.
fn on_air(p: u64) -> u8 {
    (p * 13 + p / 977) as u8
}

fn live() -> HttpOptions {
    HttpOptions { live: true, live_backoff: Duration::from_millis(10), ..quick() }
}

// A metadata block holding `text`, as a server sends it.
fn icy_block(text: &str) -> Vec<u8> {
    let mut block = text.as_bytes().to_vec();
    block.resize(block.len().div_ceil(16) * 16, 0);
    let mut out = vec![(block.len() / 16) as u8];
    out.extend_from_slice(&block);
    out
}

// Reads `len` bytes in small pieces, taking the titles reached on the way.
fn read_live(source: &mut HttpSource, slot: &TitleSlot, len: usize) -> (Vec<u8>, Vec<String>) {
    let (mut out, mut titles) = (Vec::new(), Vec::new());
    let mut buf = vec![0u8; 1000];
    while out.len() < len {
        let n = source.read(&mut buf).unwrap();
        assert!(n > 0, "a live stream never ends");
        out.extend_from_slice(&buf[..n]);
        titles.extend(slot.take().map(|meta| meta.title));
    }
    out.truncate(len);
    (out, titles)
}

#[test]
fn an_endless_icy_stream_gives_its_titles_and_clean_audio() {
    use crate::testing::http_server::ScriptServer;
    const METAINT: u64 = 8000;
    let server = ScriptServer::start(|_, conn, stopped| {
        let head =
            "HTTP/1.1 200 OK\r\nContent-Type: audio/mpeg\r\nicy-metaint: 8000\r\nConnection: close\r\n\r\n";
        if conn.write_all(head.as_bytes()).is_err() {
            return;
        }
        for i in 0u64.. {
            let audio: Vec<u8> = (i * METAINT..(i + 1) * METAINT).map(on_air).collect();
            // Each title comes three times, with an empty one and an empty
            // block among them.
            // Each title comes twice, with an empty block and blocks
            // naming no title among them, and once an empty title.
            let block = match (i, i % 3) {
                (4, _) => vec![0],
                (10, _) => icy_block("StreamTitle='';"),
                (_, 1) => icy_block("StreamUrl='http://example.com';"),
                _ => icy_block(&format!("StreamTitle='Song {}';StreamUrl='';", i / 3)),
            };
            if stopped.load(Ordering::Acquire)
                || conn.write_all(&audio).is_err()
                || conn.write_all(&block).is_err()
            {
                return;
            }
        }
    });
    let slot = Arc::new(TitleSlot::default());
    let opts = HttpOptions { titles: Some(slot.clone()), ..live() };
    let mut source = HttpSource::open(&server.url("/radio"), opts).unwrap();
    assert!(!source.is_seekable());
    assert_eq!(source.byte_len(), None);
    let (audio, titles) = read_live(&mut source, &slot, 160_000);
    let expected: Vec<u8> = (0..160_000).map(on_air).collect();
    assert!(audio == expected, "the audio came through changed");
    // The empty title clears the one before, so the same one counts again.
    assert_eq!(titles, ["Song 0", "Song 1", "Song 2", "Song 3", "", "Song 3", "Song 4", "Song 5", "Song 6"]);
    let asked = &server.asked()[0];
    assert_eq!(asked.header("icy-metadata"), Some("1"));
    assert_eq!(asked.header("range"), None, "a live stream asks for no range");
}

#[test]
fn a_live_stream_that_drops_reconnects_and_skips_nothing() {
    use crate::testing::http_server::ScriptServer;
    use std::sync::atomic::AtomicU64;
    // Every connection gets 50 000 bytes from wherever the broadcast is,
    // then the server hangs up.
    let air = Arc::new(AtomicU64::new(0));
    let clock = air.clone();
    let server = ScriptServer::start(move |_, conn, _| {
        let head = "HTTP/1.1 200 OK\r\nContent-Type: audio/mpeg\r\nContent-Length: 999999999\r\n\r\n";
        if conn.write_all(head.as_bytes()).is_err() {
            return;
        }
        let from = clock.fetch_add(50_000, Ordering::SeqCst);
        let bytes: Vec<u8> = (from..from + 50_000).map(on_air).collect();
        let _ = conn.write_all(&bytes);
    });
    let slot = TitleSlot::default();
    let mut source = HttpSource::open(&server.url("/radio"), live()).unwrap();
    // The length the server claims is no length for a live stream.
    assert_eq!(source.byte_len(), None);
    let (audio, _) = read_live(&mut source, &slot, 180_000);
    let expected: Vec<u8> = (0..180_000).map(on_air).collect();
    assert!(audio == expected, "bytes were lost or doubled across the reconnections");
    let asked = server.asked();
    assert!(asked.len() >= 4, "{}", asked.len());
    assert!(asked.iter().all(|a| a.header("range").is_none()));
}

#[test]
fn a_live_server_answering_200_after_a_stall_is_read_from_its_first_byte() {
    // A server that ignores ranges and stalls on the first connection.
    let body = data(300_000);
    let server = TestServer::start(
        body.clone(),
        Behaviour {
            ranges: false,
            stall_after: Some(100_000),
            content_type: "audio/mpeg",
            ..Default::default()
        },
    );
    let opts = HttpOptions { stall_timeout: Duration::from_millis(500), ..live() };
    let mut source = HttpSource::open(&server.url(), opts).unwrap();
    let slot = TitleSlot::default();
    let (audio, _) = read_live(&mut source, &slot, 400_000);
    // The new connection's bytes follow straight on, none thrown away.
    let mut expected = body[..100_000].to_vec();
    expected.extend_from_slice(&body);
    assert!(audio == expected, "the new connection's start was skipped");
    assert!(server.ranges_asked().is_empty(), "{:?}", server.ranges_asked());
}

#[test]
fn a_live_stream_that_stays_gone_fails_clearly() {
    use crate::testing::http_server::ScriptServer;
    let answers = Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let server = ScriptServer::start(move |_, conn, _| {
        // The first answer has a little sound; every later one is empty.
        let first = answers.fetch_add(1, Ordering::SeqCst) == 0;
        let body = if first { vec![1u8; 1000] } else { Vec::new() };
        let _ = conn.write_all(b"HTTP/1.1 200 OK\r\nContent-Type: audio/mpeg\r\n\r\n");
        let _ = conn.write_all(&body);
    });
    let started = Instant::now();
    let mut source = HttpSource::open(&server.url("/radio"), live()).unwrap();
    let mut out = Vec::new();
    let err = source.read_to_end(&mut out).unwrap_err();
    assert_eq!(out.len(), 1000);
    assert!(err.to_string().contains("did not come back"), "{err}");
    // Four tries after the first, waiting 10, 20, 40 and 80 ms.
    assert_eq!(server.asked().len(), 5);
    assert!(started.elapsed() >= Duration::from_millis(150));
}

#[test]
fn an_old_shoutcast_server_answering_icy_200_ok_plays() {
    use crate::testing::http_server::ScriptServer;
    let server = ScriptServer::start(|_, conn, stopped| {
        // The status line in pieces, the way a slow server may send it.
        for piece in [&b"IC"[..], b"Y 2", b"00 OK\r\n"] {
            if conn.write_all(piece).is_err() || conn.flush().is_err() {
                return;
            }
            thread::sleep(Duration::from_millis(20));
        }
        let head = "icy-notice1:This stream requires Winamp\r\nicy-name:Old FM\r\ncontent-type:audio/mpeg\r\nicy-metaint:8000\r\n\r\n";
        if conn.write_all(head.as_bytes()).is_err() {
            return;
        }
        for i in 0u64.. {
            let audio: Vec<u8> = (i * 8000..(i + 1) * 8000).map(on_air).collect();
            let block = icy_block(&format!("StreamTitle='Old FM {}';", i / 4));
            if stopped.load(Ordering::Acquire)
                || conn.write_all(&audio).is_err()
                || conn.write_all(&block).is_err()
            {
                return;
            }
        }
    });
    let slot = Arc::new(TitleSlot::default());
    let opts = HttpOptions { titles: Some(slot.clone()), ..live() };
    let mut source = HttpSource::open(&server.url("/;stream.mp3"), opts).unwrap();
    assert_eq!(source.content_type(), Some("audio/mpeg"));
    let (audio, titles) = read_live(&mut source, &slot, 100_000);
    let expected: Vec<u8> = (0..100_000).map(on_air).collect();
    assert!(audio == expected, "the audio came through changed");
    assert_eq!(titles, ["Old FM 0", "Old FM 1", "Old FM 2"]);
}

#[test]
fn a_live_server_that_hangs_up_after_a_little_each_time_counts_as_gone() {
    use crate::testing::http_server::ScriptServer;
    // Every connection gives 1 000 bytes and hangs up.
    let server = ScriptServer::start(|_, conn, _| {
        let _ = conn.write_all(
            b"HTTP/1.1 200 OK
Content-Type: audio/mpeg

",
        );
        let _ = conn.write_all(&[7u8; 1000]);
    });
    let mut source = HttpSource::open(&server.url("/radio"), live()).unwrap();
    let mut out = Vec::new();
    let err = source.read_to_end(&mut out).unwrap_err();
    assert!(err.to_string().contains("did not come back"), "{err}");
    // The first connection and four more, none of them counted as working.
    assert_eq!(server.asked().len(), 5);
    assert_eq!(out.len(), 5_000);
}
