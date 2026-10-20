package app.winters.octo.desktop.audio

import app.winters.octo.audio.EndReason
import app.winters.octo.audio.EngineEvent
import app.winters.octo.audio.ErrorKind
import app.winters.octo.audio.PlaybackState
import app.winters.octo.audio.TrackInfo
import app.winters.octo.desktop.FakeServer
import app.winters.octo.desktop.player.DEFAULT_OUTPUT
import app.winters.octo.desktop.player.DeviceFormat
import app.winters.octo.desktop.player.PlayFormat
import app.winters.octo.desktop.player.RepeatMode
import app.winters.octo.desktop.player.SavedQueue
import app.winters.octo.desktop.player.SongFormat
import app.winters.octo.desktop.player.formatLabel
import app.winters.octo.desktop.player.outputSentence
import app.winters.octo.subsonic.Song
import app.winters.octo.subsonic.SongReplayGain
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Test
import kotlin.random.Random
import app.winters.octo.audio.OutputDevice as EngineDevice
import app.winters.octo.audio.OutputFormat as EngineFormat

// The player's side of the engine: that the engine's queue always holds
// the songs in the order they play, that jumps use the queue it has, and
// that the engine's news turns into the right state.
class EngineSyncTest {
    private val songs = (1..5).map { Song("s$it", "Song $it", albumId = "al", track = it, duration = 100) }
    private val extra = listOf(Song("x", "X", duration = 60), Song("y", "Y", duration = 60))
    private var now = 0L

    private fun setUp(): Pair<EnginePlayer, FakeEngine> {
        val engine = FakeEngine()
        val player = EnginePlayer(engine, { SongAddress("file:///${it.id}.flac") }, Random(3), clock = { now })
        return player to engine
    }

    // What the engine holds, as song ids, and the one it is on.
    private fun EnginePlayer.engineSongs(engine: FakeEngine) =
        engine.ids.map { id -> state.value.queue.first { itemId(it.key) == id }.song.id }

    private fun EnginePlayer.playOrder() = listOfNotNull(state.value.current?.song?.id) + state.value.upcoming.map { it.song.id }

    private fun EnginePlayer.key(id: String) = state.value.queue.first { it.song.id == id }.key

    @Test
    fun playLoadsTheSongsInTheOrderTheyPlay() {
        val (p, engine) = setUp()
        p.play(songs, 2, shuffle = true)
        assertEquals(listOf("load 5 at 0 from 0 playing"), engine.calls)
        assertEquals(p.playOrder(), p.engineSongs(engine))
        val first = engine.queue.first()
        assertEquals(100_000uL, first.durationMs)
        assertEquals("file:///s3.flac", first.source)
        assertEquals("al", first.albumId)
        assertEquals(1003, first.albumOrder)
    }

    // Octo lists many songs found online at 3:00, a guess. The engine is
    // left to read the length from the file, and that length is the one
    // shown and sought within.
    @Test
    fun aGuessedLengthIsLeftToTheFile() {
        val (p, engine) = setUp()
        p.play(listOf(Song("f", "Found online", duration = 180), Song("l", "Listed", duration = 240)), 0, shuffle = false)
        assertNull(engine.queue[0].durationMs)
        assertEquals(240_000uL, engine.queue[1].durationMs)
        engine.heard = Heard(engine.queue[0].id, 0.0, 713_000)
        p.seekTo(400_000)
        assertEquals("seek 400000", engine.calls.last())
        assertEquals(713_000, p.state.value.durationMs)
    }

    @Test
    fun loudnessTheServerKnowsGoesAlong() {
        val (p, engine) = setUp()
        p.play(listOf(Song("g", "G", duration = 10, replayGain = SongReplayGain(trackGain = -6.5f, trackPeak = 0.9f))))
        assertEquals(-6.5f, engine.queue.single().replayGain?.trackGain)
    }

