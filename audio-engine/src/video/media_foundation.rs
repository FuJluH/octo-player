//! Loops decoded by Windows Media Foundation: a Source Reader on the file
//! with its video processing on, giving 32-bit RGB frames in the size
//! asked for. Everything is made and used on the loop's own thread.

use std::sync::{Arc, Mutex};
use std::time::Duration;

use windows::Win32::Foundation::HMODULE;
use windows::Win32::Graphics::Direct3D::D3D_DRIVER_TYPE_HARDWARE;
use windows::Win32::Graphics::Direct3D11::{
    D3D11_CREATE_DEVICE_BGRA_SUPPORT, D3D11_CREATE_DEVICE_VIDEO_SUPPORT, D3D11_SDK_VERSION,
    D3D11CreateDevice, ID3D11Device, ID3D11Multithread,
};
use windows::Win32::Media::MediaFoundation::{
    IMF2DBuffer, IMFAttributes, IMFDXGIDeviceManager, IMFMediaType, IMFSample, IMFSourceReader,
    MF_MT_DEFAULT_STRIDE, MF_MT_FRAME_SIZE, MF_MT_MAJOR_TYPE, MF_MT_MINIMUM_DISPLAY_APERTURE, MF_MT_SUBTYPE,
    MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, MF_SOURCE_READER_ALL_STREAMS, MF_SOURCE_READER_D3D_MANAGER,
    MF_SOURCE_READER_ENABLE_ADVANCED_VIDEO_PROCESSING, MF_SOURCE_READER_FIRST_VIDEO_STREAM,
    MF_SOURCE_READERF_ENDOFSTREAM, MF_SOURCE_READERF_ERROR, MF_VERSION, MFCreateAttributes,
    MFCreateDXGIDeviceManager, MFCreateMediaType, MFCreateSourceReaderFromURL, MFMediaType_Video,
    MFSTARTUP_NOSOCKET, MFShutdown, MFStartup, MFVideoArea, MFVideoFormat_RGB32,
};
use windows::Win32::System::Com::StructuredStorage::PROPVARIANT;
use windows::Win32::System::Com::{COINIT_MULTITHREADED, CoInitializeEx, CoUninitialize};
use windows::core::{GUID, HSTRING, Interface};

use super::{FrameSource, FrameTime, copy_rows, scaled_size};
use crate::error::{ErrorKind, Failure};

/// Media Foundation's time unit: 100 ns.
const TICKS_PER_MICRO: i64 = 10;

fn failed(what: &str, error: windows::core::Error) -> Failure {
    Failure::new(ErrorKind::Decode, format!("Media Foundation could not {what}: {error}"))
}

/// The part of the decoded picture to show: its offset and size.
#[derive(Clone, Copy, Debug)]
struct Area {
    x: u32,
    y: u32,
    width: u32,
    height: u32,
}

pub(crate) struct MfSource {
    reader: IMFSourceReader,
    stream: u32,
    /// The decoded frame's whole size, and the part of it shown.
    frame: (u32, u32),
    area: Area,
    /// The rows' distance in a buffer that is not two-dimensional.
    stride: isize,
    /// The graphics card decoding, when it does; kept until the reader
    /// has gone, and Media Foundation and COM after that (fields drop in
    /// order).
    gpu: Option<Arc<Gpu>>,
    _started: Started,
}

/// A Direct3D 11 device the decoder and its colour conversion run on, one
/// for every loop: a device of its own for each open cost the driver's
/// memory for a whole device each time, kept until that loop closed.
struct Gpu {
    manager: IMFDXGIDeviceManager,
    device: ID3D11Device,
    /// Media Foundation kept started for as long as the device is.
    _started: Started,
}

// SAFETY: the device is multithread protected (the decoders call it from
// their own threads anyway), and the device manager is free-threaded.
unsafe impl Send for Gpu {}
unsafe impl Sync for Gpu {}

