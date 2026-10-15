//! Short muted video loops (animated album covers), decoded by the
//! system's own video decoder: Media Foundation on Windows, AVFoundation on
//! macOS, GStreamer (loaded when asked, if installed) on Linux.
//!
//! A `LoopVideo` decodes one local file on a thread of its own, paces the
//! frames by their timestamps, starts over at the end without a gap, and
//! keeps the newest frame for the app to copy into memory it owns. Nothing
//! here touches the audio threads, device or clock.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::thread;
use std::time::{Duration, Instant};

use crate::error::{EngineError, ErrorKind, Failure};

#[cfg(all(unix, not(target_os = "macos")))]
mod gstreamer;
#[cfg(target_os = "macos")]
mod mac;
#[cfg(windows)]
mod media_foundation;

/// The frame gap assumed when a decoder gives none: 24 frames a second.
const DEFAULT_GAP: Duration = Duration::from_micros(41_667);

/// How late a frame may be before the clock starts again from it, rather
/// than rushing through the frames it missed (after the computer slept, say).
const LATE_RESYNC: Duration = Duration::from_millis(250);

/// Ends in a row with no frame between them before the file counts as empty.
const EMPTY_ENDS: u32 = 2;

/// One decoded frame's place in its file: its timestamp and how long it
/// shows, when the decoder says.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct FrameTime {
    pub at: Duration,
    pub length: Option<Duration>,
}

/// A decoder of one file, made and used on the loop's own thread.
pub(crate) trait FrameSource {
    /// The size of the frames it gives, in pixels.
    fn size(&self) -> (u32, u32);

    /// Decodes the next frame into `pixels` (BGRA, top row first, rows
    /// packed, alpha 255) and gives its time, or None at the end.
    fn next_frame(&mut self, pixels: &mut [u8]) -> Result<Option<FrameTime>, Failure>;

    /// Goes back to the first frame.
    fn rewind(&mut self) -> Result<(), Failure>;
}

/// Opens the system's decoder on `path`, scaling down towards `target`
/// where the decoder can.
type Opener = Box<dyn FnOnce() -> Result<Box<dyn FrameSource>, Failure> + Send>;

/// The size to decode a `native` frame at for a space `target` wide and
/// high, scaled to cover it: never larger than the native size, the same
/// shape, and even on both sides. A zero target keeps the native size.
pub(crate) fn scaled_size(native: (u32, u32), target: (u32, u32)) -> (u32, u32) {
    let (w, h) = native;
    let (tw, th) = target;
    if w == 0 || h == 0 || tw == 0 || th == 0 {
        return native;
    }
    let scale = (tw as f64 / w as f64).max(th as f64 / h as f64);
    if scale >= 1.0 {
        return native;
    }
    let even = |v: f64| ((v.ceil() as u32 + 1) & !1).max(2);
    (even(w as f64 * scale).min(w), even(h as f64 * scale).min(h))
}

/// Where each frame falls on the loop's own clock, which keeps counting
/// across the starts over, so the first frame of a round follows the last
/// of the one before by exactly that frame's length.
#[derive(Debug, Default)]
pub(crate) struct Timeline {
    /// Where this round started on the loop's clock.
    offset: Duration,
    /// The first timestamp of this round.
    first: Option<Duration>,
    /// Where this round ends so far, from its start.
    end: Duration,
    /// The last gap seen between frames.
    gap: Option<Duration>,
    previous: Option<Duration>,
}

impl Timeline {
    /// The place on the loop's clock of a frame with this time.
    pub(crate) fn place(&mut self, frame: FrameTime) -> Duration {
        let first = *self.first.get_or_insert(frame.at);
        let from_start = frame.at.saturating_sub(first);
        if let Some(previous) = self.previous {
            let gap = frame.at.saturating_sub(previous);
            if !gap.is_zero() {
                self.gap = Some(gap);
            }
        }
        self.previous = Some(frame.at);
        let length = frame.length.filter(|l| !l.is_zero()).or(self.gap).unwrap_or(DEFAULT_GAP);
        self.end = self.end.max(from_start + length);
        self.offset + from_start
    }

    /// The end of the file: the next round starts where this one ended.
    pub(crate) fn wrap(&mut self) {
        self.offset += if self.end.is_zero() { DEFAULT_GAP } else { self.end };
        self.first = None;
        self.previous = None;
        self.end = Duration::ZERO;
    }
}

/// What the app has asked of the loop.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Control {
    Play,
    Hold,
    Stop,
}

/// The newest frame and its number, and the asks from the app.
struct Shared {
    width: u32,
    height: u32,
    control: Mutex<Control>,
    wake: Condvar,
    front: Mutex<Vec<u8>>,
    /// How many frames have been shown; 0 until the first.
    frames: AtomicU64,
    /// Woken on each new frame, and on hold and stop.
    newer: Condvar,
    newer_lock: Mutex<()>,
    /// Why decoding stopped, when it failed.
    failure: Mutex<Option<String>>,
    /// How many frames were decoded, for the tests.
    decoded: AtomicU64,
}

