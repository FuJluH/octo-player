//! MPEG-TS, as HLS segments carry it, cut down to its first audio stream.
//! The packets are 188 bytes, each starting with 0x47. The PAT names the
//! PMT, the PMT names the streams, and the audio stream's PES packets
//! carry AAC in ADTS frames (stream type 0x0F) or MPEG audio (0x03, 0x04),
//! whose payloads joined are a stream the decoder reads as it is. Timed
//! ID3 metadata (0x15) and every other stream are passed over.
//!
//! The demuxer keeps its place between calls, so a packet or a PES packet
//! cut across two segments joins up. Lost or repeated packets are not
//! mended: the frames around them are found again by their sync words.

const PACKET: usize = 188;
const SYNC: u8 = 0x47;

/// The kind of audio a transport stream carries.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TsAudio {
    /// AAC in ADTS frames.
    Aac,
    /// MPEG-1 or MPEG-2 audio, MP3 among it.
    Mpeg,
}

impl TsAudio {
    fn of(stream_type: u8) -> Option<Self> {
        match stream_type {
            0x0f => Some(Self::Aac),
            0x03 | 0x04 => Some(Self::Mpeg),
            _ => None,
        }
    }

    /// The extension that names it, for the format guess.
    pub fn extension(self) -> &'static str {
        match self {
            Self::Aac => "aac",
            Self::Mpeg => "mp3",
        }
    }
}

/// Takes transport stream bytes in and gives the audio stream's bytes out.
#[derive(Default)]
pub struct TsDemuxer {
    // A packet not yet whole.
    partial: Vec<u8>,
    pmt_pid: Option<u16>,
    audio: Option<(u16, TsAudio)>,
    // The PMT was read and named no audio the engine plays.
    no_audio: bool,
    // A PES header cut across packets, until it is whole.
    header: Vec<u8>,
    // Inside the audio stream's PES packets, past a header.
    in_pes: bool,
}

impl TsDemuxer {
    pub fn new() -> Self {
        Self::default()
    }

    /// The audio stream found, once the PMT has been read.
    pub fn audio(&self) -> Option<TsAudio> {
        self.audio.map(|(_, kind)| kind)
    }

    /// Whether the PMT was read and lists no audio stream the engine plays.
    pub fn has_no_audio(&self) -> bool {
        self.no_audio
    }

    /// Adds the audio in `input` to `out`.
    pub fn feed(&mut self, mut input: &[u8], out: &mut Vec<u8>) {
        if !self.partial.is_empty() {
            let need = PACKET - self.partial.len();
            let n = need.min(input.len());
            self.partial.extend_from_slice(&input[..n]);
            input = &input[n..];
            if self.partial.len() < PACKET {
                return;
            }
            let packet = std::mem::take(&mut self.partial);
            if packet[0] == SYNC {
                self.packet(&packet, out);
            }
        }
        let mut at = 0;
        while at < input.len() {
            if input[at] != SYNC {
                // Lost the packet edges: find a sync byte with another a packet on.
                at += 1;
                while at < input.len()
                    && !(input[at] == SYNC && input.get(at + PACKET).is_none_or(|&b| b == SYNC))
                {
                    at += 1;
                }
                continue;
            }
            if at + PACKET > input.len() {
                self.partial.extend_from_slice(&input[at..]);
                return;
            }
            self.packet(&input[at..at + PACKET], out);
            at += PACKET;
        }
    }

    fn packet(&mut self, packet: &[u8], out: &mut Vec<u8>) {
        let start = packet[1] & 0x40 != 0;
        let pid = u16::from(packet[1] & 0x1f) << 8 | u16::from(packet[2]);
        let control = (packet[3] >> 4) & 3;
        if control & 1 == 0 {
            // An adaptation field and no payload.
            return;
        }
        let mut at = 4;
        if control & 2 != 0 {
            at += 1 + packet[4] as usize;
        }
        if at >= PACKET {
            return;
        }
        let payload = &packet[at..];
        if pid == 0 {
            if start {
                self.read_pat(payload);
            }
        } else if Some(pid) == self.pmt_pid {
            if start {
                self.read_pmt(payload);
            }
        } else if self.audio.is_some_and(|(audio, _)| audio == pid) {
            self.read_pes(payload, start, out);
        }
    }