/// The device every loop decodes on, once made.
static SHARED_GPU: Mutex<Option<Arc<Gpu>>> = Mutex::new(None);

impl Gpu {
    /// The shared device, made the first time; None where there is none (a
    /// remote session, a basic display driver).
    fn shared() -> Option<Arc<Self>> {
        let mut shared = SHARED_GPU.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(gpu) = shared.as_ref() {
            return Some(gpu.clone());
        }
        // SAFETY: plain device and Media Foundation calls; the objects are
        // free-threaded (see above).
        let gpu = Arc::new(unsafe { Self::new() }?);
        *shared = Some(gpu.clone());
        Some(gpu)
    }

    /// Lets the shared device go when the driver lost it (a driver update,
    /// a reset), so the next loop makes a new one; loops on it keep theirs
    /// until they close.
    fn forget_if_lost(gpu: &Arc<Self>) {
        // SAFETY: a plain query on the device.
        let lost = unsafe { gpu.device.GetDeviceRemovedReason() }.is_err();
        if !lost {
            return;
        }
        let mut shared = SHARED_GPU.lock().unwrap_or_else(|e| e.into_inner());
        if shared.as_ref().is_some_and(|now| Arc::ptr_eq(now, gpu)) {
            log::info!("the video device was lost; the next loop makes a new one");
            *shared = None;
        }
    }

    /// Made on a loop's thread, which has COM and Media Foundation started.
    unsafe fn new() -> Option<Self> {
        let started = Started::media_only().ok()?;
        unsafe {
            let mut device: Option<ID3D11Device> = None;
            D3D11CreateDevice(
                None,
                D3D_DRIVER_TYPE_HARDWARE,
                HMODULE::default(),
                D3D11_CREATE_DEVICE_VIDEO_SUPPORT | D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                None,
                D3D11_SDK_VERSION,
                Some(&mut device),
                None,
                None,
            )
            .ok()?;
            let device = device?;
            // The decoders call the device from their own threads.
            if let Ok(multithread) = device.cast::<ID3D11Multithread>() {
                let _ = multithread.SetMultithreadProtected(true);
            }
            let mut token = 0u32;
            let mut manager: Option<IMFDXGIDeviceManager> = None;
            MFCreateDXGIDeviceManager(&mut token, &mut manager).ok()?;
            let manager = manager?;
            manager.ResetDevice(&device, token).ok()?;
            Some(Self { manager, device, _started: started })
        }
    }
}

/// Media Foundation (and COM, when this thread had none) started for one
/// reader, and stopped again when it goes.
struct Started {
    com: bool,
    live: bool,
}

impl Started {
    fn new() -> Result<Self, Failure> {
        // SAFETY: plain start calls, paired in drop.
        unsafe {
            let com = CoInitializeEx(None, COINIT_MULTITHREADED).is_ok();
            if let Err(e) = MFStartup(MF_VERSION, MFSTARTUP_NOSOCKET) {
                if com {
                    CoUninitialize();
                }
                return Err(failed("start", e));
            }
            Ok(Self { com, live: true })
        }
    }
}

impl Started {
    /// Media Foundation alone, on a thread that has COM already: what the
    /// shared device keeps, so it stays usable after the loop that made it
    /// closes, and lets go of from whichever thread drops it.
    fn media_only() -> Result<Self, Failure> {
        // SAFETY: a plain start call, paired in drop.
        unsafe { MFStartup(MF_VERSION, MFSTARTUP_NOSOCKET) }.map_err(|e| failed("start", e))?;
        Ok(Self { com: false, live: true })
    }
}

impl Drop for Started {
    fn drop(&mut self) {
        if !self.live {
            return;
        }
        // SAFETY: pairs the calls in `new`.
        unsafe {
            let _ = MFShutdown();
            if self.com {
                CoUninitialize();
            }
        }
    }
}