    @Test
    fun songsPutInReachTheEngineInPlayOrder() {
        val (p, engine) = setUp()
        p.play(songs, 0, shuffle = true)
        engine.calls.clear()
        p.playNext(extra)
        assertEquals(listOf("queue 7 at 0"), engine.calls)
        assertEquals(p.playOrder(), p.engineSongs(engine))
        p.addToQueue(listOf(Song("z", "Z", duration = 60)))
        assertEquals(p.playOrder(), p.engineSongs(engine))
        p.moveUpcoming(0, 4)
        assertEquals(p.playOrder(), p.engineSongs(engine))
        p.remove(p.state.value.upcoming[1].key)
        assertEquals(p.playOrder(), p.engineSongs(engine))
    }

    @Test
    fun shuffleOnAndOffGivesTheEngineTheWholeNewOrder() {
        val (p, engine) = setUp()
        p.play(songs, 2)
        p.setShuffle(true)
        // Every song once, from the one playing: nothing left over from
        // the order before, for repeat all to go round to.
        assertEquals(p.playOrder(), p.engineSongs(engine))
        assertEquals(0, engine.index)
        p.setShuffle(false)
        assertEquals(listOf("s1", "s2", "s3", "s4", "s5"), p.engineSongs(engine))
        assertEquals("s3", p.engineSongs(engine)[engine.index])
    }

    @Test
    fun aQueueChangeAsTheEngineMovesOnKeepsEverySongOnce() {
        val (p, engine) = setUp()
        p.play(songs)
        // The engine has moved on to s2; the news of it is on the way.
        engine.index = 1
        p.addToQueue(extra)
        assertEquals(listOf("s1", "s2", "s3", "s4", "s5", "x", "y"), p.engineSongs(engine))
        assertEquals("s2", p.engineSongs(engine)[engine.index])
    }

    @Test
    fun nextAndBackSkipWithinTheEnginesQueue() {
        val (p, engine) = setUp()
        p.play(songs)
        engine.calls.clear()
        p.next()
        assertEquals(listOf("skip 1", "play"), engine.calls)
        engine.calls.clear()
        p.previous()
        assertEquals(listOf("skip 0", "play"), engine.calls)
    }

    @Test
    fun afterShuffleComesOffBackFindsTheSongWhereTheEngineHasIt() {
        val (p, engine) = setUp()
        p.play(songs, 0, shuffle = true)
        p.next()
        p.next()
        p.setShuffle(false)
        assertEquals(p.playOrder(), p.engineSongs(engine).drop(engine.index))
        engine.calls.clear()
        val before = p.state.value.current!!.song.id
        p.previous()
        val back = p.state.value.current!!.song.id
        // Unshuffled, back is the song before in the album, wherever the
        // engine keeps it.
        assertEquals("s${before.drop(1).toInt() - 1}", back)
        assertEquals(back, p.engineSongs(engine)[engine.index])
    }

    @Test
    fun aSkipWhilePausedStartsPlaying() {
        val (p, engine) = setUp()
        p.play(songs)
        p.pause()
        engine.calls.clear()
        p.skipTo(p.key("s4"))
        assertEquals(listOf("skip 3", "play"), engine.calls)
        assertTrue(p.state.value.playing)
    }

    @Test
    fun nextWhilePausedStaysPaused() {
        val (p, engine) = setUp()
        p.play(songs)
        p.pause()
        engine.calls.clear()
        p.next()
        assertEquals(listOf("skip 1"), engine.calls)
    }

    @Test
    fun songsPutIntoAnEmptyQueueAreLoadedPaused() {
        val (p, engine) = setUp()
        p.addToQueue(extra)
        assertEquals(listOf("load 2 at 0 from 0 paused"), engine.calls)
        engine.calls.clear()
        p.resume()
        assertEquals(listOf("play"), engine.calls)
    }

    @Test
    fun clearingEmptiesTheEngine() {
        val (p, engine) = setUp()
        p.play(songs)
        p.clear()
        assertEquals("load 0 at 0 from 0 paused", engine.calls.last())
        assertTrue(engine.queue.isEmpty())
    }

    @Test
    fun repeatAndStopAfterCurrentReachTheEngine() {
        val (p, engine) = setUp()
        p.setRepeat(RepeatMode.One)
        p.setStopAfterCurrent(true)
        assertEquals(listOf("repeat ONE", "stop after true"), engine.calls)
    }

