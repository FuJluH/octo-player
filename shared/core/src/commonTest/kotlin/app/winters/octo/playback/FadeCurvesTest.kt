package app.winters.octo.playback

import java.io.File
import kotlin.math.abs
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.add
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

// The crossfade curves, and fade-curve-vectors.json, which the audio
// engine's Rust copy of the curves checks too.
//
// OCTO_WRITE_FADE_VECTORS=<path> writes a fresh file instead of checking it.
class FadeCurvesTest {
    private val points = doubleArrayOf(0.0, 0.01, 0.0375, 0.05, 0.1, 0.25, 0.4, 0.5, 0.6, 0.75, 0.9, 0.95, 0.9625, 0.975, 0.99, 1.0)

    // Every curve over 8 s, and mix only over a blend short enough that
    // its edges take half of it each.
    private val cases = FadeCurve.entries.map { it to 8_000.0 } + (FadeCurve.MixOnly to 400.0)

    @Test
    fun equalPowerIsTheCrossfadeAsItWas() {
        for (i in 0..100) {
            val t = i / 100.0
            assertEquals(automixOutGain(t, 0.0), fadeOutGain(FadeCurve.EqualPower, t, 8_000.0), 0.0)
            assertEquals(automixInGain(t, 0.0), fadeInGain(FadeCurve.EqualPower, t, 8_000.0), 0.0)
        }
        val plan = fixedCrossfadePlan(200_000, 8_000, "test")
        assertEquals(FadeCurve.EqualPower, plan.curve)
        assertEquals(0.0, plan.headroomDb, 0.0)
        assertEquals(automixOutGain(0.3, 0.0), plan.outGain(0.3), 0.0)
    }

    @Test
    fun everyCurveStartsWithTheOldSongAndEndsWithTheNewOne() {
        for ((curve, overlap) in cases) {
            assertEquals("$curve out at 0", 1.0, fadeOutGain(curve, 0.0, overlap), 1e-12)
            assertEquals("$curve in at 0", 0.0, fadeInGain(curve, 0.0, overlap), 1e-12)
            assertEquals("$curve out at 1", 0.0, fadeOutGain(curve, 1.0, overlap), 1e-12)
            assertEquals("$curve in at 1", 1.0, fadeInGain(curve, 1.0, overlap), 1e-12)
        }
    }

    @Test
    fun noCurveRaisesASongAndEachMovesOneWay() {
        for ((curve, overlap) in cases) {
            var lastOut = 1.0
            var lastIn = 0.0
            for (i in 0..1_000) {
                val t = i / 1_000.0
                val (out, inGain) = fadeGains(curve, t, overlap)
                assertTrue("$curve at $t", out in 0.0..1.0 && inGain in 0.0..1.0)
                assertTrue("$curve out rises at $t", out <= lastOut + 1e-12)
                assertTrue("$curve in falls at $t", inGain >= lastIn - 1e-12)
                lastOut = out
                lastIn = inGain
            }
        }
    }

    @Test
    fun theCurvesHaveTheirShapes() {
        assertEquals(0.5, fadeOutGain(FadeCurve.Linear, 0.5, 8_000.0), 1e-12)
        // Power-complementary: the squares add up to one all the way.
        for (t in points) {
            val (out, inGain) = fadeGains(FadeCurve.SCurve, t, 8_000.0)
            assertEquals(1.0, out * out + inGain * inGain, 1e-9)
        }
        // The S curve holds the old song near full for its first fifth.
        assertTrue(fadeOutGain(FadeCurve.SCurve, 0.2, 8_000.0) > 0.95)
        // Even in loudness: the same number of decibels down at every step.
        val db = { t: Double -> 20 * kotlin.math.log10(fadeOutGain(FadeCurve.EvenLoudness, t, 8_000.0)) }
        assertEquals(EVEN_LOUDNESS_FLOOR_DB / 2, db(EVEN_LOUDNESS_FLOOR_AT / 2), 1e-9)
        assertEquals(db(0.2) - db(0.1), db(0.6) - db(0.5), 1e-9)
        assertEquals(EVEN_LOUDNESS_FLOOR_DB, db(EVEN_LOUDNESS_FLOOR_AT), 1e-9)
        assertEquals(fadeOutGain(FadeCurve.EvenLoudness, 0.3, 8_000.0), fadeInGain(FadeCurve.EvenLoudness, 0.7, 8_000.0), 1e-15)
    }

    @Test
    fun mixOnlyPlaysBothSongsFullAndFadesOnlyTheEdges() {
        // 300 ms of an 8 s blend is 0.0375 of it.
        assertEquals(1.0, fadeInGain(FadeCurve.MixOnly, 0.0375, 8_000.0), 1e-12)
        assertTrue(fadeInGain(FadeCurve.MixOnly, 0.02, 8_000.0) < 1.0)
        assertEquals(1.0, fadeOutGain(FadeCurve.MixOnly, 0.9625, 8_000.0), 1e-12)
        assertTrue(fadeOutGain(FadeCurve.MixOnly, 0.98, 8_000.0) < 1.0)
        for (t in listOf(0.1, 0.5, 0.9)) {
            assertEquals(1.0 to 1.0, fadeGains(FadeCurve.MixOnly, t, 8_000.0))
        }
        // A blend shorter than both edges splits itself between them.
        assertEquals(1.0, fadeInGain(FadeCurve.MixOnly, 0.5, 400.0), 1e-12)
        assertEquals(1.0, fadeOutGain(FadeCurve.MixOnly, 0.5, 400.0), 1e-12)
        assertEquals(MIX_ONLY_HEADROOM_DB, fixedCrossfadePlan(200_000, 8_000, "test", FadeCurve.MixOnly).headroomDb, 0.0)
    }

