# Test fixtures

Small lossy files the decoder tests read. All are pure sine tones, so no
recorded music is checked in. WAV and FLAC test files are made while the
tests run instead.

| File | Contents |
| --- | --- |
| `tone-440-44k-mono.mp3` | 1 s of 440 Hz, 44.1 kHz mono, 96 kbps CBR, with the LAME header holding the encoder delay and padding |
| `tone-440-48k-stereo.opus` | 1 s of 440 Hz, 48 kHz stereo, Ogg Opus at 128 kbps, pre-skip 312 |
| `tone-440-44k-stereo.aac` | 2 s of 440 Hz, 44.1 kHz stereo, AAC-LC in ADTS at 96 kbps |
| `tone-440-48k-stereo.aac` | 1 s of 440 Hz, 48 kHz stereo, AAC-LC in ADTS at 96 kbps |
| `tone-440-44k-stereo-aac.ts` | 2 s of 440 Hz, 44.1 kHz stereo, AAC-LC at 96 kbps in MPEG-TS |
| `tone-440-44k-mono-mp3.ts` | 2 s of 440 Hz, 44.1 kHz mono, MP3 at 96 kbps in MPEG-TS |
| `hls-fmp4/` | The 44.1 kHz tone as fragmented MP4 for HLS: `init.mp4` and four segments of about 0.5 s |

The MP3 and Opus files come from `tools/make-fixtures`:

```sh
cd tools/make-fixtures
cargo run --release
```

The AAC files and the MPEG-TS ones (the MP3 one through LAME) come from FFmpeg:

```sh
ffmpeg -f lavfi -i "sine=frequency=440:sample_rate=44100:duration=2" -ac 2 \
    -c:a aac -b:a 96k -f adts tone-440-44k-stereo.aac
ffmpeg -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=1" -ac 2 \
    -c:a aac -b:a 96k -f adts tone-440-48k-stereo.aac
ffmpeg -f lavfi -i "sine=frequency=440:sample_rate=44100:duration=2" -ac 2 \
    -c:a aac -b:a 96k -f mpegts tone-440-44k-stereo-aac.ts
ffmpeg -f lavfi -i "sine=frequency=440:sample_rate=44100:duration=2" -ac 1 \
    -c:a libmp3lame -b:a 96k -f mpegts tone-440-44k-mono-mp3.ts
ffmpeg -f lavfi -i "sine=frequency=440:sample_rate=44100:duration=2" -ac 2 \
    -c:a aac -b:a 96k -f hls -hls_segment_type fmp4 -hls_time 0.5 -hls_list_size 0 \
    -hls_fmp4_init_filename init.mp4 -hls_segment_filename "hls-fmp4/seg%d.m4s" hls-fmp4/list.m3u8
```

The last command also writes `list.m3u8` and a short fifth segment, which
are not kept: the tests write their own playlists.
