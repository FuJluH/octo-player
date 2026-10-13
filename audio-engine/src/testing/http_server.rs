//! A tiny HTTP server for tests, able to act like the servers a player
//! meets: with or without ranges, dropping or stalling mid-song, and over
//! HTTPS with a self-signed certificate.

use std::io::{BufRead, BufReader, Read, Write};
use std::net::{Shutdown, TcpListener, TcpStream};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

#[derive(Clone, Debug)]
pub struct Behaviour {
    /// Answers range requests with 206.
    pub ranges: bool,
    /// On the first request, closes the connection after this many bytes.
    pub drop_after: Option<usize>,
    /// On the first request, goes quiet after this many bytes, until the
    /// server is dropped.
    pub stall_after: Option<usize>,
    /// Answers every request with this status and no body.
    pub status: Option<u16>,
    /// Sends at most this many bytes a second, on every request.
    pub per_second: Option<usize>,
    pub content_type: &'static str,
}

impl Default for Behaviour {
    fn default() -> Self {
        Self {
            ranges: true,
            drop_after: None,
            stall_after: None,
            status: None,
            per_second: None,
            content_type: "audio/flac",
        }
    }
}

/// A self-signed certificate for the HTTPS server, and its key.
pub struct SelfSigned {
    /// The certificate's DER bytes, whose SHA-256 is its fingerprint.
    pub der: Vec<u8>,
    key: Vec<u8>,
}

impl SelfSigned {
    /// A certificate naming these hosts, trusted by no system.
    pub fn new(names: &[&str]) -> Self {
        let made =
            rcgen::generate_simple_self_signed(names.iter().map(|n| n.to_string()).collect::<Vec<_>>())
                .unwrap();
        Self { der: made.cert.der().to_vec(), key: made.signing_key.serialize_der() }
    }

    /// The SHA-256 fingerprint in lowercase hex, as the app keeps it.
    pub fn fingerprint(&self) -> String {
        ring::digest::digest(&ring::digest::SHA256, &self.der)
            .as_ref()
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect()
    }
}

pub struct TestServer {
    scheme: &'static str,
    port: u16,
    ranges: Arc<Mutex<Vec<u64>>>,
    requests: Arc<AtomicUsize>,
    stopped: Arc<AtomicBool>,
    targets: Arc<Mutex<Vec<String>>>,
}

impl TestServer {
    pub fn start(body: Vec<u8>, behaviour: Behaviour) -> Self {
        Self::start_with(body, behaviour, None)
    }

    /// The same over HTTPS, showing this certificate.
    pub fn start_tls(body: Vec<u8>, behaviour: Behaviour, certificate: &SelfSigned) -> Self {
        let provider = Arc::new(rustls::crypto::ring::default_provider());
        let key = rustls::pki_types::PrivatePkcs8KeyDer::from(certificate.key.clone());
        let config = rustls::ServerConfig::builder_with_provider(provider)
            .with_safe_default_protocol_versions()
            .unwrap()
            .with_no_client_auth()
            .with_single_cert(vec![certificate.der.clone().into()], key.into())
            .unwrap();
        Self::start_with(body, behaviour, Some(Arc::new(config)))
    }

