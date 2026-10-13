package app.winters.octo.sound

import java.io.IOException

// A frame or setup the ALAC decoder cannot read.
class AlacException(message: String) : IOException(message)

// An ALAC stream's setup: the 24 big-endian bytes an MP4 or CAF file keeps
// in its "alac" box. `historyMult`, `initialHistory` and `riceLimit` tune
// the entropy coder; the rest describe the sound.
class AlacConfig(
    val frameLength: Int,
    val bitDepth: Int,
    val historyMult: Int,
    val initialHistory: Int,
    val riceLimit: Int,
    val channels: Int,
    val maxRun: Int,
    val maxFrameBytes: Int,
    val avgBitRate: Int,
    val sampleRate: Int,
) {
    companion object {
        const val SIZE = 24

        // Reads the setup from its bare 24 bytes, or from a whole "alac" box
        // (12 bytes of box header first), which may follow a "frma" box.
        fun parse(bytes: ByteArray): AlacConfig {
            var at = 0
            if (boxAt(bytes, at) == "frma") at += u32(bytes, at).toInt().coerceAtLeast(8)
            if (boxAt(bytes, at) == "alac") at += 12
            if (bytes.size - at < SIZE) throw AlacException("ALAC setup has ${bytes.size - at} bytes, not $SIZE")
            val config = AlacConfig(
                frameLength = u32(bytes, at).coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
                bitDepth = u8(bytes, at + 5),
                historyMult = u8(bytes, at + 6),
                initialHistory = u8(bytes, at + 7),
                riceLimit = u8(bytes, at + 8),
                channels = u8(bytes, at + 9),
                maxRun = (u8(bytes, at + 10) shl 8) or u8(bytes, at + 11),
                maxFrameBytes = u32(bytes, at + 12).coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
                avgBitRate = u32(bytes, at + 16).coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
                sampleRate = u32(bytes, at + 20).coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
            )
            val version = u8(bytes, at + 4)
            if (version != 0) throw AlacException("ALAC version $version is not supported")
            if (config.bitDepth !in SUPPORTED_DEPTHS) throw AlacException("ALAC at ${config.bitDepth} bits is not supported")
            if (config.channels !in 1..MAX_CHANNELS) throw AlacException("ALAC with ${config.channels} channels is not supported")
            if (config.frameLength !in 1..MAX_FRAME_LENGTH) throw AlacException("ALAC frames of ${config.frameLength} samples are not supported")
            if (config.sampleRate <= 0) throw AlacException("ALAC setup has no sample rate")
            return config
        }

        fun parseOrNull(bytes: ByteArray): AlacConfig? = try {
            parse(bytes)
        } catch (_: AlacException) {
            null
        }

        private fun boxAt(bytes: ByteArray, at: Int): String? =
            if (bytes.size >= at + 12) String(bytes, at + 4, 4, Charsets.US_ASCII) else null

        private fun u8(bytes: ByteArray, at: Int): Int = bytes[at].toInt() and 0xFF

        private fun u32(bytes: ByteArray, at: Int): Long =
            (u8(bytes, at).toLong() shl 24) or (u8(bytes, at + 1).toLong() shl 16) or
                (u8(bytes, at + 2).toLong() shl 8) or u8(bytes, at + 3).toLong()
    }
}

private val SUPPORTED_DEPTHS = setOf(16, 20, 24, 32)
private const val MAX_CHANNELS = 8
private const val MAX_FRAME_LENGTH = 1 shl 16

// Element tags in a frame.
private const val ID_SCE = 0
private const val ID_CPE = 1
private const val ID_LFE = 3
private const val ID_DSE = 4
private const val ID_FIL = 6
private const val ID_END = 7

