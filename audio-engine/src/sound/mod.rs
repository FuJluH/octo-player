//! Octo's sound shaping, ported from the Android app so both sound alike.

pub mod biquad;
pub mod crossfeed;
pub mod limiter;
pub mod model;
pub mod replaygain;
pub mod shaper;

#[cfg(test)]
mod tests;