impl Shared {
    fn control(&self) -> MutexGuard<'_, Control> {
        self.control.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn set(&self, control: Control) {
        let mut now = self.control();
        if *now != Control::Stop {
            *now = control;
        }
        drop(now);
        self.wake.notify_all();
        let _held = self.newer_lock.lock().unwrap_or_else(|e| e.into_inner());
        self.newer.notify_all();
    }

    fn publish(&self, back: &mut Vec<u8>) {
        {
            let mut front = self.front.lock().unwrap_or_else(|e| e.into_inner());
            std::mem::swap(&mut *front, back);
            self.frames.fetch_add(1, Ordering::AcqRel);
        }
        let _held = self.newer_lock.lock().unwrap_or_else(|e| e.into_inner());
        self.newer.notify_all();
    }

    fn fail(&self, failure: &Failure) {
        log::warn!("video loop stopped: {failure}");
        *self.failure.lock().unwrap_or_else(|e| e.into_inner()) = Some(failure.message.clone());
        let _held = self.newer_lock.lock().unwrap_or_else(|e| e.into_inner());
        self.newer.notify_all();
    }

    /// Copies the newest frame into `into` (rows `row_bytes` apart) when it
    /// is newer than `have`; gives the newest frame's number either way.
    fn copy_into(&self, into: &mut [u8], row_bytes: usize, have: u64) -> Result<u64, Failure> {
        let row = self.width as usize * 4;
        let rows = self.height as usize;
        if row_bytes < row || rows == 0 || into.len() < (rows - 1) * row_bytes + row {
            return Err(Failure::new(
                ErrorKind::InvalidArgument,
                format!(
                    "{} bytes in rows of {row_bytes} cannot hold a {}x{} frame",
                    into.len(),
                    self.width,
                    self.height
                ),
            ));
        }
        let front = self.front.lock().unwrap_or_else(|e| e.into_inner());
        let newest = self.frames.load(Ordering::Acquire);
        if newest == have || newest == 0 {
            return Ok(newest);
        }
        if row_bytes == row {
            into[..row * rows].copy_from_slice(&front[..row * rows]);
        } else {
            for (y, line) in front.chunks_exact(row).take(rows).enumerate() {
                into[y * row_bytes..y * row_bytes + row].copy_from_slice(line);
            }
        }
        Ok(newest)
    }

    /// Waits until a frame newer than `have` is shown, the loop is held or
    /// stopped, or `timeout` passes; gives the newest frame's number.
    fn wait_newer(&self, have: u64, timeout: Duration) -> u64 {
        let end = Instant::now() + timeout;
        let mut held = self.newer_lock.lock().unwrap_or_else(|e| e.into_inner());
        loop {
            let newest = self.frames.load(Ordering::Acquire);
            if newest != have
                || *self.control() != Control::Play
                || self.failure.lock().map(|f| f.is_some()).unwrap_or(true)
            {
                return newest;
            }
            let now = Instant::now();
            if now >= end {
                return newest;
            }
            held = self.newer.wait_timeout(held, end - now).unwrap_or_else(|e| e.into_inner()).0;
        }
    }
}

/// The decode thread: frames are decoded one ahead and shown at their
/// time; held, it waits without decoding; at the end it starts over.
fn run(shared: &Shared, mut source: Box<dyn FrameSource>) {
    let mut back = vec![0u8; shared.width as usize * shared.height as usize * 4];
    let mut timeline = Timeline::default();
    // The decoded frame waiting for its time, by its place on the clock.
    let mut pending: Option<Duration> = None;
    // A moment and where the loop's clock was then, while it plays.
    let mut anchor: Option<(Instant, Duration)> = None;
    let mut ends = 0;
    loop {
        {
            let mut control = shared.control();
            while *control == Control::Hold {
                anchor = None;
                control = shared.wake.wait(control).unwrap_or_else(|e| e.into_inner());
            }
            if *control == Control::Stop {
                return;
            }
        }
        let due = match pending {
            Some(due) => due,
            None => match source.next_frame(&mut back) {
                Ok(Some(time)) => {
                    ends = 0;
                    shared.decoded.fetch_add(1, Ordering::Relaxed);
                    let due = timeline.place(time);
                    pending = Some(due);
                    due
                }
                Ok(None) => {
                    ends += 1;
                    if ends >= EMPTY_ENDS {
                        shared.fail(&Failure::new(ErrorKind::Decode, "the video has no frames"));
                        return;
                    }
                    timeline.wrap();
                    if let Err(failure) = source.rewind() {
                        shared.fail(&failure);
                        return;
                    }
                    continue;
                }
                Err(failure) => {
                    shared.fail(&failure);
                    return;
                }
            },
        };
        let (then, then_at) = *anchor.get_or_insert_with(|| (Instant::now(), due));
        let at = then + due.saturating_sub(then_at);
        {
            let mut control = shared.control();
            loop {
                if *control != Control::Play {
                    break;
                }
                let now = Instant::now();
                if now >= at {
                    break;
                }
                control = shared.wake.wait_timeout(control, at - now).unwrap_or_else(|e| e.into_inner()).0;
            }
            if *control != Control::Play {
                continue;
            }
        }
        if Instant::now().saturating_duration_since(at) > LATE_RESYNC {
            anchor = None;
        }
        shared.publish(&mut back);
        pending = None;
    }
}

