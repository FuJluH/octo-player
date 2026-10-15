package app.winters.octo.desktop.pages

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.width
import androidx.compose.ui.text.style.TextAlign
import app.winters.octo.design.ControlHeight
import app.winters.octo.design.GlazeCapsule
import app.winters.octo.design.SettingsSize
import app.winters.octo.desktop.lyrics.BLUETOOTH_OUTPUT_TIMING_MS
import app.winters.octo.desktop.lyrics.OUTPUT_TIMING_LIMIT_MS
import app.winters.octo.desktop.lyrics.WIRED_OUTPUT_TIMING_MS
import app.winters.octo.desktop.lyrics.outputTimingAbout
import app.winters.octo.desktop.lyrics.outputTimingOf
import app.winters.octo.desktop.lyrics.signedTiming
import app.winters.octo.desktop.lyrics.timingWords
import app.winters.octo.desktop.settings.MaxTextScale
import app.winters.octo.desktop.settings.DesktopOs
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import app.winters.octo.design.DesktopType
import app.winters.octo.design.LocalReduceMotion
import app.winters.octo.design.OctoColors
import app.winters.octo.design.RowHeight
import app.winters.octo.design.Space
import app.winters.octo.design.Txt
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.setLibraryOnly
import app.winters.octo.discovery.LIBRARY_ONLY_HELP
import app.winters.octo.discovery.LIBRARY_ONLY_SETTING
import app.winters.octo.desktop.nav.Page
import app.winters.octo.desktop.nav.Visit
import app.winters.octo.desktop.nav.shortcutList
import app.winters.octo.desktop.server.Connection
import app.winters.octo.desktop.server.OCTO_LYRICS
import app.winters.octo.playback.START_AFTER_HELP
import app.winters.octo.playback.START_AFTER_SETTING
import app.winters.octo.playback.StartAfter
import app.winters.octo.server.serverOffers
import app.winters.octo.desktop.setAutoplay
import app.winters.octo.desktop.settings.AmbienceMotion
import app.winters.octo.covers.PLAYLIST_COVERS_SETTING
import app.winters.octo.covers.PlaylistCoverStyle
import app.winters.octo.covers.playlistCoverStyleHelp
import app.winters.octo.covers.playlistCoverStyleName
import app.winters.octo.desktop.settings.AmbienceStyle
import app.winters.octo.desktop.settings.AppSettings
import app.winters.octo.desktop.settings.Appearance
import app.winters.octo.desktop.settings.WashPrefs
import app.winters.octo.desktop.system.SystemRows
import app.winters.octo.desktop.system.TaskbarAndStartupRows
import app.winters.octo.desktop.system.MiniPlayerGroup
import app.winters.octo.desktop.system.DiscordRows
import app.winters.octo.desktop.system.hasDiscord
import app.winters.octo.desktop.discord.DiscordMark
import app.winters.octo.design.OctoIcons
import app.winters.octo.desktop.hotkeys.GlobalShortcutGroup
import app.winters.octo.desktop.ui.LocalSoftwareDrawing
import app.winters.octo.ui.family.AUDIO_QUALITY
import app.winters.octo.animated.AnimatedArtSetting
import app.winters.octo.desktop.settings.animatedArtSetting
import kotlin.math.roundToInt

// Settings: the servers, how Octo looks, playback, listening, lyrics, radio,
// Discord, how it fits into the system, the keyboard shortcuts and the
// version, each a section of its own in the list beside the page. Every
// change is saved at once.