impl MfSource {
    pub(crate) fn open(path: &str, target: (u32, u32)) -> Result<Self, Failure> {
        let started = Started::new()?;
        // The graphics card first; the processor where it cannot.
        // SAFETY: plain Media Foundation calls on this thread; every object
        // stays on it.
        unsafe {
            if !software_only()
                && let Some(gpu) = Gpu::shared()
            {
                match Self::with(path, target, Some(gpu.clone())) {
                    Ok((reader, gpu)) => return Ok(Self::made(reader, gpu, started)),
                    Err(failure) => {
                        Gpu::forget_if_lost(&gpu);
                        log::info!("video on the graphics card failed, decoding on the processor: {failure}")
                    }
                }
            }
            let (reader, gpu) = Self::with(path, target, None)?;
            Ok(Self::made(reader, gpu, started))
        }
    }

    fn made(mut reader: Self, gpu: Option<Arc<Gpu>>, started: Started) -> Self {
        reader.gpu = gpu;
        reader._started = started;
        reader
    }

    /// A source on `path`, decoding on `gpu` when given. Started and given
    /// back its device separately, so a failure lets both go.
    unsafe fn with(path: &str, target: (u32, u32), gpu: Option<Arc<Gpu>>) -> Result<(Self, Option<Arc<Gpu>>), Failure> {
        unsafe {
            let reader = open_reader(path, gpu.as_ref().map(|g| &g.manager))?;
            let mut source = Self {
                reader,
                stream: MF_SOURCE_READER_FIRST_VIDEO_STREAM.0 as u32,
                frame: (0, 0),
                area: Area { x: 0, y: 0, width: 0, height: 0 },
                stride: 0,
                gpu: None,
                _started: Started { com: false, live: false },
            };
            source.choose_output(target)?;
            if gpu.is_some() {
                // One frame through, to know the card can decode this file.
                let (w, h) = source.size();
                let mut first = vec![0u8; w as usize * h as usize * 4];
                source
                    .next_frame(&mut first)?
                    .ok_or_else(|| Failure::new(ErrorKind::Decode, "no first frame"))?;
                source.rewind()?;
            }
            Ok((source, gpu))
        }
    }

    /// Whether the decoder runs on the graphics card.
    #[allow(dead_code)]
    pub(crate) fn on_gpu(&self) -> bool {
        self.gpu.is_some()
    }

    /// Whether both decode on the one device.
    #[cfg(test)]
    pub(crate) fn shares_device_with(&self, other: &MfSource) -> bool {
        matches!((&self.gpu, &other.gpu), (Some(a), Some(b)) if Arc::ptr_eq(a, b))
    }

    /// Asks for 32-bit RGB at the size that covers `target`, falling back
    /// to the file's own size when the decoder cannot scale.
    unsafe fn choose_output(&mut self, target: (u32, u32)) -> Result<(), Failure> {
        unsafe {
            let reader = &self.reader;
            reader
                .SetStreamSelection(MF_SOURCE_READER_ALL_STREAMS.0 as u32, false)
                .map_err(|e| failed("pick the video", e))?;
            reader.SetStreamSelection(self.stream, true).map_err(|e| failed("pick the video", e))?;
            let native = reader
                .GetNativeMediaType(self.stream, 0)
                .map_err(|e| failed("read the video's format", e))?;
            let native_area = aperture(&native);
            let shown =
                native_area.map(|a| (a.width, a.height)).or_else(|| frame_size(&native)).unwrap_or((0, 0));
            let wanted = scaled_size(shown, target);
            let mut set = false;
            if wanted != shown {
                let scaled = rgb_type()?;
                let _ = scaled.SetUINT64(&MF_MT_FRAME_SIZE, ((wanted.0 as u64) << 32) | wanted.1 as u64);
                set = reader.SetCurrentMediaType(self.stream, None, &scaled).is_ok();
            }
            if !set {
                reader
                    .SetCurrentMediaType(self.stream, None, &rgb_type()?)
                    .map_err(|e| failed("decode the video to RGB", e))?;
            }
            let current =
                reader.GetCurrentMediaType(self.stream).map_err(|e| failed("read the decoded format", e))?;
            self.frame =
                frame_size(&current).ok_or_else(|| Failure::new(ErrorKind::Decode, "no frame size"))?;
            // A frame decoded at its own coded size (486 shown of 496, say)
            // keeps the file's picture area when the output names none.
            let unscaled = (!set).then_some(native_area).flatten();
            self.area = aperture(&current)
                .or(unscaled)
                .filter(|a| a.x + a.width <= self.frame.0 && a.y + a.height <= self.frame.1)
                .unwrap_or(Area { x: 0, y: 0, width: self.frame.0, height: self.frame.1 });
            self.stride = current
                .GetUINT32(&MF_MT_DEFAULT_STRIDE)
                .map(|s| s as i32 as isize)
                .unwrap_or(self.frame.0 as isize * 4);
            Ok(())
        }
    }

