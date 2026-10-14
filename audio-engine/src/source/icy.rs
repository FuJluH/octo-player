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
    /// that ends in it with a `StreamTitle`, what it names with where in
    /// `audio` the block sat. An empty title is kept: it says there is none.
    pub fn feed(&mut self, mut input: &[u8], audio: &mut Vec<u8>, titles: &mut Vec<(usize, StreamMeta)>) {
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
            if let Some(meta) = stream_meta(&self.meta) {
                titles.push((audio.len(), meta));
            }
        }
    }
}

/// What a metadata block names: its `StreamTitle`, trimmed, and the address
/// sent with it (`StreamArtwork`, else `StreamUrl`), empty when neither.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct StreamMeta {
    pub title: String,
    pub url: String,
}

impl StreamMeta {
    pub fn is_empty(&self) -> bool {
        self.title.is_empty() && self.url.is_empty()
    }
}

/// The `StreamTitle` of a metadata block, with its address, or `None` when
/// it has no `StreamTitle`. Text that is not UTF-8 is read as Latin-1, as
/// older servers send it.
pub fn stream_meta(block: &[u8]) -> Option<StreamMeta> {
    let end = block.iter().rposition(|&b| b != 0).map_or(0, |i| i + 1);
    let bytes = &block[..end];
    let text = match std::str::from_utf8(bytes) {
        Ok(text) => text.to_string(),
        Err(_) => bytes.iter().map(|&b| b as char).collect(),
    };
    let fields = icy_fields(&text);
    let title = fields.iter().find(|(k, _)| *k == "StreamTitle")?.1.trim().to_string();
    let url = ["StreamArtwork", "StreamUrl"]
        .iter()
        .filter_map(|key| fields.iter().find(|(k, _)| k == key))
        .map(|(_, v)| v.trim())
        .find(|v| !v.is_empty())
        .unwrap_or("")
        .to_string();
    Some(StreamMeta { title, url })
}

/// Each `Key='value';` of a block, in order. A value ends at a `';` that the
/// next `Key='` or the end of the block follows, so a quote inside a name
/// stays in it ("LA's #1"); else at a quote that ends the block, else at the
/// end.
fn icy_fields(text: &str) -> Vec<(&str, &str)> {
    let mut fields = Vec::new();
    let mut at = 0;
    while let Some(eq) = text[at..].find("='").map(|i| at + i) {
        let key = text[at..eq].trim().trim_start_matches(';').trim();
        let start = eq + 2;
        let end = value_end(text, start);
        if !key.is_empty() && key.chars().all(|c| c.is_alphanumeric() || c == '_' || c == '-') {
            fields.push((key, &text[start..end]));
        }
        at = (end + 1).min(text.len());
        if text[at..].starts_with(';') {
            at += 1;
        }
    }
    fields
}

// Where a value that starts at `start` ends.
fn value_end(text: &str, start: usize) -> usize {
    let mut search = start;
    while let Some(close) = text[search..].find("';").map(|i| search + i) {
        let rest = &text[close + 2..];
        if rest.trim().is_empty() || starts_with_key(rest) {
            return close;
        }
        search = close + 1;
    }
    let trimmed = text.trim_end();
    if trimmed.len() > start && trimmed.ends_with('\'') { trimmed.len() - 1 } else { text.len() }
}

// Whether `rest` starts (after white space) with `Key='`.
fn starts_with_key(rest: &str) -> bool {
    let rest = rest.trim_start();
    let key_len =
        rest.find(|c: char| !(c.is_ascii_alphanumeric() || c == '_' || c == '-')).unwrap_or(rest.len());
    key_len > 0 && rest.as_bytes()[0].is_ascii_alphabetic() && rest[key_len..].starts_with("='")
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
            assert_eq!(titles[0], (1000, meta("Guns N' Roses - Patience", "")));
            assert_eq!(titles[1].0, 3000);
        }
    }

    fn meta(title: &str, url: &str) -> StreamMeta {
        StreamMeta { title: title.to_string(), url: url.to_string() }
    }

    #[test]
    fn reads_titles() {
        assert_eq!(stream_meta(b"StreamTitle='A - B';\0\0\0"), Some(meta("A - B", "")));
        assert_eq!(stream_meta(b"StreamTitle='';"), Some(meta("", "")));
        assert_eq!(stream_meta(b"StreamUrl='x';"), None);
        assert_eq!(stream_meta(b"StreamTitle='Caf\xe9';"), Some(meta("Caf\u{e9}", "")));
        assert_eq!(stream_meta("StreamTitle='Café';".as_bytes()), Some(meta("Café", "")));
    }

    // Blocks as stations sent them on 2026-10-13.
    #[test]
    fn reads_real_blocks() {
        let kiis = "StreamTitle='LA's #1 Hit Music Station - text=\"102.7 KIIS FM\" song_spot=\"T\" amgArtworkURL=\"\" length=\"00:00:00\" unsID=\"0\" spotInstanceId=\"-1\"';";
        assert_eq!(
            stream_meta(kiis.as_bytes()).unwrap().title,
            "LA's #1 Hit Music Station - text=\"102.7 KIIS FM\" song_spot=\"T\" amgArtworkURL=\"\" length=\"00:00:00\" unsID=\"0\" spotInstanceId=\"-1\""
        );
        assert_eq!(
            stream_meta(b"StreamTitle='AEROSMITH - I DON'T WANNA MISS A THING';"),
            Some(meta("AEROSMITH - I DON'T WANNA MISS A THING", ""))
        );
        assert_eq!(
            stream_meta(b"StreamTitle='Portugal. The Man - Angoon';StreamUrl='http://img.radioparadise.com/covers/l/24684.jpg';"),
            Some(meta("Portugal. The Man - Angoon", "http://img.radioparadise.com/covers/l/24684.jpg"))
        );
        assert_eq!(
            stream_meta(
                b"StreamTitle='Ice Cube - We Be Clubbin` (Clean Radio Edit) ';StreamUrl='';StreamArtwork='';"
            ),
            Some(meta("Ice Cube - We Be Clubbin` (Clean Radio Edit)", ""))
        );
        assert_eq!(
            stream_meta(b"StreamTitle='A - B';StreamUrl='https://x/page';StreamArtwork='https://x/a.jpg';"),
            Some(meta("A - B", "https://x/a.jpg"))
        );
        assert_eq!(
            stream_meta(b"StreamTitle='Riccardo Garzoni - Dick's Boogie'"),
            Some(meta("Riccardo Garzoni - Dick's Boogie", ""))
        );
        assert_eq!(stream_meta(b"StreamTitle='It's on"), Some(meta("It's on", "")));
    }
}