    fn start_with(body: Vec<u8>, behaviour: Behaviour, tls: Option<Arc<rustls::ServerConfig>>) -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let ranges = Arc::new(Mutex::new(Vec::new()));
        let requests = Arc::new(AtomicUsize::new(0));
        let stopped = Arc::new(AtomicBool::new(false));
        let targets = Arc::new(Mutex::new(Vec::new()));
        let body = Arc::new(body);
        let (log, count, stop, asked) = (ranges.clone(), requests.clone(), stopped.clone(), targets.clone());
        let scheme = if tls.is_some() { "https" } else { "http" };
        thread::spawn(move || {
            for stream in listener.incoming().flatten() {
                let (body, behaviour, log, count, stop, asked, tls) = (
                    body.clone(),
                    behaviour.clone(),
                    log.clone(),
                    count.clone(),
                    stop.clone(),
                    asked.clone(),
                    tls.clone(),
                );
                thread::spawn(move || match tls {
                    None => serve(stream, &body, &behaviour, &log, &count, &stop, &asked),
                    Some(config) => {
                        let Ok(conn) = rustls::ServerConnection::new(config) else { return };
                        let stream = rustls::StreamOwned::new(conn, stream);
                        serve(stream, &body, &behaviour, &log, &count, &stop, &asked)
                    }
                });
            }
        });
        Self { scheme, port, ranges, requests, stopped, targets }
    }

    pub fn url(&self) -> String {
        format!("{}://127.0.0.1:{}/song.flac", self.scheme, self.port)
    }

    /// The range starts asked for, in order.
    pub fn ranges_asked(&self) -> Vec<u64> {
        self.ranges.lock().unwrap().clone()
    }

    pub fn requests(&self) -> usize {
        self.requests.load(Ordering::SeqCst)
    }

    /// The path and query of each request, in order.
    pub fn targets_asked(&self) -> Vec<String> {
        self.targets.lock().unwrap().clone()
    }
}

impl Drop for TestServer {
    fn drop(&mut self) {
        self.stopped.store(true, Ordering::Release);
    }
}

// A connection, plain or with TLS on it.
trait Conn: Read + Write {
    fn close(&mut self);
}

impl Conn for TcpStream {
    fn close(&mut self) {
        let _ = self.shutdown(Shutdown::Both);
    }
}

impl Conn for rustls::StreamOwned<rustls::ServerConnection, TcpStream> {
    fn close(&mut self) {
        self.conn.send_close_notify();
        let _ = self.flush();
        let _ = self.sock.shutdown(Shutdown::Both);
    }
}

