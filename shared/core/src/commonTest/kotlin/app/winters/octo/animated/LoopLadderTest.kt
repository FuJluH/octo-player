package app.winters.octo.animated

import app.winters.octo.subsonic.AnimatedClip
import kotlinx.coroutines.test.runTest
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

// Playlists shaped like Apple's (Verified 2026-10-15 on Short n' Sweet).
private val master = """
    #EXTM3U
    #EXT-X-VERSION:7
    #EXT-X-INDEPENDENT-SEGMENTS

    #EXT-X-I-FRAME-STREAM-INF:AVERAGE-BANDWIDTH=173473,BANDWIDTH=186220,VIDEO-RANGE=SDR,CODECS="avc1.64001f",RESOLUTION=486x486,URI="https://cdn.example.com/a/trick_486.m3u8"

    #EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=2186028,BANDWIDTH=2425166,VIDEO-RANGE=SDR,CLOSED-CAPTIONS=NONE,CODECS="avc1.64001f",FRAME-RATE=24.000,RESOLUTION=768x768,STABLE-VARIANT-ID="a2"
    https://cdn.example.com/b/video_768.m3u8
    #EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=1578939,BANDWIDTH=1909638,VIDEO-RANGE=SDR,CLOSED-CAPTIONS=NONE,CODECS="hvc1.2.20000000.L123.B0",FRAME-RATE=24.000,RESOLUTION=768x768
    https://cdn.example.com/c/video_hevc_768.m3u8
    #EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=773877,BANDWIDTH=859244,CODECS="avc1.64001f",FRAME-RATE=24.000,RESOLUTION=486x486
    https://cdn.example.com/d/video_486_low.m3u8
    #EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=1531650,BANDWIDTH=1702562,CODECS="avc1.64001f",FRAME-RATE=24.000,RESOLUTION=486x486
    video_486_high.m3u8
    #EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=6788272,BANDWIDTH=7671972,CODECS="avc1.640020",FRAME-RATE=24.000,RESOLUTION=1080x1080
    https://cdn.example.com/e/video_1080_top.m3u8
    #EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=3952898,BANDWIDTH=4341150,CODECS="avc1.640020",FRAME-RATE=24.000,RESOLUTION=1080x1080
    https://cdn.example.com/f/video_1080.m3u8
""".trimIndent()

private val media = """
    #EXTM3U
    #EXT-X-TARGETDURATION:4
    #EXT-X-VERSION:7
    #EXT-X-MEDIA-SEQUENCE:0
    #EXT-X-PLAYLIST-TYPE:VOD
    #EXT-X-INDEPENDENT-SEGMENTS
    #EXT-X-MAP:URI="loop-.mp4",BYTERANGE="899@0"
    #EXTINF:4.00000,
    #EXT-X-BYTERANGE:1875981@899
    loop-.mp4
    #EXTINF:4.00000,
    #EXT-X-BYTERANGE:2007629@1876880
    loop-.mp4
    #EXT-X-ENDLIST
""".trimIndent()

class LoopLadderTest {
    @get:Rule
    val folder = TemporaryFolder()

    private val server = MockWebServer()

    @Before
    fun start() = server.start()

    @After
    fun stop() = server.close()

    private val masterUrl = "https://cdn.example.com/m/default.m3u8".toHttpUrl()

    @Test
    fun theLadderListsEveryVersionButTheStills() {
        val ladder = parseLoopLadder(master, masterUrl)
        assertEquals(6, ladder.size)
        assertEquals("https://cdn.example.com/m/video_486_high.m3u8", ladder[3].url.toString())
        assertEquals(LoopCodec.Hevc, ladder[1].codec)
        assertEquals(768, ladder[0].width)
        assertEquals(2425166L, ladder[0].bandwidth)
    }

    @Test
    fun theSmallestVersionThatNeedsNoEnlargingIsPicked() {
        val ladder = parseLoopLadder(master, masterUrl)
        // A 450 px cover: the better of the two 486 versions.
        assertEquals("video_486_high.m3u8", pickLoopVariant(ladder, 450, 450)?.url?.pathSegments?.last())
        // 700 px: the H.264 768, not the HEVC one.
        assertEquals("video_768.m3u8", pickLoopVariant(ladder, 700, 700)?.url?.pathSegments?.last())
        // Where HEVC plays, still the best of that size.
        assertEquals("video_768.m3u8", pickLoopVariant(ladder, 700, 700, setOf(LoopCodec.Avc, LoopCodec.Hevc))?.url?.pathSegments?.last())
        // Larger than any: the largest, at the highest rate under the cap.
        assertEquals("video_1080.m3u8", pickLoopVariant(ladder, 2000, 2000)?.url?.pathSegments?.last())
        // A tall space on a square loop: covering the height decides.
        assertEquals("video_1080.m3u8", pickLoopVariant(ladder, 600, 900)?.url?.pathSegments?.last())
        assertNull(pickLoopVariant(ladder, 100, 100, emptySet()))
    }

