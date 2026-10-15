package app.winters.octo.subsonic

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.Call
import okhttp3.Callback
import okhttp3.FormBody
import okhttp3.HttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resumeWithException

const val API_VERSION = "1.16.1"

class SubsonicClient(
    // The address the server is known by. Its library is kept under this
    // address whichever one the calls go to.
    val primaryUrl: HttpUrl,
    credentials: Credentials,
    http: OkHttpClient,
    private val clientName: String = "Octo",
    // Headers every request to the server carries, such as a proxy's
    // access token. They go only to the server's own addresses.
    private val headers: Map<String, String> = emptyMap(),
    // The library folder calls are limited to, or null for all of them.
    val musicFolderId: String? = null,
    // Where calls go right now, when the server has more than one address.
    private val route: () -> HttpUrl = { primaryUrl },
) {
    // The address calls go to right now: a home address while it answers,
    // otherwise the primary one.
    val baseUrl: HttpUrl get() = route()

    // Who signs in, and how. A change of the signed-in user's own password
    // here puts the new one in, so the client keeps working afterwards.
    @Volatile private var credentials: Credentials = credentials

    val username: String get() = credentials.username

    val authMode: AuthMode get() = credentials.mode

    // The client as it was given, before this server's headers were added.
    private val plainHttp: OkHttpClient = http

    private val http: OkHttpClient =
        if (headers.isEmpty()) http
        else http.newBuilder()
            .addNetworkInterceptor(ServerHeaders { HeaderScope(setOf(origin(primaryUrl), origin(baseUrl)), headers) })
            .build()

    // For the one call that can take minutes: Octo builds the stations the
    // first time they are asked for after it starts.
    private val patient: OkHttpClient by lazy { this.http.newBuilder().readTimeout(3, TimeUnit.MINUTES).build() }

    // A signed address for an endpoint. Every call gets a fresh salt, so
    // never use one of these as a cache key.
    fun url(endpoint: String, params: Map<String, String> = emptyMap()): HttpUrl =
        baseUrl.newBuilder()
            .addPathSegment("rest")
            .addPathSegment(endpoint)
            .apply { credentials.authParams().forEach { (key, value) -> addQueryParameter(key, value) } }
            .addQueryParameter("v", API_VERSION)
            .addQueryParameter("c", clientName)
            .addQueryParameter("f", "json")
            .apply { params.forEach { (key, value) -> addQueryParameter(key, value) } }
            .build()

    // Signs an address outside /rest, such as Octo's admin pages, with the
    // same sign-in as every Subsonic call. A fresh salt each time.
    fun signed(url: HttpUrl): HttpUrl =
        url.newBuilder()
            .apply { credentials.authParams().forEach { (key, value) -> addQueryParameter(key, value) } }
            .addQueryParameter("v", API_VERSION)
            .addQueryParameter("c", clientName)
            .build()

    fun coverArtUrl(coverId: String, size: Int): HttpUrl =
        url("getCoverArt", mapOf("id" to coverId, "size" to size.toString()))

    suspend fun ping(): ServerInfo = get("ping", key = null, serializer = ServerInfo.serializer())

    suspend fun extensions(): List<Extension> =
        get(
            "getOpenSubsonicExtensions",
            key = "openSubsonicExtensions",
            serializer = ListSerializer(Extension.serializer()),
            default = emptyList(),
        )

    // Whether the server lists an extension at this version. A server that
    // cannot say which extensions it has lists none, and so does one that
    // could not be asked; see supportsIfKnown for telling those apart.
    suspend fun supports(name: String, version: Int = 1): Boolean = supportsIfKnown(name, version) ?: false

    // Whether the server lists an extension at this version, or null when it
    // could not be asked: out of reach, a proxy answering while it restarts,
    // a page that is not the server's, or the sign-in refused. Only a yes or
    // no is the server's own answer, worth keeping; a null is worth asking
    // again. A server that answers the call with an error, or has no such
    // address (a 404), has no extensions to list, which is a no.
    suspend fun supportsIfKnown(name: String, version: Int = 1): Boolean? =
        try {
            extensions().lists(name, version)
        } catch (e: SubsonicException.Unreachable) {
            null
        } catch (e: SubsonicException.NotSubsonic) {
            if (e.status != null && !e.serverBusy) false else null
        } catch (e: SubsonicException.WrongCredentials) {
            null
        } catch (e: SubsonicException) {
            false
        }

    // The downloads Octo is doing for the signed-in user, and the ones it
    // finished lately. Only for servers that list the octoAcquisitions
    // extension; others answer with an error.
    suspend fun acquisitions(): List<Acquisition> =
        get("getAcquisitions", key = "acquisitions", serializer = Acquisitions.serializer(), default = Acquisitions()).acquisition

    // One download with its whole log, by the key the list gives it. Only
    // for servers that list octoAcquisitions at version 2.
    suspend fun acquisition(key: String): Acquisition =
        get("getAcquisition", mapOf("key" to key), "acquisition", Acquisition.serializer())

    // Takes the finished downloads off the signed-in user's list, or only
    // the one with this key, and answers how many left it.
    suspend fun clearAcquisitions(key: String? = null): Int =
        get("clearAcquisitions", key?.let { mapOf("key" to it) }.orEmpty(), "cleared", Cleared.serializer(), Cleared()).count

    // Starts a search for one song (a found song's id, or a library song's)
    // on the user's download sources, answered at once while it runs.
    suspend fun findSongs(id: String): FoundSongs = get("findSongs", mapOf("id" to id), "foundSongs", FoundSongs.serializer())

    // A Find songs search as it stands, by the id findSongs answered.
    suspend fun foundSongs(search: String): FoundSongs =
        get("getFoundSongs", mapOf("search" to search), "foundSongs", FoundSongs.serializer())

    // Fetches exactly this copy from a Find songs list: by its id, or on a
    // server older than copy ids, by its place on the list, which holds
    // only once the search has finished. `anyway` is sent only when not
    // null, and only to a server that lists octoAcquisitions at
    // OCTO_REPLACE_ANYWAY_VERSION: false asks first about a copy that is
    // not better than the library's, true replaces it all the same.
    suspend fun pickFoundSong(search: String, copy: FoundCandidate, anyway: Boolean? = null): PickResult {
        val which = copy.id?.let { "copy" to it }
            ?: copy.index?.let { "candidate" to it.toString() }
            ?: return PickResult(PICK_SKIPPED, "This copy cannot be picked. Search again.")
        val params = buildMap {
            put("search", search)
            put(which.first, which.second)
            anyway?.let { put("anyway", it.toString()) }
        }
        return get("pickFoundSong", params, "pick", PickResult.serializer())
    }

    // What the signed-in user may do to the library's files. Only for
    // servers that list the octoLibraryActions extension.
    suspend fun libraryActions(): LibraryActions =
        get("getLibraryActions", key = "libraryActions", serializer = LibraryActions.serializer(), default = LibraryActions())

    // Asks the server to act on one library song's file: LIBRARY_ACTION_REMOVE
    // moves it out of the library into the server's trash, and
    // LIBRARY_ACTION_UPGRADE queues a look for its FLAC and answers at once.
    // Never a rating: on some servers a low rating deletes.
    suspend fun libraryAction(id: String, action: String = LIBRARY_ACTION_REMOVE): LibraryActionResult =
        get("libraryAction", mapOf("id" to id, "action" to action), "libraryAction", LibraryActionResult.serializer())

    // A version 3 fix with what it needs: the tags to write for
    // LIBRARY_ACTION_RETAG (by SongTag name; an empty one clears it), `like`
    // for LIBRARY_ACTION_JOIN_ALBUM, `preview` for LIBRARY_ACTION_COVER.
    suspend fun libraryAction(id: String, action: String, with: Map<String, String>): LibraryActionResult =
        get("libraryAction", with + mapOf("id" to id, "action" to action), "libraryAction", LibraryActionResult.serializer())

    // The tags a download of the song would get, beside what its file says
    // now. Writes nothing. Version 3.
    suspend fun lookUpTags(id: String): SongLookup =
        get("libraryAction", mapOf("id" to id, "action" to LIBRARY_ACTION_LOOKUP), "libraryAction", SongLookup.serializer())

    // The songs in the server's trash, newest first. Version 3.
    suspend fun libraryTrash(): LibraryTrash =
        get("getLibraryTrash", key = "libraryTrash", serializer = LibraryTrash.serializer(), default = LibraryTrash())

    // The FLACs the signed-in user asked for, and how each is going. Only for
    // servers that list octoLibraryActions at version 2.
    suspend fun upgrades(): List<Upgrade> =
        get("getUpgrades", key = "upgrades", serializer = ListSerializer(Upgrade.serializer()), default = emptyList())

    // The signed-in user's imports: lists and trickle. Only for servers that
    // list octoImports.
    suspend fun imports(): ImportOverview =
        get("getImports", key = "imports", serializer = ImportOverview.serializer(), default = ImportOverview())

    // One imported list and every song in it.
    suspend fun importList(id: String): ImportListDetail =
        get("getImport", mapOf("id" to id), "import", ImportListDetail.serializer())

    // One import action (see ImportActions). Keys name songs, and may repeat.
    suspend fun importAction(
        action: String,
        params: Map<String, String> = emptyMap(),
        keys: List<String> = emptyList(),
    ): ImportAnswer =
        getWith(
            "importAction",
            listOf("action" to action) + params.toList() + keys.map { "key" to it },
            "importAction",
            ImportAnswer.serializer(),
            ImportAnswer(),
        )

    // The services a person can bring their music from. Only for servers
    // that list octoImports at OCTO_IMPORTS_FILES.
    suspend fun importServices(): ImportServices =
        get("getImportServices", key = "importServices", serializer = ImportServices.serializer(), default = ImportServices())

    // Sends a list file (.txt, .csv, .json or .zip) for the server to read
    // into lists. The answer is the server's, ok or not, in its own words.
    suspend fun importFile(name: String, bytes: ByteArray): ImportAnswer {
        val part = bytes.toRequestBody(importFileType(name))
        val body = MultipartBody.Builder()
            .setType(MultipartBody.FORM)
            .addFormDataPart("file", name, part)
            .build()
        val request = Request.Builder().url(url("importFile", mapOf("name" to name))).post(body).build()
        val answer = exchange(request, "importFile", patient)
        return withContext(Dispatchers.Default) { decode(answer, "importAction", ImportAnswer.serializer(), ImportAnswer()) }
    }

    // A list typed or pasted as text, one song a line, for the server to
    // read. Sent in a form body, since a list can be long.
    suspend fun importText(name: String, text: String): ImportAnswer {
        val answer = postForm("importText", listOf("name" to name, "text" to text), patient)
        return withContext(Dispatchers.Default) { decode(answer, "importAction", ImportAnswer.serializer(), ImportAnswer()) }
    }

    // One song, by its id on the server.
    suspend fun song(id: String): Song = get("getSong", mapOf("id" to id), "song", Song.serializer())

    suspend fun user(username: String): User =
        get("getUser", mapOf("username" to username), "user", User.serializer())

    suspend fun albumList(
        type: AlbumListType,
        size: Int,
        offset: Int = 0,
        musicFolderId: String? = this.musicFolderId,
    ): List<Album> =
        get(
            "getAlbumList2",
            mapOf("type" to type.wire, "size" to size.toString(), "offset" to offset.toString()).inFolder(musicFolderId),
            "albumList2",
            AlbumList.serializer(),
            AlbumList(),
        ).album

    suspend fun album(id: String): AlbumWithSongs =
        get("getAlbum", mapOf("id" to id), "album", AlbumWithSongs.serializer()).let { album ->
            album.animatedArt?.let { album.copy(animatedArt = it.resolvedOn(baseUrl).takeUnless(AnimatedArt::isEmpty)) } ?: album
        }

    // An album's animated art, on a server that lists octoAnimatedArt, with
    // whole addresses. A server that never asked Apple about the album asks
    // now, for up to 10 seconds, so this call may take that long.
    suspend fun animatedArt(albumId: String): AnimatedArtAnswer =
        try {
            val art = getOptional("getAnimatedArt", mapOf("id" to albumId), "animatedArt", AnimatedArt.serializer(), patient)
                ?.resolvedOn(baseUrl)
            if (art == null || art.isEmpty) AnimatedArtAnswer.None else AnimatedArtAnswer.Found(art)
        } catch (e: SubsonicException) {
            animatedArtAnswerFor(e)
        }

    // A whole address for one of an animated art clip's, which a server
    // passing the clips on itself gives relative to its own address.
    fun animatedArtUrl(address: String): HttpUrl? = resolveArtAddress(address, baseUrl)

    suspend fun artists(musicFolderId: String? = this.musicFolderId): List<ArtistIndex> =
        get(
            "getArtists",
            emptyMap<String, String>().inFolder(musicFolderId),
            "artists",
            Artists.serializer(),
            Artists(),
        ).index

    // The library folders on the server. A server with several libraries
    // lists each as a folder.
    suspend fun musicFolders(): List<MusicFolder> =
        get(
            "getMusicFolders",
            key = "musicFolders",
            serializer = MusicFolders.serializer(),
            default = MusicFolders(),
        ).musicFolder

    // The server's folders from the top, limited to one library folder when
    // given. Servers that file by tags make these folders up from the tags.
    suspend fun indexes(musicFolderId: String? = this.musicFolderId): FolderIndex {
        val wire = get(
            "getIndexes",
            emptyMap<String, String>().inFolder(musicFolderId),
            "indexes",
            IndexesWire.serializer(),
            IndexesWire(),
        )
        val loose = children(wire.child)
        return FolderIndex(wire.index.flatMap { it.artist } + loose.first, loose.second)
    }

    // One folder on the server and what it holds.
    suspend fun musicDirectory(id: String): MusicDirectory {
        val wire = get("getMusicDirectory", mapOf("id" to id), "directory", DirectoryWire.serializer())
        val (folders, songs) = children(wire.child)
        return MusicDirectory(wire.id, wire.name, folders, songs, wire.parent?.takeIf(String::isNotEmpty))
    }

    // Splits a folder's children into folders and songs. A folder is named
    // by its title, or its name on servers that send that instead.
    private fun children(list: List<kotlinx.serialization.json.JsonObject>): Pair<List<DirectoryRef>, List<Song>> {
        val folders = mutableListOf<DirectoryRef>()
        val songs = mutableListOf<Song>()
        for (child in list) {
            val isDir = child["isDir"]?.jsonPrimitive?.booleanOrNull ?: false
            val id = child["id"]?.jsonPrimitive?.contentOrNull ?: continue
            if (isDir) {
                val name = child["title"]?.jsonPrimitive?.contentOrNull ?: child["name"]?.jsonPrimitive?.contentOrNull
                folders += DirectoryRef(
                    id,
                    name.orEmpty(),
                    coverArt = child["coverArt"]?.jsonPrimitive?.contentOrNull,
                    songCount = child["songCount"]?.jsonPrimitive?.intOrNull,
                )
            } else {
                songs += json.decodeFromJsonElement(Song.serializer(), child)
            }
        }
        return folders to songs
    }

    // Who an API key belongs to. Only servers that take API keys answer.
    suspend fun tokenInfo(): String? =
        get("tokenInfo", key = "tokenInfo", serializer = TokenInfo.serializer(), default = TokenInfo()).username

    suspend fun artist(id: String): ArtistWithAlbums =
        get("getArtist", mapOf("id" to id), "artist", ArtistWithAlbums.serializer())

    // An artist's biography, pictures and artists like them. The id may also
    // be an album's or a song's, for their artist.
    suspend fun artistInfo(id: String, similar: Int = 20): ArtistInfo =
        get("getArtistInfo2", mapOf("id" to id, "count" to "$similar"), "artistInfo2", ArtistInfo.serializer(), ArtistInfo())

    // An artist's most played songs. Servers look them up by name; one that
    // lists the "topSongsByArtistId" extension can take the artist's id too,
    // which is surer when two artists share a name.
    suspend fun topSongs(artistName: String, count: Int = 10, artistId: String? = null): List<Song> =
        get(
            "getTopSongs",
            buildMap {
                put("artist", artistName)
                put("count", "$count")
                artistId?.let { put("id", it) }
            },
            "topSongs",
            SongList.serializer(),
            SongList(),
        ).song

    // An artist's most played songs, ranked, each in the library or found
    // online. `artistId` may be the artist's id from a search, which names
    // the artist more surely than the name. Only for servers that list the
    // octoTopSongs extension.
    suspend fun artistTopSongs(artistName: String, artistId: String? = null, count: Int = 20): TopSongs =
        get(
            "getArtistTopSongs",
            buildMap {
                put("artist", artistName)
                put("count", "$count")
                artistId?.let { put("id", it) }
            },
            "topSongs",
            TopSongs.serializer(),
            TopSongs(),
        )

    // A song's transition profile, or `ready = false` while the server has
    // none. Only for servers that list the octoTransitions extension.
    suspend fun transitionProfile(id: String): TransitionProfileAnswer =
        get("getTransitionProfile", mapOf("id" to id), "transitionProfile", TransitionProfileAnswer.serializer(), TransitionProfileAnswer(id))

    // The songs played most right now, ranked like an artist's top songs.
    // `chart` picks another chart (CHART_NEW_SONGS, CHART_TRENDING, a genre's
    // number) on servers that list octoTopSongs version 2; without it, the
    // overall chart. Only for servers that list the octoTopSongs extension.
    suspend fun topChart(count: Int = 20, chart: String? = null): TopSongs =
        get(
            "getTopChart",
            buildMap {
                put("count", "$count")
                chart?.let { put("chart", it) }
            },
            "topSongs",
            TopSongs.serializer(),
            TopSongs(),
        )

    // The charts the server's country has. Only for servers that list
    // octoTopSongs version 2.
    suspend fun charts(): ChartChoices =
        get("getCharts", emptyMap(), "charts", ChartChoices.serializer(), ChartChoices())

    // On Octo this call also sets up per-user playlists and the radio
    // profile, so callers keep the result for the session.
    suspend fun playlists(): List<Playlist> =
        get("getPlaylists", key = "playlists", serializer = Playlists.serializer(), default = Playlists()).playlist

    suspend fun playlist(id: String): PlaylistWithSongs =
        get("getPlaylist", mapOf("id" to id), "playlist", PlaylistWithSongs.serializer())

    // Where a playlist's songs sit on the server, in its order, for a
    // playlist file. A server that keeps its paths to itself sends none.
    suspend fun playlistPaths(id: String): List<SongPath> =
        get("getPlaylist", mapOf("id" to id), "playlist", PlaylistPaths.serializer()).entry

    // Songs like this one, for a radio that starts from it. On Octo these
    // mix library songs with songs found online. octoMix=client asks Octo
    // for its own order of fit, since the app mixes the radio itself;
    // other servers ignore it.
    suspend fun similarSongs(id: String, count: Int = 50): List<Song> =
        get(
            "getSimilarSongs2",
            mapOf("id" to id, "count" to "$count", "octoMix" to "client"),
            "similarSongs2",
            SongList.serializer(),
            SongList(),
        ).song

    // A station's next songs on Octo (octoStations): up to `count`, none of
    // the ones in `after` (the station's songs already queued).
    suspend fun stationSongs(id: String, count: Int, after: List<String>): List<Song> =
        getWith(
            "getStationSongs",
            listOf("id" to id, "count" to "$count") + after.map { "after" to it },
            "stationSongs",
            StationSongs.serializer(),
            StationSongs(),
        ).entry

    // Streams the server runs. On Octo each is also a read-only playlist
    // with the same id, holding the songs it will play.
    suspend fun radioStations(): List<RadioStation> =
        get(
            "getInternetRadioStations",
            key = "internetRadioStations",
            serializer = RadioStations.serializer(),
            default = RadioStations(),
            http = patient,
        ).internetRadioStation

    suspend fun search(
        query: String,
        artists: Int = 10,
        albums: Int = 20,
        songs: Int = 30,
        musicFolderId: String? = this.musicFolderId,
    ): SearchResult =
        get(
            "search3",
            mapOf(
                "query" to query,
                "artistCount" to "$artists",
                "albumCount" to "$albums",
                "songCount" to "$songs",
            ).inFolder(musicFolderId),
            "searchResult3",
            SearchResult.serializer(),
            SearchResult(),
        )

    // One page of every song on the server, for copying the whole library.
    // An empty search matches everything on servers that allow it; others
    // answer with nothing.
    suspend fun songPage(size: Int, offset: Int, musicFolderId: String? = this.musicFolderId): List<Song> =
        get(
            "search3",
            mapOf(
                "query" to "",
                "artistCount" to "0",
                "albumCount" to "0",
                "songCount" to "$size",
                "songOffset" to "$offset",
            ).inFolder(musicFolderId),
            "searchResult3",
            SearchResult.serializer(),
            SearchResult(),
        ).song

    suspend fun starred(): Starred =
        get("getStarred2", key = "starred2", serializer = Starred.serializer(), default = Starred())

    // Marks songs as starred for the signed-in user. Several go in one call.
    suspend fun star(ids: List<String>) = send("star", ids.map { "id" to it })

    suspend fun unstar(ids: List<String>) = send("unstar", ids.map { "id" to it })

    // Rates a song for the signed-in user, 1 to 5 stars; 0 takes the rating off.
    suspend fun setRating(id: String, rating: Int) =
        send("setRating", listOf("id" to id, "rating" to "${rating.coerceIn(0, 5)}"))

    // Stars whole albums. On Octo an album found online is downloaded.
    suspend fun starAlbums(ids: List<String>) = send("star", ids.map { "albumId" to it })

    suspend fun unstarAlbums(ids: List<String>) = send("unstar", ids.map { "albumId" to it })

    // Stars whole artists, as favourites. Several go in one call.
    suspend fun starArtists(ids: List<String>) = send("star", ids.map { "artistId" to it })

    suspend fun unstarArtists(ids: List<String>) = send("unstar", ids.map { "artistId" to it })

    // Tells the server a song was played (submission) or is playing now.
    // The time is when it started, in milliseconds.
    suspend fun scrobble(id: String, time: Long, submission: Boolean) =
        send("scrobble", listOf("id" to id, "time" to "$time", "submission" to "$submission"))

    // Every set of lyrics the server has for a song. Only for servers that
    // list the songLyrics extension. Enhanced (version 2) adds word timings,
    // who sings each line, and translations.
    suspend fun lyricsBySongId(id: String, enhanced: Boolean): List<StructuredLyrics> =
        get(
            "getLyricsBySongId",
            if (enhanced) mapOf("id" to id, "enhanced" to "true") else mapOf("id" to id),
            "lyricsList",
            LyricsList.serializer(),
            LyricsList(),
        ).structuredLyrics

    // Every copy of a song's lyrics the server's sources hold, and what the
    // song is set to. Only for servers that list the octoLyrics extension.
    // A title or artist given searches for those instead of the song's tags.
    suspend fun lyricsCandidates(id: String, title: String? = null, artist: String? = null): LyricsCandidates =
        get("getLyricsCandidates", lyricsCandidatesParams(id, title, artist), "lyricsCandidates", LyricsCandidates.serializer())

    // Sets a song's lyrics on the server to one copy from lyricsCandidates,
    // to LYRICS_NONE to hide them, or to LYRICS_AUTO to let the server find
    // them again. It holds for every app and user on the server. Answers
    // with what the song is set to now.
    suspend fun setLyricsChoice(id: String, candidate: String): String =
        get(
            "setLyricsChoice",
            mapOf("id" to id, "candidate" to candidate),
            "lyricsChoice",
            LyricsChoiceAnswer.serializer(),
            LyricsChoiceAnswer(id, candidate),
        ).choice

    // The older lyrics call, found by artist and title: plain text, or null
    // when the server has none.
    suspend fun lyrics(artist: String, title: String): String? =
        get(
            "getLyrics",
            mapOf("artist" to artist, "title" to title),
            "lyrics",
            PlainLyrics.serializer(),
            PlainLyrics(),
        ).value?.takeIf(String::isNotBlank)

    // Makes a playlist for the signed-in user with these songs in this
    // order, and answers with it as the server now has it (null from a
    // server older than API 1.14, which sends nothing back). `formPost`
    // sends the params in a form body, for a server that lists that
    // extension; otherwise a long list goes in batches.
    suspend fun createPlaylist(name: String, songIds: List<String>, formPost: Boolean = false): PlaylistWithSongs? {
        val (first, rest) = createCalls(name, songIds, formPost)
        val created = decode(sendCall(first, formPost), null, CreatedPlaylist.serializer(), null).playlist
        if (rest.isNotEmpty()) {
            val id = created?.id ?: throw SubsonicException.Server(0, "The server did not say the new playlist's id")
            addSongsCalls(id, rest).forEach { sendCall(it, formPost) }
        }
        return created
    }

    // Makes a playlist's songs exactly these, in this order: createPlaylist
    // with the playlist's id replaces its whole list.
    suspend fun replacePlaylistSongs(id: String, songIds: List<String>, formPost: Boolean = false) {
        replaceSongsCalls(id, songIds, formPost).forEach { sendCall(it, formPost) }
    }

    // Changes a playlist's details, takes songs out by their place in the
    // list (a place may repeat) and adds songs to the end. Only what is
    // given changes.
    suspend fun updatePlaylist(
        id: String,
        name: String? = null,
        comment: String? = null,
        public: Boolean? = null,
        songIdsToAdd: List<String> = emptyList(),
        songIndexesToRemove: List<Int> = emptyList(),
        formPost: Boolean = false,
    ) {
        updateCalls(id, name, comment, public, songIdsToAdd, songIndexesToRemove, formPost).forEach { sendCall(it, formPost) }
    }

    suspend fun deletePlaylist(id: String) = send("deletePlaylist", listOf("id" to id))

    // Runs one playlist call, with its params in the address or in a form
    // body, and hands back the answer once it is known to be ok.
    private suspend fun sendCall(call: PlaylistCall, formPost: Boolean): String {
        if (formPost) return postForm(call.endpoint, call.params)
        val address = url(call.endpoint).newBuilder().apply { call.params.forEach { (key, value) -> addQueryParameter(key, value) } }.build()
        return exchange(Request.Builder().url(address).build(), call.endpoint)
    }

    // Sends the params in a form body rather than the address, and hands
    // back the answer once it is known to be ok. Only the sign-in is in the
    // address.
    private suspend fun postForm(endpoint: String, params: List<Pair<String, String>>, http: OkHttpClient = this.http): String {
        val form = FormBody.Builder().apply { params.forEach { (key, value) -> add(key, value) } }.build()
        return exchange(Request.Builder().url(url(endpoint)).post(form).build(), endpoint, http)
    }

    private suspend fun exchange(request: Request, endpoint: String, http: OkHttpClient = this.http): String {
        val body = try {
            val response = http.newCall(request).await()
            withContext(Dispatchers.IO) {
                response.use {
                    if (!it.isSuccessful) throw SubsonicException.NotSubsonic("HTTP ${it.code} from $endpoint", it.code)
                    it.body.string()
                }
            }
        } catch (e: IOException) {
            throw SubsonicException.Unreachable(e)
        }
        withContext(Dispatchers.Default) { decode(body, null, ServerInfo.serializer(), null) }
        return body
    }

    // Gives a user a new password: the signed-in user's own, or anyone's
    // for an admin. The password goes in a form body, never in the
    // address, which proxies and servers write to their logs. When it is
    // the signed-in user's own, this client signs in with it from then on.
    // A family member's own password, which the server checks against the
    // current one. Every app then needs the new one; this client switches
    // to it at once.
    suspend fun changeFamilyPassword(current: String, next: String) {
        postForm("changeFamilyPassword", listOf("current" to current, "next" to next))
        val now = credentials
        if (now.mode != AuthMode.ApiKey) credentials = Credentials(now.username, next, now.mode)
    }

    // What this client signs in with, for sealing into a hand-over to the
    // same person's other device. Never logged or sent anywhere else.
    fun handOverSecret(): String = credentials.handOverSecret()

    suspend fun changePassword(username: String, newPassword: String) {
        postForm("changePassword", listOf("username" to username, "password" to newPassword))
        val now = credentials
        if (username == now.username && now.mode != AuthMode.ApiKey) credentials = Credentials(username, newPassword, now.mode)
    }

    // The family page's calls on this server, through this client's
    // connections and headers, each signed as every Subsonic call is.
    fun familyWeb(): FamilyWeb = FamilyWeb(baseUrl, http, ::signed)

    // The same server, headers and route signed in with another secret, for
    // checking a password without touching this client.
    fun withSecret(secret: String): SubsonicClient =
        SubsonicClient(primaryUrl, Credentials(username, secret, authMode), plainHttp, clientName, headers, musicFolderId, route)

    // A call that only answers ok or an error. The params may repeat a name.
    internal suspend fun send(endpoint: String, params: List<Pair<String, String>>) {
        val url = url(endpoint).newBuilder().apply { params.forEach { (key, value) -> addQueryParameter(key, value) } }.build()
        val body = fetch(url, endpoint)
        withContext(Dispatchers.Default) { decode(body, null, ServerInfo.serializer(), null) }
    }

    // A call whose answer may leave its key out, or null: null then.
    internal suspend fun <T> getOptional(
        endpoint: String,
        params: Map<String, String>,
        key: String,
        serializer: KSerializer<T>,
        http: OkHttpClient = this.http,
    ): T? {
        val body = fetch(url(endpoint, params), endpoint, http)
        return withContext(Dispatchers.Default) {
            val root = decode(body, null, kotlinx.serialization.json.JsonObject.serializer(), null)
            val payload = root[key]
            if (payload == null || payload is kotlinx.serialization.json.JsonNull) null else json.decodeFromJsonElement(serializer, payload)
        }
    }

    // Params in a form body rather than the address; only ok or an error.
    internal suspend fun sendForm(endpoint: String, params: List<Pair<String, String>>) {
        postForm(endpoint, params)
    }

    internal suspend fun <T> get(
        endpoint: String,
        params: Map<String, String> = emptyMap(),
        key: String?,
        serializer: KSerializer<T>,
        default: T? = null,
        http: OkHttpClient = this.http,
    ): T {
        val body = fetch(url(endpoint, params), endpoint, http)
        // Big answers (all artists is ~260 KB) must not parse on the main thread.
        return withContext(Dispatchers.Default) { decode(body, key, serializer, default) }
    }

    private suspend fun fetch(url: HttpUrl, endpoint: String, http: OkHttpClient = this.http): String {
        val request = Request.Builder().url(url).build()
        return try {
            val response = http.newCall(request).await()
            withContext(Dispatchers.IO) {
                response.use {
                    if (!it.isSuccessful) {
                        throw SubsonicException.NotSubsonic("HTTP ${it.code} from $endpoint", it.code)
                    }
                    it.body.string()
                }
            }
        } catch (e: IOException) {
            throw SubsonicException.Unreachable(e)
        }
    }

    internal fun <T> decode(body: String, key: String?, serializer: KSerializer<T>, default: T?): T {
        val root = runCatching { json.parseToJsonElement(body).jsonObject }.getOrNull()
            ?.get("subsonic-response")?.jsonObject
            ?: throw SubsonicException.NotSubsonic("The server did not answer like a Subsonic server")
        if (root["status"]?.jsonPrimitive?.contentOrNull != "ok") {
            val error = root["error"]?.jsonObject
            val code = error?.get("code")?.jsonPrimitive?.intOrNull ?: 0
            val message = error?.get("message")?.jsonPrimitive?.contentOrNull ?: "Request failed"
            throw when (code) {
                40, 44 -> SubsonicException.WrongCredentials(message)
                41, 42 -> SubsonicException.AuthNotSupported(code, message)
                70 -> SubsonicException.NotFound(message)
                else -> SubsonicException.Server(code, message)
            }
        }
        val payload = if (key == null) root else root[key]
        return when {
            payload != null -> json.decodeFromJsonElement(serializer, payload)
            default != null -> default
            else -> throw SubsonicException.Server(0, "Missing \"$key\" in the answer")
        }
    }

    // The params with the folder added, when there is one.
    private fun Map<String, String>.inFolder(folder: String?) = if (folder == null) this else this + ("musicFolderId" to folder)

    // The queue saved on the server, or null when none is. Only for
    // servers that list the indexBasedQueue extension.
    suspend fun playQueueByIndex(): PlayQueueByIndex? =
        get("getPlayQueueByIndex", key = "playQueueByIndex", serializer = PlayQueueByIndex.serializer(), default = PlayQueueByIndex())
            .takeIf { it.entry.isNotEmpty() }

    // The older form, where the current song is named by id.
    suspend fun playQueue(): PlayQueue? =
        get("getPlayQueue", key = "playQueue", serializer = PlayQueue.serializer(), default = PlayQueue())
            .takeIf { it.entry.isNotEmpty() }

    // Saves the queue, with the current song as its place in the list.
    suspend fun savePlayQueueByIndex(ids: List<String>, currentIndex: Int, positionMs: Long) =
        send("savePlayQueueByIndex", queueSaveParams(ids, currentIndex, positionMs, indexBased = true))

    // Saves the queue, with the current song named by id.
    suspend fun savePlayQueue(ids: List<String>, currentIndex: Int, positionMs: Long) =
        send("savePlayQueue", queueSaveParams(ids, currentIndex, positionMs, indexBased = false))

    // Makes a public link to songs or an album. Servers answer with the new
    // share; one with sharing switched off answers with an error.
    suspend fun createShare(ids: List<String>, description: String? = null, expiresAtMs: Long? = null): Share =
        getWith("createShare", shareParams(ids, description, expiresAtMs), "shares", Shares.serializer(), Shares())
            .share.firstOrNull() ?: throw SubsonicException.Server(0, "The server made no share")

    // The signed-in user's shares.
    suspend fun shares(): List<Share> =
        get("getShares", key = "shares", serializer = Shares.serializer(), default = Shares()).share

    suspend fun deleteShare(id: String) = send("deleteShare", listOf("id" to id))

    // Asks the server to read its music folders again. Needs an admin.
    suspend fun startScan(): ScanStatus =
        get("startScan", key = "scanStatus", serializer = ScanStatus.serializer(), default = ScanStatus())

    suspend fun scanStatus(): ScanStatus =
        get("getScanStatus", key = "scanStatus", serializer = ScanStatus.serializer(), default = ScanStatus())

    // What everyone on the server is playing right now.
    suspend fun nowPlaying(): List<NowPlayingEntry> =
        get("getNowPlaying", key = "nowPlaying", serializer = NowPlayingList.serializer(), default = NowPlayingList()).entry

    // The radio stations with their home pages, for editing. Patient for
    // the same reason as radioStations.
    suspend fun radioStationDetails(): List<RadioStationDetails> =
        get(
            "getInternetRadioStations",
            key = "internetRadioStations",
            serializer = RadioStationDetailsList.serializer(),
            default = RadioStationDetailsList(),
            http = patient,
        ).internetRadioStation

    suspend fun createRadioStation(streamUrl: String, name: String, homepageUrl: String? = null) =
        send("createInternetRadioStation", stationParams(streamUrl, name, homepageUrl))

    suspend fun updateRadioStation(id: String, streamUrl: String, name: String, homepageUrl: String? = null) =
        send("updateInternetRadioStation", listOf("id" to id) + stationParams(streamUrl, name, homepageUrl))

    suspend fun deleteRadioStation(id: String) = send("deleteInternetRadioStation", listOf("id" to id))

    // Where a postal code (`code`) or a city (`name`, with `state` when
    // known) is in `country` (ISO alpha-2), or, with neither, the nearest
    // place to a position (`latitude`, `longitude`), on a server that lists
    // octoPlaces; null when the server does not know the place.
    suspend fun place(
        code: String?,
        name: String?,
        state: String?,
        country: String,
        latitude: Double? = null,
        longitude: Double? = null,
    ): Place? =
        try {
            getOptional("getPlace", placeParams(code, name, state, country, latitude, longitude), "place", Place.serializer())
        } catch (e: SubsonicException.NotFound) {
            null
        }

    // Like get, for params that may repeat a name.
    internal suspend fun <T> getWith(
        endpoint: String,
        params: List<Pair<String, String>>,
        key: String,
        serializer: KSerializer<T>,
        default: T,
    ): T {
        val url = url(endpoint).newBuilder().apply { params.forEach { (name, value) -> addQueryParameter(name, value) } }.build()
        val body = fetch(url, endpoint)
        return withContext(Dispatchers.Default) { decode(body, key, serializer, default) }
    }

    private companion object {
        val json = Json {
            ignoreUnknownKeys = true
            coerceInputValues = true
            explicitNulls = false
        }
    }
}

// Runs the call without blocking a thread, and cancels it if the caller
// stops waiting.
internal suspend fun Call.await(): Response = suspendCancellableCoroutine { cont ->
    cont.invokeOnCancellation { cancel() }
    enqueue(object : Callback {
        override fun onFailure(call: Call, e: IOException) = cont.resumeWithException(e)
        override fun onResponse(call: Call, response: Response) {
            cont.resume(response) { _, value, _ -> value.close() }
        }
    })
}

// The type a list file is sent as, by its name's ending.
internal fun importFileType(name: String) = when (name.substringAfterLast('.', "").lowercase()) {
    "csv" -> "text/csv"
    "json" -> "application/json"
    "zip" -> "application/zip"
    "txt" -> "text/plain"
    else -> "application/octet-stream"
}.toMediaType()
