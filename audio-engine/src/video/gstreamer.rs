//! Loops decoded by GStreamer on Linux, loaded when first asked for, so the
//! engine loads and plays music on a system without it (loops then show
//! their still). The pipeline reads the file, demuxes the MP4, decodes
//! with whatever decoder GStreamer has, converts to BGRA and hands frames
//! to an app sink the loop's thread pulls from.

use std::ffi::{CString, c_char, c_int, c_uint, c_void};
use std::ptr;
use std::sync::OnceLock;
use std::time::Duration;

use libloading::Library;

use super::{FrameSource, FrameTime, copy_rows, scaled_size};
use crate::error::{ErrorKind, Failure};

type Gboolean = c_int;
type GstClockTime = u64;

const CLOCK_TIME_NONE: GstClockTime = u64::MAX;
const STATE_NULL: c_int = 1;
const STATE_PAUSED: c_int = 3;
const STATE_PLAYING: c_int = 4;
const CHANGE_FAILURE: c_int = 0;
const FORMAT_TIME: c_int = 3;
const SEEK_FLUSH: c_int = 1;
const SEEK_KEY_UNIT: c_int = 4;
const MAP_READ: c_int = 1;
const SECOND: GstClockTime = 1_000_000_000;

/// How long opening and each frame may take before the file counts as
/// one GStreamer cannot decode.
const WAIT: GstClockTime = 5 * SECOND;

/// GstMiniObject and the start of GstBuffer, as laid out in GStreamer 1.x.
#[repr(C)]
struct MiniObject {
    kind: usize,
    refcount: c_int,
    lockstate: c_int,
    flags: c_uint,
    copy: *mut c_void,
    dispose: *mut c_void,
    free: *mut c_void,
    priv_uint: c_uint,
    priv_pointer: *mut c_void,
}

#[repr(C)]
struct Buffer {
    mini_object: MiniObject,
    pool: *mut c_void,
    pts: GstClockTime,
    dts: GstClockTime,
    duration: GstClockTime,
}

#[repr(C)]
struct MapInfo {
    memory: *mut c_void,
    flags: c_int,
    data: *mut u8,
    size: usize,
    maxsize: usize,
    user_data: [*mut c_void; 4],
    reserved: [*mut c_void; 4],
}

/// The GStreamer calls used, from its libraries loaded at run time.
struct Api {
    parse_launch: unsafe extern "C" fn(*const c_char, *mut *mut c_void) -> *mut c_void,
    bin_get_by_name: unsafe extern "C" fn(*mut c_void, *const c_char) -> *mut c_void,
    set_object_arg: unsafe extern "C" fn(*mut c_void, *const c_char, *const c_char),
    set_state: unsafe extern "C" fn(*mut c_void, c_int) -> c_int,
    get_state: unsafe extern "C" fn(*mut c_void, *mut c_int, *mut c_int, GstClockTime) -> c_int,
    seek_simple: unsafe extern "C" fn(*mut c_void, c_int, c_int, i64) -> Gboolean,
    object_unref: unsafe extern "C" fn(*mut c_void),
    mini_object_unref: unsafe extern "C" fn(*mut c_void),
    sample_get_buffer: unsafe extern "C" fn(*mut c_void) -> *mut Buffer,
    sample_get_caps: unsafe extern "C" fn(*mut c_void) -> *mut c_void,
    caps_get_structure: unsafe extern "C" fn(*mut c_void, c_uint) -> *mut c_void,
    structure_get_int: unsafe extern "C" fn(*mut c_void, *const c_char, *mut c_int) -> Gboolean,
    buffer_map: unsafe extern "C" fn(*mut Buffer, *mut MapInfo, c_int) -> Gboolean,
    buffer_unmap: unsafe extern "C" fn(*mut Buffer, *mut MapInfo),
    factory_find: unsafe extern "C" fn(*const c_char) -> *mut c_void,
    try_pull_sample: unsafe extern "C" fn(*mut c_void, GstClockTime) -> *mut c_void,
    try_pull_preroll: unsafe extern "C" fn(*mut c_void, GstClockTime) -> *mut c_void,
    is_eos: unsafe extern "C" fn(*mut c_void) -> Gboolean,
    _core: Library,
    _app: Library,
}

