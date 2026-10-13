package app.winters.octo.sound

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.security.MessageDigest

// The files in resources/alac were made by ffmpeg's ALAC encoder from its
// own test signals (sines, noise, silence, quiet runs, 1 to 6 channels,
// 16 and 24 bits, 44.1 to 96 kHz, fixed prediction orders, stored frames).
// Each hash is of ffmpeg's own decoding of the file as little-endian PCM,
// which equals the signal it encoded.
class AlacDecoderTest {
    private class Vector(val file: String, val bytes: Int, val sha256: String)

    private val vectors = listOf(
        Vector("hires24.m4a", 69120, "1e832d9e91b41e7b770fa6e2ca3a6ce26c7157fc7c8c42d4a1938ebd63bad9c5"),
        Vector("mono16.m4a", 22050, "1423fc2ed4dcf2da23c9c8f983aa84c97440251c6ae01355050ed2b9edf84f43"),
        Vector("noise16.m4a", 35280, "72d41add78a3b102d2f7861786b2925df54ea1f25420eaf3e4bafb36ce1fd6fa"),
        Vector("noise24.m4a", 26460, "2d591b02e0e49be508483384d5b7117fbdd940dd2e43cddb9b55d254d9868f70"),
        Vector("order30.m4a", 35280, "babef10b0486342410ee3e6ad882b689cb5fd753ab444084964169d64ba4e1d8"),
        Vector("order4.m4a", 35280, "babef10b0486342410ee3e6ad882b689cb5fd753ab444084964169d64ba4e1d8"),
        Vector("order8.m4a", 35280, "babef10b0486342410ee3e6ad882b689cb5fd753ab444084964169d64ba4e1d8"),
        Vector("quiet16.m4a", 52920, "8804f0aa109bc364a251bb45aff3001997a7da6abe805e84939eabe3baa62ae1"),
        Vector("silence16.m4a", 44100, "cb795d877d4e5e80602e1a75763e50d98df46a95daf1f5050781414b7665188c"),
        Vector("six16.m4a", 105840, "1ed3bc28266f432d1b2e4c30fc40dbbfa5814fdc4821ef23ed1187e090379539"),
        Vector("stereo16.m4a", 52920, "34a88826324ce4ad2a708bcaa6a6c3346c25335ba0cd4a026fa17de3500297f2"),
        Vector("stereo24.m4a", 72000, "29f9bf1feadeadc7b66cf4f886234eeeba49a49bc5dc4cd93cc11f1e914de688"),
        Vector("three16.m4a", 26460, "e4e2696974d358bbbfc7b02a6c1aeff1da118c76c07a4d0e83461de2e361405b"),
        Vector("verbatim16.m4a", 17640, "042c526a5900f2633bc5a162f37f52a17995b4429af03c10171a106d694b6f4b"),
        Vector("verbatim24.m4a", 52920, "f36cc639c5f753dd6fd8561e4d52a4fc4526a88d78848c0a2469514d835c3d4f"),
    )

    @Test
    fun everyFileDecodesToExactlyTheSoundThatWasEncoded() {
        for (vector in vectors) {
            val track = Mp4Track.read(javaClass.getResourceAsStream("/alac/${vector.file}")!!.readBytes())
            val decoder = AlacDecoder(AlacConfig.parse(track.setup))
            val pcm = ByteArrayOutputStream()
            val out = ByteArray(decoder.maxOutputBytes)
            for (frame in track.frames) {
                val frames = decoder.decode(frame)
                pcm.write(out, 0, decoder.writeLittleEndian(frames, out))
            }
            val bytes = pcm.toByteArray()
            assertEquals(vector.file, vector.bytes, bytes.size)
            assertEquals(vector.file, vector.sha256, sha256(bytes))
        }
    }

    @Test
    fun theSetupReadsFromItsBytesOrItsWholeBox() {
        val setup = setup(bitDepth = 24, channels = 2, sampleRate = 96_000)
        val bare = AlacConfig.parse(setup)
        assertEquals(4096, bare.frameLength)
        assertEquals(24, bare.bitDepth)
        assertEquals(2, bare.channels)
        assertEquals(96_000, bare.sampleRate)
        assertEquals(40, bare.historyMult)
        val boxed = AlacConfig.parse(byteArrayOf(0, 0, 0, 36, 'a'.code.toByte(), 'l'.code.toByte(), 'a'.code.toByte(), 'c'.code.toByte(), 0, 0, 0, 0) + setup)
        assertEquals(96_000, boxed.sampleRate)
        assertEquals(24, boxed.bitDepth)
    }

