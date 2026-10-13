//! In-stream titles from Shoutcast and Icecast servers. Asked for with
//! `Icy-MetaData: 1`, a server that has them says `icy-metaint: N` and then
//! puts a metadata block after every N bytes of audio: one byte giving its
//! length in sixteens, then that much text such as
//! `StreamTitle='Artist - Song';`.

use ureq::unversioned::transport::{
    Buffers, ConnectionDetails, Connector, LazyBuffers, NextTimeout, Transport,
};

/// Splits a live stream's bytes into its audio and its metadata blocks, in
/// pieces of any size, so a block may arrive across several reads.
pub struct IcySplitter {
    metaint: usize,
    // Audio bytes left before the next metadata block.
    audio_left: usize,
    // Bytes of the block still to come, once its length byte is read.
    meta_left: Option<usize>,
    meta: Vec<u8>,
}

impl IcySplitter {
    pub fn new(metaint: usize) -> Self {
        Self { metaint: metaint.max(1), audio_left: metaint.max(1), meta_left: None, meta: Vec::new() }
    }

    /// Adds the audio in `input` to `audio`, and for each metadata block
    /// that ends in it, its title with where in `audio` the block sat. A
    /// block without a title gives an empty one.
    pub fn feed(&mut self, mut input: &[u8], audio: &mut Vec<u8>, titles: &mut Vec<(usize, String)>) {
        while !input.is_empty() {
            if self.audio_left > 0 {
                let n = self.audio_left.min(input.len());
                audio.extend_from_slice(&input[..n]);
                self.audio_left -= n;
                input = &input[n..];
                continue;
            }
            let left = match self.meta_left {
                Some(left) => left,
                None => {
                    let len = input[0] as usize * 16;
                    input = &input[1..];
                    self.meta.clear();
                    self.meta_left = Some(len);
                    len
                }
            };
            let n = left.min(input.len());
            self.meta.extend_from_slice(&input[..n]);
            input = &input[n..];
            let left = left - n;
            if left > 0 {
                self.meta_left = Some(left);
                continue;
            }
            self.meta_left = None;
            self.audio_left = self.metaint;
            if !self.meta.is_empty() {
                titles.push((audio.len(), stream_title(&self.meta).unwrap_or_default()));
            }
        }
    }
}

/// The `StreamTitle` in a metadata block, trimmed. Text that is not UTF-8
/// is read as Latin-1, as older servers send it.
pub fn stream_title(block: &[u8]) -> Option<String> {
    let end = block.iter().rposition(|&b| b != 0).map_or(0, |i| i + 1);
    let bytes = &block[..end];
    let text = match std::str::from_utf8(bytes) {
        Ok(text) => text.to_string(),
        Err(_) => bytes.iter().map(|&b| b as char).collect(),
    };
    const KEY: &str = "StreamTitle='";
    let start = text.find(KEY)? + KEY.len();
    let rest = &text[start..];
    // The value ends at "';", so a quote inside a name stays in it.
    let value = match rest.find("';") {
        Some(i) => &rest[..i],
        None => rest.strip_suffix('\'').unwrap_or(rest),
    };
    Some(value.trim().to_string())
}

/// A link in the client's connection chain for old SHOUTcast servers,
/// which answer `ICY 200 OK` where HTTP has `HTTP/1.0 200 OK`: the start of
/// each connection's first answer is read as the latter. Everything else
/// passes as it is.
#[derive(Debug, Default)]
pub struct IcyStatus;

impl<In: Transport> Connector<In> for IcyStatus {
    type Out = IcyTransport<In>;

    fn connect(
        &self,
        details: &ConnectionDetails,
        chained: Option<In>,
    ) -> Result<Option<Self::Out>, ureq::Error> {
        let sizes = (details.config.input_buffer_size(), details.config.output_buffer_size());
        Ok(chained.map(|inner| IcyTransport {
            inner,
            buffers: LazyBuffers::new(sizes.0, sizes.1),
            first: true,
        }))
    }
}

/// A connection whose first answer may start `ICY `.
#[derive(Debug)]
pub struct IcyTransport<In> {
    inner: In,
    // What ureq reads and writes; the inner connection's are copied to and from.
    buffers: LazyBuffers,
    // Nothing of the answer has been passed on yet.
    first: bool,
}

