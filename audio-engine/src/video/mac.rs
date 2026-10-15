//! Loops decoded by AVFoundation on macOS: an asset reader on the file's
//! video track giving 32-bit BGRA pixel buffers (VideoToolbox decodes on
//! the graphics hardware where it can). A reader cannot go back, so each
//! round of the loop has a new one.

use std::time::Duration;

use objc2::rc::{Retained, autoreleasepool};
use objc2::runtime::AnyObject;
use objc2_av_foundation::{
    AVAssetReader, AVAssetReaderOutput, AVAssetReaderStatus, AVAssetReaderTrackOutput, AVAssetTrack,
    AVMediaTypeVideo, AVURLAsset,
};
use objc2_core_media::{CMSampleBuffer, CMTime};
use objc2_core_video::{
    CVPixelBufferGetBaseAddress, CVPixelBufferGetBytesPerRow, CVPixelBufferGetHeight, CVPixelBufferGetWidth,
    CVPixelBufferLockBaseAddress, CVPixelBufferLockFlags, CVPixelBufferUnlockBaseAddress,
    kCVPixelBufferHeightKey, kCVPixelBufferPixelFormatTypeKey, kCVPixelBufferWidthKey,
    kCVPixelFormatType_32BGRA,
};
use objc2_foundation::{NSDictionary, NSNumber, NSString, NSURL};

use super::{FrameSource, FrameTime, copy_rows, scaled_size};
use crate::error::{ErrorKind, Failure};

fn failure(message: impl Into<String>) -> Failure {
    Failure::new(ErrorKind::Decode, message)
}

pub(crate) struct AvSource {
    track: Retained<AVAssetTrack>,
    asset: Retained<AVURLAsset>,
    reader: Retained<AVAssetReader>,
    output: Retained<AVAssetReaderTrackOutput>,
    /// The size asked of the reader, or None for the file's own.
    asked: Option<(u32, u32)>,
    size: (u32, u32),
    /// The first frame, read while opening to learn the size.
    first: Option<Retained<CMSampleBuffer>>,
}

impl AvSource {
    pub(crate) fn open(path: &str, target: (u32, u32)) -> Result<Self, Failure> {
        autoreleasepool(|_| {
            // SAFETY: AVFoundation calls on objects made and used on this
            // thread only.
            unsafe {
                let url = NSURL::fileURLWithPath(&NSString::from_str(path));
                let asset = AVURLAsset::URLAssetWithURL_options(&url, None);
                let kind = AVMediaTypeVideo.ok_or_else(|| failure("AVFoundation has no video type"))?;
                #[allow(deprecated)]
                let track = asset
                    .tracksWithMediaType(kind)
                    .firstObject()
                    .ok_or_else(|| failure("the file has no video"))?;
                let (reader, output) = reader_for(&asset, &track, None)?;
                let mut source =
                    Self { track, asset, reader, output, asked: None, size: (0, 0), first: None };
                let first =
                    source.output.copyNextSampleBuffer().ok_or_else(|| failure("the video has no frames"))?;
                let native = size_of(&first).ok_or_else(|| failure("the video's frames have no picture"))?;
                let wanted = scaled_size(native, target);
                if wanted != native
                    && let Ok((reader, output)) = reader_for(&source.asset, &source.track, Some(wanted))
                    && let Some(scaled) = output.copyNextSampleBuffer()
                    && let Some(size) = size_of(&scaled)
                {
                    source.reader.cancelReading();
                    source.reader = reader;
                    source.output = output;
                    source.asked = Some(wanted);
                    source.size = size;
                    source.first = Some(scaled);
                } else {
                    source.size = native;
                    source.first = Some(first);
                }
                Ok(source)
            }
        })
    }

    /// Copies a sample's picture into `pixels`.
    unsafe fn copy(&self, sample: &CMSampleBuffer, pixels: &mut [u8]) -> Result<(), Failure> {
        // SAFETY: the pixel buffer is locked while its memory is read.
        unsafe {
            let image = sample.image_buffer().ok_or_else(|| failure("a frame has no picture"))?;
            if CVPixelBufferLockBaseAddress(&image, CVPixelBufferLockFlags::ReadOnly) != 0 {
                return Err(failure("a frame could not be read"));
            }
            let base = CVPixelBufferGetBaseAddress(&image) as *const u8;
            let stride = CVPixelBufferGetBytesPerRow(&image);
            let width = CVPixelBufferGetWidth(&image).min(self.size.0 as usize);
            let height = CVPixelBufferGetHeight(&image).min(self.size.1 as usize);
            if !base.is_null() {
                let all = std::slice::from_raw_parts(base, stride * height);
                copy_rows(all, 0, stride as isize, width, height, pixels);
            }
            CVPixelBufferUnlockBaseAddress(&image, CVPixelBufferLockFlags::ReadOnly);
            Ok(())
        }
    }
}