    /// Copies the shown part of a sample into `pixels`.
    unsafe fn copy_sample(&self, sample: &IMFSample, pixels: &mut [u8]) -> Result<(), Failure> {
        unsafe {
            let buffer = sample.GetBufferByIndex(0).map_err(|e| failed("read a frame", e))?;
            let (width, height) = (self.area.width as usize, self.area.height as usize);
            let skip = |stride: isize| stride * self.area.y as isize + self.area.x as isize * 4;
            if let Ok(planar) = buffer.cast::<IMF2DBuffer>() {
                let mut first: *mut u8 = std::ptr::null_mut();
                let mut pitch = 0i32;
                planar.Lock2D(&mut first, &mut pitch).map_err(|e| failed("read a frame", e))?;
                let pitch = pitch as isize;
                // The rows run from `first`, `pitch` apart (upwards when it
                // is negative); seen as one span from the lowest address.
                let rows = self.frame.1 as isize;
                let low = if pitch < 0 { first.offset(pitch * (rows - 1)) } else { first };
                let span = pitch.unsigned_abs() * rows as usize;
                let all = std::slice::from_raw_parts(low, span);
                let start = if pitch < 0 { pitch.unsigned_abs() * (rows as usize - 1) } else { 0 } as isize
                    + skip(pitch);
                copy_rows(all, start.max(0) as usize, pitch, width, height, pixels);
                let _ = planar.Unlock2D();
            } else {
                let mut data = std::ptr::null_mut();
                let mut length = 0u32;
                buffer.Lock(&mut data, None, Some(&mut length)).map_err(|e| failed("read a frame", e))?;
                let all = std::slice::from_raw_parts(data, length as usize);
                let stride = self.stride;
                let start =
                    if stride < 0 { stride.unsigned_abs() as isize * (self.frame.1 as isize - 1) } else { 0 }
                        + skip(stride);
                copy_rows(all, start.max(0) as usize, stride, width, height, pixels);
                let _ = buffer.Unlock();
            }
            Ok(())
        }
    }
}

impl FrameSource for MfSource {
    fn size(&self) -> (u32, u32) {
        (self.area.width, self.area.height)
    }

    fn next_frame(&mut self, pixels: &mut [u8]) -> Result<Option<FrameTime>, Failure> {
        // SAFETY: the reader and its samples are used on this thread only.
        unsafe {
            loop {
                let mut flags = 0u32;
                let mut at = 0i64;
                let mut sample: Option<IMFSample> = None;
                self.reader
                    .ReadSample(self.stream, 0, None, Some(&mut flags), Some(&mut at), Some(&mut sample))
                    .map_err(|e| failed("decode a frame", e))?;
                if flags & MF_SOURCE_READERF_ERROR.0 as u32 != 0 {
                    return Err(Failure::new(
                        ErrorKind::Decode,
                        "Media Foundation could not decode the video",
                    ));
                }
                if flags & MF_SOURCE_READERF_ENDOFSTREAM.0 as u32 != 0 {
                    return Ok(None);
                }
                // A read can come back with no sample (a format change, a
                // gap); the next read carries on.
                let Some(sample) = sample else { continue };
                self.copy_sample(&sample, pixels)?;
                let length = sample.GetSampleDuration().ok().filter(|d| *d > 0);
                return Ok(Some(FrameTime { at: ticks(at), length: length.map(ticks) }));
            }
        }
    }

