//! Plays files or stream addresses through the engine, for trying it by ear.
//!
//! cargo run --release --example play -- <path-or-url>... [options]
//!
//! Options:
//!   --volume <0..1>        --crossfade <ms>       --speed <0.5..2>
//!   --pitch <factor>       --eq <preset name>     --replaygain <off|track|album|smart>
//!   --start <ms>           --device <id>          --list-devices
//!   --silent               --seconds <n>          --live (streams are live radio)
//!
//! While playing, type a line and press Enter:
//!   p  pause or resume     n  next song           s <secs>  seek
//!   v <0..1>  volume       q  quit

use std::io::BufRead;
use std::sync::Arc;
use std::sync::mpsc;
use std::time::{Duration, Instant};

use octo_audio::api::{Engine, EngineEvent, EngineListener, PlaybackState, QueueItem, equalizer_presets};
use octo_audio::sound::model::{EqMode, EqSettings, ReplayGainMode, ReplayGainSettings};

struct Printer(mpsc::Sender<EngineEvent>);

impl EngineListener for Printer {
    fn on_event(&self, event: EngineEvent) {
        let _ = self.0.send(event);
    }
}

fn value<T: std::str::FromStr>(args: &mut impl Iterator<Item = String>, name: &str) -> T {
    let raw = args.next().unwrap_or_else(|| fail(&format!("{name} needs a value")));
    raw.parse().unwrap_or_else(|_| fail(&format!("{name}: cannot read {raw}")))
}

fn fail(message: &str) -> ! {
    eprintln!("{message}");
    std::process::exit(2);
}

// The engine's own notes (a device lost, a song that would not open) on
// standard error, so trouble on a machine can be seen.
struct Notes;

impl log::Log for Notes {
    fn enabled(&self, metadata: &log::Metadata) -> bool {
        metadata.level() <= log::Level::Info
    }

    fn log(&self, record: &log::Record) {
        if self.enabled(record.metadata()) {
            eprintln!("[{}] {}", record.level(), record.args());
        }
    }

    fn flush(&self) {}
}

fn main() {
    let _ = log::set_logger(&Notes).map(|()| log::set_max_level(log::LevelFilter::Info));
    let mut sources = Vec::new();
    let (mut volume, mut crossfade, mut speed, mut pitch) = (1.0f32, 0u32, 1.0f32, 1.0f32);
    let (mut eq, mut replaygain, mut start, mut device) =
        (None::<String>, None::<String>, 0u64, None::<String>);
    let (mut list, mut silent, mut seconds, mut live) = (false, false, None::<f64>, false);
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--volume" => volume = value(&mut args, &arg),
            "--crossfade" => crossfade = value(&mut args, &arg),
            "--speed" => speed = value(&mut args, &arg),
            "--pitch" => pitch = value(&mut args, &arg),
            "--eq" => eq = Some(value(&mut args, &arg)),
            "--replaygain" => replaygain = Some(value(&mut args, &arg)),
            "--start" => start = value(&mut args, &arg),
            "--device" => device = Some(value(&mut args, &arg)),
            "--list-devices" => list = true,
            "--silent" => silent = true,
            "--seconds" => seconds = Some(value(&mut args, &arg)),
            "--live" => live = true,
            other if other.starts_with("--") => fail(&format!("unknown option {other}")),
            other => sources.push(other.to_string()),
        }
    }

    let engine = if silent { Engine::new_silent() } else { Engine::new() };
    if list {
        for d in engine.devices() {
            println!("{}{}  [{}]", if d.is_default { "* " } else { "  " }, d.name, d.id);
        }
        if sources.is_empty() {
            return;
        }
    }
    if sources.is_empty() {
        fail("usage: play <path-or-url>... [--volume v] [--crossfade ms] [--speed x] [--eq preset] ...");
    }

    let (tx, events) = mpsc::channel();
    engine.set_listener(Arc::new(Printer(tx)));
    if device.is_some() {
        engine.set_output_device(device).unwrap();
    }
    engine.set_volume(volume).unwrap();
    engine.set_crossfade(crossfade).unwrap();
    engine.set_speed(speed, pitch).unwrap();
    if let Some(name) = eq {
        let preset = equalizer_presets()
            .into_iter()
            .find(|p| p.name.eq_ignore_ascii_case(&name))
            .unwrap_or_else(|| fail(&format!("no preset {name}")));
        engine
            .set_eq(EqSettings {
                enabled: true,
                mode: EqMode::Graphic,
                graphic_gains: preset.gains,
                ..Default::default()
            })
            .unwrap();
    }
    if let Some(mode) = replaygain {
        let mode = match mode.as_str() {
            "off" => ReplayGainMode::Off,
            "track" => ReplayGainMode::Track,
            "album" => ReplayGainMode::Album,
            "smart" => ReplayGainMode::Smart,
            other => fail(&format!("unknown ReplayGain mode {other}")),
        };
        engine.set_replaygain(ReplayGainSettings { mode, ..Default::default() }).unwrap();
    }

    let items = sources
        .iter()
        .enumerate()
        .map(|(i, s)| QueueItem {
            id: format!("{}: {}", i + 1, s),
            source: s.clone(),
            album_id: None,
            album_order: None,
            duration_ms: None,
            replay_gain: None,
            headers: Vec::new(),
            genre: None,
            bpm: None,
            live: live && s.contains("://"),
            hls: false,
        })
        .collect();
    engine.load(items, 0, start, true).unwrap();

    // Commands typed on the terminal.
    let (lines_tx, lines) = mpsc::channel::<String>();
    std::thread::spawn(move || {
        for line in std::io::stdin().lock().lines().map_while(Result::ok) {
            if lines_tx.send(line).is_err() {
                break;
            }
        }
    });

    let started = Instant::now();
    let mut last_print = Instant::now();
    loop {
        while let Ok(event) = events.try_recv() {
            println!("[event] {event:?}");
            if matches!(event, EngineEvent::QueueEnded) {
                engine.shutdown();
                return;
            }
        }
        while let Ok(line) = lines.try_recv() {
            let mut parts = line.split_whitespace();
            match (parts.next(), parts.next()) {
                (Some("p"), _) => {
                    if engine.state() == PlaybackState::Paused {
                        engine.play().unwrap();
                    } else {
                        engine.pause().unwrap();
                    }
                }
                (Some("n"), _) => engine.skip_next().unwrap(),
                (Some("s"), Some(secs)) => match secs.parse::<f64>() {
                    Ok(s) => engine.seek((s * 1_000.0) as u64).unwrap(),
                    Err(_) => eprintln!("seek needs seconds"),
                },
                (Some("v"), Some(v)) => match v.parse::<f32>() {
                    Ok(v) => engine.set_volume(v).unwrap(),
                    Err(_) => eprintln!("volume needs a number"),
                },
                (Some("q"), _) => {
                    engine.shutdown();
                    return;
                }
                _ => eprintln!("p, n, s <secs>, v <0..1>, q"),
            }
        }
        if last_print.elapsed() >= Duration::from_millis(500) {
            last_print = Instant::now();
            let p = engine.position();
            println!(
                "{:?}  {}  {:.3} s / {}  underruns {}",
                engine.state(),
                p.item_id.unwrap_or_default(),
                p.position_ms / 1_000.0,
                p.duration_ms.map(|d| format!("{:.1} s", d as f64 / 1_000.0)).unwrap_or_else(|| "?".into()),
                engine.underruns(),
            );
        }
        if seconds.is_some_and(|s| started.elapsed().as_secs_f64() >= s) {
            engine.shutdown();
            return;
        }
        std::thread::sleep(Duration::from_millis(20));
    }
}