    @Test
    fun theVolumeSliderIsSquared() {
        val (p, engine) = setUp()
        p.setVolume(0.5f)
        assertEquals(0.25f, engine.level)
        assertEquals(0.5f, p.state.value.volume)
    }

    // ---- The engine's news ----

    @Test
    fun aSongStartingByItselfBecomesTheCurrentOne() {
        val (p, engine) = setUp()
        p.play(songs)
        engine.emit(EngineEvent.TrackStarted(itemId(p.key("s1")), 0u, null))
        engine.emit(EngineEvent.TrackStarted(itemId(p.key("s2")), 1u, null))
        assertEquals("s2", p.state.value.current?.song?.id)
        assertEquals(listOf("s3", "s4", "s5"), p.state.value.upcoming.map { it.song.id })
    }

    @Test
    fun newsFromBeforeAJumpIsIgnored() {
        val (p, engine) = setUp()
        p.play(songs)
        engine.emit(EngineEvent.TrackStarted(itemId(p.key("s1")), 0u, null))
        p.skipTo(p.key("s4"))
        // s1 ran into s2 just before the jump reached the engine.
        engine.emit(EngineEvent.TrackStarted(itemId(p.key("s2")), 1u, null))
        assertEquals("s4", p.state.value.current?.song?.id)
        engine.emit(EngineEvent.TrackStarted(itemId(p.key("s4")), 3u, null))
        engine.emit(EngineEvent.TrackStarted(itemId(p.key("s5")), 4u, null))
        assertEquals("s5", p.state.value.current?.song?.id)
    }

    @Test
    fun newsOfAReplacedQueueIsIgnored() {
        val (p, engine) = setUp()
        p.play(songs)
        val old = p.key("s3")
        p.play(extra)
        engine.emit(EngineEvent.TrackStarted(itemId(old), 2u, null))
        assertEquals("x", p.state.value.current?.song?.id)
    }

    @Test
    fun theEndOfTheQueueStopsPlaying() {
        val (p, engine) = setUp()
        p.play(songs, 4)
        engine.emit(EngineEvent.QueueEnded)
        assertFalse(p.state.value.playing)
        assertEquals("s5", p.state.value.current?.song?.id)
    }

    @Test
    fun bufferingShowsWhilePlaying() {
        val (p, engine) = setUp()
        p.play(songs)
        engine.emit(EngineEvent.Buffering(itemId(p.key("s1"))))
        assertTrue(p.state.value.buffering)
        engine.emit(EngineEvent.Ready(itemId(p.key("s1"))))
        assertFalse(p.state.value.buffering)
        p.pause()
        engine.emit(EngineEvent.StateChanged(PlaybackState.BUFFERING))
        assertFalse("paused is not buffering", p.state.value.buffering)
    }

    @Test
    fun aSongThatFailsSaysWhyUntilTheNextStarts() {
        val (p, engine) = setUp()
        p.play(songs)
        engine.emit(EngineEvent.Error(ErrorKind.NETWORK, "timed out", itemId(p.key("s1"))))
        assertEquals("Couldn't reach the server to play that song.", p.state.value.problem?.words)
        engine.emit(EngineEvent.TrackStarted(itemId(p.key("s2")), 1u, null))
        assertEquals("s2", p.state.value.current?.song?.id)
        assertNull(p.state.value.problem)
    }

    // Brandon: pressing play on a song did nothing. The last song failed,
    // the queue ended on it, and Play only asked the engine to carry on
    // with a song it had given up on.
    @Test
    fun playOnASongThatFailedTriesItAgain() {
        val (p, engine) = setUp()
        p.play(songs, 4)
        engine.emit(EngineEvent.Error(ErrorKind.NETWORK, "timed out", itemId(p.key("s5"))))
        engine.emit(EngineEvent.QueueEnded)
        engine.engineState = PlaybackState.ENDED
        engine.calls.clear()
        p.togglePlay()
        assertTrue(p.state.value.playing)
        assertNull(p.state.value.problem)
        assertEquals(listOf("load 5 at 4 from 0 playing"), engine.calls)
        // A pause and play on a song that is fine only carries on.
        p.pause()
        engine.calls.clear()
        engine.engineState = PlaybackState.PAUSED
        p.resume()
        assertEquals(listOf("play"), engine.calls)
    }