    @Test
    fun aSetupItCannotPlayIsRefused() {
        assertNull(AlacConfig.parseOrNull(setup(bitDepth = 8)))
        assertNull(AlacConfig.parseOrNull(setup(channels = 9)))
        assertNull(AlacConfig.parseOrNull(setup(channels = 0)))
        assertNull(AlacConfig.parseOrNull(setup(sampleRate = 0)))
        assertNull(AlacConfig.parseOrNull(setup().copyOf(20)))
        assertNotNull(AlacConfig.parseOrNull(setup(bitDepth = 20)))
        assertNotNull(AlacConfig.parseOrNull(setup(bitDepth = 32)))
    }

    // 20-bit samples come out in the top of 24 bits.
    @Test
    fun storedTwentyBitSamplesComeOutInTwentyFourBits() {
        val decoder = AlacDecoder(AlacConfig.parse(setup(bitDepth = 20, channels = 1)))
        val frame = Bits().apply {
            storedHeader(tag = 0, samples = 3)
            put(0x7FFFF, 20)
            put(0xFFFFF, 20)
            put(0x80000, 20)
            put(7, 3)
        }.bytes()
        assertEquals(3, decoder.decode(frame))
        assertEquals(listOf(0x7FFFF, -1, -0x80000), decoder.samples.take(3))
        val out = ByteArray(9)
        assertEquals(9, decoder.writeLittleEndian(3, out))
        assertArrayEquals(
            byteArrayOf(0xF0.toByte(), 0xFF.toByte(), 0x7F, 0xF0.toByte(), 0xFF.toByte(), 0xFF.toByte(), 0x00, 0x00, 0x80.toByte()),
            out,
        )
    }

    @Test
    fun storedThirtyTwoBitPairsKeepEveryBit() {
        val decoder = AlacDecoder(AlacConfig.parse(setup(bitDepth = 32, channels = 2)))
        val frame = Bits().apply {
            storedHeader(tag = 1, samples = 2)
            put(Int.MIN_VALUE.toLong() and 0xFFFF_FFFFL, 32)
            put(Int.MAX_VALUE.toLong(), 32)
            put(-2L and 0xFFFF_FFFFL, 32)
            put(5, 32)
            put(7, 3)
        }.bytes()
        assertEquals(2, decoder.decode(frame))
        assertEquals(listOf(Int.MIN_VALUE, Int.MAX_VALUE, -2, 5), decoder.samples.take(4))
        val floats = FloatArray(4)
        decoder.toFloats(2, floats)
        assertEquals(-1f, floats[0], 0f)
    }

    @Test
    fun dataAndFillElementsAreSkipped() {
        val decoder = AlacDecoder(AlacConfig.parse(setup(bitDepth = 16, channels = 1)))
        val frame = Bits().apply {
            // A data element: tag, instance, byte-aligned, two bytes.
            put(4, 3)
            put(0, 4)
            put(1, 1)
            put(2, 8)
            align()
            put(0xAB, 8)
            put(0xCD, 8)
            // A fill element of three bytes.
            put(6, 3)
            put(3, 4)
            put(0xFFFFFF, 24)
            storedHeader(tag = 0, samples = 2)
            put(1234, 16)
            put(-1234L and 0xFFFF, 16)
            put(7, 3)
        }.bytes()
        assertEquals(2, decoder.decode(frame))
        assertEquals(listOf(1234, -1234), decoder.samples.take(2))
    }

    @Test
    fun aChannelTheFrameLeavesOutIsSilent() {
        val decoder = AlacDecoder(AlacConfig.parse(setup(bitDepth = 16, channels = 2)))
        decoder.samples.fill(99)
        val frame = Bits().apply {
            storedHeader(tag = 0, samples = 2)
            put(100, 16)
            put(200, 16)
            put(7, 3)
        }.bytes()
        assertEquals(2, decoder.decode(frame))
        assertEquals(listOf(100, 0, 200, 0), decoder.samples.take(4))
    }

    @Test
    fun aDamagedFrameFailsInsteadOfPlayingNoise() {
        val decoder = AlacDecoder(AlacConfig.parse(setup(bitDepth = 16, channels = 1)))
        // Says it holds three samples but carries one.
        val short = Bits().apply {
            storedHeader(tag = 0, samples = 3)
            put(1, 16)
        }.bytes()
        assertThrows(AlacException::class.java) { decoder.decode(short) }
        // Longer than the setup's frames.
        val long = Bits().apply { storedHeader(tag = 0, samples = 5000) }.bytes()
        assertThrows(AlacException::class.java) { decoder.decode(long) }
        // An element kind ALAC files do not use.
        val unknown = Bits().apply { put(2, 3) }.bytes()
        assertThrows(AlacException::class.java) { decoder.decode(unknown) }
    }