// The Radio section's key, for a link straight to it.
const val RADIO_SECTION = "radio"
@Composable
fun SettingsPage(app: AppState, visit: Visit) {
    val settings by app.settings.state.collectAsState()
    val discord = hasDiscord()
    SectionedPage(
        app,
        visit,
        "Settings",
        listOfNotNull(
            PageSection("servers", "Servers", OctoIcons.Servers, mark = if (serverUpdateWaits(app)) SERVER_UPDATE_MARK else null) { ServerRows(app) },
            PageSection("look", "Appearance", OctoIcons.Appearance) { AppearanceGroups(app, settings) },
            PageSection("playback", "Playback", OctoIcons.Playback) { PlaybackRows(app, settings) },
            PageSection("quality", AUDIO_QUALITY, OctoIcons.Equalizer, detail = "At home, away, and on this computer.") { AudioQualityRows(app, settings) },
            PageSection("offline", "Offline", OctoIcons.Download, detail = "Songs kept here to play without a connection.") { OfflineRows(app, settings) },
            PageSection("listening", "Listening", OctoIcons.Headphones) { ListeningRows(app, settings) },
            PageSection("lyrics", "Lyrics", OctoIcons.Lyrics) { LyricsRows(app, settings) },
            PageSection(RADIO_SECTION, "Radio", OctoIcons.Radio, detail = "Song radio from your music, and live radio on the air.") { RadioRows(app, settings) },
            if (discord) PageSection("discord", "Discord", DiscordMark, detail = "Show what you're playing to your friends.", brand = true) { DiscordRows(app) } else null,
            PageSection("system", "System", OctoIcons.System) {
                SystemRows(app)
                TaskbarAndStartupRows(app)
                MiniPlayerGroup(app)
            },
            PageSection("keys", "Keyboard", OctoIcons.Keyboard) {
                KeyRows(app)
                GlobalShortcutGroup(app)
            },
            PageSection("about", "About", OctoIcons.Info) { AboutRows(app, settings) },
        ),
    )
}

// What the server brings beyond the music, in plain words.
internal fun serverOffers(connection: Connection): String? =
    serverOffers(lyrics = connection.lyricsByIdOn || connection.supports(OCTO_LYRICS), adds = connection.acquires)

// The accent, the window's background, Home's sections, the full player's
// background, then how much moves.
// Each tuning line shows only while it has something to change.
@Composable
private fun AppearanceGroups(app: AppState, settings: AppSettings) {
    val look = settings.appearance
    fun appearance(edit: (Appearance) -> Appearance) = app.settings.update { it.copy(appearance = edit(it.appearance)) }
    fun wash(edit: (WashPrefs) -> WashPrefs) = appearance { it.copy(wash = edit(it.wash)) }
    val chosen = ambienceOf(look)
    Group {
        AccentRow(look.accent) { accent -> appearance { it.copy(accent = accent) } }
    }
    Group("Window background") {
        ChoiceRow("Ambience", ambienceHelp(chosen), listOf(null, AmbienceStyle.Glow, AmbienceStyle.Immersive), chosen, ::ambienceName) { style ->
            appearance { withAmbience(it, style) }
        }
        if (chosen != null) {
            SliderRow("Strength", null, "${(look.glowStrength * 100).roundToInt()}%", look.glowStrength, { value ->
                appearance { it.copy(glowStrength = value) }
            })
        }
        if (chosen == AmbienceStyle.Immersive) {
            val detail = when {
                LocalSoftwareDrawing.current -> "Holds still here: this computer draws Octo without its graphics card."
                LocalReduceMotion.current -> "Holds still while motion is reduced, by Calm motion or your system."
                else -> motionHelp(look.ambienceMotion)
            }
            ChoiceRow("Movement", detail, AmbienceMotion.entries, look.ambienceMotion, ::motionName) { motion ->
                appearance { it.copy(ambienceMotion = motion) }
            }
        }
    }
    HomeSectionsGroup(app, look.homeSections)
    Group("Full player") {
        val animated = look.animatedArtSetting
        val animatedHelp = when {
            animated == AnimatedArtSetting.Off -> animated.about
            LocalReduceMotion.current -> "Shows the still cover while motion is reduced, by Calm motion or your system."
            else -> animated.about
        }
        ChoiceRow(AnimatedArtSetting.TITLE, animatedHelp, AnimatedArtSetting.entries, animated, AnimatedArtSetting::label) { choice ->
            appearance { it.copy(animatedArt = choice.key) }
        }
        SwitchRow("Moving background", "Off holds the colors still, easier on a battery.", look.wash.moving) { on ->
            wash { it.copy(moving = on) }
        }
        if (look.wash.moving && !look.calmMotion) {
            SliderRow("Drift speed", null, "${look.wash.speed}%", (look.wash.speed - 5) / 95f, { x ->
                wash { it.copy(speed = (5 + x * 95).roundToInt()) }
            }, live = false)
            SwitchRow("Move with the beat", "Slow songs drift slower, quick ones faster.", look.wash.useBpm) { on ->
                wash { it.copy(useBpm = on) }
            }
        }
        SliderRow("Brightness cap", "Lower it if bright covers make words hard to read.", "${look.wash.brightnessCap}%", (look.wash.brightnessCap - 20) / 80f, { x ->
            wash { it.copy(brightnessCap = (20 + x * 80).roundToInt()) }
        }, live = false)
    }
    Group("Playlists") {
        ChoiceRow(PLAYLIST_COVERS_SETTING, playlistCoverStyleHelp(look.playlistCovers), PlaylistCoverStyle.entries, look.playlistCovers, ::playlistCoverStyleName) { style ->
            appearance { it.copy(playlistCovers = style) }
        }
    }
    Group("Motion") {
        SwitchRow("Calm motion", "Backgrounds hold still and lyrics move without springs.", look.calmMotion) { on ->
            appearance { it.copy(calmMotion = on) }
        }
    }
    Group("Text") {
        val system = if (app.os == DesktopOs.Windows) "Windows" else "your system"
        ChoiceRow(
            "Text size",
            "Like $system follows its own text size, up to ${(MaxTextScale * 100).roundToInt()}%.",
            TextSizes,
            look.textSize.takeIf { it in TextSizes } ?: 0,
            { size -> if (size == 0) "Like $system" else "$size%" },
        ) { size -> appearance { it.copy(textSize = size) } }
    }
}