fn serve(
    mut stream: impl Conn,
    body: &[u8],
    b: &Behaviour,
    log: &Mutex<Vec<u64>>,
    count: &AtomicUsize,
    stopped: &AtomicBool,
    targets: &Mutex<Vec<String>>,
) {
    let mut range = None;
    {
        let mut reader = BufReader::new(&mut stream);
        let mut line = String::new();
        let mut first = true;
        loop {
            line.clear();
            if reader.read_line(&mut line).unwrap_or(0) == 0 {
                return;
            }
            if first {
                first = false;
                if let Some(target) = line.split_whitespace().nth(1) {
                    targets.lock().unwrap().push(target.to_string());
                }
            }
            let trimmed = line.trim_end();
            if trimmed.is_empty() {
                break;
            }
            let lower = trimmed.to_ascii_lowercase();
            if let Some(value) = lower.strip_prefix("range:") {
                range = value
                    .trim()
                    .strip_prefix("bytes=")
                    .and_then(|v| v.split('-').next()?.parse::<u64>().ok());
            }
        }
    }
    let nth = count.fetch_add(1, Ordering::SeqCst);
    if let Some(start) = range {
        log.lock().unwrap().push(start);
    }
    if let Some(status) = b.status {
        let _ = write!(stream, "HTTP/1.1 {status} Nope\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
        return;
    }
    let len = body.len() as u64;
    let start = if b.ranges { range.unwrap_or(0) } else { 0 };
    if b.ranges && start >= len && len > 0 {
        let _ = write!(
            stream,
            "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        );
        return;
    }
    let head = if b.ranges && range.is_some() {
        format!(
            "HTTP/1.1 206 Partial Content\r\nContent-Type: {}\r\nContent-Range: bytes {}-{}/{}\r\nContent-Length: {}\r\nAccept-Ranges: bytes\r\nConnection: close\r\n\r\n",
            b.content_type,
            start,
            len.saturating_sub(1),
            len,
            len - start
        )
    } else {
        format!(
            "HTTP/1.1 200 OK\r\nContent-Type: {}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
            b.content_type, len
        )
    };
    if stream.write_all(head.as_bytes()).is_err() {
        return;
    }
    let rest = &body[start as usize..];
    let cut = if nth == 0 { b.drop_after.or(b.stall_after) } else { None };
    let mut sent = 0;
    let piece = b.per_second.map_or(16 << 10, |rate| (rate / 20).max(1));
    for chunk in rest.chunks(piece) {
        if b.per_second.is_some() {
            thread::sleep(Duration::from_millis(50));
        }
        let chunk = match cut {
            Some(limit) if sent + chunk.len() > limit => &chunk[..limit - sent],
            _ => chunk,
        };
        if stream.write_all(chunk).is_err() {
            return;
        }
        sent += chunk.len();
        if cut.is_some_and(|limit| sent >= limit) {
            if nth == 0 && b.stall_after.is_some() {
                while !stopped.load(Ordering::Acquire) {
                    thread::sleep(Duration::from_millis(20));
                }
            }
            stream.close();
            return;
        }
    }
    stream.close();
}

/// A request as a scripted server saw it.
#[derive(Clone, Debug)]
pub struct Asked {
    /// The path and query.
    pub target: String,
    /// Header names in lowercase, with their values.
    pub headers: Vec<(String, String)>,
}

impl Asked {
    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers.iter().find(|(n, _)| n.eq_ignore_ascii_case(name)).map(|(_, v)| v.as_str())
    }
}

type Script = dyn Fn(&Asked, &mut TcpStream, &AtomicBool) + Send + Sync;

/// A server whose answers the test writes in full, status line and all, for
/// endless streams, playlists that change and servers that misbehave. The
/// script is handed a flag that is set once the server is dropped, so an
/// endless answer can stop.
pub struct ScriptServer {
    port: u16,
    asked: Arc<Mutex<Vec<Asked>>>,
    stopped: Arc<AtomicBool>,
}

impl ScriptServer {
    pub fn start(script: impl Fn(&Asked, &mut TcpStream, &AtomicBool) + Send + Sync + 'static) -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let asked = Arc::new(Mutex::new(Vec::new()));
        let stopped = Arc::new(AtomicBool::new(false));
        let script: Arc<Script> = Arc::new(script);
        let (log, stop) = (asked.clone(), stopped.clone());
        thread::spawn(move || {
            for stream in listener.incoming().flatten() {
                if stop.load(Ordering::Acquire) {
                    return;
                }
                let (script, log, stop) = (script.clone(), log.clone(), stop.clone());
                thread::spawn(move || {
                    let mut stream = stream;
                    let Some(request) = read_request(&mut stream) else { return };
                    log.lock().unwrap().push(request.clone());
                    script(&request, &mut stream, &stop);
                    let _ = stream.flush();
                    let _ = stream.shutdown(Shutdown::Both);
                });
            }
        });
        Self { port, asked, stopped }
    }

    pub fn url(&self, path: &str) -> String {
        format!("http://127.0.0.1:{}{path}", self.port)
    }

    /// Every request so far, in order.
    pub fn asked(&self) -> Vec<Asked> {
        self.asked.lock().unwrap().clone()
    }
}

impl Drop for ScriptServer {
    fn drop(&mut self) {
        self.stopped.store(true, Ordering::Release);
    }
}

fn read_request(stream: &mut TcpStream) -> Option<Asked> {
    let mut reader = BufReader::new(stream.try_clone().ok()?);
    let mut line = String::new();
    reader.read_line(&mut line).ok()?;
    let target = line.split_whitespace().nth(1)?.to_string();
    let mut headers = Vec::new();
    loop {
        line.clear();
        if reader.read_line(&mut line).ok()? == 0 {
            return None;
        }
        let trimmed = line.trim_end();
        if trimmed.is_empty() {
            break;
        }
        if let Some((name, value)) = trimmed.split_once(':') {
            headers.push((name.trim().to_ascii_lowercase(), value.trim().to_string()));
        }
    }
    Some(Asked { target, headers })
}