    @Test
    fun theCurveShapesOnlyTheCrossfadeWithSmartTransitionsOff() {
        val a = FadeSong("a", 1, 200_000)
        val b = FadeSong("b", 1, 180_000)
        val fixed = planTransition(a, b, null, null, AutomixSettings(8_000, smart = false, fadeCurve = FadeCurve.Linear))
        assertEquals(TransitionKind.CROSSFADE, fixed.kind)
        assertEquals(FadeCurve.Linear, fixed.curve)
        assertEquals(0.75, fixed.outGain(0.25), 1e-12)
        assertEquals(0.25, fixed.inGain(0.25), 1e-12)
        // Smart transitions keep their own curves.
        val planned = planTransition(a, b, null, null, AutomixSettings(8_000, smart = true, fadeCurve = FadeCurve.Linear))
        assertEquals(FadeCurve.EqualPower, planned.curve)
        assertEquals(automixOutGain(0.25, planned.k), planned.outGain(0.25), 0.0)
    }

    @Test
    fun theCurveRowSaysWhyItCannotBeChosenAndWhichSwitchFreesIt() {
        val smart = curveRowLook(FadeCurve.Linear, smartTransitions = true)
        assertEquals(false, smart.choosable)
        assertEquals(SMART_CURVE_VALUE, smart.value)
        // The reason names the switch by the title it has on the page.
        assertTrue(smart.helper.contains("Turn off Smart transitions"))
        assertTrue(!smart.helper.contains("Automix"))
        val chosen = curveRowLook(FadeCurve.Linear, smartTransitions = false)
        assertEquals(CurveRowLook(choosable = true, value = "Linear", helper = FadeCurve.Linear.detail), chosen)
    }

    @Test
    fun everyVectorMatches() {
        val target = System.getenv("OCTO_WRITE_FADE_VECTORS")
        if (!target.isNullOrBlank()) {
            File(target).writeText(Json { prettyPrint = true }.encodeToString(JsonElement.serializer(), write()) + "\n")
            return
        }
        val file = javaClass.classLoader!!.getResource("fade-curve-vectors.json")!!.readText()
        val vectors = Json.parseToJsonElement(file).jsonObject
        val tolerance = vectors.getValue("tolerance").jsonPrimitive.double
        val failures = mutableListOf<String>()
        val written = vectors.getValue("cases").jsonArray
        assertEquals(cases.size, written.size)
        for (case in written) {
            val o = case.jsonObject
            val curve = FadeCurve.valueOf(o.getValue("curve").jsonPrimitive.content)
            val overlap = o.getValue("overlapMs").jsonPrimitive.double
            for (point in o.getValue("points").jsonArray) {
                val p = point.jsonObject
                val t = p.getValue("t").jsonPrimitive.double
                val (out, inGain) = fadeGains(curve, t, overlap)
                val wantOut = p.getValue("out").jsonPrimitive.double
                val wantIn = p.getValue("in").jsonPrimitive.double
                if (abs(out - wantOut) > tolerance || abs(inGain - wantIn) > tolerance) {
                    failures += "$curve over $overlap ms at $t: ($out, $inGain), want ($wantOut, $wantIn)"
                }
            }
        }
        assertTrue(failures.joinToString("\n"), failures.isEmpty())
    }

    private fun write(): JsonObject = buildJsonObject {
        putJsonArray("about") {
            add("Crossfade curves: the Kotlin tests (FadeCurvesTest) and the audio engine's Rust tests both check these.")
            add("t is the place through the blend (0 to 1); out is the outgoing song's gain and in the incoming song's, before any headroom.")
            add("EqualPower: out = cos(t pi/2), in = sqrt(max(0, 1 - out^2)).")
            add("Linear: out = 1 - t, in = t.")
            add("SCurve: s(t) = (g(t) - g(0)) / (g(1) - g(0)) with g(t) = 1 / (1 + exp(-12 (t - 0.5))); out = 1 - s(t), in = sqrt(max(0, 1 - out^2)).")
            add("EvenLoudness: f(t) = 10^(-60 t / 0.95 / 20) for t <= 0.95, else 0.001 (1 - t) / 0.05; out = f(t), in = f(1 - t).")
            add("MixOnly: edge e = min(0.5, 300 / overlapMs); out = 1 for t <= 1 - e, else cos((t - (1 - e)) / e pi/2) (0 at t = 1); in = sin(t / e pi/2) for t < e, else 1. Mix only blends also play 3 dB quieter (headroom).")
            add("Every gain is clamped to 0..1.")
        }
        put("tolerance", 1e-12)
        putJsonArray("cases") {
            for ((curve, overlap) in cases) {
                addJsonObject {
                    put("curve", curve.name)
                    put("overlapMs", overlap)
                    putJsonArray("points") {
                        for (t in points) {
                            val (out, inGain) = fadeGains(curve, t, overlap)
                            addJsonObject {
                                put("t", t)
                                put("out", out)
                                put("in", inGain)
                            }
                        }
                    }
                }
            }
        }
    }
}
