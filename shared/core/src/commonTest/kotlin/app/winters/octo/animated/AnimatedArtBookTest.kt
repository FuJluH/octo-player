package app.winters.octo.animated

import app.winters.octo.subsonic.AnimatedArt
import app.winters.octo.subsonic.AnimatedArtAnswer
import app.winters.octo.subsonic.AnimatedClip
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AnimatedArtBookTest {
    private val art = AnimatedArt(square = AnimatedClip(video = "https://cdn.example.com/s.m3u8"))

    @Test
    fun twoAsksAtOnceShareOneCall() = runTest {
        val gate = CompletableDeferred<Unit>()
        val asked = mutableListOf<String>()
        val book = AnimatedArtBook(backgroundScope, { true }, { asked += it; gate.await(); AnimatedArtAnswer.Found(art) })
        val first = async { book.art("al-1") }
        val second = async { book.art("al-1") }
        runCurrent()
        gate.complete(Unit)
        assertEquals(art, first.await())
        assertEquals(art, second.await())
        assertEquals(listOf("al-1"), asked)
        // Kept: no second call.
        assertEquals(art, book.art("al-1"))
        assertEquals(listOf("al-1"), asked)
    }

    @Test
    fun noneIsKeptToo() = runTest {
        var calls = 0
        val book = AnimatedArtBook(backgroundScope, { true }, { calls++; AnimatedArtAnswer.None })
        assertNull(book.art("al-1"))
        assertNull(book.art("al-1"))
        assertEquals(1, calls)
        assertEquals(KnownArt.HasNone, book.peek("al-1"))
    }

    @Test
    fun anOutageIsNotKeptAndTheAlbumIsAskedAgainLater() = runTest {
        var clock = 0L
        var answer: AnimatedArtAnswer = AnimatedArtAnswer.NotNow
        var calls = 0
        val book = AnimatedArtBook(backgroundScope, { true }, { calls++; answer }, now = { clock })
        assertNull(book.art("al-1"))
        assertEquals(KnownArt.Unknown, book.peek("al-1"))
        // Left alone for a while.
        assertNull(book.art("al-1"))
        assertEquals(1, calls)
        clock += NOT_NOW_PAUSE_MS + 1
        answer = AnimatedArtAnswer.Found(art)
        assertEquals(art, book.art("al-1"))
        assertEquals(2, calls)
    }

    @Test
    fun aServerWithoutTheExtensionIsNeverAsked() = runTest {
        var calls = 0
        var checks = 0
        val book = AnimatedArtBook(backgroundScope, { checks++; false }, { calls++; AnimatedArtAnswer.Found(art) })
        assertNull(book.art("al-1"))
        assertNull(book.art("al-2"))
        assertEquals(0, calls)
        assertEquals(1, checks)
    }

    @Test
    fun aServerWithArtOffIsLeftAloneForAWhile() = runTest {
        var clock = 0L
        var calls = 0
        val book = AnimatedArtBook(backgroundScope, { true }, { calls++; AnimatedArtAnswer.Off }, now = { clock })
        assertNull(book.art("al-1"))
        assertNull(book.art("al-2"))
        assertEquals(1, calls)
        clock += SERVER_OFF_PAUSE_MS + 1
        assertNull(book.art("al-2"))
        assertEquals(2, calls)
    }

    @Test
    fun aServerThatCouldNotSayIsCheckedAgainAMinuteLater() = runTest {
        var clock = 0L
        var listed: Boolean? = null
        var calls = 0
        val book = AnimatedArtBook(backgroundScope, { listed }, { calls++; AnimatedArtAnswer.Found(art) }, now = { clock })
        assertNull(book.art("al-1"))
        listed = true
        assertNull(book.art("al-1"))
        clock += SERVER_UNKNOWN_PAUSE_MS + 1
        assertEquals(art, book.art("al-1"))
        assertEquals(1, calls)
    }

    @Test
    fun artFromGetAlbumIsUsedWithoutAsking() = runTest {
        var calls = 0
        val book = AnimatedArtBook(backgroundScope, { true }, { calls++; AnimatedArtAnswer.None })
        book.note("al-1", art)
        assertEquals(KnownArt.Has(art), book.peek("al-1"))
        assertEquals(art, book.art("al-1"))
        // getAlbum without art says nothing.
        book.note("al-2", null)
        assertEquals(KnownArt.Unknown, book.peek("al-2"))
        assertEquals(0, calls)
    }

    @Test
    fun theNextSongsAlbumIsAskedAhead() = runTest {
        val asked = mutableListOf<String>()
        val book = AnimatedArtBook(backgroundScope, { true }, { asked += it; AnimatedArtAnswer.Found(art) })
        book.ahead(albumsToAsk("al-now", listOf("al-next", "al-later")))
        runCurrent()
        assertEquals(listOf("al-now", "al-next"), asked)
        assertEquals(KnownArt.Has(art), book.peek("al-next"))
    }

    @Test
    fun theSettingDecidesWhereTheLoopGoes() {
        val tall = AnimatedClip(video = "https://cdn.example.com/t.m3u8")
        val both = art.copy(tall = tall)
        assertEquals(PlayerLoop.Cover(art.square!!), AnimatedArtSetting.Square.inPlayer(both))
        assertEquals(PlayerLoop.Backdrop(tall), AnimatedArtSetting.FullScreen.inPlayer(both))
        // No tall loop: full screen falls back to the square one.
        assertEquals(PlayerLoop.Cover(art.square!!), AnimatedArtSetting.FullScreen.inPlayer(art))
        assertEquals(PlayerLoop.None, AnimatedArtSetting.Off.inPlayer(both))
        assertEquals(PlayerLoop.None, AnimatedArtSetting.Square.inPlayer(AnimatedArt(tall = tall)))
        assertEquals(art.square, AnimatedArtSetting.FullScreen.onAlbumPage(both))
        assertNull(AnimatedArtSetting.Off.onAlbumPage(both))
        assertEquals(AnimatedArtSetting.Square, AnimatedArtSetting.fromKey(null))
        assertEquals(AnimatedArtSetting.FullScreen, AnimatedArtSetting.fromKey("full_screen"))
    }

    @Test
    fun aLoopPlaysOnlyWhenSeen() {
        assertEquals(LoopPlay.Play, loopPlay(seen = true, powerSave = false, reduceMotion = false))
        assertEquals(LoopPlay.Hold, loopPlay(seen = false, powerSave = false, reduceMotion = false))
        assertEquals(LoopPlay.Hold, loopPlay(seen = true, powerSave = true, reduceMotion = false))
        assertEquals(LoopPlay.StillOnly, loopPlay(seen = true, powerSave = false, reduceMotion = true))
    }
}