    @Test
    fun aFailureNamesTheSongAndKeepsTheEnginesWords() {
        val (p, engine) = setUp()
        p.play(songs)
        engine.emit(EngineEvent.Error(ErrorKind.NOT_FOUND, "404 from server", itemId(p.key("s1"))))
        val problem = p.state.value.problem!!
        assertEquals("s1", problem.song?.id)
        assertEquals("404 from server", problem.detail)
    }

    // A song found online was never on the server, so its "not found" is a refusal.
    @Test
    fun aNotFoundOnAnOutsideSongIsARefusal() {
        val (p, engine) = setUp()
        p.play(listOf(songs[0].copy(id = "ext1", isExternal = true)) + songs.drop(1))
        engine.emit(EngineEvent.Error(ErrorKind.NOT_FOUND, "404 from server", itemId(p.key("ext1"))))
        assertEquals("The server wouldn't send that song.", p.state.value.problem?.words)
        engine.emit(EngineEvent.Error(ErrorKind.NOT_FOUND, "404 from server", itemId(p.key("s2"))))
        assertEquals("That song isn't on the server any more.", p.state.value.problem?.words)
    }

    @Test
    fun repeatOneCountsEachTimeRound() {
        val (p, engine) = setUp()
        p.setRepeat(RepeatMode.One)
        p.play(songs)
        val s1 = itemId(p.key("s1"))
        engine.emit(EngineEvent.TrackStarted(s1, 1u, null))
        assertEquals("the first start is not a repeat", 0, p.state.value.rounds)
        engine.emit(EngineEvent.TrackStarted(s1, 2u, null))
        engine.emit(EngineEvent.TrackStarted(s1, 3u, null))
        assertEquals(2, p.state.value.rounds)
        p.next()
        engine.emit(EngineEvent.TrackStarted(itemId(p.key("s2")), 4u, null))
        assertEquals("a new song starts at nought", 0, p.state.value.rounds)
    }

    @Test
    fun aSavedQueueComesBackPausedWhereItWasLeft() {
        val (p, engine) = setUp()
        p.restore(SavedQueue(songs, listOf(4, 3, 2, 1, 0), index = 2, positionMs = 42_000, shuffle = true, repeat = RepeatMode.All))
        val state = p.state.value
        assertEquals("s3", state.current?.song?.id)
        assertFalse(state.playing)
        assertTrue(state.shuffle)
        assertEquals(RepeatMode.All, state.repeat)
        assertEquals(listOf("s2", "s1"), state.upcoming.map { it.song.id })
        assertEquals(listOf("s5", "s4"), state.played.map { it.song.id })
        assertEquals("load 5 at 2 from 42000 paused", engine.calls.first { it.startsWith("load") })
        assertEquals(42_000, p.positionMs())
    }

    @Test
    fun stopAfterCurrentFollowsTheEngineToTheNextSongPaused() {
        val (p, engine) = setUp()
        p.play(songs)
        p.setStopAfterCurrent(true)
        engine.emit(EngineEvent.TrackEnded(itemId(p.key("s1")), EndReason.FINISHED))
        assertEquals("s2", p.state.value.current?.song?.id)
        assertFalse(p.state.value.playing)
        assertFalse(p.state.value.stopAfterCurrent)
    }

    @Test
    fun beingHeardOnAnotherSongMovesThereWhenNothingIsAwaited() {
        val (p, engine) = setUp()
        p.play(songs)
        engine.emit(EngineEvent.Position(itemId(p.key("s1")), 50.0))
        engine.emit(EngineEvent.Position(itemId(p.key("s2")), 10.0))
        assertEquals("s2", p.state.value.current?.song?.id)
    }