// Where each channel of a frame goes in the output, by channel count. A
// frame carries its channels center first (C L R ...); the output follows
// Android's order (L R C LFE back-left back-right ...).
private val CHANNEL_ORDER = arrayOf(
    intArrayOf(0),
    intArrayOf(0, 1),
    intArrayOf(2, 0, 1),
    intArrayOf(2, 0, 1, 3),
    intArrayOf(2, 0, 1, 3, 4),
    intArrayOf(2, 0, 1, 4, 5, 3),
    intArrayOf(2, 0, 1, 4, 5, 6, 3),
    intArrayOf(2, 6, 7, 0, 1, 4, 5, 3),
)

// The adaptive Golomb coder's constants.
private const val QB_SHIFT = 9
private const val QB = 1 shl QB_SHIFT
private const val MMUL_SHIFT = 2
private const val MDEN_SHIFT = QB_SHIFT - MMUL_SHIFT - 1
private const val MOFF = 1 shl (MDEN_SHIFT - 2)
private const val BIT_OFF = 24
private const val MAX_PREFIX = 9
private const val RUN_ESCAPE_BITS = 16
private const val MEAN_CLAMP = 0xFFFF

// Decodes Apple Lossless (ALAC) frames into PCM, exactly: every sample
// comes out as it went in. One frame at a time, from the frame's bytes;
// `samples` then holds that frame's samples, interleaved in output channel
// order, as signed values of the stream's bit depth.
class AlacDecoder(val config: AlacConfig) {
    val channels = config.channels

    // Bytes each sample takes in the output: 2, 3 for 20- and 24-bit
    // (20-bit sits in the top of 24), or 4.
    val bytesPerSample = when (config.bitDepth) {
        16 -> 2
        20, 24 -> 3
        else -> 4
    }

    val samples = IntArray(config.frameLength * channels)

    private val frameLength = config.frameLength
    private val order = CHANNEL_ORDER[channels - 1]
    private val mix = Array(2) { IntArray(frameLength) }
    private val shifted = Array(2) { IntArray(frameLength) }
    private val predictor = IntArray(frameLength)
    private val coefs = Array(2) { IntArray(32) }
    private val modes = IntArray(2)
    private val denShifts = IntArray(2)
    private val pbFactors = IntArray(2)
    private val coefCounts = IntArray(2)
    private val bits = Bits()

    // The most bytes one frame can decode to.
    val maxOutputBytes: Int get() = frameLength * channels * bytesPerSample

    // Decodes one frame and returns how many samples each channel got.
    fun decode(packet: ByteArray, offset: Int = 0, length: Int = packet.size - offset): Int {
        bits.reset(packet, offset, length)
        var channel = 0
        var frameSamples = -1
        elements@ while (channel < channels) {
            when (val tag = bits.read(3)) {
                ID_SCE, ID_LFE -> {
                    frameSamples = element(1, channel, frameSamples)
                    channel += 1
                }
                ID_CPE -> {
                    if (channel + 2 > channels) break@elements
                    frameSamples = element(2, channel, frameSamples)
                    channel += 2
                }
                ID_DSE -> skipData()
                ID_FIL -> skipFill()
                ID_END -> break@elements
                else -> throw AlacException("ALAC element $tag is not supported")
            }
        }
        if (frameSamples < 0) return 0
        // Channels a frame leaves out are silent.
        for (missing in channel until channels) {
            val out = order[missing]
            for (i in 0 until frameSamples) samples[i * channels + out] = 0
        }
        return frameSamples
    }

    // Writes the last frame's `frames` samples per channel as little-endian
    // PCM into `out` from `at`, and returns the bytes written.
    fun writeLittleEndian(frames: Int, out: ByteArray, at: Int = 0): Int {
        val count = frames * channels
        var p = at
        when (config.bitDepth) {
            16 -> for (i in 0 until count) {
                val v = samples[i]
                out[p++] = v.toByte()
                out[p++] = (v shr 8).toByte()
            }
            20, 24 -> {
                val up = if (config.bitDepth == 20) 4 else 0
                for (i in 0 until count) {
                    val v = samples[i] shl up
                    out[p++] = v.toByte()
                    out[p++] = (v shr 8).toByte()
                    out[p++] = (v shr 16).toByte()
                }
            }
            else -> for (i in 0 until count) {
                val v = samples[i]
                out[p++] = v.toByte()
                out[p++] = (v shr 8).toByte()
                out[p++] = (v shr 16).toByte()
                out[p++] = (v shr 24).toByte()
            }
        }
        return p - at
    }

