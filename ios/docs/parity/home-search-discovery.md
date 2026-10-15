# Parity contract: home, search and discovery

Read from octo-player origin/main 0f11df0f (git ref `origin/main`, read 2026-10-11). Every item below is one behavior the iPhone app must match exactly.

Path prefixes used in the citations:

- `app/` is `app/src/main/java/app/winters/octo/`
- `core/` is `shared/core/src/commonMain/kotlin/app/winters/octo/`
- `subsonic/` is `subsonic/src/main/kotlin/app/winters/octo/subsonic/`
- `design/` is `design/src/main/java/app/winters/octo/design/`

## 1. Server kinds: Octo, plain Subsonic, no server

- [x] A server "runs Octo" when it was probed as Octo, or its `serverType` equals "octo" ignoring case, or any extension name starts with "octo". This can turn true after sign-in once extensions are read again. (app/data/OctoProbe.kt:17-19)
- [x] Session extensions are kept as strings of the form "name:version" and checks look for the exact string, for example "octoTopSongs:2". (app/discovery/ChartLists.kt:80, app/discovery/SearchTopSongs.kt:83, app/discovery/Downloads.kt:325)
- [x] With no server signed in every Discovery call answers nothing: search answers null, radio/stations/Made for you/station songs answer an empty list, album and artist pages answer null. (app/discovery/Discovery.kt:120-215, 311-314)
- [x] `Discovery.available` is true only while the session state is SignedIn. (app/discovery/Discovery.kt:103)
- [x] `Discovery.server` is the signed-in account id, distinct-until-changed; switching to another kept server changes it, so search, the empty-search chart and top songs are asked again. (app/discovery/Discovery.kt:108)
- [x] `Discovery.stationsFrom` is the session id only while the signed-in server runs Octo, else null; distinct-until-changed. (app/discovery/Discovery.kt:117-118)
- [x] Stations and Made for you exist only on Octo; any other server shows neither shelf (other servers list internet radio, which is a stream, not songs). (app/discovery/Discovery.kt:145-162)
- [x] Home's Charts row and the Charts page need `octoTopSongs:2` in the extensions, or else a server that runs Octo answering a live extensions check for octoTopSongs version 2. (app/discovery/ChartLists.kt:79-86)
- [x] Search's artist top songs and the empty-search chart need `octoTopSongs:1` in the extensions, or else Octo answering a live check for octoTopSongs version 1. (app/discovery/SearchTopSongs.kt:82-89)
- [x] A live extension check's answer is cached per server sourceId only when the server itself answered (true or false); an unreachable server is asked again next time. (app/discovery/ChartLists.kt:82-85, app/discovery/SearchTopSongs.kt:85-88)
- [x] The live check (`supportsIfKnown`): Unreachable answers unknown; NotSubsonic answers false when it has an HTTP status and the server is not busy, else unknown; WrongCredentials answers unknown; any other Subsonic error answers false. (subsonic/SubsonicClient.kt:116-127)
- [x] The server downloads sheet, the downloads pill, follow-from-button and Find songs need `octoAcquisitions:2`. (app/data/ServerDownloads.kt:162, 166)
- [x] "Asks first" (Replace anyway) is on only when the server lists both `octoAcquisitions:2` and `octoAcquisitions:3`. (app/data/ServerDownloads.kt:163-165)
- [x] Higher quality copies (getUpgrades) are read only when the server lists `octoLibraryActions:2`; otherwise the upgrades list is empty. (app/data/ServerDownloads.kt:101-104)
- [x] Live download progress (getAcquisitions) is used when the server lists `octoAcquisitions:1`, else after a live check; a "yes" is kept, a "no" is rechecked after 10 minutes. (app/discovery/Downloads.kt:75, 323-337)
- [x] The library album "as the server lists it now" (with finds) is only for Octo. (app/discovery/Discovery.kt:185-194)
- [x] Only Octo marks playlists as Made for you lists (`octoList`), so any other server gives an empty Made for you. (app/discovery/Discovery.kt:60-63)

## 2. Home: layout and gate

- [x] Home is a vertical list with pull to refresh; the first item is the screen title "Home". (app/ui/home/HomeScreen.kt:76-83) (iPhone: system pull to refresh)
- [x] Order of items: title, access card (when asked), resume card, what's new card, then either the empty card plus Charts, or the shelves. (app/ui/home/HomeScreen.kt:83-120)
- [x] `homeLayout`: askAccess = phone access is not Granted AND accessDismissed is exactly false (null, not read yet, shows nothing). (app/ui/home/HomeGate.kt:29-31)
- [x] `homeLayout`: shelves = library song count is known and greater than 0; the count is every song in the library, phone and server together (`SELECT COUNT(*) FROM track`). (app/ui/home/HomeGate.kt:32, app/catalog/CatalogDao.kt:139-140)
- [x] `homeLayout`: empty = library song count is exactly 0 (null shows neither, so nothing flickers). (app/ui/home/HomeGate.kt:33)
- [x] A listener with only a server still gets full shelves. (app/ui/home/HomeGate.kt:25-28)
- [x] Empty layout shows the empty card, then the Charts song shelf (the charts help most in an empty library). (app/ui/home/HomeScreen.kt:88-92)
- [x] Shelves layout order: Pinned, Recently played, Made for you, Stations, Charts, Recently added, Favorite albums, Most played, Something different, Not played in 6 months, Albums you never finished, Unplayed albums, Artists. (app/ui/home/HomeScreen.kt:93-118)
- [x] Every shelf hides itself entirely (title and row) when its list is empty. (app/ui/home/HomeScreen.kt:131, 152, 199; app/ui/home/PinnedShelf.kt:47)
- [x] Every shelf row is a horizontal list with 20dp side content padding and 14dp between items. (app/ui/home/HomeScreen.kt:134-137, 155-158, 202-205)
- [x] Shelf titles sit 18dp below the previous item. (app/ui/home/HomeScreen.kt:171, 176, 200)
- [x] A shelf title that opens a page is a button with accessibility label "Open <title>" and a chevron icon 22dp, tint TextMuted, drawn offset 16dp to the left into the title's end margin. (app/ui/home/HomeScreen.kt:168-189) (iPhone: a navigation link with the SF Symbol chevron, hint "Open <title>")
- [x] Titles that open pages: "Recently played" opens History; "Charts" opens the Charts page; "Favorite albums" opens Favorites on the albums part; "Most played" opens History on most played. All others are plain titles. (app/ui/home/HomeScreen.kt:91, 95, 98, 100, 101)
- [x] Stations and Made for you titles are never buttons. (app/ui/home/HomeScreen.kt:200)
- [x] All Home flows use "while subscribed, 5 seconds" sharing (they stop 5 s after Home leaves). (app/ui/home/HomeViewModel.kt:62-95) (iPhone: the state lives with the screen and is read again whenever it shows)

## 3. Home: phone access card and empty card

- [x] Access card: glass panel, 20dp corner radius, 20dp side margin, 12dp bottom margin, 20dp inner padding, 6dp between lines. (app/ui/home/HomeScreen.kt:218-225)
- [x] Access card text: "Music on this phone" (bodySmall, TextPrimary), then "Allow access to play the music already on your phone here too." (caption, TextSecondary). (app/ui/home/HomeScreen.kt:227-232)
- [x] Access card buttons, 10dp below, 12dp apart: accent button "Allow" (or "Open settings" when access is denied for good), and glaze button "Not now". (app/ui/home/HomeScreen.kt:233-236, app/ui/common/LibraryReach.kt:80)
- [x] "Not now" stores `phone_access_dismissed = true` in the "home" preferences store and the card never shows again; the empty Library pages still offer access. (app/ui/home/HomeGate.kt:36-48, app/ui/home/HomeViewModel.kt:194-196)
- [x] Empty card: "No music yet" (headline, TextPrimary) and "Songs on this phone and on your server show up here on their own." (bodySmall, TextMuted), 20dp side padding, 6dp spacing. (app/ui/home/HomeScreen.kt:243-250)
- [x] Empty card actions 12dp below: "Allow access" (or "Open settings" when denied for good) only when access is missing AND the access card above is not already asking; "Sign in to a server" only when signed out. Nothing when neither applies. Buttons flow-wrap 12dp apart. (app/ui/home/HomeScreen.kt:251, app/ui/common/LibraryReach.kt:86-98)

## 4. Home: resume card (carry on from another device)

- [x] Shows when the queue sync has an offer: the server's saved queue changed later than both this phone's last save and the last offer answered here, and it is not this phone's own save stamp, and it has a current song. (core/server/ServerQueues.kt:74-79, app/server/QueueSync.kt:241)
- [x] The offer is looked for when the app comes to the front, at most once every 30 seconds, and at once when another server comes into use. Not while "Sync play queue with the server" is off. (app/server/QueueSync.kt:52, 172-193, 219-222)
- [x] Device name is the queue's `changedBy`, trimmed, or "another device" when empty. (app/server/QueueSync.kt:242)
- [x] Card layout: glass panel radius 20dp, 20dp side margin, 8dp bottom margin, 20dp padding, 4dp between lines. (app/ui/home/ResumeCard.kt:84-91)
- [x] Line 1: "Pick up where you left off on <device>" (caption, TextMuted). Line 2: song title (body, TextPrimary, 1 line, ellipsis). Line 3: artist (bodySmall, TextSecondary, 1 line, ellipsis) only when not blank; artist is displayArtist else artist. (app/ui/home/ResumeCard.kt:93-97, app/server/QueueSync.kt:242)
- [x] Buttons 12dp below, 12dp apart: accent "Resume" with a loading state, glaze "Not now". (app/ui/home/ResumeCard.kt:98-101)
- [x] Resume: ignored while already loading; resolves the remote songs to library songs and finds; when none resolve nothing happens; loads the queue in place of this one, paused, at the current song and its position (position 0 when the current song is not found, index 0). (app/ui/home/ResumeCard.kt:54-69, app/server/QueueSync.kt:196-204)
- [x] Resume and Not now both record the offer's `changedAt` as answered for this server, so the same queue is never offered again; the card hides at once. (app/server/QueueSync.kt:207-216)
- [x] Resume failures are logged only, never shown. (app/ui/home/ResumeCard.kt:63-65)
- [x] Appears with fade in plus expand vertically, leaves with fade out plus shrink vertically; the last offer stays drawn while it folds away. (app/ui/home/ResumeCard.kt:80-83)

## 5. Home: what's new card

