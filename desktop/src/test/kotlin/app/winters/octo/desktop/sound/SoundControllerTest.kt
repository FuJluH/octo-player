package app.winters.octo.desktop.sound

import app.winters.octo.audio.AutomixSettings
import app.winters.octo.audio.CrossfeedSettings
import app.winters.octo.audio.DspSettings
import app.winters.octo.audio.EqSettings
import app.winters.octo.audio.ReplayGainSettings
import app.winters.octo.desktop.audio.SoundTarget
import app.winters.octo.desktop.settings.SHARED_SOUND
import app.winters.octo.desktop.settings.SettingsStore
import app.winters.octo.desktop.settings.SoundPrefs
import app.winters.octo.playback.FadeCurve
import app.winters.octo.sound.Crossfeed
import app.winters.octo.sound.CrossfeedPreset
import app.winters.octo.sound.EqFilter
import app.winters.octo.sound.EqMode
import app.winters.octo.sound.EqPresets
import app.winters.octo.sound.FilterType
import app.winters.octo.sound.HeadphoneCorrection
import app.winters.octo.sound.ReplayGainMode
import app.winters.octo.sound.SoundSettings
import app.winters.octo.ui.sound.withPreset
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import app.winters.octo.audio.FadeCurve as EngineFadeCurve
import app.winters.octo.audio.EqMode as EngineEqMode
import app.winters.octo.audio.FilterType as EngineFilterType
import app.winters.octo.audio.ReplayGainMode as EngineGainMode