// The text sizes to choose from: the system's, then Octo's own steps.
private val TextSizes = listOf(0, 100, 115, 130)

// The window's ambience as one choice, null being off.
internal fun ambienceOf(look: Appearance): AmbienceStyle? = if (look.ambientGlow) look.ambience else null

// The ambience chosen, kept as the switch and the look it had before, so
// turning it back on returns the same look.
internal fun withAmbience(look: Appearance, style: AmbienceStyle?): Appearance =
    if (style == null) look.copy(ambientGlow = false) else look.copy(ambientGlow = true, ambience = style)

@Composable
private fun PlaybackRows(app: AppState, settings: AppSettings) {
    Rows {
        SwitchRow("Autoplay", "When the queue ends, similar songs keep playing, picked as Radio settings say.", settings.playback.autoplay) { on ->
            app.setAutoplay(on)
        }
        ChoiceRow(START_AFTER_SETTING, START_AFTER_HELP, StartAfter.entries, settings.playback.startAfter, { it.label }) { wait ->
            app.settings.update { it.copy(playback = it.playback.copy(startAfter = wait)) }
        }
        SwitchRow(LIBRARY_ONLY_SETTING, LIBRARY_ONLY_HELP, settings.libraryOnly) { on -> app.setLibraryOnly(on) }
        ActionRow("Equalizer, loudness, crossfade and speed", null, "Open Sound", { app.navigator.go(Page.Sound) })
    }
}

@Composable
private fun ListeningRows(app: AppState, settings: AppSettings) {
    val listening = settings.listening
    Rows {
        SwitchRow(
            "Tell the server what you play",
            "Keeps play counts and history right in every app.",
            listening.reportPlays,
        ) { on -> app.settings.update { it.copy(listening = it.listening.copy(reportPlays = on)) } }
        SwitchRow(
            "Carry the queue between devices",
            "Pick up on your phone where you left off here, and back.",
            listening.syncQueue,
        ) { on -> app.settings.update { it.copy(listening = it.listening.copy(syncQueue = on)) } }
    }
}