    // The last frame's `frames` samples per channel as floats from -1 to 1.
    fun toFloats(frames: Int, out: FloatArray) {
        val scale = 1f / (1L shl (config.bitDepth - 1)).toFloat()
        for (i in 0 until frames * channels) out[i] = samples[i] * scale
    }

    // One element: a single channel (`count` 1) or a pair (2), starting at
    // frame channel `first`. Returns its sample count, which must match the
    // frame's other elements.
    private fun element(count: Int, first: Int, expected: Int): Int {
        bits.skip(4)
        if (bits.read(12) != 0) throw AlacException("ALAC element header is damaged")
        val partial = bits.read(1) != 0
        val bytesShifted = bits.read(2)
        val verbatim = bits.read(1) != 0
        val numSamples = if (partial) bits.readUnsigned(32) else frameLength.toLong()
        if (numSamples > frameLength) throw AlacException("ALAC frame of $numSamples samples is longer than $frameLength")
        val n = numSamples.toInt()
        if (expected >= 0 && n != expected) throw AlacException("ALAC frame's channels differ in length")

        var shift = bytesShifted * 8
        var mixBits = 0
        var mixRes = 0
        if (!verbatim) {
            val chanBits = config.bitDepth - shift + (count - 1)
            if (chanBits !in 1..32) throw AlacException("ALAC frame shifts away every bit")
            mixBits = bits.read(8)
            mixRes = bits.read(8).toByte().toInt()
            if (count == 2 && mixRes != 0 && mixBits > 31) throw AlacException("ALAC stereo mix is damaged")
            for (c in 0 until count) {
                val head = bits.read(8)
                modes[c] = head ushr 4
                denShifts[c] = head and 0xF
                val rice = bits.read(8)
                pbFactors[c] = rice ushr 5
                coefCounts[c] = rice and 0x1F
                for (i in 0 until coefCounts[c]) coefs[c][i] = bits.read(16).toShort().toInt()
            }
            // The low bytes shifted off each sample come first, the coded
            // samples after them.
            val shiftedAt = bits.position
            if (shift != 0) bits.skip(shift.toLong() * count * n)
            for (c in 0 until count) {
                residuals(n, chanBits, pbFactors[c])
                if (modes[c] != 0) predict(predictor, predictor, n, null, 31, chanBits, 0)
                predict(predictor, mix[c], n, coefs[c], coefCounts[c], chanBits, denShifts[c])
            }
            if (shift != 0) {
                val end = bits.position
                bits.position = shiftedAt
                for (i in 0 until n) for (c in 0 until count) shifted[c][i] = bits.read(shift)
                bits.position = end
            }
        } else {
            // Samples stored as they are, interleaved.
            val chanBits = if (count == 1) config.bitDepth - shift else config.bitDepth
            if (chanBits !in 1..32) throw AlacException("ALAC frame shifts away every bit")
            for (i in 0 until n) for (c in 0 until count) mix[c][i] = signExtend(bits.read(chanBits), chanBits)
            shift = 0
        }

        val outU = order[first]
        if (count == 1) {
            val u = mix[0]
            val su = shifted[0]
            for (i in 0 until n) samples[i * channels + outU] = sample(u[i], shift, su[i])
        } else {
            val outV = order[first + 1]
            val u = mix[0]
            val v = mix[1]
            val su = shifted[0]
            val sv = shifted[1]
            for (i in 0 until n) {
                var left = u[i]
                var right = v[i]
                if (mixRes != 0) {
                    left = u[i] + v[i] - ((mixRes * v[i]) shr mixBits)
                    right = left - v[i]
                }
                samples[i * channels + outU] = sample(left, shift, su[i])
                samples[i * channels + outV] = sample(right, shift, sv[i])
            }
        }
        return n
    }

