//! Where a song's bytes come from: a file on this computer, or a server.

pub mod hls;
pub mod http;
pub mod icy;
pub mod trust;
pub mod ts;

use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

use symphonia::core::io::MediaSource;

use crate::error::{ErrorKind, Failure};
use http::{HttpOptions, HttpSource};

/// An opened song, and what is known about its format before decoding.
pub struct Opened {
    pub source: Box<dyn MediaSource>,
    /// The file extension or type, for the format guess.
    pub hint: Option<String>,
    pub remote: bool,
    /// A jump far into the song is cheap: a file, or a stream whose server
    /// answers with ranges.
    pub seeks_cheaply: bool,
    /// A live stream: it has no length, is never sought, and may restart
    /// its codec part way.
    pub live: bool,
    /// The parts after the first that each need a fresh decoder.
    pub periods: Option<Box<dyn Periods>>,
}

/// The parts of a stream that each need a fresh decoder, such as the
/// stretches between an HLS playlist's discontinuities.
pub trait Periods: Send {
    /// Waits for the next part; `None` once the stream is over.
    fn next(&mut self) -> Result<Option<Box<dyn MediaSource>>, Failure>;
}

/// Whether a source string names a stream rather than a file.
pub fn is_remote(source: &str) -> bool {
    let lower = source.get(..8).unwrap_or(source).to_ascii_lowercase();
    lower.starts_with("http://") || lower.starts_with("https://")
}

/// Opens a file path, a `file://` address, or an HTTP(S) address, which
/// may be an HLS playlist: by its extension, its content type, or `http.hls`.
pub fn open(source: &str, http: HttpOptions) -> Result<Opened, Failure> {
    if is_remote(source) {
        if http.hls || hls::is_hls_url(source) {
            return hls::open(source, http);
        }
        return open_stream(source, http, 0);
    }
    let path = source.strip_prefix("file://").unwrap_or(source);
    let file = File::open(path).map_err(|e| {
        let kind =
            if e.kind() == std::io::ErrorKind::NotFound { ErrorKind::NotFound } else { ErrorKind::Other };
        Failure::new(kind, format!("{path}: {e}"))
    })?;
    let hint = Path::new(path).extension().and_then(|e| e.to_str()).map(str::to_ascii_lowercase);
    Ok(Opened {
        source: Box::new(file),
        hint,
        remote: false,
        seeks_cheaply: true,
        live: false,
        periods: None,
    })
}

// An HTTP(S) stream, or the playlist it turns out to be by its server's
// type or, for a live stream, by its first bytes; `hops` playlists in after
// the address first asked for.
fn open_stream(source: &str, http: HttpOptions, hops: u32) -> Result<Opened, Failure> {
    let live = http.live;
    let mut stream = HttpSource::open(source, http.clone())?;
    let listed = stream.content_type().is_some_and(hls::is_playlist_type);
    if listed || (live && starts_as_playlist(&mut stream)?) {
        drop(stream);
        return hls::open_hop(source, http, hops);
    }
    let hint = stream.content_type().and_then(extension_for_type).or_else(|| url_extension(source));
    let seeks_cheaply = stream.answered_with_range();
    Ok(Opened { source: Box::new(stream), hint, remote: true, seeks_cheaply, live, periods: None })
}

// Whether a stream starts `#EXTM3U`, after any byte order mark and white
// space, as an M3U or HLS playlist does. Reads only as far as it takes to
// tell, and puts the stream back at its start.
fn starts_as_playlist(stream: &mut HttpSource) -> Result<bool, Failure> {
    const MARK: &[u8] = b"#EXTM3U";
    const BOM: &[u8] = &[0xef, 0xbb, 0xbf];
    let trimmed = |head: &[u8]| -> Vec<u8> {
        let head = head.strip_prefix(BOM).unwrap_or(head);
        head.iter().copied().skip_while(u8::is_ascii_whitespace).collect()
    };
    let mut head = Vec::new();
    let mut buf = [0u8; 64];
    loop {
        let n = stream.read(&mut buf).map_err(|e| read_failure(&e))?;
        head.extend_from_slice(&buf[..n]);
        let text = trimmed(&head);
        // Only part of the mark, or of the byte order mark, so far.
        let partial = (text.len() < MARK.len() && MARK.starts_with(&text)) || BOM.starts_with(&head);
        if n == 0 || !partial || head.len() >= 1024 {
            break;
        }
    }
    stream.seek(SeekFrom::Start(0)).map_err(|e| read_failure(&e))?;
    Ok(trimmed(&head).starts_with(MARK))
}

// A failed read's own failure, when it carries one.
fn read_failure(e: &std::io::Error) -> Failure {
    match e.get_ref().and_then(|inner| inner.downcast_ref::<Failure>()) {
        Some(f) => f.clone(),
        None => Failure::new(ErrorKind::Network, e.to_string()),
    }
}

