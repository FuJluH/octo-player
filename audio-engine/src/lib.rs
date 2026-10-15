//! The audio engine for the Octo desktop app.

uniffi::setup_scaffolding!();

pub mod api;
pub mod automix;
pub mod crossfade;
pub mod deck;
pub mod decode;
pub mod error;
pub mod fifo;
pub mod lane;
pub mod mixer;
#[cfg(feature = "opus")]
pub mod opus;
pub mod output;
pub mod pace;
pub mod player;
pub mod scout;
pub mod sound;
pub mod source;
pub mod timeline;
pub mod video;

pub use api::{Engine, EngineEvent, EngineListener, QueueItem};
pub use automix::AutomixSettings;

#[cfg(test)]
mod testing;
#[cfg(test)]
mod tests;