    @Test
    fun aJumpThatLandsElsewhereIsFollowedOnceTheWaitIsOver() {
        val (p, engine) = setUp()
        p.play(songs)
        p.skipTo(p.key("s4"))
        // The engine is heard on s2, and never on s4.
        engine.emit(EngineEvent.Position(itemId(p.key("s2")), 10.0))
        assertEquals("s4", p.state.value.current?.song?.id)
        now += 3_100
        engine.emit(EngineEvent.Position(itemId(p.key("s2")), 3_000.0))
        assertEquals("s2", p.state.value.current?.song?.id)
        // Nothing is awaited now, so the next song is followed at once.
        engine.emit(EngineEvent.TrackStarted(itemId(p.key("s3")), 2u, null))
        assertEquals("s3", p.state.value.current?.song?.id)
    }

    @Test
    fun aJumpShowsItsTargetUntilTheEngineIsHeardThere() {
        val (p, engine) = setUp()
        p.play(songs)
        engine.heard = Heard(itemId(p.key("s1")), 30_000.0, 100_000)
        now = 10
        p.seekTo(60_000)
        assertEquals(60_000, p.positionMs())
        engine.heard = Heard(itemId(p.key("s1")), 60_020.0, 100_000)
        now = 40
        assertEquals(60_020, p.positionMs())
        engine.heard = Heard(itemId(p.key("s1")), 61_000.0, 100_000)
        assertEquals(61_000, p.positionMs())
    }

    @Test
    fun aJumpThatNeverArrivesGivesWayToTheEngine() {
        val (p, engine) = setUp()
        p.play(songs)
        engine.heard = Heard(itemId(p.key("s1")), 5_000.0, 100_000)
        p.seekTo(90_000)
        assertEquals(90_000, p.positionMs())
        now += 10_000
        assertEquals(5_000, p.positionMs())
    }

    @Test
    fun devicesAreListedAndTheOneInUseShown() {
        val (p, engine) = setUp()
        engine.current = EngineDevice("spk", "Speakers", true)
        engine.emit(EngineEvent.DeviceChanged(engine.current, null))
        val until = System.currentTimeMillis() + 2_000
        while (p.state.value.outputs.size < 3 && System.currentTimeMillis() < until) Thread.sleep(5)
        val state = p.state.value
        assertEquals(listOf(DEFAULT_OUTPUT, "spk", "usb"), state.outputs.map { it.id })
        assertEquals("System default (Speakers)", state.output?.name)
        assertEquals("spk", p.deviceKey.value)
        p.selectOutput("usb")
        assertEquals("usb", engine.device)
        assertEquals("usb", p.state.value.output?.id)
        p.selectOutput(DEFAULT_OUTPUT)
        assertNull(engine.device)
    }

    @Test
    fun streamsAreSignedForTheOriginalFile() {
        FakeServer().use { server ->
            val address = ServerSongs { server.client() }.addressOf(Song("abc", "A"))!!
            val url = address.source.toHttpUrl()
            assertEquals("stream", url.pathSegments.last())
            assertEquals("abc", url.queryParameter("id"))
            assertEquals("raw", url.queryParameter("format"))
            assertEquals("winters", url.queryParameter("u"))
            assertTrue("signed", url.queryParameter("t") != null || url.queryParameter("p") != null)
        }
        assertNull(ServerSongs { null }.addressOf(Song("abc", "A")))
    }

    @Test
    fun theSongsFormatAndTheDevicesReachTheState() {
        val (p, engine) = setUp()
        val flac = songs.map { it.copy(suffix = "flac", samplingRate = 44_100, bitDepth = 16) }
        p.play(flac)
        // The library's word until the song starts.
        assertEquals("FLAC 16/44.1", formatLabel(p.state.value.format))
        engine.current = EngineDevice("spk", "Speakers", true)
        engine.emit(EngineEvent.DeviceChanged(engine.current, EngineFormat(48_000u, 2u, "f32", 32u)))
        val info = TrackInfo("flac", true, 96_000u, 2u, 24u, null, null)
        engine.emit(EngineEvent.TrackStarted(itemId(p.key("s1")), 0u, info))
        val format = p.state.value.format!!
        assertEquals(SongFormat("flac", true, 96_000, 24, 2), format.song)
        assertEquals(DeviceFormat(48_000, 2, 32, float = true), format.output)
        assertTrue(format.resampled)
        assertEquals("Playing at 48 kHz, 32-bit float on Speakers, resampled from 96 kHz", outputSentence(format, p.state.value.playingOn?.name))
        // The next song shows the library's word again until it starts.
        p.next()
        assertEquals(44_100, p.state.value.format?.song?.sampleRate)
        assertEquals(format.output, p.state.value.format?.output)
    }

