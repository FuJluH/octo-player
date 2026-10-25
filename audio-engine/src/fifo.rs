//! A growable first-in first-out buffer of samples that reuses its memory,
//! for the stages that run off the audio thread.

#[derive(Clone, Debug, Default)]
pub struct Fifo {
    buf: Vec<f32>,
    start: usize,
}

impl Fifo {
    pub fn with_capacity(samples: usize) -> Self {
        Self { buf: Vec::with_capacity(samples), start: 0 }
    }

    /// Samples held.
    pub fn len(&self) -> usize {
        self.buf.len() - self.start
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    pub fn as_slice(&self) -> &[f32] {
        &self.buf[self.start..]
    }

    pub fn push(&mut self, samples: &[f32]) {
        self.compact();
        self.buf.extend_from_slice(samples);
    }

    /// Room for `samples` more at the end, handed back for writing.
    pub fn extend_zeroed(&mut self, samples: usize) -> &mut [f32] {
        self.compact();
        let at = self.buf.len();
        self.buf.resize(at + samples, 0.0);
        &mut self.buf[at..]
    }

    /// Takes up to `out.len()` samples into `out`, oldest first.
    pub fn pop_into(&mut self, out: &mut [f32]) -> usize {
        let n = out.len().min(self.len());
        out[..n].copy_from_slice(&self.buf[self.start..self.start + n]);
        self.consume(n);
        n
    }

    /// Drops the oldest `samples`.
    pub fn consume(&mut self, samples: usize) {
        self.start = (self.start + samples).min(self.buf.len());
        if self.start == self.buf.len() {
            self.buf.clear();
            self.start = 0;
        }
    }

    pub fn clear(&mut self) {
        self.buf.clear();
        self.start = 0;
    }

    /// Gives back the room above `samples`, keeping what is held. A stage
    /// that opened big and runs small hands its spares back here.
    pub fn shrink_to(&mut self, samples: usize) {
        self.compact();
        self.buf.shrink_to(samples);
    }

    // Moves what is held to the front once the used part is large, so the
    // buffer does not grow forever.
    fn compact(&mut self) {
        if self.start > 0 && self.start >= self.buf.len() / 2 {
            self.buf.drain(..self.start);
            self.start = 0;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::Fifo;

    #[test]
    fn keeps_order_across_compaction() {
        let mut f = Fifo::default();
        let mut next = 0.0;
        let mut expect = 0.0;
        for round in 0..50 {
            let chunk: Vec<f32> = (0..(round % 7 + 1))
                .map(|_| {
                    next += 1.0;
                    next
                })
                .collect();
            f.push(&chunk);
            let mut out = [0.0; 3];
            let n = f.pop_into(&mut out);
            for v in &out[..n] {
                expect += 1.0;
                assert_eq!(*v, expect);
            }
        }
        assert_eq!(f.len() as f32, next - expect);
    }
}