impl Api {
    /// Loads GStreamer and starts it, or None where it is missing.
    fn load() -> Option<Self> {
        // SAFETY: the libraries are GStreamer's own, and each symbol is
        // given its C signature from GStreamer's headers.
        unsafe {
            let core = Library::new("libgstreamer-1.0.so.0").ok()?;
            let app = Library::new("libgstapp-1.0.so.0").ok()?;
            let init: unsafe extern "C" fn(*mut c_int, *mut *mut *mut c_char, *mut *mut c_void) -> Gboolean =
                *core.get(b"gst_init_check\0").ok()?;
            if init(ptr::null_mut(), ptr::null_mut(), ptr::null_mut()) == 0 {
                return None;
            }
            Some(Self {
                parse_launch: *core.get(b"gst_parse_launch\0").ok()?,
                bin_get_by_name: *core.get(b"gst_bin_get_by_name\0").ok()?,
                set_object_arg: *core.get(b"gst_util_set_object_arg\0").ok()?,
                set_state: *core.get(b"gst_element_set_state\0").ok()?,
                get_state: *core.get(b"gst_element_get_state\0").ok()?,
                seek_simple: *core.get(b"gst_element_seek_simple\0").ok()?,
                object_unref: *core.get(b"gst_object_unref\0").ok()?,
                mini_object_unref: *core.get(b"gst_mini_object_unref\0").ok()?,
                sample_get_buffer: *core.get(b"gst_sample_get_buffer\0").ok()?,
                sample_get_caps: *core.get(b"gst_sample_get_caps\0").ok()?,
                caps_get_structure: *core.get(b"gst_caps_get_structure\0").ok()?,
                structure_get_int: *core.get(b"gst_structure_get_int\0").ok()?,
                buffer_map: *core.get(b"gst_buffer_map\0").ok()?,
                buffer_unmap: *core.get(b"gst_buffer_unmap\0").ok()?,
                factory_find: *core.get(b"gst_element_factory_find\0").ok()?,
                try_pull_sample: *app.get(b"gst_app_sink_try_pull_sample\0").ok()?,
                try_pull_preroll: *app.get(b"gst_app_sink_try_pull_preroll\0").ok()?,
                is_eos: *app.get(b"gst_app_sink_is_eos\0").ok()?,
                _core: core,
                _app: app,
            })
        }
    }

    /// Whether GStreamer has an element of this name.
    fn has(&self, name: &str) -> bool {
        let Ok(name) = CString::new(name) else { return false };
        // SAFETY: a found factory comes with a reference, given back here.
        unsafe {
            let factory = (self.factory_find)(name.as_ptr());
            if factory.is_null() {
                return false;
            }
            (self.object_unref)(factory);
            true
        }
    }
}

fn api() -> Option<&'static Api> {
    static API: OnceLock<Option<Api>> = OnceLock::new();
    API.get_or_init(|| {
        let api = Api::load();
        if api.is_none() {
            log::info!("GStreamer is not installed: animated covers show their still");
        }
        api
    })
    .as_ref()
}

/// Whether GStreamer is here with the elements a loop needs.
pub(crate) fn available() -> bool {
    api().is_some_and(|api| {
        ["filesrc", "qtdemux", "decodebin", "videoconvert", "videoscale", "appsink"]
            .iter()
            .all(|name| api.has(name))
    })
}

fn failure(message: impl Into<String>) -> Failure {
    Failure::new(ErrorKind::Unsupported, message)
}

pub(crate) struct GstSource {
    api: &'static Api,
    pipeline: *mut c_void,
    sink: *mut c_void,
    size: (u32, u32),
    /// Frames given this round, for files whose frames carry no time.
    count: u32,
}

impl GstSource {
    pub(crate) fn open(path: &str, target: (u32, u32)) -> Result<Self, Failure> {
        let api = api().ok_or_else(|| failure("GStreamer is not installed"))?;
        if !available() {
            return Err(failure("GStreamer lacks the elements to decode video"));
        }
        // SAFETY: GStreamer calls on objects made here, each given back in drop.
        unsafe {
            let mut source = Self::build(api, path, "video/x-raw,format=BGRA")?;
            let native = source.preroll()?;
            let wanted = scaled_size(native, target);
            source.size = native;
            // A pipeline's dynamic links are made once, so a smaller size
            // is a new pipeline.
            if wanted != native {
                let caps = format!(
                    "video/x-raw,format=BGRA,width={},height={},pixel-aspect-ratio=1/1",
                    wanted.0, wanted.1
                );
                let mut scaled = Self::build(api, path, &caps)?;
                if let Ok(size) = scaled.preroll() {
                    scaled.size = size;
                    source = scaled;
                }
            }
            if (api.set_state)(source.pipeline, STATE_PLAYING) == CHANGE_FAILURE {
                return Err(failure("GStreamer could not play the video"));
            }
            Ok(source)
        }
    }