/// A muted, looping video, decoded on its own thread. It starts held:
/// `play` starts it. Frames are read with `copy_frame`, into memory the
/// app owns, so no frame crosses into the app as a new array.
#[derive(uniffi::Object)]
pub struct LoopVideo {
    shared: Arc<Shared>,
    thread: Mutex<Option<thread::JoinHandle<()>>>,
}

impl LoopVideo {
    fn start(opener: Opener) -> Result<Arc<Self>, Failure> {
        let (sizes, size) = std::sync::mpsc::sync_channel::<Result<(u32, u32), Failure>>(1);
        let (shares, shared_rx) = std::sync::mpsc::sync_channel::<Arc<Shared>>(1);
        let thread = thread::Builder::new()
            .name("octo-video".into())
            .spawn(move || {
                let source = match opener() {
                    Ok(source) => source,
                    Err(failure) => {
                        let _ = sizes.send(Err(failure));
                        return;
                    }
                };
                if sizes.send(Ok(source.size())).is_err() {
                    return;
                }
                let Ok(shared) = shared_rx.recv() else { return };
                run(&shared, source);
            })
            .map_err(|e| Failure::new(ErrorKind::Other, format!("could not start the video thread: {e}")))?;
        let (width, height) = match size.recv() {
            Ok(Ok(size)) => size,
            Ok(Err(failure)) => {
                let _ = thread.join();
                return Err(failure);
            }
            Err(_) => {
                let _ = thread.join();
                return Err(Failure::new(ErrorKind::Decode, "the video decoder stopped while opening"));
            }
        };
        if width == 0 || height == 0 {
            return Err(Failure::new(ErrorKind::Decode, "the video has no picture size"));
        }
        let shared = Arc::new(Shared {
            width,
            height,
            control: Mutex::new(Control::Hold),
            wake: Condvar::new(),
            front: Mutex::new(vec![0u8; width as usize * height as usize * 4]),
            frames: AtomicU64::new(0),
            newer: Condvar::new(),
            newer_lock: Mutex::new(()),
            failure: Mutex::new(None),
            decoded: AtomicU64::new(0),
        });
        let _ = shares.send(shared.clone());
        Ok(Arc::new(Self { shared, thread: Mutex::new(Some(thread)) }))
    }

    #[cfg(test)]
    fn decoded(&self) -> u64 {
        self.shared.decoded.load(Ordering::Relaxed)
    }
}

#[uniffi::export]
impl LoopVideo {
    /// Opens the video file at `path` through the system's decoder, scaled
    /// down to cover `width` by `height` pixels where the decoder can (0
    /// for the file's own size). Fails with `Unsupported` where the system
    /// has no decoder for it (Linux without GStreamer, say).
    #[uniffi::constructor]
    pub fn open(path: String, width: u32, height: u32) -> Result<Arc<Self>, EngineError> {
        if !std::path::Path::new(&path).is_file() {
            return Err(Failure::new(ErrorKind::NotFound, format!("no video file at {path}")).into());
        }
        let target = (width, height);
        Ok(Self::start(Box::new(move || system_source(&path, target)))?)
    }

    /// The frames' width in pixels.
    pub fn width(&self) -> u32 {
        self.shared.width
    }

    /// The frames' height in pixels.
    pub fn height(&self) -> u32 {
        self.shared.height
    }

    /// Plays from where it was held.
    pub fn play(&self) {
        self.shared.set(Control::Play);
    }

    /// Holds on the frame shown; nothing is decoded until `play`.
    pub fn hold(&self) {
        self.shared.set(Control::Hold);
    }

    /// Stops for good and lets the decoder go.
    pub fn stop(&self) {
        self.shared.set(Control::Stop);
        let handle = self.thread.lock().unwrap_or_else(|e| e.into_inner()).take();
        if let Some(handle) = handle
            && handle.thread().id() != thread::current().id()
        {
            let _ = handle.join();
        }
    }

