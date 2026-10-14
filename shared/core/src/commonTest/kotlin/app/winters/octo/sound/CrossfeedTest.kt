package app.winters.octo.sound

import java.io.File
import kotlin.math.abs
import kotlin.math.pow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.add
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// The crossfeed filter, and crossfeed-vectors.json, which the audio
// engine's Rust copy of the filter checks too.
//
// OCTO_WRITE_CROSSFEED_VECTORS=<path> writes a fresh file instead of
// checking it.
class CrossfeedTest {
    private val impulseLength = 16
    private val frequencies = doubleArrayOf(20.0, 100.0, 300.0, 700.0, 1_000.0, 2_000.0, 5_000.0, 10_000.0, 20_000.0)
    private val rates = intArrayOf(44_100, 48_000)

    // Every preset, and a custom one at its own values.
    private val settings = listOf(
        Crossfeed(on = true, preset = CrossfeedPreset.Natural),
        Crossfeed(on = true, preset = CrossfeedPreset.ChuMoy),
        Crossfeed(on = true, preset = CrossfeedPreset.JanMeier),
        Crossfeed(on = true, preset = CrossfeedPreset.Custom, cutHz = 1_200, feedDb = 3f),
    )

    // Runs `left` and `right` through a filter that is fully on.
    private fun run(c: CrossfeedCoefficients, left: FloatArray, right: FloatArray): Pair<FloatArray, FloatArray> {
        val filter = CrossfeedFilter()
        filter.set(c, on = true, frames = 0)
        val samples = FloatArray(left.size * 2) { if (it % 2 == 0) left[it / 2] else right[it / 2] }
        filter.process(samples, left.size, 2)
        return FloatArray(left.size) { samples[it * 2] } to FloatArray(left.size) { samples[it * 2 + 1] }
    }

    @Test
    fun thePresetsAreTheKnownOnes() {
        assertEquals(700 to 4.5f, CrossfeedPreset.Natural.cutHz to CrossfeedPreset.Natural.feedDb)
        assertEquals(700 to 6f, CrossfeedPreset.ChuMoy.cutHz to CrossfeedPreset.ChuMoy.feedDb)
        assertEquals(650 to 9.5f, CrossfeedPreset.JanMeier.cutHz to CrossfeedPreset.JanMeier.feedDb)
        // Custom takes the listener's values, kept inside the ranges.
        val custom = Crossfeed(preset = CrossfeedPreset.Custom, cutHz = 5_000, feedDb = 0f)
        assertEquals(CROSSFEED_MAX_CUT_HZ, custom.activeCutHz)
        assertEquals(CROSSFEED_MIN_FEED_DB, custom.activeFeedDb)
        // A preset ignores them.
        assertEquals(650, Crossfeed(preset = CrossfeedPreset.JanMeier, cutHz = 1_500).activeCutHz)
    }

    @Test
    fun soundInTheMiddlePassesThroughExactly() {
        val c = crossfeedCoefficients(Crossfeed(preset = CrossfeedPreset.JanMeier), 44_100)
        val tone = FloatArray(2_000) { if (it % 7 < 3) 1f else -1f }
        val (left, right) = run(c, tone, tone.copyOf())
        assertTrue(left.contentEquals(tone))
        assertTrue(right.contentEquals(tone))
    }

    @Test
    fun theBassReachesTheOtherEarAtTheFeedLevel() {
        for (crossfeed in settings) {
            val c = crossfeedCoefficients(crossfeed, 48_000)
            val (own, other) = crossfeedResponseDb(c, 5.0, 48_000)
            assertEquals(crossfeed.toString(), crossfeed.activeFeedDb.toDouble(), own - other, 0.05)
            // The other ear's low-pass is 3 dB down at the cut frequency.
            val (_, atCut) = crossfeedResponseDb(c, crossfeed.activeCutHz.toDouble(), 48_000)
            assertEquals(crossfeed.toString(), other - 3.0, atCut, 0.2)
            // The ear's own side is nearly untouched high up.
            assertEquals(0.0, crossfeedResponseDb(c, 16_000.0, 48_000).first, 0.5)
        }
    }

    @Test
    fun aSideOnItsOwnNeverComesOutLouder() {
        for (crossfeed in settings) {
            val c = crossfeedCoefficients(crossfeed, 44_100)
            for (hz in frequencies) {
                val (own, other) = crossfeedResponseDb(c, hz, 44_100)
                assertTrue("$crossfeed at $hz", own <= 1e-9 && other < own)
            }
        }
    }

    @Test
    fun turningItOnFadesItIn() {
        val c = crossfeedCoefficients(Crossfeed(preset = CrossfeedPreset.ChuMoy), 48_000)
        val filter = CrossfeedFilter()
        assertFalse(filter.active)
        filter.set(c, on = true, frames = 100)
        assertTrue(filter.active)
        val samples = FloatArray(400) { if (it % 2 == 0) 1f else 0f }
        filter.process(samples, 200, 2)
        // The right ear's share grows from nothing as the filter fades in.
        assertTrue(samples[1] < samples[101] && samples[101] < samples[201])
        filter.set(c, on = false, frames = 0)
        assertFalse(filter.active)
        val after = FloatArray(4) { 0.5f }
        filter.process(after, 2, 2)
        assertTrue(after.all { it == 0.5f })
    }

    @Test
    fun aSpeakerPlaysWithoutIt() {
        val on = SoundSettings(crossfeed = Crossfeed(on = true))
        assertFalse(on.heardOn(headphones = false).crossfeed.on)
        assertTrue(on.heardOn(headphones = true).crossfeed.on)
        assertTrue(on.heardOn(headphones = true) === on)
    }