    // The first program's PMT.
    fn read_pat(&mut self, payload: &[u8]) {
        let Some(section) = section(payload, 0x00) else { return };
        // After the 5 bytes of stream id, version and numbers, 4 a program.
        for program in section.get(5..).unwrap_or(&[]).chunks_exact(4) {
            let number = u16::from_be_bytes([program[0], program[1]]);
            if number != 0 {
                self.pmt_pid = Some(u16::from(program[2] & 0x1f) << 8 | u16::from(program[3]));
                return;
            }
        }
    }

    // The first audio stream the engine plays.
    fn read_pmt(&mut self, payload: &[u8]) {
        let Some(section) = section(payload, 0x02) else { return };
        if section.len() < 9 {
            return;
        }
        let info = (usize::from(section[7] & 0x0f) << 8) | usize::from(section[8]);
        let mut streams = section.get(9 + info..).unwrap_or(&[]);
        let mut found = None;
        while streams.len() >= 5 {
            let pid = u16::from(streams[1] & 0x1f) << 8 | u16::from(streams[2]);
            let es_info = (usize::from(streams[3] & 0x0f) << 8) | usize::from(streams[4]);
            if found.is_none() {
                found = TsAudio::of(streams[0]).map(|kind| (pid, kind));
            }
            streams = streams.get(5 + es_info..).unwrap_or(&[]);
        }
        if found != self.audio {
            self.in_pes = false;
            self.header.clear();
        }
        self.no_audio = found.is_none();
        self.audio = found;
    }

    // A piece of the audio stream: a new PES packet when `start`, its
    // header taken off, and anything after it as it comes.
    fn read_pes(&mut self, payload: &[u8], start: bool, out: &mut Vec<u8>) {
        if start {
            self.header.clear();
            self.in_pes = false;
        } else if self.in_pes {
            out.extend_from_slice(payload);
            return;
        } else if self.header.is_empty() {
            // The middle of a PES packet whose start was never seen.
            return;
        }
        self.header.extend_from_slice(payload);
        let h = &self.header;
        if h.len() < 9 {
            return;
        }
        if h[..3] != [0, 0, 1] {
            self.header.clear();
            return;
        }
        let body = 9 + h[8] as usize;
        if h.len() < body {
            return;
        }
        out.extend_from_slice(&h[body..]);
        self.header.clear();
        self.in_pes = true;
    }
}

// A PSI section's bytes after its length field, without the CRC, when the
// payload holds one of `table` whole.
fn section(payload: &[u8], table: u8) -> Option<&[u8]> {
    let pointer = *payload.first()? as usize;
    let s = payload.get(1 + pointer..)?;
    if s.len() < 3 || s[0] != table {
        return None;
    }
    let len = (usize::from(s[1] & 0x0f) << 8) | usize::from(s[2]);
    let body = s.get(3..3 + len)?;
    body.get(..body.len().checked_sub(4)?)
}

#[cfg(test)]
mod tests {
    use super::*;