    fn rewind(&mut self) -> Result<(), Failure> {
        // SAFETY: as above.
        unsafe {
            let start = PROPVARIANT::from(0i64);
            self.reader
                .SetCurrentPosition(&GUID::zeroed(), &start)
                .map_err(|e| failed("go back to the start", e))
        }
    }
}

fn ticks(value: i64) -> Duration {
    Duration::from_micros((value.max(0) / TICKS_PER_MICRO) as u64)
}

/// Set OCTO_VIDEO_SOFTWARE to decode on the processor only, for comparing.
fn software_only() -> bool {
    std::env::var_os("OCTO_VIDEO_SOFTWARE").is_some()
}

unsafe fn open_reader(
    path: &str,
    manager: Option<&IMFDXGIDeviceManager>,
) -> Result<IMFSourceReader, Failure> {
    unsafe {
        let mut attributes: Option<IMFAttributes> = None;
        MFCreateAttributes(&mut attributes, 3).map_err(|e| failed("set up", e))?;
        let attributes = attributes.ok_or_else(|| Failure::new(ErrorKind::Decode, "no attributes"))?;
        attributes
            .SetUINT32(&MF_SOURCE_READER_ENABLE_ADVANCED_VIDEO_PROCESSING, 1)
            .map_err(|e| failed("set up", e))?;
        if let Some(manager) = manager {
            attributes.SetUnknown(&MF_SOURCE_READER_D3D_MANAGER, manager).map_err(|e| failed("set up", e))?;
        }
        let _ = attributes.SetUINT32(&MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, 1);
        MFCreateSourceReaderFromURL(&HSTRING::from(path), &attributes)
            .map_err(|e| failed("open the video", e))
    }
}

unsafe fn rgb_type() -> Result<IMFMediaType, Failure> {
    unsafe {
        let kind = MFCreateMediaType().map_err(|e| failed("set up", e))?;
        kind.SetGUID(&MF_MT_MAJOR_TYPE, &MFMediaType_Video).map_err(|e| failed("set up", e))?;
        kind.SetGUID(&MF_MT_SUBTYPE, &MFVideoFormat_RGB32).map_err(|e| failed("set up", e))?;
        Ok(kind)
    }
}

unsafe fn frame_size(kind: &IMFMediaType) -> Option<(u32, u32)> {
    let packed = unsafe { kind.GetUINT64(&MF_MT_FRAME_SIZE) }.ok()?;
    Some(((packed >> 32) as u32, packed as u32))
}

unsafe fn aperture(kind: &IMFMediaType) -> Option<Area> {
    let mut area = MFVideoArea::default();
    let size = std::mem::size_of::<MFVideoArea>() as u32;
    // SAFETY: `area` is a plain struct of `size` bytes.
    unsafe {
        kind.GetBlob(
            &MF_MT_MINIMUM_DISPLAY_APERTURE,
            std::slice::from_raw_parts_mut(&mut area as *mut MFVideoArea as *mut u8, size as usize),
            None,
        )
        .ok()?;
    }
    let (x, y) = (area.OffsetX.value.max(0) as u32, area.OffsetY.value.max(0) as u32);
    let (width, height) = (area.Area.cx.max(0) as u32, area.Area.cy.max(0) as u32);
    (width > 0 && height > 0).then_some(Area { x, y, width, height })
}