impl FrameSource for AvSource {
    fn size(&self) -> (u32, u32) {
        self.size
    }

    fn next_frame(&mut self, pixels: &mut [u8]) -> Result<Option<FrameTime>, Failure> {
        autoreleasepool(|_| {
            // SAFETY: as in `open`.
            unsafe {
                let sample = match self.first.take() {
                    Some(first) => first,
                    None => match self.output.copyNextSampleBuffer() {
                        Some(sample) => sample,
                        None if self.reader.status() == AVAssetReaderStatus::Failed => {
                            return Err(failure("AVFoundation could not decode the video"));
                        }
                        None => return Ok(None),
                    },
                };
                self.copy(&sample, pixels)?;
                let at = seconds(sample.presentation_time_stamp()).unwrap_or(Duration::ZERO);
                Ok(Some(FrameTime { at, length: seconds(sample.duration()) }))
            }
        })
    }

    fn rewind(&mut self) -> Result<(), Failure> {
        autoreleasepool(|_| {
            // SAFETY: as in `open`.
            unsafe {
                self.reader.cancelReading();
                let (reader, output) = reader_for(&self.asset, &self.track, self.asked)?;
                self.reader = reader;
                self.output = output;
                self.first = None;
                Ok(())
            }
        })
    }
}

impl Drop for AvSource {
    fn drop(&mut self) {
        // SAFETY: stops the reader's own work before it goes.
        unsafe { self.reader.cancelReading() };
    }
}

/// A started reader giving BGRA frames of the track, at `size` if given.
unsafe fn reader_for(
    asset: &AVURLAsset,
    track: &AVAssetTrack,
    size: Option<(u32, u32)>,
) -> Result<(Retained<AVAssetReader>, Retained<AVAssetReaderTrackOutput>), Failure> {
    // SAFETY: the keys are CoreVideo's constant strings, which are NSStrings
    // too (toll-free bridged).
    unsafe {
        let key = |k: &'static objc2_core_foundation::CFString| &*(k as *const _ as *const NSString);
        let format = NSNumber::new_u32(kCVPixelFormatType_32BGRA);
        let mut keys: Vec<&NSString> = vec![key(kCVPixelBufferPixelFormatTypeKey)];
        let mut numbers: Vec<Retained<NSNumber>> = vec![format];
        if let Some((width, height)) = size {
            keys.push(key(kCVPixelBufferWidthKey));
            numbers.push(NSNumber::new_u32(width));
            keys.push(key(kCVPixelBufferHeightKey));
            numbers.push(NSNumber::new_u32(height));
        }
        let values: Vec<&AnyObject> = numbers.iter().map(|n| -> &AnyObject { n }).collect();
        let settings = NSDictionary::from_slices(&keys, &values);
        let reader = AVAssetReader::assetReaderWithAsset_error(asset).map_err(|e| {
            failure(format!("AVFoundation could not read the file: {}", e.localizedDescription()))
        })?;
        let output =
            AVAssetReaderTrackOutput::assetReaderTrackOutputWithTrack_outputSettings(track, Some(&settings));
        // The frames are only read, so the decoder's own buffers will do.
        output.setAlwaysCopiesSampleData(false);
        let as_output: &AVAssetReaderOutput = &output;
        if !reader.canAddOutput(as_output) {
            return Err(failure("AVFoundation cannot give this video's frames"));
        }
        reader.addOutput(as_output);
        if !reader.startReading() {
            return Err(failure("AVFoundation could not start reading the video"));
        }
        Ok((reader, output))
    }
}

unsafe fn size_of(sample: &CMSampleBuffer) -> Option<(u32, u32)> {
    // SAFETY: reads the sample's picture size only.
    let image = unsafe { sample.image_buffer() }?;
    let (width, height) = (CVPixelBufferGetWidth(&image), CVPixelBufferGetHeight(&image));
    (width > 0 && height > 0).then_some((width as u32, height as u32))
}

fn seconds(time: CMTime) -> Option<Duration> {
    if time.timescale <= 0 || time.value < 0 {
        return None;
    }
    Some(Duration::from_secs_f64(time.value as f64 / time.timescale as f64))
}