/// Whether a stream is made on the way (a server's transcode, asked for with
/// a `format` other than `raw`): it has no length and cannot jump by bytes,
/// so it is opened again at a time instead, with `timeOffset`.
pub fn seeks_by_time(source: &str) -> bool {
    if !is_remote(source) {
        return false;
    }
    let Some((_, query)) = source.split_once('?') else { return false };
    let query = query.split('#').next().unwrap_or(query);
    query.split('&').any(|pair| {
        let (name, value) = pair.split_once('=').unwrap_or((pair, ""));
        name.eq_ignore_ascii_case("format") && !value.is_empty() && !value.eq_ignore_ascii_case("raw")
    })
}

/// The address of a time-seeking stream starting `secs` in, in whole
/// seconds as servers take it, and where that lands.
pub fn at_time(source: &str, secs: f64) -> (String, f64) {
    let whole = secs.max(0.0).floor();
    if whole <= 0.0 {
        return (source.to_string(), 0.0);
    }
    let (base, fragment) = match source.split_once('#') {
        Some((b, f)) => (b, Some(f)),
        None => (source, None),
    };
    let kept: Vec<&str> = match base.split_once('?') {
        Some((_, q)) => q.split('&').filter(|p| !p.to_ascii_lowercase().starts_with("timeoffset=")).collect(),
        None => Vec::new(),
    };
    let path = base.split('?').next().unwrap_or(base);
    let mut query = kept.join("&");
    if !query.is_empty() {
        query.push('&');
    }
    query.push_str(&format!("timeOffset={}", whole as u64));
    let mut out = format!("{path}?{query}");
    if let Some(f) = fragment {
        out.push('#');
        out.push_str(f);
    }
    (out, whole)
}

// The extension a server's content type stands for.
fn extension_for_type(content_type: &str) -> Option<String> {
    let bare = content_type.split(';').next()?.trim().to_ascii_lowercase();
    let ext = match bare.as_str() {
        "audio/flac" | "audio/x-flac" => "flac",
        "audio/mpeg" | "audio/mp3" => "mp3",
        "audio/mp4" | "audio/x-m4a" | "audio/m4a" => "m4a",
        // Raw AAC in ADTS frames, as radio sends it, HE-AAC included.
        "audio/aac" | "audio/aacp" | "audio/x-aac" | "audio/x-aacp" => "aac",
        "audio/ogg" | "application/ogg" | "audio/vorbis" => "ogg",
        "audio/opus" => "opus",
        "audio/wav" | "audio/x-wav" | "audio/wave" => "wav",
        "audio/aiff" | "audio/x-aiff" => "aiff",
        _ => return None,
    };
    Some(ext.to_string())
}

// The extension in an address's path, ignoring the query.
pub(crate) fn url_extension(url: &str) -> Option<String> {
    let path = url.split(['?', '#']).next()?;
    let last = path.rsplit('/').next()?;
    let (_, ext) = last.rsplit_once('.')?;
    (!ext.is_empty() && ext.len() <= 5).then(|| ext.to_ascii_lowercase())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hints() {
        assert!(is_remote("HTTPS://x/y"));
        assert!(!is_remote("C:\\music\\a.flac"));
        assert_eq!(extension_for_type("audio/flac; charset=binary").as_deref(), Some("flac"));
        assert_eq!(extension_for_type("audio/aacp").as_deref(), Some("aac"));
        assert_eq!(extension_for_type("audio/AAC").as_deref(), Some("aac"));
        assert_eq!(extension_for_type("audio/x-aac").as_deref(), Some("aac"));
        assert_eq!(extension_for_type("audio/mpeg").as_deref(), Some("mp3"));
        assert_eq!(extension_for_type("application/ogg").as_deref(), Some("ogg"));
        assert!(hls::is_hls_url("https://h/live/index.M3U8?token=a.mp3"));
        assert!(!hls::is_hls_url("https://h/live/stream.mp3?list=a.m3u8"));
        assert!(hls::is_playlist_type("application/vnd.apple.mpegurl"));
        assert!(hls::is_playlist_type("audio/mpegurl; charset=utf-8"));
        assert_eq!(url_extension("http://h/rest/stream.view?id=1&f=mp3").as_deref(), Some("view"));
        assert_eq!(url_extension("http://h/a/song.opus").as_deref(), Some("opus"));
    }

    #[test]
    fn a_transcode_seeks_by_time() {
        assert!(seeks_by_time("http://h/rest/stream?id=1&format=mp3&maxBitRate=192"));
        assert!(!seeks_by_time("http://h/rest/stream?id=1&format=raw"));
        assert!(!seeks_by_time("http://h/rest/stream?id=1"));
        assert!(!seeks_by_time("C:\\music\\a.flac"));
        assert_eq!(
            at_time("http://h/rest/stream?id=1&format=mp3", 61.7),
            ("http://h/rest/stream?id=1&format=mp3&timeOffset=61".to_string(), 61.0)
        );
        assert_eq!(
            at_time("http://h/rest/stream?id=1&format=mp3&timeOffset=61", 5.0).0,
            "http://h/rest/stream?id=1&format=mp3&timeOffset=5"
        );
        assert_eq!(at_time("http://h/rest/stream?id=1&format=mp3", 0.4).1, 0.0);
    }

    #[test]
    fn missing_file() {
        let err = open("Z:/no/such/file.flac", HttpOptions::default()).err().unwrap();
        assert_eq!(err.kind, ErrorKind::NotFound);
    }
}