    // A transport stream made here: PAT, a PMT naming an ID3 stream before
    // an AAC one, and `audio` in PES packets of `pes` bytes, each cut across
    // as many packets as it takes, some with adaptation-field stuffing.
    fn made(audio: &[u8], pes: usize) -> Vec<u8> {
        let mut out = Vec::new();
        let mut packet = |pid: u16, start: bool, adaptation: usize, payload: &[u8]| {
            let mut p = vec![SYNC, (u8::from(start) << 6) | (pid >> 8) as u8, pid as u8];
            let control = if adaptation > 0 { 0x30 } else { 0x10 };
            p.push(control);
            if adaptation > 0 {
                p.push((adaptation - 1) as u8);
                if adaptation > 1 {
                    p.push(0);
                    p.extend(std::iter::repeat_n(0xff, adaptation - 2));
                }
            }
            p.extend_from_slice(payload);
            assert_eq!(p.len(), PACKET);
            out.extend_from_slice(&p);
        };
        let psi = |table: u8, body: &[u8]| {
            let mut s = vec![0u8, table, 0xb0, (body.len() + 4) as u8];
            s.extend_from_slice(body);
            s.extend_from_slice(&[0, 0, 0, 0]);
            s.resize(PACKET - 4, 0xff);
            s
        };
        packet(0, true, 0, &psi(0x00, &[0, 1, 0xc1, 0, 0, 0, 1, 0xf0, 0x00]));
        let streams = [0x15, 0xe1, 0x02, 0xf0, 0x00, 0x0f, 0xe1, 0x01, 0xf0, 0x00];
        let mut pmt = vec![0, 1, 0xc1, 0, 0, 0xe1, 0x01, 0xf0, 0x00];
        pmt.extend_from_slice(&streams);
        packet(0x1000, true, 0, &psi(0x02, &pmt));
        for (n, piece) in audio.chunks(pes).enumerate() {
            let mut bytes = vec![0, 0, 1, 0xc0, 0, 0, 0x80, 0x80, 5, 0x21, 0, 1, 0, 1];
            bytes.extend_from_slice(piece);
            let mut first = true;
            for chunk in bytes.chunks(PACKET - 4) {
                let stuffing = PACKET - 4 - chunk.len();
                packet(0x101, first, stuffing, chunk);
                first = false;
            }
            // Timed metadata between the audio, to be passed over.
            if n % 3 == 0 {
                let mut id3 = vec![0, 0, 1, 0xbd, 0, 0, 0x80, 0x80, 0];
                id3.extend_from_slice(b"ID3 not audio");
                packet(0x102, true, PACKET - 4 - id3.len(), &id3);
            }
        }
        out
    }

    fn audio_bytes(len: usize) -> Vec<u8> {
        (0..len).map(|i| (i * 7 % 253) as u8).collect()
    }

    #[test]
    fn takes_out_the_audio_in_any_pieces() {
        let audio = audio_bytes(20_000);
        let ts = made(&audio, 1_500);
        for piece in [1, 100, 188, 187, 189, 5_000, ts.len()] {
            let mut demuxer = TsDemuxer::new();
            let mut out = Vec::new();
            for part in ts.chunks(piece) {
                demuxer.feed(part, &mut out);
            }
            assert_eq!(demuxer.audio(), Some(TsAudio::Aac));
            assert!(out == audio, "pieces of {piece}: {} bytes out of {}", out.len(), audio.len());
        }
    }

    #[test]
    fn a_lost_packet_loses_only_its_bytes() {
        let audio = audio_bytes(20_000);
        let mut ts = made(&audio, 1_500);
        // Drop the fifth packet, inside the first PES packet.
        ts.drain(4 * PACKET..5 * PACKET);
        let mut demuxer = TsDemuxer::new();
        let mut out = Vec::new();
        demuxer.feed(&ts, &mut out);
        assert_eq!(out.len(), audio.len() - (PACKET - 4));
        // Junk between packets is passed over too.
        let mut junk = made(&audio, 1_500);
        junk.splice(10 * PACKET..10 * PACKET, [1, 2, 3, SYNC, 9]);
        let mut demuxer = TsDemuxer::new();
        let mut out = Vec::new();
        demuxer.feed(&junk, &mut out);
        assert!(out == audio);
    }

    #[test]
    fn a_stream_without_playable_audio_says_so() {
        let mut ts = made(&audio_bytes(1_000), 1_000);
        // The AAC stream turned into AC-3 (0x81).
        let at = PACKET + 4 + 1 + 3 + 9 + 5;
        assert_eq!(ts[at], 0x0f);
        ts[at] = 0x81;
        let mut demuxer = TsDemuxer::new();
        let mut out = Vec::new();
        demuxer.feed(&ts, &mut out);
        assert!(demuxer.has_no_audio());
        assert!(out.is_empty());
    }
}