    @Test
    fun oldSettingsReadWithItOff() {
        val json = Json { ignoreUnknownKeys = true; encodeDefaults = false }
        val old = json.decodeFromString(SoundSettings.serializer(), """{"eqEnabled":true}""")
        assertEquals(Crossfeed(), old.crossfeed)
        assertFalse("crossfeed" in json.encodeToString(SoundSettings.serializer(), old))
        val custom = SoundSettings(crossfeed = Crossfeed(on = true, preset = CrossfeedPreset.Custom, cutHz = 900, feedDb = 7f))
        assertEquals(custom, json.decodeFromString(SoundSettings.serializer(), json.encodeToString(SoundSettings.serializer(), custom)))
    }

    @Test
    fun everyVectorMatches() {
        val target = System.getenv("OCTO_WRITE_CROSSFEED_VECTORS")
        if (!target.isNullOrBlank()) {
            File(target).writeText(Json { prettyPrint = true }.encodeToString(JsonElement.serializer(), write()) + "\n")
            return
        }
        val file = javaClass.classLoader!!.getResource("crossfeed-vectors.json")!!.readText()
        val vectors = Json.parseToJsonElement(file).jsonObject
        val tolerances = vectors.getValue("tolerances").jsonObject
        fun tolerance(name: String) = tolerances.getValue(name).jsonPrimitive.double
        val failures = mutableListOf<String>()
        fun near(what: String, got: Double, want: Double, within: Double) {
            if (abs(got - want) > within) failures += "$what: $got, want $want"
        }
        for (case in vectors.getValue("cases").jsonArray) {
            val o = case.jsonObject
            val cut = o.getValue("cutHz").jsonPrimitive.double
            val feed = o.getValue("feedDb").jsonPrimitive.double
            val rate = o.getValue("rate").jsonPrimitive.int
            val name = "${o.getValue("preset").jsonPrimitive.content} at $rate"
            val c = crossfeedCoefficients(cut, feed, rate)
            near("$name gain", c.gain, o.getValue("gain").jsonPrimitive.double, tolerance("coefficient"))
            near("$name pole", c.pole, o.getValue("pole").jsonPrimitive.double, tolerance("coefficient"))
            val impulse = o.getValue("impulse").jsonObject
            val own = impulse.getValue("own").jsonArray.map { it.jsonPrimitive.double }
            val other = impulse.getValue("other").jsonArray.map { it.jsonPrimitive.double }
            val left = FloatArray(own.size).also { it[0] = 1f }
            val (gotOwn, gotOther) = run(c, left, FloatArray(own.size))
            for (n in own.indices) {
                near("$name own[$n]", gotOwn[n].toDouble(), own[n], tolerance("floatSample"))
                near("$name other[$n]", gotOther[n].toDouble(), other[n], tolerance("floatSample"))
            }
            for (point in o.getValue("response").jsonArray) {
                val p = point.jsonObject
                val hz = p.getValue("hz").jsonPrimitive.double
                val (ownDb, otherDb) = crossfeedResponseDb(c, hz, rate)
                near("$name own dB at $hz", ownDb, p.getValue("ownDb").jsonPrimitive.double, tolerance("db"))
                near("$name other dB at $hz", otherDb, p.getValue("otherDb").jsonPrimitive.double, tolerance("db"))
            }
        }
        assertTrue(failures.joinToString("\n"), failures.isEmpty())
    }

    private fun write(): JsonObject = buildJsonObject {
        putJsonArray("about") {
            add("Headphone crossfeed: the Kotlin tests (CrossfeedTest) and the audio engine's Rust tests both check these.")
            add("pole = exp(-2 pi cutHz / rate); feed = 10^(-feedDb / 20); gain = feed / (1 + feed) * (1 - pole).")
            add("Per frame: d = gain * (R - L) + pole * d_prev (d starts at 0, kept in doubles); L' = L + d; R' = R - d.")
            add("impulse: L = 1 at frame 0 and 0 after, R = 0 throughout; own is L' and other is R' (own[0] = 1 - gain, own[n] = -gain pole^n, other[n] = gain pole^n). Samples are 32-bit floats in and out.")
            add("response: the size in dB of one side's sound in its own ear (1 - gain / (1 - pole e^-jw)) and in the other ear (gain / (1 - pole e^-jw)), w = 2 pi hz / rate.")
            add("Presets: Natural 700 Hz 4.5 dB, Chu Moy 700 Hz 6 dB, Jan Meier 650 Hz 9.5 dB; Custom takes cutHz 300 to 2000 and feedDb 1 to 15.")
        }
        putJsonObject("tolerances") {
            put("coefficient", 1e-12)
            put("db", 1e-9)
            put("floatSample", 1e-6)
        }
        putJsonArray("cases") {
            for (crossfeed in settings) {
                for (rate in rates) {
                    val c = crossfeedCoefficients(crossfeed, rate)
                    addJsonObject {
                        put("preset", crossfeed.preset.name)
                        put("cutHz", crossfeed.activeCutHz)
                        put("feedDb", crossfeed.activeFeedDb.toDouble())
                        put("rate", rate)
                        put("gain", c.gain)
                        put("pole", c.pole)
                        putJsonObject("impulse") {
                            putJsonArray("own") { for (n in 0 until impulseLength) add(if (n == 0) 1 - c.gain else -c.gain * c.pole.pow(n)) }
                            putJsonArray("other") { for (n in 0 until impulseLength) add(c.gain * c.pole.pow(n)) }
                        }
                        putJsonArray("response") {
                            for (hz in frequencies) {
                                val (own, other) = crossfeedResponseDb(c, hz, rate)
                                addJsonObject {
                                    put("hz", hz)
                                    put("ownDb", own)
                                    put("otherDb", other)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