    @Test
    fun aVersionKeptInOneFileIsThatFile() {
        val playlistUrl = "https://cdn.example.com/b/video_768.m3u8".toHttpUrl()
        val file = parseLoopFile(media, playlistUrl)!!
        assertEquals("https://cdn.example.com/b/loop-.mp4", file.url.toString())
        assertEquals(8.0, file.seconds, 0.001)
        // Parts from two files cannot be kept as one.
        assertNull(parseLoopFile(media.replaceFirst("\nloop-.mp4", "\nother.mp4"), playlistUrl))
    }

    @Test
    fun aLoopIsLocatedAndFetchedOnce() = runTest {
        val body = ByteArray(4096) { it.toByte() }
        val masterHere = master.replace("https://cdn.example.com/d/video_486_low.m3u8", "low.m3u8")
        server.enqueue(MockResponse.Builder().body(masterHere).build())
        server.enqueue(MockResponse.Builder().body(media).build())
        server.enqueue(MockResponse.Builder().body(okio.Buffer().write(body)).build())
        val fetcher = LoopFetcher(OkHttpClient())
        val clip = AnimatedClip(video = server.url("/m/default.m3u8").toString())
        val file = fetcher.locate(clip, 450, 450)!!
        assertEquals(server.url("/m/loop-.mp4"), file.url)
        assertEquals("/m/default.m3u8", server.takeRequest().url.encodedPath)
        assertEquals("/m/video_486_high.m3u8", server.takeRequest().url.encodedPath)

        val target = folder.root.resolve("loops/one.mp4")
        assertTrue(fetcher.fetch(file, target))
        assertArrayEquals(body, target.readBytes())
        assertFalse(target.resolveSibling("one.mp4.part").exists())
        // Already there: not fetched again.
        assertTrue(fetcher.fetch(file, target))
        assertEquals(3, server.requestCount)
    }

    @Test
    fun aPlayerIsGivenTheOneVersionThatSuits() = runTest {
        server.enqueue(MockResponse.Builder().body(master).build())
        val fetcher = LoopFetcher(OkHttpClient())
        val picked = fetcher.pick(AnimatedClip(video = server.url("/m/default.m3u8").toString()), 700, 700)!!
        assertEquals("https://cdn.example.com/b/video_768.m3u8", picked.url.toString())
        assertEquals(1, server.requestCount)
        // A version's own playlist is played as it is.
        server.enqueue(MockResponse.Builder().body(media).build())
        val alone = fetcher.pick(AnimatedClip(video = server.url("/b/video.m3u8").toString(), width = 768, height = 768), 700, 700)!!
        assertEquals(server.url("/b/video.m3u8"), alone.url)
        assertEquals(768, alone.width)
        // Nothing that answers is nothing to play.
        server.enqueue(MockResponse.Builder().code(500).build())
        assertNull(fetcher.pick(AnimatedClip(video = server.url("/gone.m3u8").toString()), 700, 700))
        assertNull(fetcher.pick(AnimatedClip(video = "not an address"), 700, 700))
    }

    @Test
    fun aFailedFetchLeavesNothingBehind() = runTest {
        server.enqueue(MockResponse.Builder().code(404).build())
        val target = folder.root.resolve("gone.mp4")
        assertFalse(LoopFetcher(OkHttpClient()).fetch(LoopFile(server.url("/x.mp4"), 1.0), target))
        assertFalse(target.exists())
        assertFalse(target.resolveSibling("gone.mp4.part").exists())
    }

    @Test
    fun theShelfDropsTheLeastLatelyUsedFirst() {
        val shelf = LoopShelf(folder.newFolder("shelf"), maxBytes = 250)
        val old = shelf.fileFor("https://cdn.example.com/old.mp4".toHttpUrl()).apply { writeBytes(ByteArray(100)); setLastModified(1_000) }
        val kept = shelf.fileFor("https://cdn.example.com/kept.mp4".toHttpUrl()).apply { writeBytes(ByteArray(100)); setLastModified(2_000) }
        val new = shelf.fileFor("https://cdn.example.com/new.mp4".toHttpUrl()).apply { writeBytes(ByteArray(100)); setLastModified(3_000) }
        shelf.trim(keep = setOf(old))
        assertTrue(old.exists())
        assertFalse(kept.exists())
        assertTrue(new.exists())
    }
}