    @Test
    fun theFadeTurnsTheEngineDownAndLeavesTheVolume() {
        val (p, engine) = setUp()
        p.setVolume(0.5f)
        assertEquals(0.25f, engine.level, 0.0001f)
        p.setFade(0.5f)
        assertEquals(0.125f, engine.level, 0.0001f)
        assertEquals(0.5f, p.state.value.volume)
        assertEquals(0.5f, p.state.value.fade)
        // A volume change under a fade keeps the fade.
        p.setVolume(1f)
        assertEquals(0.5f, engine.level, 0.0001f)
        p.setFade(1f)
        assertEquals(1f, engine.level, 0.0001f)
    }

    @Test
    fun onlySongsThatPlayOutCountAsEnded() {
        val (p, engine) = setUp()
        p.play(songs)
        engine.emit(EngineEvent.TrackEnded(itemId(p.key("s1")), EndReason.FINISHED))
        engine.emit(EngineEvent.TrackEnded(itemId(p.key("s2")), EndReason.SKIPPED))
        engine.emit(EngineEvent.TrackEnded("q:9999", EndReason.FINISHED))
        assertEquals(1, p.state.value.ended)
    }

    // An outside song can be listed with another copy's length. Once the
    // engine has opened it, the length of its sound is the one shown and
    // sought within, the place in the song does not move, and every entry
    // of the song (and the next time it is queued) carries that length.
    @Test
    fun theSoundsLengthReplacesAWrongListing() {
        val (p, engine) = setUp()
        val listed = Song("o", "Outside", duration = 296)
        p.play(listOf(listed, Song("n", "Next", duration = 200), listed))
        val key = p.key("o")
        // Until the engine has opened it, the listing stands in.
        assertEquals(296_000, p.state.value.durationMs)
        assertEquals(296_000uL, engine.queue[0].durationMs)
        now += 100_000
        engine.heard = Heard(itemId(key), 100_000.0, 296_000)
        assertEquals(100_000, p.positionMs())
        engine.emit(EngineEvent.TrackStarted(itemId(key), 0u, TrackInfo("aac", false, 44_100u, 2u, null, 291_000uL, null)))
        assertEquals(291_000, p.state.value.durationMs)
        assertEquals(100_000, p.positionMs())
        assertEquals(listOf(291, 200, 291), p.state.value.queue.map { it.song.duration })
        assertEquals(mapOf("o" to 291_000L), p.lengths.corrected.value)
        // The engine holds the corrected listing for the song's next entry.
        assertEquals(listOf(291_000uL, 200_000uL, 291_000uL), engine.queue.map { it.durationMs })
        // The scrub bar ends at the sound's end.
        p.seekTo(295_000)
        assertEquals("seek 291000", engine.calls.last())
        // A word from the engine still carrying the listing changes nothing.
        engine.heard = Heard(itemId(key), 291_000.0, 296_000)
        now += 3_000
        engine.emit(EngineEvent.Position(itemId(key), 291_000.0))
        assertEquals(291_000, p.state.value.durationMs)
        assertEquals(291, p.state.value.current?.song?.duration)
        // Queued again from a list that still has the listing.
        p.addToQueue(listOf(listed))
        assertEquals(291, p.state.value.queue.last().song.duration)
        assertEquals(291_000uL, engine.queue.last().durationMs)
    }

    // A stream that only knows its length once it has played a while: the
    // listing holds until then, and the switch moves the place not at all.
    @Test
    fun aLengthTheEngineLearnsLaterTakesOverWithoutAJump() {
        val (p, engine) = setUp()
        p.play(listOf(Song("o", "Outside", duration = 296)))
        val key = p.key("o")
        engine.emit(EngineEvent.TrackStarted(itemId(key), 0u, null))
        now += 100_000
        engine.heard = Heard(itemId(key), 100_000.0, 296_000)
        assertEquals(100_000, p.positionMs())
        assertEquals(296_000, p.state.value.durationMs)
        now += 250
        engine.heard = Heard(itemId(key), 100_250.0, 291_000)
        engine.emit(EngineEvent.Position(itemId(key), 100_250.0))
        assertEquals(291_000, p.state.value.durationMs)
        assertEquals(100_250, p.positionMs())
        assertEquals(291, p.state.value.current?.song?.duration)
    }