    private fun setup(bitDepth: Int = 16, channels: Int = 2, sampleRate: Int = 44_100): ByteArray {
        val b = ByteArray(24)
        fun u32(at: Int, v: Int) {
            b[at] = (v ushr 24).toByte()
            b[at + 1] = (v ushr 16).toByte()
            b[at + 2] = (v ushr 8).toByte()
            b[at + 3] = v.toByte()
        }
        u32(0, 4096)
        b[4] = 0
        b[5] = bitDepth.toByte()
        b[6] = 40
        b[7] = 10
        b[8] = 14
        b[9] = channels.toByte()
        b[10] = 0
        b[11] = 255.toByte()
        u32(12, 0)
        u32(16, 0)
        u32(20, sampleRate)
        return b
    }

    private fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    // Writes bits most significant first.
    private class Bits {
        private val out = ByteArrayOutputStream()
        private var current = 0
        private var used = 0

        fun put(value: Long, count: Int) {
            for (i in count - 1 downTo 0) {
                current = (current shl 1) or ((value ushr i).toInt() and 1)
                if (++used == 8) {
                    out.write(current)
                    current = 0
                    used = 0
                }
            }
        }

        fun put(value: Int, count: Int) = put(value.toLong(), count)

        fun align() {
            while (used != 0) put(0, 1)
        }

        // An element holding `samples` samples stored as they are.
        fun storedHeader(tag: Int, samples: Int) {
            put(tag, 3)
            put(0, 4)
            put(0, 12)
            put(1, 1)
            put(0, 2)
            put(1, 1)
            put(samples.toLong(), 32)
        }

        fun bytes(): ByteArray {
            align()
            return out.toByteArray()
        }
    }
}

// The ALAC setup and frames of the first track of an MP4 file.
class Mp4Track(val setup: ByteArray, val frames: List<ByteArray>) {
    companion object {
        fun read(file: ByteArray): Mp4Track {
            val stbl = listOf("moov", "trak", "mdia", "minf", "stbl").fold(0 until file.size) { range, type -> child(file, range, type) }
            val stsd = child(file, stbl, "stsd")
            val setupAt = indexOf(file, "alac", stsd.first + 16, stsd.last + 1)
            val setup = file.copyOfRange(setupAt + 8, setupAt + 8 + 24)

            val stsz = child(file, stbl, "stsz")
            val fixed = u32(file, stsz.first + 4)
            val count = u32(file, stsz.first + 8)
            val sizes = List(count) { if (fixed != 0) fixed else u32(file, stsz.first + 12 + it * 4) }

            val stsc = child(file, stbl, "stsc")
            val runs = List(u32(file, stsc.first + 4)) { u32(file, stsc.first + 8 + it * 12) to u32(file, stsc.first + 12 + it * 12) }

            val stco = child(file, stbl, "stco")
            val offsets = List(u32(file, stco.first + 4)) { u32(file, stco.first + 8 + it * 4) }

            val frames = ArrayList<ByteArray>()
            for ((index, start) in offsets.withIndex()) {
                val chunk = index + 1
                val perChunk = runs.last { it.first <= chunk }.second
                var at = start
                repeat(perChunk) {
                    if (frames.size < sizes.size) {
                        val size = sizes[frames.size]
                        frames.add(file.copyOfRange(at, at + size))
                        at += size
                    }
                }
            }
            return Mp4Track(setup, frames)
        }

        // The payload of the first `type` box directly inside `range`.
        private fun child(file: ByteArray, range: IntRange, type: String): IntRange {
            var at = range.first
            while (at + 8 <= range.last + 1) {
                val size = u32(file, at)
                val name = String(file, at + 4, 4, Charsets.US_ASCII)
                if (name == type) return (at + 8) until (at + size)
                at += size
            }
            error("no $type box")
        }

        private fun indexOf(file: ByteArray, tag: String, from: Int, to: Int): Int {
            val bytes = tag.toByteArray(Charsets.US_ASCII)
            for (i in from until to - 4) if ((0 until 4).all { file[i + it] == bytes[it] }) return i
            error("no $tag")
        }

        private fun u32(b: ByteArray, at: Int): Int =
            ((b[at].toInt() and 0xFF) shl 24) or ((b[at + 1].toInt() and 0xFF) shl 16) or
                ((b[at + 2].toInt() and 0xFF) shl 8) or (b[at + 3].toInt() and 0xFF)
    }
}