- [x] Due once after each update: last seen version code is null means due unless this is a fresh install; otherwise due when last seen < current version code. (app/whatsnew/WhatsNew.kt:25-26)
- [x] Fresh install = first install time equals last update time (missing package info counts as fresh). A fresh install is marked seen at once (settle on view model start). (app/whatsnew/WhatsNew.kt:39-54, app/ui/home/WhatsNewCard.kt:47) (iPhone: Apple gives apps no install or update time, so a fresh install is one with none of Octo's settings stored yet)
- [x] Stored in the "whats_new" preferences store under int key `last_seen_version`. (app/whatsnew/WhatsNew.kt:28-30)
- [x] Starts hidden until the stored state is read, so it never flashes. (app/ui/home/WhatsNewCard.kt:43-44)
- [x] Card: glass panel radius 20dp, 20dp side margin, 8dp bottom margin, 20dp padding, 4dp spacing; "New in Octo" (caption, TextMuted); summary "A new equalizer, sorting, favorites, downloads and much more" (body, TextPrimary, max 2 lines, ellipsis). (app/ui/home/WhatsNewCard.kt:62-78, app/whatsnew/WhatsNew.kt:17)
- [x] Buttons 12dp below, 12dp apart, both glaze: "See what's new" opens the panel; "Dismiss" marks seen. (app/ui/home/WhatsNewCard.kt:79-82)
- [x] Closing the panel also marks seen. (app/ui/home/WhatsNewCard.kt:85-91)
- [x] Panel: centered glass popup, title "What's new", max width 460dp, 82% of the screen height; content scrolls; padding 24 start/end, 26 top, 28 bottom; small "What's new" label (TextSecondary), then "Octo <version name>" big title with 2dp top and 18dp bottom padding (a heading), then the markdown of `whats_new.md` from the app's assets. Unreadable notes show nothing. Tap outside or back closes. (app/whatsnew/WhatsNewPanel.kt:32-68) (iPhone: a system sheet at medium and large heights that a swipe down closes; the notes are built into the app)
- [x] Card enter: fade in plus expand vertically; exit: fade out plus shrink vertically. (app/ui/home/WhatsNewCard.kt:61)

## 6. Home: Pinned shelf

- [x] First shelf in the shelves layout, titled "Pinned", showing pinned albums, artists and playlists in their pinned order. (app/ui/home/PinnedShelf.kt:43-48, app/ui/home/HomeViewModel.kt:61-62)
- [x] Item key is "<kind id>:<id>"; items animate when they move or change (animateItem). (app/ui/home/PinnedShelf.kt:54-69)
- [x] An album is a normal album card (tap opens the album; long press opens the album menu, which can unpin or move to front). (app/ui/home/PinnedShelf.kt:56) (iPhone: system context menu, with Unpin and Move to front)
- [x] An artist card: 150dp wide, round artwork 150dp, name (bodySmall SemiBold, 1 line, ellipsis), subtitle "Artist" (caption, TextMuted); tap opens the artist. (app/ui/home/PinnedShelf.kt:57-63, 84-118)
- [x] A playlist card: 150dp wide, playlist artwork with phone playlist footer (song count) and the playlist glyph from its Octo notice; subtitle "Playlist"; tap opens the playlist. (app/ui/home/PinnedShelf.kt:64-74)
- [x] Artist and playlist cards: long press does a long-press haptic and opens the collection menu (accessibility label "More options"). (app/ui/home/PinnedShelf.kt:97-104) (iPhone: system context menu, which gives its own haptic)

## 7. Home: album shelves

- [x] Album card: 150dp wide, square artwork fill, 8dp gap, title (bodySmall SemiBold, 1 line, ellipsis), artist (caption, TextMuted, 1 line, ellipsis). Tap opens the album; long press opens the album menu with haptic; press squeezes. (app/ui/common/Items.kt:80-158) (iPhone: system context menu, which gives its own haptic)
- [x] "Recently played": albums from the play history (phone and server together), newest last play first, ties by album id, at most 20. Follows the history live, so a song that just counted shows. (app/ui/home/HomeViewModel.kt:71-73, app/catalog/Plays.kt:25-29)
- [x] "Recently added": `SELECT * FROM album ORDER BY addedAt DESC LIMIT 20`; null until read. (app/ui/home/HomeViewModel.kt:86-87, app/catalog/CatalogDao.kt:14-15)
- [x] "Favorite albums": liked albums the library still has, newest like first, at most 20. (app/ui/home/HomeViewModel.kt:65-67, app/catalog/FavouritesDao.kt:28-29)
- [x] "Something different": 20 random albums (`ORDER BY RANDOM()`), picked once and again only on a pull, a change in library size, or after a server copy finishes (sync time changes). (app/ui/home/HomeViewModel.kt:97-100, 128-133, 245-248)
- [x] "Not played in 6 months": albums whose latest play is before now minus 180 days, most plays first, then older last play first, then id; at most 20. (core/home/Rediscovery.kt:29, 35-42; app/ui/home/Rediscovery.kt:10)
- [x] "Albums you never finished": albums with at least one played song and fewer played songs than the album holds, newest last play first (no date last), then id; at most 20; an album already on "Not played in 6 months" is left out. (core/home/Rediscovery.kt:46-51, 85-93)
- [x] "Unplayed albums": albums none of whose songs was ever played (no played songs, no plays, no play date), newest added first (unknown last), then id; at most 20. (core/home/Rediscovery.kt:25, 54-59)
- [x] Each album's listening on the phone: its played songs grouped by album id, each song once; songs = the album's own song count; played songs = songs with plays > 0; plays = sum; last played = latest play time when > 0, else none; added = album addedAt when > 0, else none. (app/ui/home/Rediscovery.kt:14-28)
- [x] The rediscovery shelves are worked out off the main thread from all albums plus the play history, again whenever either changes. (app/ui/home/HomeViewModel.kt:81-84)

## 8. Home: song shelves (Charts, Most played)

- [x] Song card: 150dp wide, faded when out of reach offline, artwork fill with the not-in-library mark for a find, title (bodySmall SemiBold, explicit mark), artist (caption, TextMuted) plus the source mark. Tap plays the shelf from that song; long press opens the song menu. (app/ui/common/Items.kt:164-193)
- [x] Tapping a song plays the shelf's songs as shown, starting at the one tapped. (app/ui/home/HomeScreen.kt:145-164, app/ui/home/HomeViewModel.kt:199)
- [x] "Most played": play history songs by plays, most first, then latest play, then id; at most 20. (app/ui/home/HomeViewModel.kt:75-77, app/catalog/Plays.kt:33-41)
- [x] "Charts": the first 10 songs (CHARTS_ROW) of the overall chart (chart id "34") as the Charts page reads it; empty on a server without charts. (app/ui/home/HomeViewModel.kt:114-117, 201-205; core/discovery/TopSongs.kt:68; subsonic/TopSongs.kt:22)
- [x] Charts load only when the stations source (Octo) changes to a server: on sign-in, server switch or turning Octo; they are cleared on every change and not reloaded on a pull or on Home showing again (the chart itself is cached an hour). (app/ui/home/HomeViewModel.kt:138-152)

## 9. Home: Made for you and Stations

- [x] "Made for you" comes before "Stations". (app/ui/home/HomeScreen.kt:96-97)
- [x] Made for you lists: the server's playlists that carry `octoList`, ordered by kind: liked, newReleases, rediscover, deepCuts; an unknown kind goes last, keeping server order among equals. (app/discovery/Discovery.kt:60-63, subsonic/Models.kt:229)
- [x] Each Made for you list's cover is the server cover of its coverArt, else of its own id; it carries its song count. (app/discovery/Discovery.kt:63)
- [x] Stations: `getInternetRadioStations` (long timeout client); each station's cover is its coverArt else its id; no song count. (app/discovery/Discovery.kt:147-154, subsonic/SubsonicClient.kt:436-443)
- [x] Station card: 150dp wide, square artwork fill, 8dp gap, name (bodySmall SemiBold, 1 line, ellipsis); a Made for you list adds "1 song" or "<n> songs" (bodySmall, TextSecondary). (app/ui/home/Stations.kt:31, 45-72)
- [x] The card fades to 50% opacity (animated) while its songs are on the way. (app/ui/home/Stations.kt:46)
- [x] Tap plays what the station or list has lined up now (getPlaylist of its id, resolved to library songs and finds) from the first song. (app/ui/home/HomeViewModel.kt:166-173, app/discovery/Discovery.kt:165-168)
- [x] Taps while any station is starting are ignored. (app/ui/home/HomeViewModel.kt:167)
- [x] An empty answer shows the toast "Nothing is playing on <name> right now" and still calls play with the empty list. (app/ui/home/HomeViewModel.kt:172-173)
- [x] A "not found" answer (the server made its stations anew): the station is removed from both shelves, the lists are read again, and the toast says "<name> isn't on the server any more". (app/ui/home/HomeViewModel.kt:176-183, app/ui/home/Stations.kt:28)
- [x] Any other failure shows "Could not start <name>". (app/ui/home/HomeViewModel.kt:184-186)
- [x] Loading runs in the background; stations and Made for you are read one after the other but separately, so one failing never hides the other; a failure keeps the last list. (app/ui/home/HomeViewModel.kt:220-243)
- [x] Only one load at a time. A load counts as fresh only when both succeeded. (app/ui/home/HomeViewModel.kt:221, 240-241)
- [x] When Home comes back on screen (resume), it asks again if stations are offered and: not loading, and (the last load failed, or never loaded, or loaded 10 minutes ago or more). (app/ui/home/HomeViewModel.kt:157-162, app/ui/home/Stations.kt:24, 35-39)
- [x] A new sign-in, another kept server, or the server turning out to be Octo: cancels the load, clears stations, Made for you and charts, then loads stations and charts when the server runs Octo. Signing out leaves them empty. (app/ui/home/HomeViewModel.kt:134-152)

## 10. Home: Artists shelf, refresh and reroll

- [x] "Artists" shelf: 16 random artists, rerolled with "Something different"; title 18dp from above; circles 96dp. Tap opens the artist; long press opens the artist menu. (app/ui/home/HomeScreen.kt:106-118, app/ui/home/HomeViewModel.kt:247, app/ui/common/Items.kt:545-573)
- [x] Artist circle: 96dp wide column, round 96dp artwork, 8dp gap, name (caption, TextPrimary, 1 line, ellipsis, centered). (app/ui/common/Items.kt:557-573)
- [x] Pull to refresh: shows refreshing, rescans the phone's music, rerolls random albums and artists, then stops refreshing; also reloads stations and Made for you when offered. (app/ui/home/HomeViewModel.kt:207-215)
- [x] Reroll triggers: once at start, whenever the library song count changes, and whenever the last server sync time changes (a copy can change the music without changing the count). (app/ui/home/HomeViewModel.kt:128-133)

## 11. Search: field, filters and top of the page

- [x] Screen: status bar padding plus 8dp, title "Search". (app/ui/search/SearchScreen.kt:123-124)
- [x] Glass input, 20dp side padding, placeholder "Songs, albums, artists", keyboard action Search, which only hides the keyboard. (app/ui/search/SearchScreen.kt:125-131)
- [x] A clear button (cross) shows in the field only while the text is not empty: 40dp circle, close icon 20dp TextMuted, accessibility "Clear search"; it empties the field. (app/ui/search/SearchScreen.kt:132, 341-356) (iPhone: SF Symbol xmark)
- [x] Segmented control under the field (12dp top, 20dp sides): All, Songs, Albums, Artists, Playlists. Picking one also scrolls the results to the top. (app/ui/search/SearchViewModel.kt:50-56, app/ui/search/SearchScreen.kt:118-121, 134-139) (iPhone: system segmented control)
- [x] "Library songs only" chip (10dp top, 20dp start) shows only while a server is signed in; it toggles the app-wide setting. (app/ui/search/SearchScreen.kt:140-142, core/discovery/LibraryOnly.kt:5)
- [x] With "Library songs only" on, nothing from the server's online finds shows: the discover section is idle, the top songs and the chart keep only library songs (each at its own rank) and disappear when none is left. (app/ui/search/SearchScreen.kt:104-107, 146; app/discovery/SearchTopSongs.kt:29-30)
- [x] Dragging any list hides the keyboard (any user scroll with vertical movement). (app/ui/search/SearchScreen.kt:358-367) (iPhone: the lists dismiss the keyboard as they scroll)
- [x] Results list padding: 12dp top, bottom = navigation bar plus 120dp. (app/ui/search/SearchScreen.kt:108, 174)

## 12. Search: which state shows

- [x] Text blank AND (recent searches exist OR a chart exists): the recent searches list with the chart under it. (app/ui/search/SearchScreen.kt:150-166)
- [x] Otherwise, library results null (fewer than 2 characters after folding): the hint "Search your music and discover more" when signed in, else "Search the music on your phone". (app/ui/search/SearchScreen.kt:167)
- [x] Library results empty AND nothing online (idle, or done with nothing): the hint "No results for "<trimmed text>"". (app/ui/search/SearchScreen.kt:148, 168)
- [x] Otherwise the results list, with multi-select over every song shown. (app/ui/search/SearchScreen.kt:170-196)
- [x] Library results empty and the server failed: a "No results for "<trimmed text>"" hint row inside the list, above the discover section. (app/ui/search/SearchScreen.kt:188-191)
- [x] Hint style: bodySmall, TextMuted, full width, 20dp sides, 24dp top and bottom. (app/ui/search/SearchScreen.kt:496-504)

## 13. Search: library results

- [x] Library search runs 150ms after typing pauses, on the folded text (trimmed, accents removed, lower case), only when it is at least 2 characters long. (app/ui/search/SearchViewModel.kt:138-147, core/catalog/Keys.kt:9-10)
- [x] It runs again when the filter changes, the playlists change, or each time the server is asked anew. (app/ui/search/SearchViewModel.kt:129-143, 193)
- [x] Each kind matches `searchKey LIKE '%q%'`, ordered by sortKey. (app/catalog/CatalogDao.kt:115-119, 132-133)
- [x] Playlists match when the folded playlist name contains the folded query. (app/ui/search/SearchViewModel.kt:152)
- [x] Caps for All: 10 artists, 20 albums, 50 songs, 10 playlists. Songs: 1,000 songs only. Albums: 500 albums only. Artists: 500 artists only. Playlists: 500 playlists only. (app/ui/search/SearchViewModel.kt:63-69)
- [x] One more than the cap is asked for, to know whether a kind has more ("See all"). (app/ui/search/SearchViewModel.kt:149-162)
- [x] All: Artists title and row of artist circles; then the artist's top songs (if any); Albums title and row of album cards; Playlists title and rows; Songs title and rows. (app/ui/search/SearchScreen.kt:202-252)
- [x] Kind titles: section title with a "See all" quiet button only when that kind has more; See all switches the filter to that kind and scrolls to top. The first title has no top padding; later ones 12dp. (app/ui/search/SearchScreen.kt:209-216, 284-293)
- [x] One kind picked: artists as rows (48dp round picture, name, "N albums"/"1 album", at least 64dp tall), albums two per row (20dp sides, 9dp top and bottom, 14dp gap, each card filling half, an empty half when the count is odd), playlists as rows, songs as rows. (app/ui/search/SearchScreen.kt:254-271, app/ui/common/Items.kt:521-540)
- [x] Playlist rows: name, "<n> songs" ("1 song"), on-server mark, 56dp playlist artwork with phone footer and glyph; tap opens the playlist. (app/ui/search/SearchScreen.kt:273-281)
- [x] Library song rows have no add button and no empty add space. (app/ui/search/SearchScreen.kt:250, 270)
- [x] Tapping a library song plays all listed library songs from the one tapped, and saves the search to recent. (app/ui/search/SearchViewModel.kt:276-280)
- [x] Opening any result (artist, album, playlist, online album, online artist) saves the search to recent first. (app/ui/search/SearchScreen.kt:112-116)
- [x] A song that joins the library while results are shown stays among the online finds until the next search; once the library is searched again, a find whose library song is listed is dropped from the finds, so no song shows twice. (app/ui/search/SearchViewModel.kt:81-99, 132-136, 163)

## 14. Search: recent searches

- [x] Kept in the "search" preferences store under string key "recent", one search per line, newest first, at most 10. (app/ui/search/RecentSearches.kt:16-37, core/ui/search/RecentSearchRules.kt:6, 26-29) (iPhone: the app's settings store, key "search.recent")
- [x] Saved only when a result is opened or played, never while typing. (app/ui/search/RecentSearches.kt:20-21)
- [x] Saved form: trimmed, runs of whitespace made one space; an empty one is not saved. (core/ui/search/RecentSearchRules.kt:11, 16-18)
- [x] Saving one already there (any case) moves it to the top instead of adding it twice. (core/ui/search/RecentSearchRules.kt:19)
- [x] Removing one removes every entry equal to it ignoring case. (core/ui/search/RecentSearchRules.kt:22-23)
- [x] List: "Recent searches" section title with "Clear all" quiet button (clears all); rows 48dp tall, 20dp start, 8dp end padding, query (body, 1 line, ellipsis), cross button 40dp "Remove <query>". Rows animate in place. (app/ui/search/SearchScreen.kt:297-338) (iPhone: SF Symbol xmark)
- [x] Tapping a row hides the keyboard and puts the query in the field (does not itself save it). Accessibility click label "Search again". (app/ui/search/SearchScreen.kt:153-156, 319) (iPhone: accessibility hint "Search again")
- [x] The recent list has 12dp top and 140dp bottom padding. (app/ui/search/SearchScreen.kt:306)

## 15. Search: chart before typing ("Popular right now")

- [x] Shown under the recent searches when the field is blank, titled "Popular right now"; its title has 12dp top padding only when recent searches show above it. (app/ui/search/SearchScreen.kt:160-165)
- [x] Source: getTopChart with count 50 and no chart id; kept one hour per kept server (one slot); asked anew when the server in use changes. (app/discovery/SearchTopSongs.kt:61-71, core/discovery/TopSongs.kt:22)
- [x] An answer that arrives after the server changed is dropped. (app/discovery/SearchTopSongs.kt:68-69)
- [x] Shows 10 rows, with "Show all" when it has more than 10, then "Show fewer"; the open state is kept for the visit. (core/discovery/TopSongs.kt:23, app/ui/search/SearchScreen.kt:536-540)
- [x] Rows show the artist in the subtitle (withArtist). Tapping plays the whole chart from that song; it does not save a recent search (the chart names no artist). (app/ui/search/SearchViewModel.kt:283-286)

## 16. Search: artist top songs

- [x] Only on the All filter, once library results are worked out (2 or more characters, even when they are empty) and a server is in use. (app/ui/search/SearchViewModel.kt:214-219)
- [x] The named artist: the first library artist among the listed results (at most the 10 shown) whose name equals the typed text (case, accents and a leading "The" aside); else the first such artist found online; "daft" or a song title names nobody. (app/ui/search/SearchViewModel.kt:301-305, core/discovery/TopSongs.kt:28-31)
- [x] Waits 150ms after typing pauses. Each change of named artist first closes "Show all" and clears the list, then asks getArtistTopSongs(name, id, 20); id is the server artist id (online find) or the server's id parsed from the library artist id when it came from this server. (app/ui/search/SearchViewModel.kt:208-228, app/discovery/SearchTopSongs.kt:50-57)
- [x] Not cached; an answer for a server no longer in use is dropped; an empty list hides the section. (app/discovery/SearchTopSongs.kt:50-57, 74-78)
- [x] Section "Top songs" after the artists row, 12dp top; 5 rows shown, "Show all" when more than 5, then "Show fewer". (app/ui/search/SearchScreen.kt:177-184, core/discovery/TopSongs.kt:17-18)
- [x] Under the title a caption line: "<artist> · <ranked by>"; ranked by is "Most played on Last.fm", "Most popular on Deezer", "Most played on Apple Music", or omitted for an unknown source. (app/ui/search/SearchScreen.kt:543-553, core/discovery/TopSongs.kt:56-65)
- [x] Rows omit the artist from the subtitle. Tapping plays the whole list from that song and saves the search to recent. (app/ui/search/SearchScreen.kt:561, app/ui/search/SearchViewModel.kt:283-286)

## 17. Search: ranked rows (top songs, chart, Charts page)

- [x] Lead: the rank right-aligned in a 20dp column (caption, TextMuted), 10dp gap, then the 44dp artwork. (app/ui/common/Items.kt:423-432)
- [x] Subtitle parts joined by " • ": artist (only where shown and not empty), album (left out for a find whose album equals its title), plays text. (app/ui/search/SearchScreen.kt:559-565, app/ui/common/Items.kt:218-219)
- [x] Plays text: "1 play", "<n> plays" under 1,000, then K/M/B with one decimal under 10 (whole when .0), rounded whole from 10 up; 999,960 reads "1M plays". (core/discovery/TopSongs.kt:34-51)
- [x] Each row offers add: a find gets the add button at the end, a library song keeps a 40dp empty space so lengths line up. (app/ui/search/SearchScreen.kt:566-569)
- [x] Rank of each entry: the server's rank when above 0, else its 1-based place in the list; a song missing from the library is left out; a song listed twice stands once at its better place; plays come from Last.fm counts. (app/discovery/SearchTopSongs.kt:106-111)
- [x] Rows keyed "<section>:<track id>". (app/ui/search/SearchScreen.kt:555)

## 18. Search: the server's finds (discover section)

- [x] It says it is looking as soon as the text changes, then asks the server 400ms after typing pauses; new text cancels the earlier ask. Only when a server is in use and the folded trimmed text is at least 2 characters; otherwise idle. (app/ui/search/SearchViewModel.kt:47, 177-202)
- [x] States: Idle, Loading, Done(found), Failed. A null answer (no server) is Idle. (app/ui/search/SearchViewModel.kt:102-108, 194-200)
- [x] Server call: search3 with 10 artists, 20 albums, 40 songs (always more than 12, since Octo holds back online songs for asks of 12 or fewer), on the trimmed text. (app/discovery/Discovery.kt:31-33, 120-122)
- [x] Songs listed: only finds (ids starting "find:"); songs resolving to library songs are dropped. (app/discovery/Discovery.kt:123)
- [x] Albums listed: not known from this server and not matching a library album by title and artist keys; albums the library holds whole are dropped; those held in part go to "Partly in your library"; the rest under "Not in your library". (app/discovery/Discovery.kt:127-134, 289-295)
- [x] Artists listed: not known from this server ("<sourceId>:<id>") and no library artist with the same name key. (app/discovery/Discovery.kt:297-304)
- [x] The filter narrows finds: Playlists shows none; Songs only songs; Albums albums plus part albums; Artists only artists; All everything. (app/ui/search/SearchScreen.kt:369-383)
- [x] The section shows only when there is something online (not idle, not done-with-nothing). (app/ui/search/SearchScreen.kt:148, 192-194)
- [x] "Partly in your library" title first (12dp top when library results above), then a row of those album cards with "<owned> of <songs> in your library" under each. If nothing else was found, the section ends there. (app/ui/search/SearchScreen.kt:401-417, core/discovery/AlbumShare.kt:27-31)
- [x] "Not in your library" title, 12dp top when library results or part albums are above. (app/ui/search/SearchScreen.kt:418)
- [x] Loading shows "Looking online"; Failed shows "Could not reach your server" (bodySmall, TextMuted, 20dp sides, 8dp vertical). (app/ui/search/SearchScreen.kt:419-421, 486-494)
- [x] Done: the add hint line (when due and there are songs), then "Songs" subtitle and song rows, "Albums" subtitle and album cards row, "Artists" subtitle and artist circles row. Subtitles: bodySmall, TextMuted, 20dp sides, 14dp top, 8dp bottom. (app/ui/search/SearchScreen.kt:422-457, 463-471)
- [x] Find song rows: add button at the end, and no empty add space for a find that turns into its library song (it ends at its length like the library rows). Tap plays the finds from that one and saves the search. (app/ui/search/SearchScreen.kt:426-430, app/ui/search/SearchViewModel.kt:289-293)
- [x] Online album card: same as an album card with the not-in-library mark on its cover and the share line when held in part; no long press menu. Tap opens the online album page. (app/ui/common/Items.kt:112-114, app/ui/search/SearchScreen.kt:438-440)
- [x] Online artist circle: not-in-library mark, no long press; tap opens the online artist page. (app/ui/common/Items.kt:553-554, app/ui/search/SearchScreen.kt:451-453)
- [x] Multi-select covers library songs, finds and top songs together, library first, each once by id. (app/ui/search/SearchScreen.kt:506-513)

## 19. Search: add hint line

- [x] Text "Tap + to add a song to your library." (caption, TextMuted, 20dp sides, 2dp bottom), under the "Not in your library" title, only when there are found songs. (app/ui/search/SearchScreen.kt:424, 475-484)
- [x] Shows while no song was ever added AND (this visit already counted it OR it has been counted fewer than 5 times). (app/discovery/AddHint.kt:26, 35-36)
- [x] Counted once per Search visit, the first time it comes on screen; once counted it stays for the rest of the visit. (app/ui/search/SearchViewModel.kt:240-254)
- [x] Any successful song or album add marks "added" and the line stops for good. (app/discovery/Downloads.kt:218, 238)
- [x] Stored in the "add_hint" preferences store: int "shown", boolean "added"; a write failure is ignored. (app/discovery/AddHint.kt:20-23, 48-60) (iPhone: the app's settings store, keys "add_hint.shown" and "add_hint.added")

## 20. Discovery engine: resolving server songs

- [x] A server song is a library song when it is not marked external and the library has a link to its server id; otherwise when a library song has the same title, artist and kind of recording (length within 10 s when both known, ISRCs win); otherwise it is a find. (app/discovery/LibraryMatching.kt:98-112, core/discovery/Matching.kt:17-19, 48-62)
- [x] A link left by an older copy is not trusted for a song the server marks external. (app/discovery/LibraryMatching.kt:93-97, 107)
- [x] A listed length of exactly 180 s, or 0 or less, is treated as unknown (Octo's guess). (core/discovery/Matching.kt:10-12, 24-25)
- [x] Candidates are looked up by title keys: as written, without bracketed extras, and the core title; then compared one by one. (core/discovery/Matching.kt:31-33, app/discovery/Discovery.kt:263)
- [x] Database lookups are chunked 900 ids/keys at a time. (app/discovery/Discovery.kt:259-263) (iPhone: looked up 500 at a time, within SQLite's limit on the phone)
- [x] A find already downloaded and still in the library resolves to the library song it became. (app/discovery/LibraryMatching.kt:42-43, app/discovery/Discovery.kt:243-245)
- [x] Finds are stored as they come (so a length learned from playing shows next time); the stored row wins over the fresh one. (app/discovery/Discovery.kt:265-267)
- [x] Lists keep the server's order; repeats are dropped by id, except for lists that keep every entry (playlists by id list) or keep places (rankings, null where a library song is gone). (app/discovery/Discovery.kt:205-226, 237-239)
- [x] A find as a song: id "find:<server id>", no library album or artist to open, track/disc/year null, addedAt 0, not on the phone; album, artist, cover, mime type (contentType else by suffix: m4a/mp4/aac audio/mp4, mp3 audio/mpeg, flac audio/flac, ogg/oga/opus audio/ogg, wav audio/wav), bitrate when above 0, explicit flag. (app/discovery/LibraryMatching.kt:50-91, core/discovery/Matching.kt:124-132)
- [x] Which radio source suggested a song is remembered from the server's `octoSuggestedBy` (trimmed, non-empty), up to 5,000 songs, each believed 12 hours, oldest dropped first, a re-suggestion moving to the newest end; not saved. (app/discovery/Discovery.kt:84-88, 228-233, 317-346; app/discovery/LibraryMatching.kt:18-22)
- [x] Radio from a song: the song's server id (a find's own, the library song's server copy, else a search "<artist> <title>" for 40 songs taking the same recording first, else the same song in any version); then getSimilarSongs2 with count 50 and octoMix=client; seed first, then the similar songs, each once. (app/discovery/Discovery.kt:35-36, 137-143, 270-285; subsonic/SubsonicClient.kt:425-432)
- [x] Library album as the server lists it now: from the album's songs' copies on this server, the album most of them belong to, fetched by its native id; only songs the server marks external stay finds, numbered as the album numbers them (0 or less means none); unmarked missing songs are dropped (the next copy brings them). (app/discovery/Discovery.kt:185-194, app/discovery/WholeAlbum.kt:13-20)
- [x] A whole library album: the server's order, each library song as the library has it, each adopted find as its library song, then library songs the server did not list (a phone-only copy) in their own order; with no finds it is the library's album unchanged. (app/discovery/WholeAlbum.kt:28-39)

## 21. Online album page

- [x] Opened from a search album card ("Not in your library" or "Partly in your library") or an online artist's album card. Loads getAlbum and resolves its songs to library songs and finds in the server's order. (app/ui/online/OnlineAlbumScreen.kt:109-112, app/discovery/Discovery.kt:170-178, app/ui/search/SearchScreen.kt:412, 439)
- [x] Loading shows a 28dp accent spinner centered; failure shows the message (bodySmall, TextSecondary, centered) and an accent "Try again" button 16dp below; no server shows "Sign in to your server to see this.". (app/ui/common/LoadState.kt:38-64, app/ui/online/LoadOnline.kt:7-11)
- [x] Error messages: unreachable "Couldn't reach the server. Check the address, and that you're on the right network."; not Subsonic "That address answered, but not like a music server. Check the port." or, when busy, "The server isn't answering right now. It may be restarting, so try again in a moment."; not found "That isn't on the server any more."; server error "The server said: <message>"; else "Something went wrong.". (app/data/UserMessages.kt:6-19)
- [x] Header: artwork, title, artist (opens the online artist page when the album has an artist id), details "year • N songs • length" (missing parts left out); Play plays from the first song; Shuffle plays shuffled. (app/ui/online/OnlineAlbumScreen.kt:157-171)
- [x] Length shows only when every song's length is known: total seconds as "<m> min" or "<h> hr <m> min", rounded to the nearest minute. (app/ui/online/OnlineAlbumScreen.kt:159-161, app/ui/common/Layout.kt:77-80)
- [x] The cover stays clean (no mark). When any song is a find, an action row shows the add-to-library action: label "Add to your library", or "Adding" and disabled while downloading. (app/ui/online/OnlineAlbumScreen.kt:172-185) (iPhone: SF Symbol plus.circle)
- [x] Beside it, for an album partly in the library, the muted line "<in library> of <songs> in your library" (1 line, 10dp sides), pushed to the end. Not shown when none or all are outside. (app/ui/online/OnlineAlbumScreen.kt:186-195, app/ui/common/NotInLibrary.kt:160-163)
- [x] "Downloading" is true once the album was asked for here (cleared if the server said no), or when every find on it is already asked for or in. (app/ui/online/OnlineAlbumScreen.kt:77-85)
- [x] Add asks the server to star the album (`star` with albumId), marks every find as asked at the same moment, and follows them. (app/ui/online/OnlineAlbumScreen.kt:126-132, app/discovery/Downloads.kt:231-248)
- [x] Songs are numbered by place on the album (1, 2, 3...), since finds have no track numbers. (app/ui/online/OnlineAlbumScreen.kt:203-209)
- [x] When any song on the album is a find, every row has an ownership mark after its number: an accent check (20dp, "In your library") for a library song, the add button (32dp, icon 20dp) for a find; rows then keep no empty end space. (app/ui/online/OnlineAlbumScreen.kt:208-215, app/ui/common/Items.kt:229-248) (iPhone: SF Symbol checkmark)
- [x] A row's subtitle shows the song's artist only when it differs from the album's artist. (app/ui/online/OnlineAlbumScreen.kt:214)
- [x] The album's main song gets a filled accent star 14dp ("Most popular") before its title: the album song that comes first in the artist's top 30 (getTopSongs), matched by id, or by title without features plus same artist. Top songs are cached per user, server and artist for the app's run; a failed ask is retried next time. (app/ui/online/OnlineAlbumScreen.kt:100-107, app/discovery/AlbumHighlight.kt:12-49, app/ui/common/Items.kt:453-465)
- [x] Tap a row plays the album from that song. (app/ui/online/OnlineAlbumScreen.kt:217)
- [x] When a download from anywhere lands, the page waits 1,500ms (the check's moment plus the swap fade) and, if a find here is now in the library, reloads the album quietly, keeping the page when the server cannot answer. (app/ui/online/OnlineAlbumScreen.kt:87-98, 114-118; app/ui/common/DownloadRing.kt:54)
- [x] The page's ambient artwork is the album's artwork; a back button overlays the page. (app/ui/online/OnlineAlbumScreen.kt:158, 221) (iPhone: the system back button)

## 22. Online artist page

- [x] Opened from a search artist circle under "Not in your library", the online album page's artist name, or a library artist page's similar artist that the library does not have. (app/ui/search/SearchScreen.kt:452, app/ui/online/OnlineAlbumScreen.kt:169, app/ui/artist/ArtistScreen.kt:370)
- [x] Loads getArtist; same loading and failure states as the online album page. (app/ui/online/OnlineArtistScreen.kt:49-52, app/discovery/Discovery.kt:196-203)
- [x] Grid of albums, adaptive 150dp columns, 14dp horizontal and 18dp vertical gaps; header spans the grid. (app/ui/online/OnlineArtistScreen.kt:73-81, app/ui/artist/ArtistScreen.kt:381-397) (iPhone: columns worked out from 150 pt cards)
- [x] Header: artwork (clean, no mark), name, and "<n> albums • Not in your library" (n = albums listed; "1 album"). (app/ui/online/OnlineArtistScreen.kt:74-77)
- [x] Album cards have the not-in-library mark and the share line; tap opens the online album page. (app/ui/online/OnlineArtistScreen.kt:78-80)
- [x] An online album's owned count is kept only when the server marks the album external. (app/discovery/Discovery.kt:306-309)

## 23. Charts page

- [x] Title "Charts" with the detail top gap, and a back button. (app/ui/charts/ChartsScreen.kt:43-44, 90) (iPhone: the system back button)
- [x] Chips: the charts the server's country has (getCharts), each chip the server's `label`; selected is the chart in view; default "34" (overall). 8dp between chips, 20dp sides, 4dp top and 12dp bottom padding. The row hides when there are no choices. (app/ui/charts/ChartsScreen.kt:45-58, app/ui/charts/ChartsViewModel.kt:28)
- [x] Choices are kept a day per server; a chart's songs an hour per server and chart; asks for a server no longer in use are dropped. (app/discovery/ChartLists.kt:17-18, 51-77)
- [x] A chart asks getTopChart with count 100 for "new" and "trending", 50 for every other chart, plus the chart id. (core/discovery/TopSongs.kt:72, app/discovery/ChartLists.kt:71)
- [x] Picking the chip already selected does nothing; another cancels the load in progress and shows the spinner (TextSecondary, 24dp top) until its songs come. (app/ui/charts/ChartsViewModel.kt:49-64, app/ui/charts/ChartsScreen.kt:62-66) (iPhone: system progress spinner)
- [x] "This server doesn't have charts." when no choices came and the server does not offer charts; this wins over everything below. (app/ui/charts/ChartsViewModel.kt:42-45, app/ui/charts/ChartsScreen.kt:61)
- [x] A chart that fails or comes back empty shows "Nothing in this chart right now. Try another.". (app/ui/charts/ChartsViewModel.kt:62, app/ui/charts/ChartsScreen.kt:67)
- [x] Caption: "<ranked by> in <country name>" from the 2-letter country code; ranked by for Apple is "Picked by Apple Music" for "new", "Trending on Apple Music" for "trending", else "Most played on Apple Music"; no country name gives just the ranked-by words; unknown source gives no caption. (app/ui/charts/ChartsScreen.kt:104-110, core/discovery/TopSongs.kt:56-65)
- [x] Quiet lines: caption, TextMuted, 20dp sides, 8dp bottom. (app/ui/charts/ChartsScreen.kt:94-102)
- [x] A glaze "Play all" button (20dp start, 8dp bottom) plays the chart from the first song. (app/ui/charts/ChartsScreen.kt:70-72)
- [x] Ranked rows with subtitle artist • album • plays, the add button for finds and add space for library songs; tap plays the whole chart from that row. Keys "chart:<chart>:<track id>". (app/ui/charts/ChartsScreen.kt:73-86, app/ui/charts/ChartsViewModel.kt:66-69)
- [x] Ambient area for the Charts page is Home's. (app/ambient/AmbientSource.kt:52)

## 24. Not-in-library signs on rows and covers

- [x] A song is outside the library when its id starts "find:" and its download has not reached the library. (app/ui/common/NotInLibrary.kt:108-116)
- [x] Row sign: a library song has none; in a list that offers add, a find gets the add button (kept after it is added, so the check has its moment); elsewhere a find gets the small mark on its artwork until it is in the library. (app/ui/common/NotInLibrary.kt:121-131)
- [x] Row end: the add button; else an empty 40dp space when the list gives library songs that space and the row has no trailing item; else the list's trailing item. (app/ui/common/NotInLibrary.kt:138-148, app/ui/common/Items.kt:399-404)
- [x] Add button in a row: 40dp, plus 22dp. (app/ui/common/Items.kt:225-227)
- [x] Accessibility for artwork outside the library: "Not in your library", or "<description>, not in your library". (app/ui/common/NotInLibrary.kt:40-41, 150-155)
- [x] Mark size: one eighth of the artwork side, clamped to 12dp..20dp. (app/ui/common/NotInLibrary.kt:171-175)
- [x] Mark inset from bottom and right: max(4% of the side, 3dp) on a square cover; on a round picture placed along the diagonal so the whole disc stays inside: centre = r - (r - margin - mark/2) / sqrt(2), inset = centre - mark/2. (app/ui/common/NotInLibrary.kt:180-186)
- [x] Mark look: a small circular glass disc with a black 42% film, holding the not-in-library plus icon at 68% of the mark's size, white 90%. It is a sign only, not a button. (app/ui/common/NotInLibrary.kt:188-211)
- [x] "Library songs only" is an app-wide setting read from player preferences and provided to every screen. (app/ui/common/NotInLibrary.kt:54-73, 96-104)
- [x] Shared wording: "Library songs only", help "Shows only songs in your library: albums, search, artists and radio leave out outside songs.", album toggle "Only my songs". (core/discovery/LibraryOnly.kt:5-7)
- [x] Desktop words for adding missing album songs: "Add the missing song" / "Add the <n> missing songs". (app/ui/common/NotInLibrary.kt:165-167) (iPhone: the words are kept in OctoKit; the iPhone has no desktop layout)

## 25. Add to library button

- [x] Used where a heart would be for a song not in the library: a plus that asks the server to download the song (the download arrow is reserved for saving to the phone). Default size 44dp, icon 24dp. (app/ui/common/AddToLibraryButton.kt:112-124) (iPhone: SF Symbol plus)
- [x] For a family member whose songs are saved rather than added, it is a heart instead: tap toggles saved for that song; accessibility "Save", state "Saved"/"Not saved"; filled heart white when saved (glowing), outline white 60% when not. (app/ui/common/AddToLibraryButton.kt:87-110, 126-130) (iPhone: SF Symbol heart)
- [x] Not asked: plus icon, white 60%, unlit. Tap asks for the download. (app/ui/common/AddToLibraryButton.kt:165-171)
- [x] Queued, downloading, adding, done: the download ring. Failed: the alert icon. (app/ui/common/AddToLibraryButton.kt:172-173)
- [x] Enabled only when not asked, failed, or on its way with a server that keeps a downloads log. (app/ui/common/AddToLibraryButton.kt:143, 150)
- [x] On its way (queued/downloading/adding) on a server with the downloads log: tap opens the server downloads sheet on that song's newest download log, or the list when not listed yet; click label "Follow it". (app/ui/common/AddToLibraryButton.kt:141-155, app/data/ServerDownloads.kt:204-214)
- [x] Failed: tap asks again (click label "Try again"); long press shows "Could not download: <reason>" (long press label "Why"); the reason is the server's error trimmed, else "the server did not say why". (app/ui/common/AddToLibraryButton.kt:70-71, 152-155; app/discovery/DownloadProgress.kt:60) (iPhone: Try again and Why are accessibility actions)
- [x] No ripple or press indication. (app/ui/common/AddToLibraryButton.kt:148-149)
- [x] Accessibility name "Add to your library"; state "Not in your library", "Queued", "Downloading, <n> percent" (rounded) or "Downloading", "Adding to your library", "In your library", "Could not download". (app/ui/common/AddToLibraryButton.kt:74-85)
- [x] While the button is on screen (lifecycle started) its song is "watched": progress is asked every 2 s instead of 5 s while it downloads, and the app counts as in front. (app/ui/common/AddToLibraryButton.kt:135-139, app/discovery/Downloads.kt:205-208) (iPhone: on screen from appearing to disappearing; in front from the scene phase)
- [x] The ring restarts fresh when the button moves to another song. (app/ui/common/AddToLibraryButton.kt:162-164)
- [x] A failed ask (server error) leaves the button as it was, with no message. (app/discovery/Downloads.kt:212-227)
- [x] Reduced motion comes from Octo's own Reduce motion or the phone's setting. (app/ui/common/AddToLibraryButton.kt:133-134)

## 26. Download ring animation

- [x] Thin ring, stroke 2dp, track white 20%, around a small plus (arms 18% of the width each side, same stroke, round caps). (app/ui/common/DownloadRing.kt:57-63, 125-160)
- [x] Waiting (queued, or downloading with unknown progress): a 90 degree white arc turning once per 1,600ms, linear, from 12 o'clock. Reduced motion: still arc. (app/ui/common/DownloadRing.kt:45, 96-102, 133-142)
- [x] Downloading with progress: a white arc from 12 o'clock filling 360 x progress, eased over 1,200ms (LinearOutSlowIn); snaps with reduced motion. (app/ui/common/DownloadRing.kt:46, 112-123, 143-152)
- [x] The fill never goes back, even when an answer does. (app/ui/common/DownloadRing.kt:110-118)
- [x] Adding: full ring pulsing opacity 1 to 0.45 and back every 900ms (FastOutSlowIn); none with reduced motion. (app/ui/common/DownloadRing.kt:47, 103-108)
- [x] Done while shown: the ring and plus fade out as a check draws itself in over 300ms (FastOutSlowIn), from its short stroke to its long one; a glow rises over 300ms, holds 500ms and fades over 700ms. (app/ui/common/DownloadRing.kt:48-50, 76-93, 165-189)
- [x] Done when first drawn, or with reduced motion: the check shows at once, no glow. (app/ui/common/DownloadRing.kt:72-86)
- [x] Check path: (0.24w, 0.52h) to (0.42w, 0.70h) to (0.78w, 0.33h), stroke 2dp, round caps and joins, white. (app/ui/common/DownloadRing.kt:173-180)
- [x] Glow: two blurred copies of the check, blur 10dp at 60% x glow and blur 3dp at 70% x glow. (app/ui/common/DownloadRing.kt:183-186)
- [x] Going back from done to not done snaps the morph and glow to 0. (app/ui/common/DownloadRing.kt:77-81)
- [x] Failed alert: white circle stroke 2dp, radius 42% of the side minus half the stroke; an exclamation line from 0.5r above center to 0.1r below; a dot of radius 0.7 x stroke at 0.48r below center. (app/ui/common/DownloadRing.kt:191-206)

## 27. Find row turning into the library song (FindSwap)

- [x] A find's row has three faces: Find, Check, Library. (app/ui/common/FindSwap.kt:21-23)
- [x] While it is unknown whether the find is in the library, the face stays as it is. (app/ui/common/FindSwap.kt:30-31)
- [x] A row that opens on a find already in the library shows the library song at once; otherwise it shows the find. (app/ui/common/FindSwap.kt:32)
- [x] A find that arrives while shown: in a list that offers add, the Check face for 1,200ms (the ring's check draws and holds), then Library; elsewhere straight to Library. (app/ui/common/FindSwap.kt:14-16, 33, 61-66)
- [x] The library song is looked up from the Check face on, so it is ready when the row turns; the last seen copy is used at once when the row is drawn again. (app/ui/common/FindSwap.kt:67-79, app/discovery/Adoptions.kt:16-28)
- [x] The turn into the library song cross-fades over 300ms only for a row that showed the find and without reduced motion; otherwise it swaps at once. (app/ui/common/FindSwap.kt:18-19, 40-43; app/ui/common/Items.kt:368-379)
- [x] The row keeps the same place and height; the find and its check hold still; after the turn the swipe, the menu and what plays are the library song's. (app/ui/common/Items.kt:250-300, 302-305)
- [x] Adoptions (find id to library song id) are null until first read, so a row can tell "already in" from "arrives while shown". (app/discovery/Downloads.kt:165-170)

## 28. Song rows used in these lists

- [x] Row: at least 56dp tall (taller for large text), 20dp sides, 4dp vertical, 12dp between parts; artwork 44dp radius 6dp. (app/ui/common/Items.kt:361-363, 407-414)
- [x] Tap plays (or picks while multi-select is on); long press opens the song menu with haptic; press squeezes. Accessibility actions "Play next" and "Add to queue". (app/ui/common/Items.kt:333-360) (iPhone: system context menu)
- [x] Swipe right puts the song next (confirm haptic), with "Play next" showing behind; not while picking. (app/ui/common/Items.kt:290-299, 494-517) (iPhone: system swipe actions, with a success haptic)
- [x] Now playing: bars over the artwork on a black 50% shade. Picked: a select mark over it. (app/ui/common/Items.kt:412-420, 481-492)
- [x] Subtitle default: "<artist> • <album>" with the album left out for a find whose album equals its title. (app/ui/common/Items.kt:216-223)
- [x] Length shown is the length learned by playing when the listing was more than a second off, else the listed one, else none. (app/ui/common/Items.kt:475, app/discovery/FindLengths.kt:10-12)
- [x] Learned lengths of finds are stored with the find, written once per value; a failed write is forgotten so it is tried again. (app/discovery/FindLengths.kt:14-48)
- [x] Out of reach offline: the row draws faint. (app/ui/common/Items.kt:364-365)

## 29. Downloads engine (asking for finds and following them)

- [x] Asking for a song: star its server id (the find id without "find:"), mark it asked now, mark the add hint done, note it for the arrival line, start its progress afresh, tell the server downloads list to look now, and follow. Answers whether it was asked. (app/discovery/Downloads.kt:210-227)
- [x] Asking for an album: star with albumId, mark every find on it asked at one same moment, mark the add hint done, note the album for one arrival line (title given, else the first coming song's album), start each coming song afresh, wake the list, follow. (app/discovery/Downloads.kt:229-248)
- [x] A song counts as asked with its album when two or more asked finds share the same album id and the same asked time. (app/discovery/DownloadProgress.kt:88-95)
- [x] A find's plain state: Done once adopted into the library; Requested while asked less than 24 hours ago; otherwise None (so it can be asked again). (app/discovery/Downloads.kt:61, 482-486)
- [x] A find's phase: Done when in the library; None when not asked; when asked, the server's live word for it, else Queued while still taken as asked for (or always Queued on a server that does not list downloads), else None. (app/discovery/DownloadProgress.kt:63-82)
- [x] Server stages map to phases: queued, searching, unknown are Queued; downloading is Downloading(progress); verifying, importing and done are Adding (until really in the library); failed is Failed(reason). (app/discovery/DownloadProgress.kt:54-61)
- [x] Progress is the server's `progress` when finite (clamped 0..1), else bytesDone / bytesTotal when total > 0, else unknown. (subsonic/Acquisitions.kt:77-80)
- [x] Still taken as asked for, while no list shows it: a song alone for at most 2 minutes and only until a list asked for after the ask comes back; a song asked with its album for at most 30 minutes. (core/ui/downloads/Downloads.kt:292-313)
- [x] Phases are worked out again by the clock when the first "still asked" runs out, while the server lists downloads. (app/discovery/Downloads.kt:148-158, 471-480)
- [x] Which server entry is a find's: the one with its id; else, by title and artist the same recording (or by title alone when the entry has no artist); the newest start wins. (app/discovery/DownloadProgress.kt:113-126)
- [x] Following on a server that reports progress: poll every 2 s while a downloading find's button is on screen, 5 s otherwise, 30 s while the app is in the background; coming back to the front asks at once. (app/discovery/DownloadProgress.kt:21-26, 107-111, 174-181) (iPhone: in the background means the scene is not active)
- [x] Progress never goes back: a lower or unknown figure keeps the highest seen for that find. (app/discovery/DownloadProgress.kt:307-315)
- [x] A finished entry is brought into the library up to 3 times, 20 s apart (take in by its library id, adopt, then copy the whole library and wait); after 3 tries it shows Done. (app/discovery/DownloadProgress.kt:28-31, 283-297, 317-337)
- [x] A download the server has not listed for 10 minutes and that is no longer "still asked" stops being followed. (app/discovery/DownloadProgress.kt:33-34, 275-279)
- [x] Following ends when nothing is waiting; an unreachable server just waits for the next turn. (app/discovery/DownloadProgress.kt:216-265)
- [x] Asking again after a failure passes over the failed entry the server still lists and starts progress from nothing. (app/discovery/DownloadProgress.kt:200-212)
- [x] An older server without getAcquisitions: if the admin pages can be reached, look every 20 s for 30 minutes at what Octo finished and copy the library up to 3 times per finished song; otherwise copy the library at 2 minutes and 8 minutes. (app/discovery/Downloads.kt:55-68, 282-303, 369-397)
- [x] Downloads asked before the app last closed carry on being followed at start, on a server that reports progress. A switch to another kept server stops following the last one's and resumes this one's. (app/discovery/Downloads.kt:184-198, 305-318)
- [x] Only finds asked on the server in use, less than 24 hours ago, are followed. (app/discovery/Downloads.kt:312-318)
- [x] After every library copy: finds not seen for 30 days are let go (on kept servers), and waiting finds whose song now appears in the library (same song, about the same length) are linked to it. Downloading never likes the song. (app/discovery/Downloads.kt:70-71, 259-276, 427-435)
- [x] A pull on a page wakes progress following, or starts it when finds wait on a server that reports progress. (app/discovery/Downloads.kt:250-257)
- [x] "Arrived" counter goes up by one each time downloads join the library, so pages holding server answers can ask again. (app/discovery/Downloads.kt:178-182, 354)

## 30. Arrival lines (toasts)

- [x] A single song asked for in this run: when it lands, a toast with a check icon "<title> is in your library". (app/discovery/Arrivals.kt:41-42, app/discovery/Downloads.kt:355)
- [x] An album asked for: one toast once its last song settles: "<title> is in your library", or "..., but 1 song could not be downloaded", or "..., but <n> songs could not be downloaded"; nothing when none landed. Album title blank reads "The album". (app/discovery/Arrivals.kt:29-37, 59-68)
- [x] A single song failing says nothing in a toast (the button shows it). (app/discovery/Arrivals.kt:49-57)
- [x] A song asked again after failing within an album counts with its album again. (app/discovery/Arrivals.kt:16-27)
- [x] Asking for an album takes over any of its songs asked alone; downloads asked before the app started arrive quietly. (app/discovery/Arrivals.kt:3-6, 31-37; app/discovery/Downloads.kt:346-357)
- [x] Toasts show 3.5 s, or 6 s with an action. (app/ui/common/Feedback.kt:56-57)

## 31. Downloads pill

- [x] A small glazed pill above the tab bar on the right (20dp from the edge, bar height plus bar gap plus 10dp up), hidden while the full player is open (fades 300ms). (app/ui/nav/MainShell.kt:308-317) (iPhone: Liquid Glass capsule)
- [x] Shown only while the count is above 0 and the server keeps a downloads log. (app/ui/downloads/DownloadsPill.kt:123)
- [x] Count: the server's running rows plus songs asked here that no running row shows but that are still taken as on their way; looked at again when the oldest of those runs out. (app/ui/downloads/DownloadsPill.kt:64-77, core/ui/downloads/Downloads.kt:321-337)
- [x] Lead row: the running row furthest along (by phase order), then the one started first. (core/ui/downloads/Downloads.kt:268-274)
- [x] Contents: download ring 20dp for the lead's step (Queued when no lead); the step words cross-fading over 160ms; the lead's title (caption, TextSecondary, ellipsis); "+<n>" chip (white 12% background, 7dp x 2dp padding) when more. (app/ui/downloads/DownloadsPill.kt:138-161)
- [x] Step words: "Waiting", "Searching", "Downloading 42%" (or "Downloading"), "Checking", "Adding", "Done", "Failed". With no lead row: "1 downloading" / "<n> downloading". (core/ui/downloads/Downloads.kt:276-285, app/ui/downloads/DownloadsPill.kt:100)
- [x] "+n" is the count minus 1 when a lead row exists. (app/ui/downloads/DownloadsPill.kt:125)
- [x] Ring step: Downloading fills with its fraction; Checking and Adding full; Done check; else turning. (app/ui/downloads/DownloadsPill.kt:104-109)
- [x] Size: 36dp tall, at most 280dp wide, fully round; padding 8dp start, 6dp end with the chip or 14dp without; 8dp between parts; its size change animates over 200ms. (app/ui/downloads/DownloadsPill.kt:128-141)
- [x] Tap opens the server downloads sheet on its list, from anywhere. Nothing opens by itself. Click label "Show server downloads". (app/ui/downloads/DownloadsPill.kt:91-95, 134) (iPhone: accessibility label with the button trait)
- [x] Spoken: "<step words>, <title>. <n> more on the way. Show server downloads" (the "more" part only when more than one row runs), or "<n> downloading. Show server downloads" with no lead. (app/ui/downloads/DownloadsPill.kt:126, 135; core/ui/downloads/Downloads.kt:339-344)
- [x] Motion durations are halved, and nothing travels, under reduced motion. (design/OctoMotion.kt:99-131, 145-149)

## 32. Server downloads: model and polling

- [x] Started once at app start; follows sign-ins: on a new session (or the same one with extensions read again) it stops, forgets everything, clears replacements, closes the sheet, then starts again when supported. (app/data/ServerDownloads.kt:147-170)
- [x] Sheet views: List, Log(key), Find(server id, title, from log key). Closed is null. (app/data/ServerDownloads.kt:44-54)
- [x] List polling: every 2 s while the sheet is open and the app is in front; every 3 s while any row runs and the app is in front; otherwise every 30 s. Opening the sheet, asking for a song, and coming to the front ask at once. (core/ui/downloads/DownloadWatches.kt:21-26, 86-135; app/data/ServerDownloads.kt:173, 305-313)
- [x] A failed poll keeps the list as it was. A failed upgrades read keeps the last upgrades. (core/ui/downloads/DownloadWatches.kt:137-154)
- [x] Rows: one per server download, joined to its higher quality copy; plus each higher quality copy not yet joined. Running first; within running newest start first; within finished newest update first. Finished upgrade rows leave after 3 hours; rows cleared here stay hidden. (core/ui/downloads/Downloads.kt:28-30, 81-103)
- [x] Row kind: "upgrade" or "pick" from the server; a plain download joined to an upgrade counts as Upgrade. Small label "HIGHER QUALITY" / "PICKED" beside the title (none for a plain download). (core/ui/downloads/Downloads.kt:107-112, 206-212; app/ui/downloads/ServerDownloadsSheet.kt:275-284)
- [x] Row phase from stage: queued Waiting; searching/unknown Searching; downloading Downloading; verifying Checking; importing Adding; done Done; failed Failed. (core/ui/downloads/Downloads.kt:180-188)
- [x] Row status: "Waiting, <n> ahead" or "Waiting its turn"; searching: the server's note as a sentence, else "Looking on <source>", else "Looking for a copy"; "Downloading[ from <source>][, <n>%]"; "Checking the file"; "Adding to your library"; "In your library"; failed: the error as a sentence, else "Could not get it". (core/ui/downloads/Downloads.kt:190-204)
- [x] A sentence is the server's words trimmed with a closing full stop removed. (core/ui/downloads/Downloads.kt:488-489)
- [x] Joined upgrade outcome wins: Upgraded is Done "<detail>" or "Upgraded"; NotFound is Failed "No higher quality copy found"; Failed/Skipped is Failed "<detail>" or "Your copy is unchanged"; Rehearsed is Done "Only rehearsed; nothing changed"; otherwise a finished download is Checking "Checking it before it replaces your copy". (core/ui/downloads/Downloads.kt:115-126)
- [x] An upgrade row on its own: Queued "Waiting its turn"; Waiting "Waiting for Soulseek"; Working or unknown "Looking for a higher quality copy" (with fraction); outcomes as above. Key "upgrade:<id>". (core/ui/downloads/Downloads.kt:148-178)
- [x] Row title blank reads "A song"; cover is the download's coverArt, else its library id, else its id. (core/ui/downloads/Downloads.kt:127-133)
- [x] Summary line: "<n> on the way, <m> finished" (each part only when above 0). (core/ui/downloads/Downloads.kt:214-222)
- [x] Clearing finished: hides them here at once, then asks the server (all finished, or one by key); upgrades stay on the server and are only hidden. (core/ui/downloads/DownloadWatches.kt:165-178)
- [x] Artwork for a row is the server cover of that id, none when signed out. (app/data/ServerDownloads.kt:90-95)

## 33. Server downloads sheet: list

- [x] Glass sheet over everything, titled "Server downloads" (the phone's own songs are "Downloads"). (app/ui/downloads/ServerDownloadsSheet.kt:104-129) (iPhone: system sheet)
- [x] Opened from the downloads pill, a song's add button while it is on its way, an album page's action, the song menu's Find songs, and upgrade toasts ("Show"). (app/ui/downloads/ServerDownloadsSheet.kt:111-114; app/ui/menu/SongMenu.kt:284-292; app/data/Upgrades.kt:238)
- [x] Head: "Server downloads" (section style, heading) and the summary caption; "Clear finished" quiet button when any row finished. (app/ui/downloads/ServerDownloadsSheet.kt:222-228)
- [x] Empty: "Asking the server" until the first answer, then "Nothing downloading. Songs you add show here, with every step on the way.". (app/ui/downloads/ServerDownloadsSheet.kt:229-232, core/ui/downloads/Downloads.kt:225)
- [x] Row: 48dp artwork radius 8dp; title (body, ellipsis) plus kind label; artist when not blank; status caption (orange when failed, max 2 lines); at the end a 22dp progress ring while running, a downloaded mark when done, an orange info mark when failed. Accessibility "<title>, <artist>" with the status as state. (app/ui/downloads/ServerDownloadsSheet.kt:244-273) (iPhone: SF Symbols)
- [x] Tap a row: opens its log when it has one; a finished row without a log opens Find songs for it; otherwise nothing. (app/ui/downloads/ServerDownloadsSheet.kt:235-239)
- [x] Progress ring: unknown fraction is a spinner; else a white arc from 12 o'clock over a white 18% track, stroke 12% of the size, round cap. (app/ui/downloads/ServerDownloadsSheet.kt:767-781) (iPhone: system progress spinner while the share is unknown)

## 34. Server downloads sheet: one download's log

- [x] Polled every 1.5 s while open and in front; once finished, for 60 more seconds (lyrics come after), then stops; a log finished longer ago is read once. Not asked while in the background. (core/ui/downloads/DownloadWatches.kt:28-34, 181-241)
- [x] Problems: "This download is no longer on the server" (stops) or "Could not reach the server" (keeps trying), shown as an orange caption. (core/ui/downloads/DownloadWatches.kt:234-237, app/ui/downloads/ServerDownloadsSheet.kt:322)
- [x] Bar: back button 44dp "Back to Server downloads"; "Find songs" quiet button when the row has a find id (opens Find songs from this log); "Clear" when finished (clears it and returns to the list). (app/ui/downloads/ServerDownloadsSheet.kt:313-319, 742-755)
- [x] Head: 56dp artwork radius 10dp; title (headline, 2 lines); "<artist> · <album>" (2 lines); the steps strip; the status (orange when failed); tags for quality, source and kind. (app/ui/downloads/ServerDownloadsSheet.kt:343-363, 425-429)
- [x] The head stays put; only the steps scroll. A 1dp rule (white 10%) 14dp under it. (app/ui/downloads/ServerDownloadsSheet.kt:320-323, 757-760)
- [x] Following: a running download opens on its newest line and keeps it in view; a finished one opens at its start; scrolling up lets go; scrolling back to the end follows again. (app/ui/downloads/ServerDownloadsSheet.kt:299-312)
- [x] "Latest step" small glaze button (downloading icon), bottom center 12dp up, while not following, running and not at the end; tap follows again. (app/ui/downloads/ServerDownloadsSheet.kt:331-339) (iPhone: glass button with an SF Symbol)
- [x] A spinner shows before the log arrives. (app/ui/downloads/ServerDownloadsSheet.kt:326)
- [x] Steps strip: four steps Find, Download, Check, Add; bars 4dp tall, 4dp apart, track white 14%; steps before the current one full; the current one half full (downloading: its fraction, else half; failed: full orange); green fill when done; fill animates over 300ms. (app/ui/downloads/ServerDownloadsSheet.kt:365-415, core/ui/downloads/Downloads.kt:350-356)
- [x] The current step breathes (opacity 0.45 to 1, 900ms, reversing) while running with unknown progress, unless motion is still. (app/ui/downloads/ServerDownloadsSheet.kt:372, 417-423)
- [x] Step labels: orange on the failed step, TextPrimary on the current running step, TextSecondary for done steps or a done row, TextMuted otherwise. Accessibility "Step <n> of 4, <label>" or "Every step done". (app/ui/downloads/ServerDownloadsSheet.kt:374-376, 401-411)
- [x] Current step: Waiting/Searching Find; Downloading Download; Checking Check; Adding Add; Done past the end; Failed: the step of the last log line that is not failed/note/done, else Find. (core/ui/downloads/Downloads.kt:358-380)
- [x] Log line: a 24dp circle with its mark icon 13dp, joined to the next by a 1dp thread; text (bodySmall, SemiBold when live, orange for failed); time "HH:mm:ss" in local time; detail caption; copies card. The live line (running, last) shows a spinner on a white 14% circle unless it is done/failed. (app/ui/downloads/ServerDownloadsSheet.kt:431-462, core/ui/downloads/Downloads.kt:405-409)
- [x] Mark icons: queued history; search search; found songs; try download; transfer downloading; check check; tags rename; cover album; lyrics lyrics; library library; done downloaded; failed close; note info. Tints: done green, failed orange, others TextSecondary. Fills: done green 16%, failed orange 16%, others white 8%. (app/ui/downloads/ServerDownloadsSheet.kt:481-508) (iPhone: SF Symbols)
- [x] Unknown log kinds draw as notes. (core/ui/downloads/Downloads.kt:389-403)
- [x] Copies card in a log line: the first 3 copies, then "Show all <n>" / "Show fewer". (app/ui/downloads/ServerDownloadsSheet.kt:464-479, core/ui/downloads/Downloads.kt:450)

## 35. Find songs

- [x] Opens for a song by its server id: a find's id without "find:", or the library song's copy on the signed-in server with the smallest native id; when there is none the song menu says "This server has no copy of the song to look for". (app/data/ServerDownloads.kt:225-237, app/ui/menu/SongMenu.kt:287-292)
- [x] The search starts with findSongs and is polled with getFoundSongs every 1.5 s while it is searching; a failure stops it. Problems: the error's own message, else "Could not start the search" (start) or "Could not reach the server" (poll). (core/ui/downloads/DownloadWatches.kt:296-322)
- [x] Bar: back "Back to the log" when opened from a log, else "Back to Server downloads"; "Search again" when not searching (also forgets an unanswered older-server question). (app/ui/downloads/ServerDownloadsSheet.kt:528-536)
- [x] Head: 64dp artwork radius 10dp (the song's cover, else the id); "FIND SONGS" caption; the song's title (or the title it was opened with); artist. (app/ui/downloads/ServerDownloadsSheet.kt:606-616)
- [x] Under it: "Your copy: <quality>, <size>" when known; then for a library song "Only a better copy can take your copy's place, and yours stays until the new one passes every check." (older server) or "Picking a copy asks you before it replaces yours. Yours stays until the new one passes every check." (asks first); for a song not in the library "Pick a copy to download that one. It goes through the same checks as any download.". (app/ui/downloads/ServerDownloadsSheet.kt:617-622, core/ui/downloads/Downloads.kt:227-254)
- [x] Sources: one line each, "<name>: Searching" with a spinner, "<name>: <text or Done>" with a check, off with a muted close, failed with an orange info and "Could not search". (app/ui/downloads/ServerDownloadsSheet.kt:625-641)
- [x] Orange caption lines for: the watch's problem, the search's error, and a pick's detail when not queued. (app/ui/downloads/ServerDownloadsSheet.kt:540-542)
- [x] When the library copy looks like another take: an info line with the server's words, over the copies. (app/ui/downloads/ServerDownloadsSheet.kt:566-574, core/ui/downloads/ReplaceAnyway.kt:61-63)
- [x] "Nothing found on your sources." when no copies and not searching; "You can pick a copy once the search is done." while copies exist and it still searches. (app/ui/downloads/ServerDownloadsSheet.kt:575-581)
- [x] Copy line: kind badge (FLAC, MP3; lossless kinds brighter on a white 16% chip, others on 8%); a "vs yours" outlined tag (read out "Compared with your copy: <words>"); title (or file name, or source); album or folder; facts joined " · "; Octo's order "1st choice", "2nd choice", "3rd choice", "11th choice" (TextPrimary for 1st) or the server's reason. (app/ui/downloads/ServerDownloadsSheet.kt:643-706, core/ui/downloads/Downloads.kt:411-467)
- [x] Facts order: quality (or format upper case), size, length m:ss, source, peer, "Free to send now" or "<n> in queue", speed. (core/ui/downloads/Downloads.kt:411-425)
- [x] Sizes: KB under 1 MiB (no decimals), MB with one decimal, GB with two; speeds "1.4 MB/s" or "<n> KB/s" (at least 1). (core/ui/downloads/Downloads.kt:469-482)
- [x] Lossless kinds: flac, wav, alac, ape, aiff, aif, wv. (core/ui/downloads/Downloads.kt:463-467)
- [x] A copy can be picked only after the search is done and when the server named it (id, or place on an older server); the pick button is 44dp with a download icon 22dp, labeled "Get this copy". (core/ui/downloads/Downloads.kt:242-245, app/ui/downloads/ServerDownloadsSheet.kt:676-687) (iPhone: SF Symbol arrow.down)
- [x] No copy can be picked while one replaces the library song's copy. (app/ui/downloads/ServerDownloadsSheet.kt:583-591)
- [x] Older server, library song: picking first shows a card "Replace your copy with <first two facts>?" with the replace rule line and buttons "Cancel" and "Replace it" (lossless icon); yes sends the pick. (app/ui/downloads/ServerDownloadsSheet.kt:543-563, 708-723)
- [x] Server that asks first: every pick is sent with anyway=false; a "ready" answer shows the same card (yes sends again with anyway=true, Cancel keeps mine); a "confirm" answer opens the Replace anyway sheet. (core/ui/downloads/DownloadWatches.kt:329-383) (iPhone: a confirm answer opens a system alert)
- [x] A pick from a list replaced by a new search answers "The list changed. Pick a copy from it again."; one sent while searching answers "You can pick a copy once the search is done."; nothing is sent then. (core/ui/downloads/DownloadWatches.kt:352-359, core/ui/downloads/Downloads.kt:236-240)
- [x] A queued pick wakes the list; if the sheet still shows that search it opens the new download's log, or the list when the server gave no key. (app/data/ServerDownloads.kt:291-297)
- [x] A copy being replaced shows on its own line a 16dp ring and "Replacing... <step words>" (polite live region). (app/ui/downloads/ServerDownloadsSheet.kt:665-674, core/ui/downloads/ReplaceAnyway.kt:139-144) (iPhone: the updates-frequently accessibility trait)

## 36. Replace anyway sheet and replacement endings

- [x] A separate sheet over Find songs for a "confirm" question: title "Replace your copy?" (headline, heading, pane title), the song's title (or the Find view's), the two copies compared, then the server's sentence word for word. (app/ui/downloads/ServerDownloadsSheet.kt:131-182) (iPhone: a system alert over the sheet, its title in place of a pane title)
- [x] Compare lines on a white 8% card radius 14dp: "Yours: <quality>, <m:ss>, <take>" (TextSecondary) then "This copy: ..." (TextPrimary); missing parts left out; a side with none is left out. (core/ui/downloads/ReplaceAnyway.kt:40-53) (iPhone: the compare lines are the alert's message)
- [x] The sentence falls back to "This copy is not better than yours. Replace yours anyway?". (core/ui/downloads/ReplaceAnyway.kt:33-34)
- [x] Buttons stay fixed under scrolling words: "Keep mine" (glaze, medium) and "Replace anyway" (accent fill, medium), equal widths, 10dp apart. Back, tap outside or pull down keep mine; nothing is sent. (app/ui/downloads/ServerDownloadsSheet.kt:146, 175-178) (iPhone: alert buttons; Keep mine is the cancel button, so closing the alert keeps mine)
- [x] When the words overflow: a 48dp fade to the sheet colour at the bottom with a "More below" pill (accent-selected fill, thread border, collapse icon 14dp) that scrolls to the end; it fades out over 200ms once the end shows. (app/ui/downloads/ServerDownloadsSheet.kt:184-212) (iPhone: the system alert scrolls its words and keeps its buttons in place)
- [x] The last question stays drawn while its sheet slides away. (app/ui/downloads/ServerDownloadsSheet.kt:142-145)
- [x] Replace anyway sends the same pick with anyway=true only if that question is still the one waiting; when queued for a library song it is followed as a replacement, else it goes on like a normal pick. (core/ui/downloads/DownloadWatches.kt:341-344, app/data/ServerDownloads.kt:254-269)
- [x] A replacement is followed through the upgrades list: still pending marks it seen; it ends on Upgraded (replaced) or NotFound/Failed/Skipped/Rehearsed (kept); an end no later than the newest job listed when it started belongs to the older job unless it was seen under way. Times compare as instants, else as text. (core/ui/downloads/ReplaceAnyway.kt:146-211)
- [x] Replaced: toast "Replaced with the copy you picked" (or "Replaced with the plain song" when the copy's take was "the plain song", ignoring case) with "Undo", which puts the old copy back on the server it was replaced on. (core/ui/downloads/ReplaceAnyway.kt:78-127, app/data/ServerDownloads.kt:274-280)
- [x] Kept: toast "<server words, ending in punctuation> Details are in Downloads." (fallback "The copy you picked did not replace yours. Your copy was kept.") with "Show downloads", which opens the list. (core/ui/downloads/ReplaceAnyway.kt:129-135, app/data/ServerDownloads.kt:281-284)

## 37. Live lists: storage and the songs they pick

- [x] Kept in the "live_lists" preferences store under "lists:<account>", where account is the session id, else the first 8 bytes of SHA-256 of "username@address" in hex, or "phone" when signed out; signing in elsewhere shows that account's lists. (app/livelists/LiveListStore.kt:22-53, core/livelists/LiveList.kt:94-100) (iPhone: the app's settings store, key "live_lists.lists:<account>")
- [x] Stored JSON: {"version":1,"lists":[{"id","name","query",["created"],["changed"]}]}; created/changed omitted when 0; unreadable lists are skipped, duplicates by id dropped, unknown rules dropped from their list only. (core/livelists/LiveList.kt:40-78)
- [x] Saving trims the name, stamps changed = now and created = now when 0; a new list goes at the end, a changed one in its place. (app/livelists/LiveListStore.kt:57-63, core/livelists/LiveList.kt:80-82)
- [x] Rename ignores a blank name or the same name. (app/livelists/LiveListStore.kt:67-71)
- [x] Duplicate makes "<name> (copy)" right after the original. (core/livelists/LiveList.kt:86-92, core/ui/playlist/PlaylistAdds.kt:63)
- [x] Songs are picked from the whole library with likes and listening (phone plays and server plays together), worked out again whenever the library, a like or a play changes, off the main thread. (app/livelists/LiveListSongs.kt:21-46)
- [x] The phone's song fields: no album artist, composer, likedAt, bit rate or BPM (rules on them match nothing); added date is the catalogue's seconds times 1,000; format from the MIME type; lossless from the MIME type or format. (app/sort/TrackQuery.kt:10-59)

## 38. Live list page

- [x] Header: title, song count, total length, Play (from the first), Shuffle, More (live list options). Artwork 240dp: a mosaic of the songs' covers, or the live mark tile when none; cover line for live lists. (app/ui/livelists/LiveListScreen.kt:108-121)
- [x] Under the header, centered caption (TextSecondary, 32dp sides, 12dp bottom): the summary of its rules without a count. (app/ui/livelists/LiveListScreen.kt:122-130)
- [x] No songs: the note "No songs match right now. As songs are added, played and liked, the ones that match show up here.". (app/ui/livelists/LiveListScreen.kt:131-133, 144)
- [x] Rows: plain song rows; tap plays the list from that song with the list's name as the playing source; multi-select available. (app/ui/livelists/LiveListScreen.kt:104-136, 75-77)
- [x] The page leaves itself when the list is deleted. (app/ui/livelists/LiveListScreen.kt:96-98)
- [x] Live mark tile: accent at 16% fill, filter icon at 42% of the size in the accent. (app/ui/livelists/LiveListParts.kt:35-42) (iPhone: SF Symbol line.3.horizontal.decrease)
- [x] Options menu titled with the list name: "Edit rules", "Rename" (popup "Rename live list", field "Live list name", "Save"), "Duplicate" (toast "Made a copy: <copy name>"), "Save a copy as a playlist" (toast "Saved a copy of <name> as a playlist, <n> songs" with thousands separators, or ""<name>" has no songs right now, so there is nothing to copy."), "Delete" (destructive, confirm). (app/ui/playlist/PlaylistSheets.kt:195-225, 306-337; app/ui/livelists/LiveListEditing.kt:56-60) (iPhone: system menu; rename and delete ask in system alerts)
- [x] In the playlists list a live list shows its mark, its name and "Live list"; "New live list" / "Songs picked by rules, always up to date" opens the editor. (app/ui/livelists/LiveListParts.kt:44-58) (iPhone: a long press gives a live list's options as a system context menu)

## 39. Live list editor

- [x] Title "New live list" or "Edit live list". Starts from the saved list, a page's filters, or nothing picked with newest-first order. (app/ui/livelists/LiveListEditScreen.kt:209, app/ui/livelists/LiveListEditing.kt:14-20)
- [x] Name field with the placeholder made from the rules (one rule; the first two rules joined; the words capitalized; else "New live list"). (app/ui/livelists/LiveListEditScreen.kt:210-212, core/livelists/LiveListWords.kt:32-43)
- [x] About text: "Picks songs from your whole library that match these rules, and keeps up as songs are added, played and liked.". (app/ui/livelists/LiveListEditScreen.kt:213-220)
- [x] Words field placeholder "With these words". (app/ui/livelists/LiveListEditScreen.kt:221-223)
- [x] Rules as on chips (tap takes one off) and an off chip "Add a rule" (or "Add another rule"), flow-wrapped 8dp apart. (app/ui/livelists/LiveListEditScreen.kt:224-233) (iPhone: Add a rule is a system menu drawn as the off chip)
- [x] With two or more rules: "A song needs to match" with chips "All of these" and "Any of these". (app/ui/livelists/LiveListEditScreen.kt:234-242, core/livelists/LiveListRules.kt:27-29)
- [x] "Order" button: the order in words, first letter capitalized, or "In library order"; opens the sort sheet over: Recently added, Most played, Recently played, Rating, Title, Artist, Album, Year, Length. (app/ui/livelists/LiveListEditScreen.kt:243-250, core/livelists/LiveListRules.kt:92-95) (iPhone: system menu: the two directions on top, then the orders)
- [x] "How many" button: "All songs" or "The first <n>"; sheet "How many songs" with All songs, 25, 50, 100, 250, 500. (app/ui/livelists/LiveListEditScreen.kt:251-256, core/livelists/LiveListRules.kt:87-89) (iPhone: system menu with checkmarks)
- [x] Buttons: accent "Make live list" (new) or "Save", and glaze "Cancel" (goes back). A new list then opens its page in place of the editor; an edited one returns. (app/ui/livelists/LiveListEditScreen.kt:259-264, app/ui/nav/MainShell.kt:392-398)
- [x] The saved name is the typed name trimmed, else the generated name. (core/livelists/LiveListWords.kt:73-85)
- [x] Starters ("Or start with one of these") show only on a new, empty editor while the listener has no live lists and it was not opened with filters: "Recently added", "Not played in a year", "Most played this month" (limit 50), "Lossless favorites", each with its detail line; a tap makes it as it is. (app/ui/livelists/LiveListEditing.kt:22-25, core/livelists/LiveListRules.kt:114-146, app/ui/livelists/LiveListEditScreen.kt:265-270)
- [x] Preview: "<n> songs match right now" ("1 song matches right now", thousands separators), or "No songs match these rules yet. Take a rule off, or pick Any of these so a song needs to match only one."; then the songs, tap plays from that one with the draft name as source. (app/ui/livelists/LiveListEditScreen.kt:271-282, 288; core/livelists/LiveListWords.kt:64-65)
- [x] Add a rule, first page: Added, Played, Times played, Length, Rating, Genre, Artist, Year, Favorites, Lossless. (app/ui/livelists/LiveListEditing.kt:38-45)
- [x] Groups: Added (In the last week / month / year); Played (In the last week, In the last month, Never, Not in the last 6 months, Not in the last year); Times played (At least once, 5, 10, 25 times or more); Length (3 minutes or shorter, 6 minutes or longer, 10 minutes or longer). (core/livelists/LiveListRules.kt:41-84)
- [x] Rating page: "5 stars", "4 stars or more" ... "1 star or more". Genre and Artist pages list the library's values A to Z; Year lists decades newest first as "The 1990s". An empty page is not shown. The current pick is ticked. (app/ui/livelists/LiveListEditing.kt:50-54, app/ui/livelists/LiveListEditScreen.kt:177-205)
- [x] Picking a rule already on takes it off; genre, artist, album artist, composer and year rules add up; any other replaces the rule on its field. (core/livelists/LiveListRules.kt:12-25)
- [x] A page's filters become a live list with the page's own rule first, then its filters; match All when the page has a rule; the page's order or newest first; the filters' limit. (core/livelists/LiveListRules.kt:100-112)

## 40. Live list summary words

- [x] Complete rules' labels joined by ", " (All) or " or " (Any), later ones starting lower case unless their second letter is upper case ("BPM"). (core/livelists/LiveListWords.kt:15-18, 69-71)
- [x] Words typed add "with “<words>”"; with nothing at all "Every song". (core/livelists/LiveListWords.kt:19-21)
- [x] Then the order in words, then: no count with a limit "the top <n>"; count at or over the limit "the top <n songs>"; else "<n songs>"; the first part capitalized; all joined ", ". (core/livelists/LiveListWords.kt:22-30)
- [x] Order words: title "by title"/"by title, Z to A"; artist and album likewise; added "newest first"/"oldest first"; year "latest year first"/"earliest year first"; length "longest first"/"shortest first"; most played "most played first"/"least played first"; recently played "last played first"/"longest unplayed first"; rating "highest rated first"/"lowest rated first"; liked "newest favorites first"/"oldest favorites first"; folder "in folder order". (core/livelists/LiveListWords.kt:45-62)

## 41. Query engine (live lists and filters)

- [x] Rule labels: text "<Field> <is|is not|contains|does not contain|starts with> <value>" (format upper case); "From the 1990s" for a whole decade; plays "Never played", "Played once", "Played <n> times", "Played at least once", "Played <n> times or more", "Played <n> times or fewer"; length "<m:ss> or longer"/"or shorter"; numbers "<Field> is/is not/at least/at most/between a and b"; bit rate "<n> kbps". (core/query/QueryLabels.kt:9-92)
- [x] Date labels: "Added in the last <span>", "Played in the last <span>", "Not added/played in the last <span>", "Added before <d MMM yyyy>", "Last played before ...", "Added since ...", "Last played since ...", "No date added", "Never played"; flags "Lossless"/"Lossy", "Favorites"/"Not favorites". (core/query/QueryLabels.kt:42-46, 94-107)
- [x] Span words: day, week, month, year, "<n> years", "<n> months", "<n> weeks", "<n> days". (core/query/QueryLabels.kt:109-120)
- [x] An incomplete rule (test not suiting its field or lacking its value) is ignored when picking and labeled by field name only. (core/query/LibraryQuery.kt:156-172, core/query/QueryLabels.kt:34)
- [x] Typed words: every word must appear in title, artist, album, album artist or a genre, folded (lower case, accents removed). (core/query/QueryMatching.kt:28, 43-59, 149-161)
- [x] Text rules: a song with several genres passes a positive test when any genre does, a negative test when none fails it. (core/query/QueryMatching.kt:74-94)
- [x] Number rules: plays and rating are 0 when none; a missing year, length, bit rate or BPM passes only "is not"; between uses the lower and upper of the two values. (core/query/QueryMatching.kt:96-117)
- [x] Date rules: a never-played song counts as not played in any span; before/after split songs that have a date. (core/query/QueryMatching.kt:119-132)
- [x] After matching, the order is applied, then the limit. (core/query/QueryMatching.kt:15-22)
- [x] Sorting keys are natural sort keys ("The" dropped, numbers by value); missing years and dates last; album songs in album order (disc, track) among ties; plays by the shared listening order. (core/query/QuerySorting.kt:18-52, core/catalog/Keys.kt:18-29)
- [x] Saved query JSON omits defaults and nulls, ignores unknown keys and reads unknown enum words as the default. (core/query/LibraryQuery.kt:175-183)

## 42. Library artist page extras (from the server)

- [x] Top songs (10), biography and similar artists, cached per user, server and artist for the app's run; "forget" drops one artist's cache. Nothing without a server; when neither part answered, nothing is cached and it is asked again next time. (app/discovery/ArtistExtras.kt:25-94)
- [x] The server's artist id: the library's own id when it came from this server (not a library-made "artist:" id); else a server artist of the same name merged into it; else the first search hit (5 artists) with the same name. (app/discovery/ArtistExtras.kt:96-106, 137-141)
- [x] Top songs by id only when the server lists "topSongsByArtistId"; asked by name, songs by someone else of a similar name are dropped. (app/discovery/ArtistExtras.kt:28-29, 76-80, 143-146)
- [x] Biography made plain: the trailing "Read more" link dropped, breaks and paragraph ends made new lines, tags removed, entities decoded, paragraphs separated by one empty line; nothing when empty. (core/discovery/Biography.kt:6-31)
- [x] Similar artists: not the same name as this artist, with an id; each opens in the library when there (library name and artwork) else as an online artist; each once. (app/discovery/ArtistExtras.kt:108-122)
- [x] With "Library songs only": top songs keep only library songs, similar artists only library ones. (app/discovery/ArtistExtras.kt:43-46)

## Shared logic to port line for line

| Path | What it does | Tests |
| --- | --- | --- |
| `shared/core/src/commonMain/kotlin/app/winters/octo/home/Rediscovery.kt` | Home rediscovery shelves (not played lately, never finished, never played), album listening from Subsonic songs | `shared/core/src/commonTest/kotlin/app/winters/octo/home/RediscoveryTest.kt`, `app/src/test/java/app/winters/octo/ui/home/RediscoveryTest.kt` |
| `shared/core/src/commonMain/kotlin/app/winters/octo/discovery/TopSongs.kt` | Top songs and chart counts, named artist, plays text, ranked-by words, chart sizes | `shared/core/src/commonTest/kotlin/app/winters/octo/discovery/TopSongsTest.kt`, `app/src/test/java/app/winters/octo/ui/search/SearchTopSongsTest.kt`, `app/src/test/java/app/winters/octo/ui/charts/ChartsCaptionTest.kt` |
| `shared/core/src/commonMain/kotlin/app/winters/octo/discovery/AlbumShare.kt` | How much of an online album the library holds, share line, "Partly in your library" | `shared/core/src/commonTest/kotlin/app/winters/octo/discovery/AlbumShareTest.kt` |
| `shared/core/src/commonMain/kotlin/app/winters/octo/discovery/Biography.kt` | Biography HTML to plain text | `shared/core/src/commonTest/kotlin/app/winters/octo/discovery/BiographyTest.kt` |
| `shared/core/src/commonMain/kotlin/app/winters/octo/discovery/LibraryOnly.kt` | "Library songs only" words and filter | `shared/core/src/commonTest/kotlin/app/winters/octo/discovery/LibraryOnlyTest.kt`, `app/src/test/java/app/winters/octo/discovery/LibraryOnlyListsTest.kt` |
| `shared/core/src/commonMain/kotlin/app/winters/octo/discovery/Matching.kt` | Same song, same recording, any version, title keys, guessed length, TitleIndex, IsrcIndex, MIME by suffix | `shared/core/src/commonTest/kotlin/app/winters/octo/discovery/MatchingTest.kt` |
| `shared/core/src/commonMain/kotlin/app/winters/octo/catalog/SongIdentity.kt` | The song identity rules Matching.kt calls (titles, artists, versions, ISRCs) | covered by the catalog area's tests; port before Matching.kt |
| `shared/core/src/commonMain/kotlin/app/winters/octo/catalog/Keys.kt` | searchKey, sortKey, naturalSortKey | catalog area tests |
| `shared/core/src/commonMain/kotlin/app/winters/octo/ui/search/RecentSearchRules.kt` | Recent searches: tidy, add, remove, encode, decode, 10 kept | `app/src/test/java/app/winters/octo/ui/search/RecentSearchesTest.kt` |
| `shared/core/src/commonMain/kotlin/app/winters/octo/ui/downloads/Downloads.kt` | Drawer rows, phases, status words, summary, pill lead and count, still-asked rules, steps, log marks, copy facts and words | `shared/core/src/commonTest/kotlin/app/winters/octo/ui/downloads/DownloadsTest.kt`, `app/src/test/java/app/winters/octo/ui/downloads/DownloadsPillTest.kt` |
| `shared/core/src/commonMain/kotlin/app/winters/octo/ui/downloads/DownloadWatches.kt` | Polling of the list, a log and a Find songs search; pick and replace-anyway flow | `shared/core/src/commonTest/kotlin/app/winters/octo/ui/downloads/DownloadsTest.kt` |
| `shared/core/src/commonMain/kotlin/app/winters/octo/ui/downloads/ReplaceAnyway.kt` | Replace anyway words, questions, replacements and their endings | `shared/core/src/commonTest/kotlin/app/winters/octo/ui/downloads/DownloadsTest.kt` |
| `shared/core/src/commonMain/kotlin/app/winters/octo/livelists/LiveList.kt` | Live list model, JSON store shape, save/remove/duplicate, account key | `shared/core/src/commonTest/kotlin/app/winters/octo/livelists/LiveListTest.kt`, `app/src/test/java/app/winters/octo/livelists/LiveListStoreTest.kt` |
| `shared/core/src/commonMain/kotlin/app/winters/octo/livelists/LiveListRules.kt` | Rule toggling, rule menu groups, limits, sorts, starters, list from page filters | `shared/core/src/commonTest/kotlin/app/winters/octo/livelists/LiveListTest.kt`, `app/src/test/java/app/winters/octo/ui/livelists/LiveListEditingTest.kt` |
| `shared/core/src/commonMain/kotlin/app/winters/octo/livelists/LiveListWords.kt` | Summary, generated name, order words, match words, draft | `shared/core/src/commonTest/kotlin/app/winters/octo/livelists/LiveListTest.kt` |
| `shared/core/src/commonMain/kotlin/app/winters/octo/query/LibraryQuery.kt` | Query model, rules, ops, completeness, JSON | `shared/core/src/commonTest/kotlin/app/winters/octo/query/LibraryQueryTest.kt` |
| `shared/core/src/commonMain/kotlin/app/winters/octo/query/FilterPresets.kt` | Preset rules, rating words, artists/genres/decades in a list | `shared/core/src/commonTest/kotlin/app/winters/octo/query/LibraryQueryTest.kt` |
| `shared/core/src/commonMain/kotlin/app/winters/octo/query/QueryLabels.kt` | Rule labels and span words | `shared/core/src/commonTest/kotlin/app/winters/octo/query/LibraryQueryTest.kt` |
| `shared/core/src/commonMain/kotlin/app/winters/octo/query/QueryMatching.kt` | Picking songs, typed words, text/number/date tests, foldText | `shared/core/src/commonTest/kotlin/app/winters/octo/query/LibraryQueryTest.kt`, `shared/core/src/commonTest/kotlin/app/winters/octo/query/QuerySpeedTest.kt` |
| `shared/core/src/commonMain/kotlin/app/winters/octo/query/QuerySorting.kt` | Song orders with tie-breaks | `shared/core/src/commonTest/kotlin/app/winters/octo/query/LibraryQueryTest.kt` |
| `shared/core/src/commonMain/kotlin/app/winters/octo/query/SongFields.kt` | Field reader interface, lossless formats, quickTime, places | `shared/core/src/commonTest/kotlin/app/winters/octo/query/LibraryQueryTest.kt` |
| `shared/core/src/commonMain/kotlin/app/winters/octo/server/ServerQueues.kt` (`shouldOfferResume`) | When the resume card offers another device's queue | `app/src/test/java/app/winters/octo/server/QueueSyncTest.kt` |
| `app/src/main/java/app/winters/octo/ui/home/HomeGate.kt` (`homeLayout`) | Which Home parts show | `app/src/test/java/app/winters/octo/ui/home/HomeGateTest.kt` |
| `app/src/main/java/app/winters/octo/ui/home/Stations.kt` | Stations stale time, gone line, song count line, when to reload | `app/src/test/java/app/winters/octo/ui/home/StationsTest.kt` |
| `app/src/main/java/app/winters/octo/ui/home/Rediscovery.kt` | Phone album listening for the rediscovery shelves | `app/src/test/java/app/winters/octo/ui/home/RediscoveryTest.kt` |
| `app/src/main/java/app/winters/octo/whatsnew/WhatsNew.kt` (`whatsNewDue`) | When the what's new card is due | `app/src/test/java/app/winters/octo/whatsnew/WhatsNewTest.kt` |
| `app/src/main/java/app/winters/octo/ui/search/SearchViewModel.kt` (`searchCaps`, `listedFinds`, `without`, `namedArtist`) | Search caps, finds already listed, named artist | `app/src/test/java/app/winters/octo/ui/search/SearchSectionsTest.kt`, `app/src/test/java/app/winters/octo/ui/search/SearchTopSongsTest.kt` |
| `app/src/main/java/app/winters/octo/discovery/AddHint.kt` (`showsAddHint`) | When the add hint line shows | `app/src/test/java/app/winters/octo/discovery/AddHintTest.kt` |
| `app/src/main/java/app/winters/octo/discovery/Arrivals.kt` | Arrival lines for songs and albums | `app/src/test/java/app/winters/octo/discovery/ArrivalsTest.kt` |
| `app/src/main/java/app/winters/octo/discovery/DownloadProgress.kt` | Download phases, poll delays, entry matching, ProgressWatch | `app/src/test/java/app/winters/octo/discovery/DownloadProgressTest.kt` |
| `app/src/main/java/app/winters/octo/discovery/Downloads.kt` (`adoptions`, `downloadMatches`, `askedSongs`, `phasesOf`, `recheckMs`, `stateOf`) | Pure download rules | `app/src/test/java/app/winters/octo/discovery/DownloadProgressTest.kt`, `app/src/test/java/app/winters/octo/discovery/LibraryMatchingTest.kt` |
| `app/src/main/java/app/winters/octo/discovery/LibraryMatching.kt` | Resolving server songs to library songs or finds, find shape | `app/src/test/java/app/winters/octo/discovery/LibraryMatchingTest.kt`, `app/src/test/java/app/winters/octo/ui/search/SearchSectionsTest.kt` |
| `app/src/main/java/app/winters/octo/discovery/Discovery.kt` (`madeForYouLists`, `Suggestions`) | Made for you order, radio source memory | `app/src/test/java/app/winters/octo/discovery/MadeForYouTest.kt` |
| `app/src/main/java/app/winters/octo/discovery/SearchTopSongs.kt` (`rankTracks`) | Ranks staying with their songs | `app/src/test/java/app/winters/octo/ui/search/SearchTopSongsTest.kt` |
| `app/src/main/java/app/winters/octo/discovery/AlbumHighlight.kt` | Album's main song star | `app/src/test/java/app/winters/octo/discovery/AlbumHighlightTest.kt` |
| `app/src/main/java/app/winters/octo/discovery/ArtistExtras.kt` (`serverArtistIdOf`, `ownSongs`, `inLibraryOnly`) | Artist extras rules | `app/src/test/java/app/winters/octo/discovery/ArtistExtrasTest.kt` |
| `app/src/main/java/app/winters/octo/discovery/WholeAlbum.kt` | Library album with finds in server order | `app/src/test/java/app/winters/octo/discovery/WholeAlbumTest.kt` |
| `app/src/main/java/app/winters/octo/discovery/FindLengths.kt` | Shown length and learned lengths of finds | `app/src/test/java/app/winters/octo/discovery/FindLengthsTest.kt` |
| `app/src/main/java/app/winters/octo/ui/common/FindSwap.kt` | Find row faces, check hold, swap fade | `app/src/test/java/app/winters/octo/ui/common/FindSwapTest.kt` |
| `app/src/main/java/app/winters/octo/ui/common/NotInLibrary.kt` | Row signs, row ends, mark size and inset, album note, spoken words | `app/src/test/java/app/winters/octo/ui/common/NotInLibraryTest.kt` |
| `app/src/main/java/app/winters/octo/ui/common/AddToLibraryButton.kt` (`downloadStateText`) | Add button spoken states | `app/src/test/java/app/winters/octo/ui/common/AddToLibraryButtonTest.kt` |
| `app/src/main/java/app/winters/octo/ui/downloads/DownloadsPill.kt` (`comingText`, `ringPhase`) | Pill words and ring step | `app/src/test/java/app/winters/octo/ui/downloads/DownloadsPillTest.kt` |
| `app/src/main/java/app/winters/octo/ui/livelists/LiveListEditing.kt` | Editor start, starters gate, rule menu, rating rules, copy messages | `app/src/test/java/app/winters/octo/ui/livelists/LiveListEditingTest.kt` |
| `app/src/main/java/app/winters/octo/ui/charts/ChartsScreen.kt` (`caption`) | Chart caption with country name | `app/src/test/java/app/winters/octo/ui/charts/ChartsCaptionTest.kt` |
| `app/src/main/java/app/winters/octo/sort/TrackQuery.kt` (`TrackFields`, `formatOf`) | The phone's song fields for queries | sort area tests |