    // A length within a second of the listing is the listing: the song is
    // left as it was.
    @Test
    fun aListingWithinASecondIsKept() {
        val (p, engine) = setUp()
        val listed = Song("l", "Library", duration = 291)
        p.play(listOf(listed))
        engine.emit(EngineEvent.TrackStarted(itemId(p.key("l")), 0u, TrackInfo("flac", true, 44_100u, 2u, 16u, 291_480uL, null)))
        assertEquals(291_480, p.state.value.durationMs)
        assertEquals(listed, p.state.value.current?.song)
        assertEquals(emptyMap<String, Long>(), p.lengths.corrected.value)
    }

    @Test
    fun theDecodersWordIsNamedForPeople() {
        val pcm = TrackInfo("pcm_s16le", true, 48_000u, 1u, 16u, null, null)
        assertEquals("wav", songFormatOf(pcm, Song("C:/music/tone.WAV")).codec)
        assertEquals("aiff", songFormatOf(pcm, Song("x", suffix = "aiff")).codec)
        assertEquals("pcm", songFormatOf(pcm, null).codec)
        val mp3 = songFormatOf(TrackInfo("mp3", false, 44_100u, 2u, null, null, null), Song("y", bitRate = 320))
        assertEquals(SongFormat("mp3", false, 44_100, null, 2, 320), mp3)
    }

    // A song can arrive as another file than the one the library lists: the
    // label is what opened, with nothing borrowed from the listing.
    @Test
    fun theFileOpenedIsShownOverTheListing() {
        val listed = Song("m", suffix = "mp3", bitRate = 320, samplingRate = 44_100)
        val flac = songFormatOf(TrackInfo("flac", true, 48_000u, 2u, 24u, null, null), listed)
        assertEquals(SongFormat("flac", true, 48_000, 24, 2, null), flac)
        assertEquals("FLAC 24/48", formatLabel(PlayFormat(flac, null)))
        val aac = songFormatOf(TrackInfo("aac", false, 44_100u, 2u, null, null, null), listed)
        assertNull(aac.bitRate)
        assertEquals(320, songFormatOf(TrackInfo("mp3", false, 44_100u, 2u, null, null, null), listed).bitRate)
    }

    @Test
    fun theListingShowsUntilTheSongOpens() {
        val (p, engine) = setUp()
        p.play(listOf(Song("m", "Listed", suffix = "mp3", bitRate = 320, samplingRate = 44_100)))
        assertEquals(SongFormat("mp3", false, 44_100, bitRate = 320), p.state.value.format?.song)
        engine.emit(EngineEvent.TrackStarted(itemId(p.key("m")), 0u, TrackInfo("flac", true, 44_100u, 2u, 16u, null, null)))
        assertEquals(SongFormat("flac", true, 44_100, 16, 2), p.state.value.format?.song)
    }

    // Polled right after a skip, the engine can already give the next
    // song's start as its place, before that song is heard. That is no word
    // of it: a late report of the song before must not take the player back.
    @Test
    fun aSkipIsNotUndoneByTheSongBeforeOnceTheNextIsPolled() {
        val (p, engine) = setUp()
        p.play(songs)
        engine.emit(EngineEvent.TrackStarted(itemId(p.key("s1")), 0u, null))
        p.next()
        engine.heard = Heard(itemId(p.key("s2")), 0.0, null)
        p.positionMs()
        now += 1_000
        engine.emit(EngineEvent.Position(itemId(p.key("s1")), 0.0))
        assertEquals("s2", p.state.value.current?.song?.id)
        engine.emit(EngineEvent.TrackStarted(itemId(p.key("s2")), 1u, null))
        assertEquals("s2", p.state.value.current?.song?.id)
    }
}