    /// The pipeline on `path`, giving frames in `caps`, not started.
    unsafe fn build(api: &'static Api, path: &str, caps: &str) -> Result<Self, Failure> {
        let description = CString::new(format!(
            "filesrc name=src ! qtdemux ! decodebin ! videoconvert ! videoscale ! capsfilter caps=\"{caps}\" ! \
             appsink name=sink sync=false max-buffers=2 drop=false enable-last-sample=false"
        ))
        .map_err(|_| failure("the caps have a nul"))?;
        // SAFETY: as in `open`.
        unsafe {
            let mut error = ptr::null_mut();
            let pipeline = (api.parse_launch)(description.as_ptr(), &mut error);
            if pipeline.is_null() {
                return Err(failure("GStreamer could not make the video pipeline"));
            }
            let mut source = Self { api, pipeline, sink: ptr::null_mut(), size: (0, 0), count: 0 };
            source.sink = (api.bin_get_by_name)(pipeline, c"sink".as_ptr());
            let file = (api.bin_get_by_name)(pipeline, c"src".as_ptr());
            if source.sink.is_null() || file.is_null() {
                if !file.is_null() {
                    (api.object_unref)(file);
                }
                return Err(failure("GStreamer's pipeline has no file or sink"));
            }
            let location = CString::new(path).map_err(|_| failure("the path has a nul"))?;
            (api.set_object_arg)(file, c"location".as_ptr(), location.as_ptr());
            (api.object_unref)(file);
            Ok(source)
        }
    }
    /// Pauses on the first frame and gives its size.
    unsafe fn preroll(&mut self) -> Result<(u32, u32), Failure> {
        let api = self.api;
        // SAFETY: the pipeline and sink are this source's own.
        unsafe {
            if (api.set_state)(self.pipeline, STATE_PAUSED) == CHANGE_FAILURE {
                return Err(failure("GStreamer could not open the video"));
            }
            let mut state = 0;
            let mut pending = 0;
            if (api.get_state)(self.pipeline, &mut state, &mut pending, WAIT) == CHANGE_FAILURE {
                return Err(failure("GStreamer has no decoder for this video"));
            }
            let sample = (api.try_pull_preroll)(self.sink, WAIT);
            if sample.is_null() {
                return Err(failure("GStreamer gave no first frame"));
            }
            let size = self.size_of(sample);
            (api.mini_object_unref)(sample);
            size.ok_or_else(|| failure("GStreamer's frames have no size"))
        }
    }

    unsafe fn size_of(&self, sample: *mut c_void) -> Option<(u32, u32)> {
        let api = self.api;
        // SAFETY: the caps and structure belong to the sample, alive here.
        unsafe {
            let caps = (api.sample_get_caps)(sample);
            if caps.is_null() {
                return None;
            }
            let structure = (api.caps_get_structure)(caps, 0);
            if structure.is_null() {
                return None;
            }
            let (mut width, mut height) = (0, 0);
            if (api.structure_get_int)(structure, c"width".as_ptr(), &mut width) == 0
                || (api.structure_get_int)(structure, c"height".as_ptr(), &mut height) == 0
            {
                return None;
            }
            (width > 0 && height > 0).then_some((width as u32, height as u32))
        }
    }
}

impl FrameSource for GstSource {
    fn size(&self) -> (u32, u32) {
        self.size
    }

    fn next_frame(&mut self, pixels: &mut [u8]) -> Result<Option<FrameTime>, Failure> {
        let api = self.api;
        // SAFETY: the sample and its buffer are held until given back below.
        unsafe {
            let sample = (api.try_pull_sample)(self.sink, WAIT);
            if sample.is_null() {
                return if (api.is_eos)(self.sink) != 0 {
                    Ok(None)
                } else {
                    Err(Failure::new(ErrorKind::Decode, "GStreamer stopped giving frames"))
                };
            }
            let buffer = (api.sample_get_buffer)(sample);
            if buffer.is_null() {
                (api.mini_object_unref)(sample);
                return Err(Failure::new(ErrorKind::Decode, "GStreamer gave a frame with no picture"));
            }
            let (pts, duration) = ((*buffer).pts, (*buffer).duration);
            let mut map: MapInfo = std::mem::zeroed();
            if (api.buffer_map)(buffer, &mut map, MAP_READ) == 0 {
                (api.mini_object_unref)(sample);
                return Err(Failure::new(ErrorKind::Decode, "GStreamer's frame could not be read"));
            }
            let (width, height) = (self.size.0 as usize, self.size.1 as usize);
            let data = std::slice::from_raw_parts(map.data, map.size);
            let stride = (map.size / height.max(1)).max(width * 4);
            copy_rows(data, 0, stride as isize, width, height, pixels);
            (api.buffer_unmap)(buffer, &mut map);
            (api.mini_object_unref)(sample);
            let gap = Duration::from_micros(41_667);
            let at = if pts == CLOCK_TIME_NONE { gap * self.count } else { Duration::from_nanos(pts) };
            self.count += 1;
            let length =
                (duration != CLOCK_TIME_NONE && duration > 0).then(|| Duration::from_nanos(duration));
            Ok(Some(FrameTime { at, length }))
        }
    }

    fn rewind(&mut self) -> Result<(), Failure> {
        self.count = 0;
        // SAFETY: the pipeline is this source's own.
        let done =
            unsafe { (self.api.seek_simple)(self.pipeline, FORMAT_TIME, SEEK_FLUSH | SEEK_KEY_UNIT, 0) != 0 };
        if done {
            Ok(())
        } else {
            Err(Failure::new(ErrorKind::Decode, "GStreamer could not go back to the start"))
        }
    }
}

impl Drop for GstSource {
    fn drop(&mut self) {
        // SAFETY: stops the pipeline and gives back the references taken.
        unsafe {
            (self.api.set_state)(self.pipeline, STATE_NULL);
            if !self.sink.is_null() {
                (self.api.object_unref)(self.sink);
            }
            (self.api.object_unref)(self.pipeline);
        }
    }
}
