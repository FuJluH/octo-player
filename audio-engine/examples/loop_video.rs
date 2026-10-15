//! Plays a video loop as the app does and says how it went: how fast the
//! system's decoder is on the file, then frames copied out for a while at
//! their own pace. Watch the process's processor time from outside.
//!
//! cargo run --release --example loop_video -- loop.mp4 --seconds 20 --size 486

use std::time::{Duration, Instant};

use octo_audio::video::{LoopVideo, decode_speed};

fn main() {
    let mut args = std::env::args().skip(1);
    let path = args.next().expect("a video file");
    let mut seconds = 10u64;
    let mut size = 0u32;
    let mut hold_after = None;
    let mut speed = true;
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--seconds" => seconds = args.next().and_then(|v| v.parse().ok()).expect("seconds"),
            "--size" => size = args.next().and_then(|v| v.parse().ok()).expect("size"),
            // Holds the loop after this many seconds, for the rest of the run.
            "--hold-after" => hold_after = args.next().and_then(|v| v.parse::<u64>().ok()),
            // Leaves out the decoding pass at full speed, for timing the rest.
            "--no-speed" => speed = false,
            other => panic!("unknown argument {other}"),
        }
    }

    match if speed { decode_speed(&path, (size, size)) } else { Ok((0, Duration::ZERO, (0, 0))) } {
        Ok((frames, took, (w, h))) => println!(
            "decoded {frames} frames at {w}x{h} in {:.1} ms: {:.3} ms a frame",
            took.as_secs_f64() * 1000.0,
            took.as_secs_f64() * 1000.0 / frames.max(1) as f64
        ),
        Err(e) => {
            println!("could not decode: {e}");
            return;
        }
    }

    let video = LoopVideo::open(path, size, size).expect("open");
    let (w, h) = (video.width(), video.height());
    let mut pixels = vec![0u8; w as usize * h as usize * 4];
    video.play();
    let start = Instant::now();
    let mut have = 0;
    let mut copied = 0u64;
    let mut held = false;
    while start.elapsed() < Duration::from_secs(seconds) {
        if let Some(after) = hold_after
            && !held
            && start.elapsed() >= Duration::from_secs(after)
        {
            video.hold();
            held = true;
            println!("held after {after} s");
        }
        if held {
            std::thread::sleep(Duration::from_millis(100));
            continue;
        }
        let newest = video.wait_frame(have, 500);
        if newest != have {
            have =
                video.copy_frame(pixels.as_mut_ptr() as u64, w * 4, pixels.len() as u64, have).expect("copy");
            copied += 1;
        }
    }
    println!(
        "{w}x{h}: {} frames shown, {copied} copied in {:.1} s ({:.1} a second); failure {:?}",
        video.frames(),
        start.elapsed().as_secs_f64(),
        copied as f64 / start.elapsed().as_secs_f64(),
        video.failure()
    );
    video.stop();
}