    /// How many frames have been shown so far; 0 until the first.
    pub fn frames(&self) -> u64 {
        self.shared.frames.load(Ordering::Acquire)
    }

    /// Why the loop stopped decoding, when it failed.
    pub fn failure(&self) -> Option<String> {
        self.shared.failure.lock().ok().and_then(|f| f.clone())
    }

    /// Copies the newest frame (BGRA, alpha 255, top row first) into the
    /// memory at `address`, `length` bytes with rows `row_bytes` apart,
    /// when it is newer than frame `have`. Gives the newest frame's number,
    /// so the same number back means nothing was copied.
    ///
    /// `address` must be writable memory of at least `length` bytes that
    /// stays valid for the call, such as a bitmap's own pixels.
    pub fn copy_frame(
        &self,
        address: u64,
        row_bytes: u32,
        length: u64,
        have: u64,
    ) -> Result<u64, EngineError> {
        if address == 0 {
            return Err(Failure::new(ErrorKind::InvalidArgument, "no memory to copy the frame into").into());
        }
        // SAFETY: the caller hands over `length` writable bytes at
        // `address` for the length of this call, and every write below is
        // checked against that length first.
        let into = unsafe { std::slice::from_raw_parts_mut(address as usize as *mut u8, length as usize) };
        Ok(self.shared.copy_into(into, row_bytes as usize, have)?)
    }

    /// Waits up to `timeout_ms` for a frame newer than `have`; returns
    /// sooner when the loop is held, stopped or fails. Gives the newest
    /// frame's number.
    pub fn wait_frame(&self, have: u64, timeout_ms: u32) -> u64 {
        self.shared.wait_newer(have, Duration::from_millis(timeout_ms as u64))
    }
}

impl Drop for LoopVideo {
    fn drop(&mut self) {
        self.stop();
    }
}

/// Decodes the whole file once through the system's decoder as fast as it
/// goes, for measuring: the frames, the time taken and their size.
#[doc(hidden)]
pub fn decode_speed(path: &str, target: (u32, u32)) -> Result<(u64, Duration, (u32, u32)), Failure> {
    let mut source = system_source(path, target)?;
    let size = source.size();
    let mut pixels = vec![0u8; size.0 as usize * size.1 as usize * 4];
    let start = Instant::now();
    let mut frames = 0;
    while source.next_frame(&mut pixels)?.is_some() {
        frames += 1;
    }
    Ok((frames, start.elapsed(), size))
}

/// Whether this computer can decode loops at all: false on Linux without
/// GStreamer, for one.
#[uniffi::export]
pub fn loop_video_available() -> bool {
    system_available()
}

#[cfg(windows)]
fn system_source(path: &str, target: (u32, u32)) -> Result<Box<dyn FrameSource>, Failure> {
    Ok(Box::new(media_foundation::MfSource::open(path, target)?))
}

#[cfg(windows)]
fn system_available() -> bool {
    true
}

#[cfg(target_os = "macos")]
fn system_source(path: &str, target: (u32, u32)) -> Result<Box<dyn FrameSource>, Failure> {
    Ok(Box::new(mac::AvSource::open(path, target)?))
}

#[cfg(target_os = "macos")]
fn system_available() -> bool {
    true
}

#[cfg(all(unix, not(target_os = "macos")))]
fn system_source(path: &str, target: (u32, u32)) -> Result<Box<dyn FrameSource>, Failure> {
    Ok(Box::new(gstreamer::GstSource::open(path, target)?))
}

#[cfg(all(unix, not(target_os = "macos")))]
fn system_available() -> bool {
    gstreamer::available()
}

#[cfg(not(any(windows, unix)))]
fn system_source(_path: &str, _target: (u32, u32)) -> Result<Box<dyn FrameSource>, Failure> {
    Err(Failure::new(ErrorKind::Unsupported, "no video decoder on this system"))
}

#[cfg(not(any(windows, unix)))]
fn system_available() -> bool {
    false
}

/// Copies `rows` rows of BGRX pixels `width` wide from `from` (rows
/// `stride` bytes apart, the first at `first`; a negative stride goes up)
/// into packed rows in `into`, with alpha set to 255.
#[allow(dead_code)]
pub(crate) fn copy_rows(
    from: &[u8],
    first: usize,
    stride: isize,
    width: usize,
    rows: usize,
    into: &mut [u8],
) {
    let row = width * 4;
    for y in 0..rows {
        let start = first as isize + stride * y as isize;
        if start < 0 {
            break;
        }
        let start = start as usize;
        let Some(line) = from.get(start..start + row) else { break };
        let out = &mut into[y * row..y * row + row];
        out.copy_from_slice(line);
        for pixel in out.chunks_exact_mut(4) {
            pixel[3] = 255;
        }
    }
}

#[cfg(test)]
mod tests;
