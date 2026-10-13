//! In-stream titles from Shoutcast and Icecast servers. Asked for with
//! `Icy-MetaData: 1`, a server that has them says `icy-metaint: N` and then
//! puts a metadata block after every N bytes of audio: one byte giving its
//! length in sixteens, then that much text such as
//! `StreamTitle='Artist - Song';`.

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