    // A decoded value with its shifted-off low bits put back, as a signed
    // value of the stream's bit depth.
    private fun sample(value: Int, shift: Int, low: Int): Int {
        val whole = if (shift != 0) (value shl shift) or low else value
        return signExtend(whole, config.bitDepth)
    }

    // The coded prediction errors of one channel, into `predictor`: an
    // adaptive Golomb code whose parameter follows the running mean, with
    // runs of zeros coded as one count when the mean falls low.
    private fun residuals(numSamples: Int, chanBits: Int, pbFactor: Int) {
        val out = predictor
        val pb = (config.historyMult * pbFactor) / 4
        val kb = config.riceLimit
        if (kb == 0) throw AlacException("ALAC setup has no Rice limit")
        val wb = (1 shl kb) - 1
        // The running mean, kept as an unsigned 32-bit value.
        var mb = config.initialHistory
        var zmode = 0
        var c = 0
        while (c < numSamples) {
            var k = 31 - Integer.numberOfLeadingZeros((mb ushr QB_SHIFT) + 3)
            if (k > kb) k = kb
            val m = (1 shl k) - 1
            val n = sampleCode(m, k, chanBits)
            val folded = n + zmode
            val magnitude = ((folded + 1) ushr 1).toInt()
            out[c++] = if (folded and 1L != 0L) -magnitude else magnitude
            mb = pb * folded.toInt() + mb - ((pb * mb) ushr QB_SHIFT)
            if (n > MEAN_CLAMP) mb = MEAN_CLAMP
            zmode = 0
            if (Integer.compareUnsigned(mb shl MMUL_SHIFT, QB) < 0 && c < numSamples) {
                zmode = 1
                val runK = Integer.numberOfLeadingZeros(mb) - BIT_OFF + ((mb + MOFF) ushr MDEN_SHIFT)
                val mz = ((1 shl runK) - 1) and wb
                val run = runCode(mz, runK)
                if (c + run > numSamples) throw AlacException("ALAC run of silence goes past the frame")
                for (j in 0 until run) out[c++] = 0
                if (run >= 65535) zmode = 0
                mb = 0
            }
        }
    }

    // One coded value: a unary prefix of up to 8 ones, then k-1 or k bits,
    // or, after 9 ones, the value itself in `escapeBits` bits.
    private fun sampleCode(m: Int, k: Int, escapeBits: Int): Long {
        val prefix = Integer.numberOfLeadingZeros(bits.peek(32).inv())
        if (prefix >= MAX_PREFIX) {
            bits.skip(MAX_PREFIX.toLong())
            return bits.readUnsigned(escapeBits)
        }
        bits.skip(prefix + 1L)
        if (k == 1) return prefix.toLong()
        val v = bits.peek(k)
        var result = prefix.toLong() * m
        if (v >= 2) {
            result += v - 1
            bits.skip(k.toLong())
        } else {
            bits.skip(k - 1L)
        }
        return result
    }

    // The length of a run of zeros, coded like a value with a 16-bit escape.
    private fun runCode(m: Int, k: Int): Int {
        val prefix = Integer.numberOfLeadingZeros(bits.peek(32).inv())
        if (prefix >= MAX_PREFIX) {
            bits.skip(MAX_PREFIX.toLong())
            return bits.read(RUN_ESCAPE_BITS)
        }
        bits.skip(prefix + 1L)
        val v = bits.peek(k)
        if (v < 2) {
            bits.skip(k - 1L)
            return prefix * m
        }
        bits.skip(k.toLong())
        return prefix * m + v - 1
    }