const ICY: &[u8] = b"ICY ";
const HTTP_1_0: &[u8] = b"HTTP/1.0 ";

impl<In: Transport> Transport for IcyTransport<In> {
    fn buffers(&mut self) -> &mut dyn Buffers {
        &mut self.buffers
    }

    fn transmit_output(&mut self, amount: usize, timeout: NextTimeout) -> Result<(), ureq::Error> {
        let output = &self.buffers.output()[..amount];
        let room = self.inner.buffers().output().len();
        let mut sent = 0;
        while sent < output.len() {
            let n = (output.len() - sent).min(room);
            self.inner.buffers().output()[..n].copy_from_slice(&output[sent..sent + n]);
            self.inner.transmit_output(n, timeout)?;
            sent += n;
        }
        Ok(())
    }

    fn await_input(&mut self, timeout: NextTimeout) -> Result<bool, ureq::Error> {
        if self.inner.buffers().input().is_empty() && !self.inner.await_input(timeout)? {
            return Ok(false);
        }
        if self.first {
            // Wait for enough to tell an ICY answer.
            while self.inner.buffers().input().len() < ICY.len()
                && ICY.starts_with(self.inner.buffers().input())
            {
                if !self.inner.await_input(timeout)? {
                    break;
                }
            }
            self.first = false;
            if self.inner.buffers().input().starts_with(ICY) {
                self.inner.buffers().input_consume(ICY.len());
                let free = self.buffers.input_append_buf();
                free[..HTTP_1_0.len()].copy_from_slice(HTTP_1_0);
                self.buffers.input_appended(HTTP_1_0.len());
            }
        }
        let input = self.inner.buffers().input();
        let free = self.buffers.input_append_buf();
        let n = input.len().min(free.len());
        free[..n].copy_from_slice(&input[..n]);
        self.buffers.input_appended(n);
        self.inner.buffers().input_consume(n);
        Ok(true)
    }

    fn is_open(&mut self) -> bool {
        self.inner.is_open()
    }

    fn is_tls(&self) -> bool {
        self.inner.is_tls()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // `audio` with a block holding `text` after every `metaint` bytes.
    fn with_blocks(audio: &[u8], metaint: usize, text: &str) -> Vec<u8> {
        let mut out = Vec::new();
        for (i, piece) in audio.chunks(metaint).enumerate() {
            out.extend_from_slice(piece);
            if piece.len() == metaint {
                if i % 2 == 0 {
                    let mut block = text.as_bytes().to_vec();
                    block.resize(block.len().div_ceil(16) * 16, 0);
                    out.push((block.len() / 16) as u8);
                    out.extend_from_slice(&block);
                } else {
                    out.push(0);
                }
            }
        }
        out
    }

    #[test]
    fn titles_come_out_and_audio_stays_whole_in_any_pieces() {
        let audio: Vec<u8> = (0..10_000u32).map(|i| (i * 31 % 251) as u8).collect();
        let stream = with_blocks(&audio, 1000, "StreamTitle='Guns N' Roses - Patience';StreamUrl='';");
        for piece in [1, 7, 999, 1000, 1001, 4096] {
            let mut splitter = IcySplitter::new(1000);
            let (mut out, mut titles) = (Vec::new(), Vec::new());
            for part in stream.chunks(piece) {
                splitter.feed(part, &mut out, &mut titles);
            }
            assert_eq!(out, audio, "pieces of {piece}");
            assert_eq!(titles.len(), 5, "pieces of {piece}");
            assert_eq!(titles[0], (1000, "Guns N' Roses - Patience".to_string()));
            assert_eq!(titles[1].0, 3000);
        }
    }

    #[test]
    fn reads_titles() {
        assert_eq!(stream_title(b"StreamTitle='A - B';\0\0\0").as_deref(), Some("A - B"));
        assert_eq!(stream_title(b"StreamTitle='';").as_deref(), Some(""));
        assert_eq!(stream_title(b"StreamUrl='x';"), None);
        assert_eq!(stream_title(b"StreamTitle='Caf\xe9';").as_deref(), Some("Caf\u{e9}"));
        assert_eq!(stream_title("StreamTitle='Café';".as_bytes()).as_deref(), Some("Café"));
    }
}