// The Sound page's settings reaching the engine: mapped one to one, kept
// in the settings file, and switched with the output that plays.
class SoundControllerTest {
    @get:Rule val folder = TemporaryFolder()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)

    @After
    fun stop() = scope.cancel()

    // Writes down what the engine is told.
    private class FakeTarget : SoundTarget {
        override val deviceKey = MutableStateFlow<String?>("spk")
        var eq: EqSettings? = null
        var gain: ReplayGainSettings? = null
        var dsp: DspSettings? = null
        var shapes = 0
        var fade = -1
        var lastAutomix: AutomixSettings? = null
        var automixSent = 0
        var pace = 0f to 0f

        override fun shape(eq: EqSettings, replayGain: ReplayGainSettings, dsp: DspSettings) {
            this.eq = eq
            gain = replayGain
            this.dsp = dsp
            shapes++
        }

        override fun setCrossfade(ms: Int) {
            fade = ms
        }

        override fun setAutomix(settings: AutomixSettings) {
            lastAutomix = settings
            automixSent++
        }

        override fun setSpeed(speed: Float, pitch: Float) {
            pace = speed to pitch
        }
    }

    private fun file() = File(folder.root, "settings.json")

    @Test
    fun everySettingReachesTheEngineAsItIs() {
        val sound = SoundSettings(
            eqEnabled = true,
            mode = EqMode.Parametric,
            graphicGains = List(10) { it.toFloat() - 5f },
            filters = listOf(
                EqFilter(FilterType.Peak, 1_000f, 3f, 1.2f),
                EqFilter(FilterType.LowShelf, 80f, -2f, 0.7f, enabled = false),
                EqFilter(FilterType.HighShelf, 9_000f, 4.5f, 0.5f),
            ),
            preampDb = -3f,
            autoPreamp = false,
            correction = HeadphoneCorrection("HD 600", "oratory1990", -6f, listOf(EqFilter(FilterType.Peak, 3_000f, -2f, 2f))),
            replayGain = ReplayGainMode.Smart,
            replayGainPreampDb = 2f,
            replayGainFallbackDb = -4f,
            preventClipping = false,
            limiter = false,
            balance = -0.25f,
            mono = true,
        )
        val eq = sound.engineEq()
        assertEquals(true, eq.enabled)
        assertEquals(EngineEqMode.PARAMETRIC, eq.mode)
        assertEquals(sound.graphicGains, eq.graphicGains)
        assertEquals(listOf(EngineFilterType.PEAK, EngineFilterType.LOW_SHELF, EngineFilterType.HIGH_SHELF), eq.filters.map { it.filterType })
        assertEquals(listOf(1_000f, 80f, 9_000f), eq.filters.map { it.frequency })
        assertEquals(listOf(3f, -2f, 4.5f), eq.filters.map { it.gainDb })
        assertEquals(listOf(1.2f, 0.7f, 0.5f), eq.filters.map { it.q })
        assertEquals(listOf(true, false, true), eq.filters.map { it.enabled })
        assertEquals(-3f, eq.preampDb)
        assertEquals(false, eq.autoPreamp)
        assertEquals("HD 600", eq.correction?.name)
        assertEquals(-6f, eq.correction?.preampDb)
        assertEquals(3_000f, eq.correction?.filters?.single()?.frequency)
        val gain = sound.engineReplayGain()
        assertEquals(ReplayGainSettings(EngineGainMode.SMART, 2f, -4f, false), gain)
        assertEquals(DspSettings(limiter = false, balance = -0.25f, mono = true, crossfeed = CrossfeedSettings(on = false, cutHz = 700f, feedDb = 4.5f)), sound.engineDsp())
        // Crossfeed goes over as the values in use: the preset's, or the listener's own.
        val meier = SoundSettings(crossfeed = Crossfeed(on = true, preset = CrossfeedPreset.JanMeier, cutHz = 1_500, feedDb = 2f))
        assertEquals(CrossfeedSettings(on = true, cutHz = 650f, feedDb = 9.5f), meier.engineDsp().crossfeed)
        val own = SoundSettings(crossfeed = Crossfeed(on = true, preset = CrossfeedPreset.Custom, cutHz = 1_500, feedDb = 2f))
        assertEquals(CrossfeedSettings(on = true, cutHz = 1_500f, feedDb = 2f), own.engineDsp().crossfeed)
        assertEquals(EngineGainMode.OFF, SoundSettings().engineReplayGain().mode)
        assertEquals(EngineEqMode.GRAPHIC, SoundSettings().engineEq().mode)
    }

    @Test
    fun theSoundIsAppliedAtStartAndOnEveryChange() {
        val target = FakeTarget()
        val settings = SettingsStore(file())
        val controller = SoundController(target, settings, scope)
        assertEquals(1, target.shapes)
        assertEquals(false, target.eq?.enabled)
        controller.update { withPreset(it, EqPresets.first { p -> p.name == "Rock" }) }
        assertEquals(true, target.eq?.enabled)
        assertEquals(EqPresets.first { it.name == "Rock" }.gains, target.eq?.graphicGains)
        assertEquals(2, target.shapes)
    }

    @Test
    fun changesAreKeptInTheSettingsFile() {
        val target = FakeTarget()
        val controller = SoundController(target, SettingsStore(file()), scope)
        controller.update { it.copy(eqEnabled = true, replayGain = ReplayGainMode.Album, balance = 0.5f) }
        val again = SettingsStore(file()).current.sound
        val kept = soundFor(again, "spk")
        assertEquals(true, kept.eqEnabled)
        assertEquals(ReplayGainMode.Album, kept.replayGain)
        assertEquals(0.5f, kept.balance)
    }

    @Test
    fun eachOutputKeepsItsOwnSoundAndSwitchesWithIt() {
        val target = FakeTarget()
        val settings = SettingsStore(file())
        val controller = SoundController(target, settings, scope)
        controller.setPerOutput(true)
        controller.update { withPreset(it, EqPresets.first { p -> p.name == "Rock" }) }
        target.deviceKey.value = "usb"
        // A new output starts from the shared set, which is still flat.
        assertEquals(false, target.eq?.enabled)
        controller.update { withPreset(it, EqPresets.first { p -> p.name == "Bass Boost" }) }
        assertEquals(EqPresets.first { it.name == "Bass Boost" }.gains, target.eq?.graphicGains)
        target.deviceKey.value = "spk"
        assertEquals(EqPresets.first { it.name == "Rock" }.gains, target.eq?.graphicGains)
        assertEquals("Rock", controller.current.value.preset)
        val saved = SettingsStore(file()).current.sound
        assertEquals(setOf("spk", "usb"), saved.profiles.keys)
        assertNull(saved.profiles[SHARED_SOUND])
    }

    @Test
    fun withOneSetEveryOutputSoundsTheSame() {
        val target = FakeTarget()
        val controller = SoundController(target, SettingsStore(file()), scope)
        controller.update { it.copy(mono = true) }
        target.deviceKey.value = "usb"
        assertEquals(true, target.dsp?.mono)
        assertEquals(SoundPrefs(profiles = mapOf(SHARED_SOUND to SoundSettings(mono = true))), SettingsStore(file()).current.sound)
    }

    @Test
    fun aDragIsHeardAtOnceAndSavedWhenLetGo() {
        val target = FakeTarget()
        val settings = SettingsStore(file())
        val controller = SoundController(target, settings, scope)
        controller.preview { it.copy(balance = -0.4f) }
        assertEquals(-0.4f, target.dsp?.balance)
        assertEquals(-0.4f, controller.current.value.balance)
        controller.preview { it.copy(balance = -0.6f) }
        assertEquals(-0.6f, target.dsp?.balance)
        controller.settle()
        assertEquals(-0.6f, soundFor(SettingsStore(file()).current.sound, "spk").balance)
        assertEquals(-0.6f, controller.current.value.balance)
    }

    @Test
    fun crossfadeAndSpeedComeFromPlayback() {
        val target = FakeTarget()
        val settings = SettingsStore(file())
        SoundController(target, settings, scope)
        assertEquals(0, target.fade)
        assertEquals(1f to 1f, target.pace)
        val shapes = target.shapes
        settings.update { it.copy(playback = it.playback.copy(crossfadeSeconds = 6, speed = 1.25f, keepPitch = true, pitchSemitones = 12)) }
        assertEquals(6_000, target.fade)
        assertEquals(1.25f, target.pace.first)
        // Twelve semitones is an octave: twice the pitch. (Held to six.)
        assertEquals(Math.pow(2.0, 0.5).toFloat(), target.pace.second, 1e-4f)
        assertEquals("the equalizer is not sent again for a crossfade change", shapes, target.shapes)
    }

    @Test
    fun transitionsFollowTheCrossfadeSettings() {
        val target = FakeTarget()
        val settings = SettingsStore(file())
        SoundController(target, settings, scope)
        assertEquals(AutomixSettings(smartTransitions = true, filterSweeps = true, matchTempo = false, maxOverlapMs = 0u, fadeCurve = EngineFadeCurve.EQUAL_POWER), target.lastAutomix)
        settings.update { it.copy(playback = it.playback.copy(crossfadeSeconds = 16, filterSweeps = false, matchTempo = true)) }
        assertEquals(16_000, target.fade)
        assertEquals(AutomixSettings(smartTransitions = true, filterSweeps = false, matchTempo = true, maxOverlapMs = 16_000u, fadeCurve = EngineFadeCurve.EQUAL_POWER), target.lastAutomix)
        // A value past the longest blend is held to it.
        settings.update { it.copy(playback = it.playback.copy(crossfadeSeconds = 30, smartTransitions = false)) }
        assertEquals(16_000, target.fade)
        assertEquals(false, target.lastAutomix?.smartTransitions)
        settings.update { it.copy(playback = it.playback.copy(crossfadeCurve = FadeCurve.MixOnly)) }
        assertEquals(EngineFadeCurve.MIX_ONLY, target.lastAutomix?.fadeCurve)
        // A change elsewhere sends nothing new.
        val sent = target.automixSent
        settings.update { it.copy(playback = it.playback.copy(speed = 1.5f)) }
        assertEquals(sent, target.automixSent)
    }

    @Test
    fun presetsCanBeSavedAndDeletedButNotOverBuiltInOnes() {
        val target = FakeTarget()
        val settings = SettingsStore(file())
        val controller = SoundController(target, settings, scope)
        controller.update { it.copy(graphicGains = List(10) { 1f }) }
        assertEquals(false, controller.canSaveAs("rock"))
        assertEquals(false, controller.canSaveAs("Custom"))
        controller.savePreset("Mine")
        assertEquals("Mine", controller.current.value.preset)
        assertEquals(List(10) { 1f }, controller.presets().last().gains)
        controller.deletePreset("Mine")
        assertEquals(EqPresets.size, controller.presets().size)
        assertNull(controller.current.value.preset)
    }
}