    // The adaptive predictor: rebuilds samples from prediction errors in
    // `input` into `output` (which may be the same array only for the
    // first-order case, `active` 31), adapting its coefficients as it goes.
    private fun predict(input: IntArray, output: IntArray, num: Int, coefs: IntArray?, active: Int, chanBits: Int, denShift: Int) {
        if (num == 0) return
        val chanShift = 32 - chanBits
        output[0] = input[0]
        if (active == 0) {
            if (input !== output) System.arraycopy(input, 1, output, 1, num - 1)
            return
        }
        if (active == 31) {
            var prev = output[0]
            for (j in 1 until num) {
                prev = ((input[j] + prev) shl chanShift) shr chanShift
                output[j] = prev
            }
            return
        }
        val a = coefs!!
        val denHalf = if (denShift > 0) 1 shl (denShift - 1) else 0
        val lim = active + 1
        for (j in 1 until minOf(lim, num)) output[j] = ((input[j] + output[j - 1]) shl chanShift) shr chanShift
        for (j in lim until num) {
            val top = output[j - lim]
            var sum = 0
            for (k in 0 until active) sum += a[k] * (output[j - 1 - k] - top)
            var del = input[j]
            var del0 = del
            val sign = Integer.signum(del)
            del += top + ((sum + denHalf) shr denShift)
            output[j] = (del shl chanShift) shr chanShift
            if (sign > 0) {
                for (k in active - 1 downTo 0) {
                    val dd = top - output[j - 1 - k]
                    val sgn = Integer.signum(dd)
                    a[k] = (a[k] - sgn).toShort().toInt()
                    del0 -= (active - k) * ((sgn * dd) shr denShift)
                    if (del0 <= 0) break
                }
            } else if (sign < 0) {
                for (k in active - 1 downTo 0) {
                    val dd = top - output[j - 1 - k]
                    val sgn = Integer.signum(dd)
                    a[k] = (a[k] + sgn).toShort().toInt()
                    del0 -= (active - k) * ((-sgn * dd) shr denShift)
                    if (del0 >= 0) break
                }
            }
        }
    }

    // A data element: skipped.
    private fun skipData() {
        bits.skip(4)
        val aligned = bits.read(1) != 0
        var count = bits.read(8)
        if (count == 255) count += bits.read(8)
        if (aligned) bits.alignToByte()
        bits.skip(count * 8L)
    }

    // A fill element: skipped.
    private fun skipFill() {
        var count = bits.read(4)
        if (count == 15) count += bits.read(8) - 1
        bits.skip(count * 8L)
    }

    private fun signExtend(value: Int, width: Int): Int = if (width >= 32) value else (value shl (32 - width)) shr (32 - width)

    // Reads a frame's bits, most significant first. Peeking past the end
    // sees zeros; moving past it fails.
    private class Bits {
        private var data = ByteArray(0)
        private var start = 0
        private var size = 0
        private var end = 0L
        var position = 0L

        fun reset(bytes: ByteArray, offset: Int, length: Int) {
            data = bytes
            start = offset
            size = length
            end = length * 8L
            position = 0L
        }

        // The next `n` bits (1 to 32) without moving.
        fun peek(n: Int): Int {
            val byte = (position ushr 3).toInt()
            val off = (position and 7).toInt()
            var window = 0L
            for (i in 0 until 5) window = (window shl 8) or byteAt(byte + i)
            return (((window shl off) and 0xFF_FFFF_FFFFL) ushr (40 - n)).toInt()
        }

        fun read(n: Int): Int {
            val v = peek(n)
            skip(n.toLong())
            return v
        }

        fun readUnsigned(n: Int): Long = read(n).toLong() and 0xFFFF_FFFFL

        fun skip(n: Long) {
            position += n
            if (position > end) throw AlacException("ALAC frame ends early")
        }

        fun alignToByte() {
            skip((8 - (position and 7)) and 7)
        }

        private fun byteAt(i: Int): Long = if (i < size) (data[start + i].toLong() and 0xFF) else 0L
    }
}