@Composable
private fun LyricsRows(app: AppState, settings: AppSettings) {
    Rows {
        SwitchRow(
            "Find lyrics online",
            "Asks LRCLIB when your server has none, sending only the song's names.",
            settings.lyrics.online,
        ) { on ->
            app.settings.update { it.copy(lyrics = it.lyrics.copy(online = on)) }
            app.lyrics.state.value.song?.let { song -> app.lyrics.sources.refresh(song.id) }
        }
        SwitchRow(
            "Bloom fast singing",
            "A word held long for its line swells and glows too. Off, only notes held a second or more bloom.",
            settings.lyrics.bloomFast,
        ) { on -> app.settings.update { it.copy(lyrics = it.lyrics.copy(bloomFast = on)) } }
        OutputTimingRow(app, settings)
    }
}

// The lyrics timing on the output playing now: its automatic one, said so,
// until moved; Earlier and Later a twentieth of a second a click.
@Composable
private fun OutputTimingRow(app: AppState, settings: AppSettings) {
    val player by app.player.state.collectAsState()
    val bluetooth by app.lyrics.bluetooth.collectAsState()
    val device = player.playingOn
    if (device == null) {
        InfoRow(
            "Lyrics timing",
            "Each output keeps its own. Until moved, lyrics show ${timingWords(WIRED_OUTPUT_TIMING_MS)} on speakers or a cable and ${timingWords(BLUETOOTH_OUTPUT_TIMING_MS)} on Bluetooth. Play a song to move it for the output in use.",
            "Automatic",
        )
        return
    }
    val timing = outputTimingOf(settings.lyrics.outputOffsets[device.id], bluetooth)
    SettingRow("Lyrics timing on ${device.name}", outputTimingAbout(bluetooth, timing.automatic)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.S)) {
            if (!timing.automatic) RowAction("Use automatic", { app.lyrics.resetOutput(device.id) })
            GlazeCapsule(null, "Earlier", { app.lyrics.stepOutput(device.id, -1) }, enabled = timing.ms > -OUTPUT_TIMING_LIMIT_MS, height = ControlHeight.M)
            Txt(signedTiming(timing.ms), DesktopType.body.copy(fontFeatureSettings = "tnum"), OctoColors.TextSecondary, Modifier.width(SettingsSize.Reading), align = TextAlign.Center)
            GlazeCapsule(null, "Later", { app.lyrics.stepOutput(device.id, 1) }, enabled = timing.ms < OUTPUT_TIMING_LIMIT_MS, height = ControlHeight.M)
        }
    }
}

// Each shortcut and its keys, in short lines.
@Composable
private fun KeyRows(app: AppState) {
    Group("In Octo") {
        shortcutList(app.mac).forEach { (what, keys) ->
            Row(
                Modifier.fillMaxWidth().heightIn(min = RowHeight.Regular).padding(horizontal = RowInset, vertical = Space.S),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Txt(what, DesktopType.body, modifier = Modifier.weight(1f).padding(end = Space.Xl), maxLines = 2)
                Txt(keys, DesktopType.meta.copy(fontFeatureSettings = "tnum"), OctoColors.TextSecondary, maxLines = 2)
            }
        }
    }
}

// The ambience choices by name, null being off.
private fun ambienceName(style: AmbienceStyle?): String = when (style) {
    null -> "Off"
    AmbienceStyle.Glow -> "Glow"
    AmbienceStyle.Immersive -> "Immersive"
}

// When each ambience choice is the one to pick.
private fun ambienceHelp(style: AmbienceStyle?): String = when (style) {
    null -> "The plain dark background."
    AmbienceStyle.Glow -> "The song's colors glow across the top of the window."
    AmbienceStyle.Immersive -> "The cover's colors behind the whole window."
}

private fun motionName(motion: AmbienceMotion): String = when (motion) {
    AmbienceMotion.Still -> "Still"
    AmbienceMotion.Gentle -> "Gentle"
    AmbienceMotion.Full -> "Full"
}

// When each movement is the one to pick.
private fun motionHelp(motion: AmbienceMotion): String = when (motion) {
    AmbienceMotion.Still -> "Holds still, easiest on a battery."
    AmbienceMotion.Gentle -> "Drifts slowly while music plays."
    AmbienceMotion.Full -> "Drifts at the full player's pace."
}

// The version the build stamped, or "Development build" when run from source
// without it.
fun appVersion(): String = System.getProperty("octo.version")?.takeIf(String::isNotBlank) ?: "Development build"
