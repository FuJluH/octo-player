# Parity contract: library, pages and menus

Read from octo-player origin/main 0f11df0f (git show only; the stale working tree was not read).

Path shorthand used in every reference below:

- `ui/...`, `catalog/...`, `sort/...`, `folders/...`, `offline/...`, `listening/...`, `playback/...`, `discovery/...`, `device/...`, `data/...` are under `app/src/main/java/app/winters/octo/`.
- `core/...` is under `shared/core/src/commonMain/kotlin/app/winters/octo/`.
- `design/...` is under `design/src/main/java/app/winters/octo/design/`.
- Line numbers are origin/main line numbers of that file.
- Words in double quotes are exact user-facing strings, including punctuation and the US spelling "Favorites".
- Style names (OctoType.display, OctoType.title, OctoType.section, OctoType.body, OctoType.bodySmall, OctoType.label, OctoType.caption) and colour tokens (OctoColors.TextPrimary, TextSecondary, TextMuted, Accent, AccentSelected, Background, BackgroundTertiary, Destructive, Error) are the design tokens; map them to the iOS token set one to one.

## 1. Page frame shared by every library page

- [x] Content padding for a scrolling page: top = status bar inset + 8dp + extraTop; bottom = navigation bar inset + 120dp (ui/common/Layout.kt:25)
- [x] Detail pages pass extraTop = DetailTopGap = 56dp so content clears the floating back button (ui/common/Layout.kt:52)
- [x] ScreenTitle: OctoType.display, TextPrimary, padding start 20, end 20, top 8, bottom 16 (ui/common/Layout.kt:32)
- [x] SectionTitle: OctoType.section, TextPrimary, padding 20 horizontal, 10 vertical (ui/common/Layout.kt:42)
- [x] BackButton: floats over the page, status bar padding, then start 16dp and top 8dp; a 40dp glazed round icon button with the Back icon, accessibility label "Back"; it blurs what is behind (ui/common/Layout.kt:56) (iPhone: a floating Liquid Glass round button with the Back symbol)
- [x] Every detail page draws BackButton last, above its content (ui/library/LibraryScreen.kt:397)
- [x] Song length as a clock: "m:ss" under an hour, "h:mm:ss" from an hour (ui/common/Layout.kt:69)
- [x] Album or playlist length in words: minutes = (seconds + 30) / 60 rounded down; at 60 or more "H hr M min", otherwise "M min" (ui/common/Layout.kt:77)
- [x] Count words: "1 song" / "N songs" and "1 album" / "N albums", no thousands separator (ui/common/Layout.kt:82)
- [x] TitleWithSort: the big title, and the page's buttons (sort, search) at the end of the same line, the buttons box padded end 20dp and bottom 8dp (ui/common/Sorting.kt:185)
- [x] TitleWithSort never shortens or wraps the title: when the title at its full one-line width plus the buttons width is wider than the line, the buttons move to their own line under the title, aligned to the end edge (ui/common/Sorting.kt:196)
- [x] TitleWithSort fit test: titleWidth + buttonsWidth <= width means side by side (ui/common/Sorting.kt:215)
- [x] Side by side, title and buttons are each centred vertically in the taller of the two (ui/common/Sorting.kt:198)
- [x] SortBar: a line above a list inside a page: optional name on the left (OctoType.section, 10dp vertical padding), the sort button at the right, row padded 20dp horizontally (ui/common/Sorting.kt:160)
- [x] Pull to refresh (Refreshable) wraps most library pages: a pull rescans the phone's music and syncs the signed-in server, and runs the page's own reload in parallel (ui/common/Refreshable.kt:34)
- [x] A second pull while one refresh runs is ignored (ui/common/Refreshable.kt:35) (iPhone: the system's pull to refresh runs one refresh at a time)
- [x] When the server sync fails, its message is shown as a feedback line, because the pull asked for it; other failures are only logged (ui/common/Refreshable.kt:41)
- [x] Refresh also refreshes server download progress, rescans the phone, and syncs the server only when signed in (data/LibraryRefresh.kt:24)
- [x] The pull indicator is drawn like Home's pull (Material pull to refresh box filling the page) (ui/common/Refreshable.kt:66) (iPhone: the system's pull to refresh spinner over the page)
- [x] Generic loading spinner: centred, Accent colour, 28dp (ui/common/LoadState.kt:45)
- [x] Generic failure state: message centred in TextSecondary bodySmall, then an accent "Try again" button, 16dp apart, 32dp page padding (ui/common/LoadState.kt:48)
- [x] Server error messages for any failure (exact words): unreachable "Couldn't reach the server. Check the address, and that you're on the right network."; not Subsonic and busy "The server isn't answering right now. It may be restarting, so try again in a moment."; not Subsonic "That address answered, but not like a music server. Check the port."; wrong credentials "Wrong username or password."; not found "That isn't on the server any more."; server error "The server said: <message>"; anything else "Something went wrong." (data/UserMessages.kt:6)

## 2. Sort button, sort popup and the orders of every list

### 2.1 Sort button

- [x] The sort button is a glass capsule 34dp tall inside a 48dp minimum touch target (ui/common/Sorting.kt:93)
- [x] Capsule content, left to right: the sort icon 16dp tinted white at 72% alpha, the option label (OctoType.label Medium weight, TextPrimary, one line, ellipsis), then the Ascending arrow icon 14dp in white 72%; padding start 12dp, end 11dp, 7dp between items (ui/common/Sorting.kt:132)
- [x] The arrow points up for ascending and is rotated 180 degrees for descending; the turn animates with a spring (damping 0.7, stiffness 300), so a change of direction shows the arrow flipping (ui/common/Sorting.kt:101)
- [x] Pressed, the capsule scales to 0.94 with a spring (damping 0.45, stiffness 600); no ripple (ui/common/Sorting.kt:111) (iPhone: the system menu button's own press highlight)
- [x] Accessibility: one merged element "Sorted by <option label>, <direction words>" with click label "Change the order" (ui/common/Sorting.kt:118)
- [x] A tap opens the sort popup anchored beside the button (choiceAnchor) (ui/common/Sorting.kt:117) (iPhone: a system menu that opens from the button)

### 2.2 Sort popup

- [x] The popup's accessibility pane title is "Sort by"; no visible title is drawn for a sort request (ui/common/ChoiceSheet.kt:150) (iPhone: a system menu; the options are its picker named "Sort by", with no title drawn)
- [x] Popup body 248dp wide, 6dp padding (ui/common/Sorting.kt:223) (iPhone: the system menu's own width and padding)
- [x] Top: the two directions side by side in one glaze 44dp tall, inner padding 4dp, 6dp gap below (ui/common/Sorting.kt:224) (iPhone: the two directions side by side as the menu's palette row)
- [x] Direction order: the option's starting direction on the left, for example "A to Z" before "Z to A" but "Newest" before "Oldest" (core/sort/SortDirections.kt:70)
- [x] The chosen direction sits in a darker selected pill that slides between halves with a spring (damping 0.8, stiffness 350) (ui/common/Sorting.kt:256) (iPhone: the palette row marks the chosen direction)
- [x] Each direction half: arrow icon 16dp (Descending icon for descending, Ascending icon for ascending) drawn with a glow when chosen, then its words; chosen words SemiBold white, other words Medium in white 45%; tint animates (ui/common/Sorting.kt:264) (iPhone: each direction with its up or down arrow symbol and its words in the palette row, the chosen one selected)
- [x] Tapping the other direction changes the order immediately (the list behind reorders) and keeps the popup open; tapping the chosen one does nothing (ui/common/Sorting.kt:224) (iPhone: the order changes at once when the other direction is picked; the system menu then closes)
- [x] Below: the options, one per row, minimum 48dp tall, shape radius 14dp, padding 14 horizontal and 10 vertical, scrolling when taller than the popup may be (ui/common/Sorting.kt:310) (iPhone: the options as the menu's inline picker rows, scrolling when long)
- [x] Rows are parted by 1dp hairlines (TextPrimary at 8%, inset 14dp), always 1dp tall even when not drawn; no hairline touches the selected row (above or below it) (ui/common/GlassMenu.kt:56) (iPhone: the system menu's own separators)
- [x] The chosen option: selected glaze pill behind, label Medium weight TextPrimary, a white check 18dp at the end; other options: Normal weight, white at 70%, an 18dp empty space where the check would be (ui/common/Sorting.kt:333) (iPhone: the system checkmark marks the chosen option)
- [x] Picking a different option switches to it in that option's own starting direction (not the direction that was showing) and closes the popup; picking the current option just closes (ui/common/Sorting.kt:233)
- [x] Each option is a radio item for accessibility; the directions are a radio group (ui/common/Sorting.kt:330) (iPhone: the system picker reads its rows as choices, the chosen one selected)

### 2.3 Direction words

- [x] Name scale: "A to Z" ascending, "Z to A" descending (core/sort/SortDirections.kt:8)
- [x] Date scale: "Oldest" ascending, "Newest" descending (core/sort/SortDirections.kt:9)
- [x] Amount scale: "Least" / "Most" (core/sort/SortDirections.kt:10)
- [x] Length scale: "Shortest" / "Longest" (core/sort/SortDirections.kt:11)
- [x] Rating scale: "Lowest" / "Highest" (core/sort/SortDirections.kt:12)
- [x] Size scale: "Smallest" / "Largest" (core/sort/SortDirections.kt:13)
- [x] Liked scale: "Liked last" / "Liked first" (core/sort/SortDirections.kt:14)
- [x] Listed scale: "In order" / "Reversed" (core/sort/SortDirections.kt:17)
- [x] Song options: Title, Artist, Album use Name; Recently added, Year, Recently played, Date liked use Date; Length uses Length; Most played uses Amount; Rating uses Rating; Liked uses Liked; Folder order uses Listed (core/sort/SortDirections.kt:29)
- [x] Album options: Title, Artist Name; Year, Recently added, Recently played Date; Most played, Song count Amount; Length Length (core/sort/SortDirections.kt:38)
- [x] Artist options: Name Name; Song count, Album count, Most played Amount; Recently played, Recently added Date (core/sort/SortDirections.kt:44)
- [x] Playlist options: Name Name; Recently changed, Recently created Date; Song count Amount (core/sort/SortDirections.kt:49)
- [x] Download options: Recently downloaded Date; Title Name; Size Size (core/sort/SortDirections.kt:54)
- [x] Favourite options: Date added Date; Name Name (core/sort/SortDirections.kt:59)

### 2.4 Options, labels, starting directions and saved ids

- [x] Song options and labels: Title "Title" (A to Z first, by name), Artist "Artist" (by name), Album "Album" (by name), RecentlyAdded "Recently added" (newest first), Year "Year" (newest first), Length "Length" (longest first), MostPlayed "Most played" (most first, by listening), RecentlyPlayed "Recently played" (newest first, by listening), Rating "Rating" (highest first), Liked "Liked" (liked first), DateLiked "Date liked" (newest first), FolderOrder "Folder order" (in order first) (core/sort/Sorts.kt:29)
- [x] Album options: Title, Artist (by name, A to Z first), Year, Recently added, Most played, Recently played, Song count "Song count", Length (descending first) (core/sort/Sorts.kt:55)
- [x] Artist options: Name "Name" (A to Z first), Song count, Album count "Album count", Most played, Recently played, Recently added (by the newest song of theirs in the library), all descending first except Name (core/sort/Sorts.kt:74)
- [x] Playlist options: Name, Recently changed "Recently changed", Recently created "Recently created", Song count (core/sort/Sorts.kt:93)
- [x] Download options: Recently downloaded "Recently downloaded", Title, Size "Size" (core/sort/Sorts.kt:103)
- [x] Favourite options (favourite albums and artists): Date added "Date added", Name (core/sort/Sorts.kt:113)
- [x] An option's saved id is its enum name and never changes once shipped (core/sort/Sorts.kt:52)
- [x] Songs list ("songs"): options Title, Artist, Album, Recently added, Year, Length, Most played, Recently played, Rating, Liked; default Title A to Z (core/sort/Sorts.kt:130)
- [x] Liked songs ("liked"): options Date liked, Title, Artist, Album, Recently added; default Date liked newest first (core/sort/Sorts.kt:131)
- [x] Genre songs ("genre_songs"): the same ten song options; default Title A to Z; one order shared by every genre page (core/sort/Sorts.kt:136)
- [x] Folder songs ("folder_songs"): options Folder order, Title, Artist, Album, Recently added, Year, Length; default Folder order in order; one order for every folder (core/sort/Sorts.kt:137)
- [x] Albums ("albums"): all eight album options; default Title A to Z (core/sort/Sorts.kt:145)
- [x] Artist page albums ("artist_albums"): options Year, Title, Most played; default Year newest first; one order for every artist page (core/sort/Sorts.kt:148)
- [x] Artists ("artists"): all six artist options; default Name A to Z (core/sort/Sorts.kt:153)
- [x] Playlists ("playlists"): all four; default Recently changed newest first (core/sort/Sorts.kt:154)
- [x] Downloads ("downloads"): all three; default Recently downloaded newest first (core/sort/Sorts.kt:155)
- [x] Favourites ("favourites"): Date added, Name; default Date added newest first; one order shared by favourite albums and favourite artists (core/sort/Sorts.kt:156)
- [x] An order is saved as "<option id>:asc" or "<option id>:desc" under the list's key (core/sort/Sorts.kt:160)
- [x] Reading a saved order: nothing saved, not two parts, an option the list does not offer, or a direction word other than asc or desc all fall back to the list's default (core/sort/Sorts.kt:164)
- [x] Orders persist across restarts, one entry per list (sort/SortSettings.kt:30)
- [x] Backups carry only orders that decode and re-encode to the same text; restore writes only lists and orders this app has, leaving others as they are (sort/SortSettings.kt:21)
- [x] Picking another option gives that option in its starting direction; picking the same option keeps the order (core/sort/Sorts.kt:25)

### 2.5 How each order sorts (port exactly)

- [x] Only the first key follows the chosen direction; tie-break keys always run the way written, so an album's songs stay in album order in a newest-first list (core/sort/SortQueries.kt:8)
- [x] Missing values (no year, no rating, never liked) go last whichever way the list runs (core/sort/SortQueries.kt:28)
- [x] Song sort keys: song title sort key; song artist = album artist's sort key, else lower-cased song artist; song album = album's sort key, else lower-cased song album (core/sort/SortQueries.kt:38)
- [x] An album's songs in album order = albumId, albumOrder, title sort key, id (core/sort/SortQueries.kt:45)
- [x] Songs by Title (and the base for Most played, Recently played, Folder order): title key (chosen), artist key, id (core/sort/SortQueries.kt:50)
- [x] Songs by Artist: artist key (chosen), album key, then album order (core/sort/SortQueries.kt:52)
- [x] Songs by Album: album key (chosen), artist key, then album order (core/sort/SortQueries.kt:53)
- [x] Songs by Recently added: addedAt (chosen), then album order (core/sort/SortQueries.kt:54)
- [x] Songs by Year: no year last, year (chosen), album key, then album order (core/sort/SortQueries.kt:55)
- [x] Songs by Length: duration (chosen), title key, id (core/sort/SortQueries.kt:56)
- [x] Songs by Rating: unrated (rating 0) last, rating (chosen), liked songs before unliked always, title key, id (core/sort/SortQueries.kt:57)
- [x] Songs by Liked: liked or not (chosen), title key, id (core/sort/SortQueries.kt:64)
- [x] Songs by Date liked: never liked last, liked time (chosen), title key, id (core/sort/SortQueries.kt:65)
- [x] Letter headings exist only for Title (title key), Artist (artist key) and Album (album key) song orders (core/sort/SortQueries.kt:69)
- [x] A genre's songs match the genre name case-insensitively (core/sort/SortQueries.kt:82)
- [x] Albums by Title (and base for Most played, Recently played): album title key (chosen), album artist key (artist sort key else lower-cased album artist), id (core/sort/SortQueries.kt:98)
- [x] Albums by Artist: artist key (chosen), title key, id (core/sort/SortQueries.kt:100)
- [x] Albums by Year: no year last, year (chosen), artist key, title key, id (core/sort/SortQueries.kt:101)
- [x] Albums by Recently added: addedAt (chosen), title key, id (core/sort/SortQueries.kt:102)
- [x] Albums by Song count and by Length: the count or duration (chosen), title key, id (core/sort/SortQueries.kt:103)
- [x] Album headings only for Title and Artist orders (core/sort/SortQueries.kt:107)
- [x] Artists by Name (and base for Most played, Recently played): name key (chosen), id (core/sort/SortQueries.kt:129)
- [x] Artists by Song count, Album count: the count (chosen), name key, id (core/sort/SortQueries.kt:130)
- [x] Artists by Recently added: the newest addedAt of any of their songs (chosen), name key, id (core/sort/SortQueries.kt:126)
- [x] Artist headings only for Name (core/sort/SortQueries.kt:136)
- [x] Orders by plays: the library comes in the title (or name) order, then only items that were played are sorted by listening; never played items keep their base order (core/sort/Listening.kt:16)
- [x] Most played counts an item as played when plays > 0; Recently played when lastPlayedAt > 0 (core/sort/Listening.kt:27)
- [x] Most played compares plays then last played time; Recently played compares last played time then plays; the sort is stable so ties keep their base order (core/sort/Listening.kt:33)
- [x] Descending puts played items first then never played; ascending puts never played first then played (core/sort/Listening.kt:41)
- [x] Orders by plays have no letter headings and no letter rail (sort/SortedLibrary.kt:50)
- [x] Plays are the phone's plays plus the server's, less the plays Octo itself sent to the server (core/sort/Listening.kt:3)
- [x] Album listening: sum of its songs' plays and the latest play of any of them, also the server's album history last played time (sort/PlayedListening.kt:15)
- [x] Artist listening: sum of plays and latest play of songs grouped by artistId (sort/PlayedListening.kt:34)
- [x] Sort keys: lower case with accents removed (NFD then drop non-spacing marks), trimmed; a leading "the ", "a " or "an " is dropped when something follows, so "The Beatles" sorts under B (core/catalog/Keys.kt:20)
- [x] Short lists sorted in memory: one key the chosen way with missing keys last either way, then ties always the same way (core/sort/ShortLists.kt:9)
- [x] Playlists by Recently changed: updatedAt, ties by name key then id; Recently created: createdAt, same ties; Song count: songCount, same ties; Name: name key, ties by id (sort/ShortListRows.kt:12)
- [x] Downloads: rows still on their way stay at the top in the database order (Downloading, then Queued (waiting), then Failed, each newest asked first then by title); only finished rows are sorted by the chosen order (sort/ShortListRows.kt:25)
- [x] Downloads by Title: title key, ties by track id; by Size: size bytes, ties title key then track id; by Recently downloaded: addedAt, same ties (sort/ShortListRows.kt:30)
- [x] Folder songs by Title: title key, ties song artist key, id; Artist: song's own artist key (not album artist), ties album key then album order; Album: album key, ties artist key then album order; Recently added: addedAt, ties album order; Year: year, ties album key then album order; Length: duration, ties title key then id; Folder order: as listed, or that list reversed for descending (sort/ShortListRows.kt:39)
- [x] Favourites by Name: album title sort key or artist name sort key, ties by id; by Date added: when it became a favourite, ties by name then id (core/sort/ShortLists.kt:32)

### 2.6 New order behaviour

- [x] When a list shows up in a new order and it is scrolled at or past its first list row (`top`), it jumps straight to that row; a page scrolled only within its header stays put; this happens as the new rows are placed so the old position never shows for a frame (ui/common/Sorting.kt:363)
- [x] Rows move lightly into their new places when the order changes (item placement animation) (ui/common/Sorting.kt:398)

## 3. Letter headings and letter rail

- [x] A list ordered by name (Songs by Title, Artist or Album; Artists by Name) shows its rows in runs under sticky letter headings (ui/library/LibraryScreen.kt:362)
- [x] Letter for a row: the first character of its heading key, upper-cased, when it is A to Z; anything else (numbers, other scripts, empty) files under "#" (core/ui/common/Letters.kt:41)
- [x] Runs: consecutive rows with the same letter form one run; a letter can come back (numbers at the top and other scripts at the end both file under "#"), and each stretch gets its own heading (core/ui/common/Letters.kt:13)
- [x] Letter heading: a small dark pill, not a full-width band: caption Bold, TextMuted, centred, black at 55% alpha in a circle shape, minimum 26 by 26dp, padding 8 horizontal 4 vertical, inside a row padded 16 horizontal 4 vertical; it sticks to the top while its rows scroll (ui/common/Sorting.kt:414)
- [x] The rail appears only when the list is ordered by name and holds at least 60 items (RAIL_MIN_ITEMS) (ui/common/Sorting.kt:431)
- [x] Rail stops: one per distinct letter in order of first appearance; a letter that comes back jumps to its first run; in a list with headings each stop's index counts the heading rows before it (index = run start + run number); in the album grid (no headings) the index is the run start (core/ui/common/Letters.kt:32)
- [x] The rail is 24dp wide along the right edge, as tall as the list area less 8dp top and 132dp bottom padding (clear of the floating bar); only the rail strip takes touches (ui/library/LibraryScreen.kt:350)
- [x] Each letter gets an equal share of the rail height; letters are caption at 10sp Bold, TextMuted, the touched letter TextPrimary (ui/common/Sorting.kt:482)
- [x] Touching or dragging: letter index = (y / rail height x number of stops), clamped; on each change of letter a light haptic tick (text handle move) and the list jumps to that stop with no animation (ui/common/Sorting.kt:459) (iPhone: the system's selection haptic on each change of letter)
- [x] While touched, a 64dp floating glass bubble shows the letter large (OctoType.title) to the left of the rail (24 + 16dp from the right edge), vertically centred on the touched letter's slot (ui/common/Sorting.kt:493) (iPhone: a Liquid Glass bubble)
- [x] Bubble appears with a fade and scale from 0.85 over 120ms, leaves with fade and scale to 0.85 over 180ms, keeping the last letter while it fades (ui/common/Sorting.kt:494)
- [x] Rail accessibility: "Letters. Drag to jump through the list." (ui/common/Sorting.kt:480)

## 4. Play controls

- [x] PlayRow (detail pages): a top line with details text on the left (caption, TextMuted, up to 2 lines, ellipsis) or a lead control, and any quieter controls (extras, for example the heart) on the right, 8dp apart; then Play and Shuffle across the full width 10dp below (ui/common/PlayControls.kt:63)
- [x] PlayRow hides Play and Shuffle when not playable (ui/common/PlayControls.kt:88)
- [x] PlayShuffle: two glass capsules of equal width, 12dp apart; Play has the lifted glaze, Shuffle the resting glaze (ui/common/PlayControls.kt:97)
- [x] Each capsule: 46dp tall drawn inside a 48dp touch target; white icon 22dp and the word in OctoType.body TextPrimary, 8dp apart; pressed it scales to 0.96 with a spring (damping 0.45, stiffness 600) and wears the lifted glaze; no ripple (ui/common/PlayControls.kt:115) (iPhone: Liquid Glass's own press on the capsules)
- [x] Disabled capsules are drawn at 40% alpha; while loading the Play capsule shows a white 18dp spinner (stroke 2dp) in place of the icon, keeps its word, stays at full alpha, and both capsules are disabled (ui/common/PlayControls.kt:130)
- [x] PlayPills (library list pages): Play as a small glass pill with icon 18dp and "Play" (label Medium), padding start 11 end 15, 34dp tall in a 48dp target, lifted glaze, press scale 0.94; Shuffle as a round 34dp glass icon button beside it, 4dp apart (ui/common/PlayControls.kt:164)
- [x] GlassIconButton: 34dp round glass in a 48dp target, white icon 17dp, lit glaze while `lit` or pressed, press scale 0.94; a new icon cross-fades over 160ms (ui/common/PlayControls.kt:209) (iPhone: Liquid Glass, lit while lit or pressed)
- [x] QuietIconAction: a plain white icon at 80% alpha, 22dp, in a 48dp circle target, no glass (ui/common/PlayControls.kt:251)
- [x] QuietAction: icon 18dp and word (OctoType.label), TextSecondary, 6dp apart, padding 10 horizontal 12 vertical, circle clip, no border or fill; disabled at 60% alpha; as a switch (`checked`) it is a toggle and turns TextPrimary while on (ui/common/PlayControls.kt:274)
- [x] QuietActions row: padded 10dp each side so the actions' words line up with the page's 20dp edge (ui/common/PlayControls.kt:305)
- [x] QuietButton: a small text button, OctoType.label, TextSecondary, one line, padding 10 horizontal 6 vertical, circle clip, no fill (ui/common/QuietButton.kt:18)

## 5. Song row anatomy

- [x] A song row is at least 56dp tall (taller for large text), padding 20dp horizontal and 4dp vertical, content vertically centred, 12dp between parts (ui/common/Items.kt:362)
- [x] Lead variants: artwork (default), track number, or a rank number then artwork (ui/common/Items.kt:208)
- [x] Artwork lead: 44dp, corner radius 6dp, on a BackgroundTertiary tile until the picture arrives (ui/common/Items.kt:414)
- [x] Number lead: a 28dp column, end aligned, the track number in caption TextMuted, empty when there is no number (ui/common/Items.kt:433)
- [x] Ranked lead: the rank in caption TextMuted end aligned in 20dp, then the artwork, 10dp apart (ui/common/Items.kt:423)
- [x] Picked row (while selecting): the artwork gets a 44dp black 50% shade with the Select icon 22dp in TextPrimary; the number lead shows the Select icon instead of the number (ui/common/Items.kt:416)
- [x] Now playing row (by track id, or the library song a find became): the artwork gets the shade with animated now-playing bars 16dp (moving only while playing); the number lead shows the bars at 14dp instead of the number; picked wins over now playing (ui/common/Items.kt:415)
- [x] Title: OctoType.bodySmall TextPrimary, one line, ellipsis, with the explicit "E" mark after it when the song is marked explicit; a long title is cut before the mark so the mark always shows (ui/common/SongTitle.kt:20)
- [x] Highlighted row (an album's main song): a filled star icon 14dp in Accent before the title, 6dp gap, accessibility "Most popular" (ui/common/Items.kt:453)
- [x] Subtitle line under the title: caption TextMuted, one line, ellipsis; omitted when null or empty (ui/common/Items.kt:467)
- [x] Default subtitle: "Artist • Album" (bullet with spaces), leaving out empty parts (ui/common/Items.kt:222)
- [x] For a song found online (a "find") whose album title equals its own title (trimmed, case-insensitive), the album is left out of the subtitle (ui/common/Items.kt:218)
- [x] After the text, 6dp apart: the source mark, then the length (ui/common/Items.kt:471)
- [x] Source mark: a filled down arrow 14dp TextMuted ("Downloaded") for a song downloaded to the phone; a cloud 14dp TextMuted ("Streams from your server") for a library song not on the phone; nothing for a phone file or a find (ui/common/Marks.kt:48)
- [x] Length: caption TextMuted with tabular figures, in a column at least as wide as "00:00" measured in that style, end aligned; nothing (but the space kept) when the length is under 1 second (ui/common/SongLength.kt:45)
- [x] For a find, the length shown is the length the player learned for it when known, else its listed length (floored at 0) (discovery/FindLengths.kt:12)
- [x] Row end: the add button (40dp, plus 22dp) for a find in a list that offers adding; an empty 40dp space for a library song in such a list (so lengths line up) unless the row has its own trailing control or the list turns that off; otherwise the trailing control if any (drag handle, row button) (ui/common/NotInLibrary.kt:144)
- [x] Ownership column (albums mixing library songs and finds): a 32dp column right after the number: an Accent check 20dp ("In your library") for a library song, the add button (32dp, plus 20dp) for a find (ui/common/Items.kt:232)
- [x] A find not in the library, in a list that does not offer the add button, carries the small not-in-library mark on its artwork (ui/common/NotInLibrary.kt:126)
- [x] Not-in-library mark: a small glass disc with a thin plus (white 90%), black 42% film under it, size one eighth of the artwork clamped to 12 to 20dp, inset from bottom right by 4% of the art (at least 3dp); on round art placed along the diagonal so the disc stays inside the circle; plus is 68% of the disc (ui/common/NotInLibrary.kt:171)
- [x] Artwork of something not in the library adds "Not in your library" to its accessibility description (or ", not in your library" after an existing description) (ui/common/NotInLibrary.kt:151)
- [x] With no connection, a row whose song cannot play (not on the phone, not downloaded, not saved whole from an earlier play) is drawn at 40% alpha (ui/common/Marks.kt:30)
- [x] When a find shown in a row is taken into the library: in a row offering the add button the check is held 1,200ms first, then the row cross-fades over 300ms into the library song (same place and height); elsewhere it turns at once; a row that opens on a find already adopted shows the library song straight away; with reduced motion the swap is instant (ui/common/FindSwap.kt:16)
- [x] Once turned, the row's swipe, menu and what plays are the library song's (ui/common/Items.kt:284)

## 6. Song row interactions

- [x] Tap: plays (each page decides what list plays from where); while the list is selecting, a tap toggles the row's pick instead (ui/common/Items.kt:340)
- [x] Press and hold: the row gives a little (scale 0.985 over 170ms there and back) and springs back (design/Buttons.kt:101)
- [x] Long press: a long-press haptic, then the song menu opens for the row's song with the page's menu context plus the list's selection and the row's key; the long press label for accessibility is "More options" (ui/common/Items.kt:341) (iPhone: a long press opens the system context menu with the system's haptic; VoiceOver offers the menu from the row)
- [x] The menu opens beside the row near where it was held: a pressed thing narrower than half the window anchors the menu to its bounds; a wide row is narrowed to the finger's x, keeping the row's top and bottom (ui/common/PressSpot.kt:29) (iPhone: the system context menu lifts the held row in place and opens beside it)
- [x] A press counts as the opener only for 2,000ms; a menu opened later appears centred (ui/common/PressSpot.kt:46) (iPhone: the system context menu always opens from the row held)
- [x] Swipe right (start to end) on a row puts its song next in the queue, on lists where a swipe does nothing else; a "Confirm" haptic, the row springs back; a feedback line "Playing next" with "Undo" that takes that one song back out (ui/common/Items.kt:497) (iPhone: the system's leading swipe action "Play next"; a full swipe runs it)
- [x] Behind a row being swiped right: Accent at 22% alpha in the row shape (radius 12dp), the Play next icon 22dp and "Play next" (bodySmall) at the start, padding 24dp, 10dp apart; the row itself gets the page Background while moving and is clear at rest (ui/common/ListEdits.kt:52) (iPhone: the swipe action shows the accent with the Play next symbol and its words)
- [x] No swiping while the list is selecting (ui/common/Items.kt:293)
- [x] Swipe left is not enabled on plain song rows (ui/common/Items.kt:503)
- [x] Accessibility custom actions on every song row: "Play next" (same as the swipe, with its Undo line) and "Add to queue" (no line) (ui/common/Items.kt:349)
- [x] While selecting, each row reports its selected state to accessibility (ui/common/Items.kt:348)
- [x] A picked row sits in the selected pill: AccentSelected fill with a light inner top edge and dark bottom edge, inset 8dp horizontally and 2dp vertically, radius 12dp (ui/common/Items.kt:330)

## 7. Cards and other rows

- [x] Album card: square artwork filling the card width (corner radius 8dp), 8dp gap, title (bodySmall SemiBold, TextPrimary, one line, ellipsis), artist (caption TextMuted, one line); no outline (ui/common/Items.kt:117)
- [x] Album card width is 150dp in horizontal rows; in grids it fills its cell (ui/common/Items.kt:104)
- [x] Album card tap opens the album page; long press (with haptic and squeeze) opens the album's collection menu (ui/common/Items.kt:106) (iPhone: a long press opens the system context menu)
- [x] An album card for an album found online carries the not-in-library mark and, when the library has some of its songs, a third line "<owned> of <songs> in your library" (only when owned is between 1 and songs - 1); no menu on long press (ui/common/Items.kt:113)
- [x] Song card (rows of songs): 150dp wide, square artwork, title with explicit mark, then artist and the source mark 4dp apart; faint when out of reach; tap plays; long press opens the song menu (ui/common/Items.kt:165)
- [x] Artist row: at least 64dp, padding 20 horizontal 4 vertical, 48dp round artwork, name (bodySmall, one line) and "N albums" (caption TextMuted), 12dp apart; tap opens the artist; long press opens the artist's collection menu; squeeze on press (ui/common/Items.kt:522)
- [x] Artist circle (rows of artists): 96dp wide column, 96dp round artwork, 8dp gap, name in caption TextPrimary centred, one line; library artist long press opens its menu; server-only artist shows the not-in-library mark and has no menu (ui/common/Items.kt:545)
- [x] Playlist line: at least 72dp, padding 20 horizontal 4 vertical, 14dp apart: a 56dp picture, the name (bodySmall, one line, ellipsis), and an optional subtitle (caption TextMuted, one line) followed by a 14dp cloud mark "On your server" when the playlist is kept on the server (ui/playlist/PlaylistParts.kt:89)
- [x] Playlist line long press (where it has a menu): long-press haptic, then its menu; long-press label "More options"; no squeeze (ui/playlist/PlaylistParts.kt:105) (iPhone: a long press opens the system context menu, with its haptic)
- [x] Artwork component: square or given shape, BackgroundTertiary tile until loaded, cropped to fill; a picture that cannot be had leaves the tile and is not asked again until shown again (ui/common/Artwork.kt:38)
- [x] Artwork 96dp and larger gets a thin rim drawn over the picture; smaller ones do not (ui/common/Artwork.kt:64)
- [x] Mosaic playlist cover: fewer than 4 covers shows the first cover (or the empty tile); 4 covers show a 2 by 2 grid of quarter-size images, always with the rim (ui/playlist/PlaylistParts.kt:56)
- [x] Playlist covers: up to four covers, one per album in song order, skipping songs with no artwork (catalog/Playlists.kt:42)
- [x] Designed playlist art (default style "Designed"; the other style is "Album mosaic"): drawn from the playlist id and name on colours picked from its covers; `line` under the name is "Playlist" (or "Live list" for live lists); the foot line is "1 song" or "N songs" with thousands separators, none at 0 songs; drawn at sizes rounded up to the cover size steps; the last picture stays up while a changed one is drawn; the tile shows the chosen background colour while waiting; rim from 96dp (ui/common/PlaylistArtwork.kt:65)
- [x] A playlist marked by the server as Octo's Review list draws a magnifier glyph instead of words; Duplicates list draws two overlapping squares; a Liked list draws a heart; unknown notice kinds draw the usual cover (core/covers/CoverGlyphs.kt:13)
- [x] Favourite heart (album and artist pages): 44dp target, Like or Liked icon 24dp with a glow when on; white when on, white 60% when off; it beats once (pulse) when added; accessibility "Favorite" with state "In favorites" or "Not in favorites" (ui/common/FavouriteHeart.kt:35)
- [x] Toggling the heart saves on the phone first with the current time, then the server's copy follows (favourites/FavouriteStore.kt:38)

## 8. Feedback lines (short messages)

- [x] One message at a time; a new one replaces the one showing; showing the same words twice still counts as new (ui/common/Feedback.kt:74)
- [x] A line stays 3,500ms, or 6,000ms when it offers an action (ui/common/Feedback.kt:56)
- [x] Drawn as a small glass pill just above the bottom bar (10dp above it), 20dp side margins, at most 520dp wide, at least 48dp tall; text bodySmall Medium, up to 2 lines; optional 18dp icon before the words; the action (for example "Undo") in bodySmall SemiBold as a pill button at the end, padded 14 horizontal 8 vertical; row padding start 16dp with an icon (20dp without), end 6dp with an action (20dp without), 12dp top and bottom (ui/common/Feedback.kt:103)
- [x] It grows in from 0.92 scale and 10dp lower with a spring (damping 0.85, stiffness 500) and leaves over 160ms; with the phone's animations off it only fades over 120ms (ui/common/Feedback.kt:113)
- [x] Tapping a line with no action puts it away; tapping the action runs it and puts the line away (ui/common/Feedback.kt:142)
- [x] Undo lines are "<text>" with action "Undo"; done lines carry a check icon (ui/common/Feedback.kt:83)
- [x] The line is a polite live region for screen readers and sits above every sheet and menu (ui/common/Feedback.kt:140)

## 9. Empty library note and ways to get music in

- [x] Empty library lists show "Nothing here yet" (bodySmall TextMuted) with the source actions under it, 16dp apart, padding 20dp (ui/common/LibraryReach.kt:102)
- [x] Source actions: a glaze button "Allow access" while the phone's music is not allowed (or "Open settings" when the system will no longer ask), and "Sign in to a server" while no server is set up (only where pages can be opened); nothing when neither applies; the buttons flow and wrap 12dp apart (ui/common/LibraryReach.kt:86)
- [x] "Allow access" asks the system for music permission; after a second refusal ("denied forever") the button opens the app's system settings page instead (ui/common/LibraryReach.kt:63) (iPhone: asks for access to the Music library; once refused the button opens Octo's page in Settings)
- [x] "Signed out" is false while the saved sign-in is still being read, so the sign-in button does not flash (ui/common/LibraryReach.kt:56) (iPhone: the saved sign-in is read as the app starts, before any page shows, so the button never flashes)

## 10. Multi-select and the selection bar

- [x] Lists that can pick songs: Songs, album page, genre page, folder songs, Liked songs, playlist page (ui/common/Selection.kt:95)
- [x] Lists that cannot pick: artist page (its Songs and Top songs), History, Library health pages, Downloads (ui/artist/ArtistScreen.kt:255)
- [x] Selecting starts only from a song menu's "Select", which picks that one row (ui/menu/SongMenuPopup.kt:241)
- [x] A row's key is the song id, except on a playlist page where it is the playlist row id, since a song can be there twice (ui/common/Selection.kt:19)
- [x] While selecting, a tap toggles a row; taking the last one off ends selecting (ui/common/Selection.kt:23)
- [x] When the list changes, picks no longer in it are dropped (for example a song just removed) (ui/common/Selection.kt:30)
- [x] Leaving the list clears its selection (ui/common/Selection.kt:107)
- [x] Picked songs act in the list's own order, not the order they were picked (ui/common/Selection.kt:33)
- [x] The selection bar shows while any list is selecting, drawn over the bottom bar and under every menu; it enters with a fade and slides up from half its height, and leaves the same way, keeping the last list drawn while it goes (ui/common/SelectionBar.kt:94)
- [x] System Back while selecting clears the selection instead of leaving the page (ui/common/SelectionBar.kt:95)
- [x] Bar look: floating glass, radius 28dp, navigation bar padding, then 20dp side and 14dp bottom margins, at most 520dp wide, inner padding 6dp (ui/common/SelectionBar.kt:137)
- [x] Bar top row: a 44dp close button "Stop selecting"; the count "1 selected" or "N selected" (bodySmall TextPrimary, polite live region, 4dp start padding); then, when every picked song has a file on the phone, a 44dp "Share file" (one song) or "Share files" button (ui/common/SelectionBar.kt:148)
- [x] Bar delete button, top row: when every picked song is on the phone and every picked song is deletable from the server's disk, one "Delete" button that asks with a choice titled "Delete" offering "Delete from phone" and "Delete from disk" (ui/common/SelectionBar.kt:161) (iPhone: one Delete button opening a system menu titled "Delete" with both choices)
- [x] Only on the phone: a "Delete from phone" button that acts at once (the system or Octo then confirms) (ui/common/SelectionBar.kt:171) (iPhone: Octo asks first, since the system has no delete confirmation of its own)
- [x] Only deletable from disk: a "Delete from disk" button that opens the disk delete question (ui/common/SelectionBar.kt:172)
- [x] Deletable from disk means: the server lets this user remove files, every picked song is a library song (no finds), and the server has a copy of every one (ui/common/SelectionBar.kt:125)
- [x] A song counts as on the phone for sharing and deleting only when it is a library song with a phone file (finds never) (ui/common/SelectionBar.kt:122)
- [x] Bar bottom row, equal-width 44dp buttons in this order: "Play", "Play next", "Add to queue", "Add to playlist", "Download", the like button, and on a playlist page "Remove from this playlist" (ui/common/SelectionBar.kt:175)
- [x] Bar buttons are icons only (22dp), named for screen readers; a button that cannot act is tinted TextMuted at 35% and disabled (ui/common/SelectionBar.kt:201)
- [x] "Play" plays the picked songs from the first, in list order, finds included (ui/common/SelectionBar.kt:70)
- [x] "Play next" and "Add to queue" put every picked song next or at the end, finds included (ui/common/SelectionBar.kt:71)
- [x] "Add to playlist" opens the playlist picker with the library songs picked (finds left out); disabled when no library song is picked (ui/common/SelectionBar.kt:180) (iPhone: the playlists on a system sheet)
- [x] "Download" downloads the picked library songs that are only on a server; enabled only when at least one picked song is a library song not on the phone (ui/common/SelectionBar.kt:183)
- [x] Like button: when every picked library song is liked it shows the Liked icon and "Remove from Liked songs" and unlikes them all; otherwise the Like icon and "Add to Liked songs" and likes those not liked yet; disabled with no library song picked (ui/common/SelectionBar.kt:184)
- [x] "Remove from this playlist" takes the picked rows out of the page's playlist, with one Undo for all (ui/common/SelectionBar.kt:190)
- [x] Every bar action ends the selecting once done (ui/common/SelectionBar.kt:132)
- [x] Disk delete question for picked songs: title "Delete this song from disk?" (one) or "Delete N songs from disk?" (thousands separators), body from the shared words naming the one title or "N songs", buttons "Delete" and "Cancel"; it goes to the server in use when it was asked; switching server cancels the open question (ui/menu/DiskDelete.kt:30) (iPhone: a system alert; switching server dismisses it)
- [x] Disk delete body: "This takes <names> off the server's disk and out of your library. The server keeps the file in its trash <for N days | for 1 day | until someone clears it>, so you can put it back from Library health. Octo will not download it again by itself." (core/health/FixWords.kt:19)

## 11. Glass menus and pop-ups (song menu, collection menu, playlist pop-up, choice lists)

- [x] A pop-up is a glass card radius 20dp, darker film (black 52%), frosted harder than the bar, with a halo and inner hairline (design/GlassPopup.kt:112) (iPhone: system menus, context menus, alerts and sheets in Apple's own glass)
- [x] It opens beside what opened it: under it with a 6dp gap when it fits, over it when only that fits, otherwise on the roomier side pushed back inside; lined up with the control's start edge, or its end edge when the control's centre is on the far half of the screen; centred on screen when nothing opened it (design/GlassPopup.kt:72) (iPhone: the system places each menu beside what opened it)
- [x] It keeps 12dp clear of every edge and of the system bars and keyboard; at most 340dp wide and 60% of the screen tall (Library health sheets 80%), the content scrolling within (design/GlassPopup.kt:114) (iPhone: the system keeps menus inside the screen and scrolls long ones)
- [x] Once it chose above or below, it stays on that side while it still fits there, so growing to its next page does not jump (design/GlassPopup.kt:101) (iPhone: system menus keep their side)
- [x] It grows from the corner nearest the control (scale 0.92 to 1 and fade over 160ms); with reduced motion it only fades (design/GlassPopup.kt:201) (iPhone: the system menu's own opening, which follows Reduce Motion)
- [x] A tap anywhere off the card closes it; Back first goes back a page when the pop-up has one, and closes only from its first page (design/GlassPopup.kt:189) (iPhone: a tap outside closes a system menu; a sub-menu goes back first)
- [x] It stays above the keyboard by itself, moving over the control when there is no room under it (design/GlassPopup.kt:197) (iPhone: system menus and alerts stay clear of the keyboard)
- [x] Menus are pages: a new page slides in from the side it is going (a third of its width) with a fade and the card eases to its height; back slides the other way; with reduced motion pages only fade and the card resizes at once (design/PopupPages.kt:94) (iPhone: pages open as the system's nested sub-menus)
- [x] Each opening starts at the first page, even when it is the same menu again (design/PopupPages.kt:49) (iPhone: a system menu always opens at its top)
- [x] Menu width is 288dp so pages line up as it turns (ui/common/GlassMenu.kt:70) (iPhone: the system menu's own width)
- [x] Menu page: 6dp padding; its header stays put and the body scrolls when too tall (ui/common/GlassMenu.kt:162) (iPhone: the system menu scrolls its rows while the context menu's preview stays)
- [x] Menu header for a song or collection: picture 40dp, then the name (bodySmall SemiBold, up to 2 lines, ellipsis) and a line under it (caption TextMuted, one line), 12dp apart, padding 10 horizontal, 6 top, 8 bottom; then a separator (ui/common/GlassMenu.kt:255) (iPhone: the context menu's preview shows the song or collection itself)
- [x] Menu rows: at least 40dp, padding 14 horizontal 8 vertical, 14dp gap: white icon 20dp, the label (bodySmall TextPrimary), optional detail under it (caption TextMuted); disabled rows dim icon and label to TextMuted; destructive labels in the Destructive colour with the icon still white; rows that open a page end with an 18dp chevron in TextMuted (ui/common/GlassMenu.kt:202) (iPhone: system menu rows: an SF Symbol, the label, the destructive role in red, sub-menus with their chevron)
- [x] A row under the finger shows a quiet accent-tinted pill (radius 14dp) at once in place of a ripple (ui/common/GlassMenu.kt:218) (iPhone: the system menu's own highlight under the finger)
- [x] Groups of rows are parted by a hairline (TextPrimary 8%, 1dp, 14dp horizontal inset, 4dp vertical padding); no hairline inside a group; empty groups are left out (ui/common/GlassMenu.kt:177) (iPhone: groups as menu sections parted by the system's separators; empty groups left out)
- [x] Back row on a sub page: a small back chevron 18dp white and the page name (OctoType.label, one line, a heading for accessibility), padding start 6 end 14, click label "Back", then a separator (ui/common/GlassMenu.kt:280) (iPhone: a sub-menu's own back row with its title)
- [x] Heading for a page with nothing to go back to: OctoType.label TextPrimary, up to 2 lines, padding 14 horizontal, 10 top, 6 bottom (ui/common/GlassMenu.kt:310) (iPhone: a section title in the menu)
- [x] Note line in a menu: caption TextMuted (or a given colour), padding 14 horizontal 8 vertical (ui/common/GlassMenu.kt:323) (iPhone: a note as a text row of the menu)
- [x] Choice lists: a quiet title (label, TextSecondary, padding 14 start and end, 10 top, 6 bottom) then the answers; 220 to 320dp wide, sized to the widest answer; padding 6dp; answers scroll when taller than allowed; the title is also the pane title (ui/common/ChoiceSheet.kt:163) (iPhone: choices as a system menu titled by its section)
- [x] Choice answers: radio rows when one is current (current one in the selected pill with a white check 18dp, the others keep 18dp of space for it); plain action rows when none is current (selected -1); a disabled answer is dimmed with its detail saying why; picking any answer runs it and closes (ui/common/GlassMenu.kt:119) (iPhone: system pickers tick the current answer, plain buttons otherwise; picking runs it and closes)
- [x] A control that asks a question marks itself so the answers pop up beside it, but only if the question is shown within 2,000ms of the press (ui/common/ChoiceSheet.kt:80) (iPhone: the answers open as a system menu on the control itself)
- [x] Question pop-up: 288dp wide, padding 20 horizontal 18 vertical: the question (OctoType.body TextPrimary, up to 3 lines, a heading), an optional detail (bodySmall TextMuted, 6dp below), anything extra, then an accent confirm button and a glaze "Cancel" button, 10dp apart, 18dp below (ui/common/PopupForms.kt:52) (iPhone: a system alert with the question, its detail, the confirm button and Cancel)
- [x] Name form pop-up: a back row (when opened from another page) or a heading, then a glass text field and an accent action button beside it, 8dp apart, padding 8 horizontal, 6 top, 10 bottom; the keyboard opens as it appears; sentence capitalisation; the keyboard's Done acts only when the name will do; the button is disabled until the name is not blank (ui/common/PopupForms.kt:87) (iPhone: a system alert with a text field: sentence capitals, the action disabled until the name is not blank)
- [x] A pop-up keeps showing its last content while it fades away after closing (ui/common/PopupForms.kt:39) (iPhone: system menus and alerts fade out as they were)

## 12. Library front page

- [x] Title "Library" (ScreenTitle) at the top of one scrolling column with the standard content padding; no back button (ui/library/LibraryScreen.kt:143)
- [x] Section rows in this order: "Playlists", "Favorites", "Artists", "Albums", "Songs", "Genres", "Folders", "Downloads", "History", "Library health" (ui/library/LibraryScreen.kt:116)
- [x] Section icons: Playlists icon, Like (heart outline) for Favorites, Artist, Album, Songs, Genres, Folder, Downloaded, History, Check for Library health (ui/library/LibraryScreen.kt:117)
- [x] Section row: 52dp tall, padding 20dp horizontal, 16dp gap: icon 24dp in Accent, label OctoType.body TextPrimary filling, optional detail (caption TextMuted), chevron 22dp in TextMuted; the whole row is a button (ui/library/LibraryScreen.kt:185)
- [x] Hairline between section rows (not above the first): 1dp TextPrimary at 8%, starting 60dp in (under the labels) and ending 20dp from the right (ui/library/LibraryScreen.kt:204)
- [x] "Favorites" opens the Favorites page with no segment asked for (it picks its own) (ui/library/LibraryScreen.kt:118)
- [x] "History" opens History on Recently played (ui/library/LibraryScreen.kt:126)
- [x] When the signed-in server keeps a log of its downloads, an extra row "Server downloads" (Cloud icon) follows Library health, with the detail "N on the way" while any download is not finished; tapping it opens the server downloads sheet (ui/library/LibraryScreen.kt:153) (iPhone: it opens the server downloads system sheet)
- [x] When any albums exist: a "Recently added" section title with 24dp extra top padding, then the 20 newest albums by date added, two cards to a row (ui/library/LibraryScreen.kt:165)
- [x] Recently added rows: padding 20dp horizontal 9dp vertical, 14dp between the two cards, each card half the width; an odd last album keeps half width (ui/library/LibraryScreen.kt:167)
- [x] Recently added order: album addedAt newest first, limit 20 (catalog/CatalogDao.kt:14)
- [x] The page has pull to refresh (ui/library/LibraryScreen.kt:141)

## 13. Library list pages (Albums, Artists, Songs): shared frame

- [x] Each list page: pull to refresh, then a collapsing header over the list: 56dp top gap, the title with its sort button (and Songs' search button) on the same line, then the page's buttons; the floating back button over it (ui/library/LibraryScreen.kt:378)
- [x] Collapsing header: scrolling the list down first slides the header up out of view (its height given up before the list moves); the header comes back only when the list is pulled down from its top; the header is clipped while sliding (ui/library/LibraryScreen.kt:406) (iPhone: the header scrolls with the list and comes back at the list's top, the page's name showing small at the top meanwhile)
- [x] The play line under the title: the count on the left ("%,d album(s)", "%,d artist(s)", "%,d song(s)", with thousands separators), caption TextMuted one line ellipsis; then room for one quieter action; then the small Play pill and Shuffle button; padded start 20, end 13, bottom 6 so the glass lines up with the sort capsule; 6dp gaps (ui/library/LibraryScreen.kt:471)
- [x] The play line shows only once the list is read and has something in it (ui/library/LibraryScreen.kt:478)
- [x] Before the first read: a centred spinner (Accent, 28dp); a loading moment is never shown as empty (ui/library/LibraryScreen.kt:505)
- [x] An empty list shows the empty library note with "Allow access" / "Sign in to a server" where they apply (ui/library/LibraryScreen.kt:509)
- [x] Lists of rows run edge to edge with 4dp top and 140dp bottom padding (room for the floating bar); grids keep 20dp side margins (ui/library/LibraryScreen.kt:346)

## 14. Albums list page

- [x] Title "Albums" with the Albums sort button (ui/library/LibraryScreen.kt:218)
- [x] Play line: "N albums", then a quiet "Random album" button, then Play and Shuffle (ui/library/LibraryScreen.kt:221)
- [x] "Random album" opens one album picked at random from the list shown (ui/library/LibraryViewModel.kt:111)
- [x] Grid: adaptive columns at least 150dp wide, 14dp between columns, 18dp between rows, padding 20 start and end, 4 top, 140 bottom; album cards fill their cells and move into place on a new order (ui/library/LibraryScreen.kt:229)
- [x] The grid has no letter headings; with a by-name order (Title or Artist) and 60 or more albums it gets the letter rail, whose stops are grid positions (ui/library/LibraryScreen.kt:240)
- [x] Play plays every album in the order shown, each album's songs in album order, from the first (ui/library/LibraryViewModel.kt:91)
- [x] Shuffle plays every song in the library shuffled (not only the albums in view) (ui/library/LibraryViewModel.kt:105)
- [x] Album songs order used for playing groups: within an album, albumOrder (catalog/CatalogDao.kt:92)
- [x] Playing a whole list of albums or artists sets no queue source name (ui/library/LibraryViewModel.kt:106)

## 15. Artists list page

- [x] Title "Artists" with the Artists sort button (ui/library/LibraryScreen.kt:254)
- [x] Play line: "N artists" and Play and Shuffle (ui/library/LibraryScreen.kt:256)
- [x] Rows are artist rows; by Name they sit under letter headings with the rail at 60 or more (ui/library/LibraryScreen.kt:258)
- [x] Play plays every artist in the order shown, artist by artist; each artist's songs album by album, newest album first (year descending, missing year as 0), then album sort key, album id, album order (ui/library/LibraryViewModel.kt:98)
- [x] Shuffle plays every song in the library shuffled (ui/library/LibraryViewModel.kt:105)

## 16. Songs list page, search and filters

- [x] Title "Songs"; at the end of the title line a search button (round glass, 2dp before the sort button) then the Songs sort button (ui/library/LibraryScreen.kt:288)
- [x] The search button shows only when the library has songs (ui/library/LibraryScreen.kt:290)
- [x] Search button: Search icon and label "Search these songs" while closed; Close icon and label "Close the search" while searching, lit; the icon cross-fades (ui/library/LibraryScreen.kt:291)
- [x] Searching is on while the panel is open or any filter is set (so a page coming back with filters keeps the panel open) (ui/library/LibraryScreen.kt:276)
- [x] Opening search by its button puts the keyboard up on the field one frame after it is laid out; coming back to a page with a search already in it does not raise the keyboard (ui/library/SongFilterRow.kt:69)
- [x] Closing search (its button or system Back) clears focus, closes the panel and clears the words and every chip (sort and limit kept) (ui/library/LibraryScreen.kt:281)
- [x] Back closes the search before it leaves the page (ui/library/LibraryScreen.kt:287)
- [x] The search panel grows open from the top on a soft spring (damping 0.9, medium-low stiffness), its contents drifting down from a fifth of its height (damping 0.85) and fading in over 220ms after 60ms; closing folds it up quicker (spring damping 1, medium stiffness) with a 120ms fade; with reduced motion it only fades in 120ms and out 100ms (ui/library/LibraryScreen.kt:447) (iPhone: the panel slides down and fades in on a spring as the list makes room; with Reduce Motion it only fades)
- [x] Panel layout: padding 2 top, 10 bottom; the field padded 20dp horizontally; the chip row 12dp under it, 20dp content padding, chips 8dp apart, scrolling sideways (ui/library/SongFilterRow.kt:95)
- [x] Search field: glass input with placeholder "Search songs", keyboard action Search which only hides the keyboard (filtering is live as you type) (ui/library/SongFilterRow.kt:96)
- [x] While the field has words, a 40dp clear button with a Close icon 20dp TextMuted, accessibility "Clear the words", empties the words only (ui/library/SongFilterRow.kt:103)
- [x] Typed words: split on spaces, tabs and new lines; each word folded (lower case, accents removed); a song matches when every word appears inside its title, artist, album, album artist or any genre (ui/library/SongFilterRow.kt:98, core/query/QueryMatching.kt:43)
- [x] Chip row order: "Clear all" (only while any filter is set), "Save as live list" (only while any filter is set), the seven quick chips, the Rating chip, the Genre chip, the Year chip (ui/library/SongFilterRow.kt:111)
- [x] Quick chips and their words: "Favorites" (liked songs), "Added in the last week" (7 days), "Added in the last month" (30 days), "Added in the last year" (365 days), "Never played", "Not played in the last 6 months" (180 days), "Lossless" (core/query/FilterPresets.kt:18)
- [x] A quick chip toggles: on adds it, replacing any other filter on the same field (picking "Added in the last month" replaces "Added in the last week"); on again takes it off (ui/library/SongFilterRow.kt:79)
- [x] Chip look: at least 36dp tall, circle, padding 14 horizontal 8 vertical, OctoType.label one line; on: AccentSelected fill with TextPrimary words; off: TextPrimary at 7% fill with TextSecondary words; no border; a checkbox role with selected state (ui/library/SongFilterRow.kt:129)
- [x] Rating chip off reads "Rating" and asks a choice titled "Rating": "5 stars", "4 stars or more", "3 stars or more", "2 stars or more", "1 star or more"; picking sets rating at least that many (ui/library/SongFilterRow.kt:85) (iPhone: a system menu titled "Rating" opening on the chip)
- [x] Genre chip shows only when the songs have any genre (or a genre filter is on); off it reads "Genre" and asks a choice titled "Genre" listing each genre once (case and accents folded, first spelling kept), sorted naturally A to Z (ui/library/SongFilterRow.kt:115) (iPhone: a system menu titled "Genre" opening on the chip)
- [x] Year chip shows only when the songs have any year (or a year filter is on); off it reads "Year" and asks a choice titled "Year" listing decades newest first as "The 2020s", "The 2010s" (ui/library/SongFilterRow.kt:118) (iPhone: a system menu titled "Year" opening on the chip)
- [x] An asking chip that is on reads as its filter ("Rating at least 4", "Genre is Electronic", "From the 1990s") in the on look; a tap takes the filter off without asking (ui/library/SongFilterRow.kt:81)
- [x] Genre and decade choices come from the whole song list, not the filtered one (ui/library/LibraryViewModel.kt:71)
- [x] The answers pop up beside the chip that asked (ui/library/SongFilterRow.kt:114) (iPhone: the system menu opens on the chip)
- [x] "Clear all" removes the words and every chip (ui/library/SongFilterRow.kt:111)
- [x] "Save as live list" opens the new live list editor started from these filters: the rules, the words trimmed, this list's current order (or newest added first when none) (ui/library/LibraryScreen.kt:314)
- [x] Filters are for this visit only (gone when the page's view model is cleared) (ui/library/LibraryViewModel.kt:61)
- [x] Filtering keeps the chosen order and keeps the letter headings in step with the songs left (sort/TrackQuery.kt:64)
- [x] With filters, the count on the play line reads "<shown> of <all> songs" with thousands separators ("song" when all is 1), for example "120 of 2,835 songs" (ui/library/LibraryScreen.kt:342)
- [x] When the filters leave nothing: "No songs match these filters" (bodySmall TextMuted) and a quiet "Clear filters" button under it (12dp apart, padding 20dp) that clears words and chips; the play line hides (ui/library/SongFilterRow.kt:160)
- [x] While the filtered list is being worked out (after the full list is read), a centred spinner (ui/library/LibraryScreen.kt:326)
- [x] Rows: song rows (artwork lead, "Artist • Album"), under letter headings for Title, Artist and Album orders, rail at 60 or more (ui/library/LibraryScreen.kt:333)
- [x] Tap plays the list as shown (filtered and ordered) from that song, queue source "Songs" (ui/library/LibraryViewModel.kt:114)
- [x] Play plays the shown list from the first; Shuffle plays it shuffled; source "Songs" (ui/library/LibraryViewModel.kt:84)
- [x] The list is selectable (multi-select from the menu) (ui/library/LibraryScreen.kt:332)
- [x] Filter fields on the phone: added date is the song's added time (stored in seconds, read as milliseconds; 0 counts as none); last played and plays come from the merged phone and server listening; favourite means liked; lossless when the MIME type is a lossless type or its format is a lossless format; rating 1 to 5 (0 none); album artist, composer, bit rate and BPM are never known on the phone so filters on them match nothing (sort/TrackQuery.kt:15)
- [x] Lossless MIME types: audio/flac, audio/x-flac, audio/alac, audio/wav, audio/x-wav, audio/wave, audio/vnd.wave, audio/aiff, audio/x-aiff, audio/ape, audio/x-ape, audio/wavpack, audio/x-wavpack (playback/Copies.kt:82)
- [x] Format from MIME: the part after the slash, lower case, without parameters or an "x-" prefix; mpeg, mp3, mpeg3 read as mp3; mp4, m4a as m4a; aac-adts as aac; wave, vnd.wave as wav; aif as aiff; wavpack as wv (sort/TrackQuery.kt:47)
- [x] Lossless formats: flac, alac, wav, wave, aiff, aif, aifc, pcm, ape, wv, dsf, dff, tta; m4a and mp4 are lossless only with a known bit depth (core/query/SongFields.kt:47)
- [x] Date rules: "in the last N days" means at or after now minus N days; "not in the last N days" includes songs never played or with no date; "never" means no date (core/query/QueryMatching.kt:121)
- [x] Number rules: rating and plays are 0 when none; a missing year or length passes only "is not" (core/query/QueryMatching.kt:96)

## 17. Album page

- [x] The page sets its cover as the page glow artwork behind it while open (ui/album/AlbumScreen.kt:235)
- [x] One scrolling column with the standard padding plus the 56dp detail gap, pull to refresh, the floating back button; the whole song list is selectable (ui/album/AlbumScreen.kt:241)
- [x] Header: cover 240dp, corner radius 10dp, with a three-layer drop shadow (elevation 3), centred (ui/album/AlbumScreen.kt:387) (iPhone: one soft drop shadow)
- [x] 20dp under the cover: the album title (OctoType.title, TextPrimary, centred, wraps) (ui/album/AlbumScreen.kt:389)
- [x] Under the title, 4dp: the album artist (OctoType.body) in Accent and tappable to the artist page (ui/album/AlbumScreen.kt:390)
- [x] 14dp under: the play line: details on the left, the favourite heart at the right, then Play and Shuffle (ui/album/AlbumScreen.kt:398)
- [x] Details: year (when known), then "N songs", then the length in words, joined with " • " (ui/album/AlbumScreen.kt:250)
- [x] When the page lists songs found online among the library's, the count and the length are those of the songs listed; otherwise the album's own song count and duration (ui/album/AlbumScreen.kt:252)
- [x] Under the buttons, a quiet actions row: "Share" (Share icon) when the signed-in server can make shared links and has this album; it opens the share pop-up for the server's album named after the album title (ui/album/AlbumShare.kt:29) (iPhone: Share opens a system menu headed "Share "<title>"" with the link's expiry choices)
- [x] In the same row: the album download action when some of the album's library songs are only on a server: "Download album" (Download icon) while any of them is not downloaded or queued, "Downloading" (Downloading icon) while some are queued but not done, "Downloaded" (Downloaded icon) when all are done; enabled only in the first state; it downloads every server-only song (ui/album/AlbumDownload.kt:26)
- [x] When the server says the album has songs the library lacks (finds), a second quiet row: the add action, the "Only my songs" switch, and a note (ui/album/AlbumScreen.kt:266)
- [x] Add action words: "Add the missing song" (one not asked for yet) or "Add the N missing songs"; once every missing song is asked for and some are still coming: "Adding, show downloads" when the server keeps a downloads list (tap opens that sheet on its list), otherwise "Adding" disabled (ui/album/AlbumScreen.kt:345)
- [x] Add missing asks the server to add every find on the album not asked for yet (ui/album/AlbumScreen.kt:174)
- [x] "Only my songs" (Library icon) is a switch that hides the finds on this page only, for while it is open; it is not offered when the "Library songs only" setting already hides them everywhere (ui/album/AlbumScreen.kt:273)
- [x] Note at the end of the row, end aligned, caption TextMuted one line: "<in library> of <songs> in your library", only when some but not all songs are in the library (ui/common/NotInLibrary.kt:160)
- [x] About line under the header, centred, 16dp apart, padding 20 sides and 12 bottom: the album genre in Accent caption (tap opens that genre's page, click label "Open genre"), and the average rating: a filled star 12dp TextMuted and "<stars> average" in caption TextMuted (ui/album/AlbumExtras.kt:71)
- [x] Album genre: the genre most of its library songs have, compared case-insensitively, the first to appear winning a tie, written as first seen; none when no song has one (ui/album/AlbumExtras.kt:43)
- [x] Average rating: the mean of ratings 1 to 5 of its library songs, unrated songs left out; shown to one place with a whole number's ".0" dropped ("4.3", "4"); spoken "Songs rated <stars> star(s) on average" (ui/album/AlbumExtras.kt:53)
- [x] The about line shows only when the genre or the average is known (ui/album/AlbumScreen.kt:284)
- [x] Songs are grouped by disc (no disc number counts as disc 1) in the order discs first appear; with more than one disc each group gets a heading "Disc N" (caption Bold, TextMuted, padding start 20, top 16, bottom 4) (ui/album/AlbumScreen.kt:287)
- [x] Song rows use the track number lead; the subtitle shows the song's artist only when it differs from the album artist, otherwise there is no subtitle (ui/album/AlbumScreen.kt:304)
- [x] When the page lists finds, every row has the ownership column after the number (check for library songs, add button for finds) (ui/album/AlbumScreen.kt:309)
- [x] The album's main song is starred: the album song that comes first in the artist's top 30 songs on the server, matched by id, else by title (features stripped, normalised) and the same artist name; none when no album song is among them or without a server (discovery/AlbumHighlight.kt:23)
- [x] Top songs for the star are kept per server, user and artist for as long as the app runs (discovery/AlbumHighlight.kt:39)
- [x] Song menus opened on this page leave out "Go to album" for this album (ui/album/AlbumScreen.kt:239)
- [x] Tap plays the listed songs from that one; queue source is the album title (ui/album/AlbumScreen.kt:199)
- [x] Play plays the listed songs from the first (ui/album/AlbumScreen.kt:256)
- [x] Shuffle: with finds listed, shuffles the listed songs; otherwise shuffles the album (ui/album/AlbumScreen.kt:202)
- [x] "More by <artist>" at the foot (16dp top padding, section title, then a sideways row of 150dp album cards, 20dp padding, 14dp apart): the artist's other albums, newest year first then by title key, this album left out; hidden when there are none (ui/album/AlbumExtras.kt:103)
- [x] Album songs list: the library's songs in album order; the server is asked once the library songs are known, and its listing (with finds in their album places) becomes the album when it includes finds; a find already adopted shows as its library song; library songs the server did not list follow at the end (discovery/WholeAlbum.kt:28)
- [x] Only songs the server marks as outside the library stay finds, each numbered as the server numbers it (track and disc only when above 0) (discovery/WholeAlbum.kt:13)
- [x] Offline or refused, the library's songs are the album (ui/album/AlbumScreen.kt:165)
- [x] After a song from here arrives in the library, the page waits 1,500ms (the check's moment plus the fade) and asks the server again when finds remain (ui/album/AlbumScreen.kt:156)
- [x] With "Library songs only" on, or "Only my songs" on, finds are left out of the list, the counts, and what plays (ui/album/AlbumScreen.kt:137)
- [x] No spinner or empty state on the album page; the header appears once the album is read (ui/album/AlbumScreen.kt:244)

## 18. Artist page

- [x] The page sets the artist's picture as the page glow artwork (ui/artist/ArtistScreen.kt:248)
- [x] One grid page: adaptive columns at least 150dp, 14dp column and 18dp row spacing, 20dp side margins, standard top (with the 56dp gap) and bottom padding; full-width parts reach past the side margins (ui/artist/ArtistScreen.kt:381)
- [x] Pull to refresh also forgets what the server said about the artist and asks again (ui/artist/ArtistScreen.kt:255)
- [x] Header: a 160dp round picture, 16dp gap, the name (OctoType.title, centred), then "N albums • N songs" (caption TextMuted, 4dp top), bottom padding 8dp (ui/artist/ArtistScreen.kt:444)
- [x] Buttons line: the favourite heart always at the right; Play and Shuffle only when the artist has songs in the library; on the left a quiet "Radio" action (Radio icon) when the artist has library songs, pulled 10dp left so its icon starts at the page edge; padding 20 horizontal, 4 bottom (ui/artist/ArtistScreen.kt:264)
- [x] Play and Shuffle play the artist's library songs in the order of the Songs section; source is the artist name (ui/artist/ArtistScreen.kt:183)
- [x] Radio: seeds are the artist's songs in Songs order (first 200), the most played first; it plays the first seed then up to 50 similar songs in place of the queue, source "<song title> radio"; "No similar songs found" when none (ui/artist/ArtistScreen.kt:192)
- [x] Songs section (when the artist has library songs): title "Songs" with, when there are more than 10, a quiet "See all" button at the right that turns into "Show fewer"; shows the first 10 until expanded; the choice survives configuration changes (ui/artist/ArtistScreen.kt:283)
- [x] Songs order: once any of their songs has been played, the most played first (ties: the one played last first), then the rest album by album (newest album first, then album sort key, album id, album order); before any play, album by album (catalog/Plays.kt:46)
- [x] Songs rows: artwork lead and the album name as subtitle; tap plays all their songs from that one (ui/artist/ArtistScreen.kt:293)
- [x] Songs rows' menus keep "Go to artist" (no artist context passed) (ui/artist/ArtistScreen.kt:293)
- [x] Top songs section (when the server answers with any): title "Top songs", up to 10 songs from the server resolved to library songs where held, finds otherwise (discovery/ArtistExtras.kt:26)
- [x] Top songs rows: subtitle is the album (left out for a find whose album equals its title); their menus leave out "Go to artist"; tap plays the top songs from that one (ui/artist/ArtistScreen.kt:311)
- [x] Top songs offer the add button when any of them is a find; once offered it stays offered while the page is open, so lengths do not shift when the last find turns into a library song (ui/artist/ArtistScreen.kt:305)
- [x] After a top song downloaded from here arrives, the page waits 1,500ms then asks the server again (ui/artist/ArtistScreen.kt:198)
- [x] Album shelves: the artist's albums in the Artist page order; split into shelves "Albums", "Singles and EPs", "Compilations", "Live", "Appears on" by the server's release types, shelves in that order, empty shelves left out; when no album has release types, one shelf "Albums" (core/catalog/ReleaseGroups.kt:34)
- [x] Shelf for a release: compilation (flag or type) first, then "live", then "single" or "ep", anything else an album (core/catalog/ReleaseGroups.kt:19)
- [x] Shelf titles: with several shelves each shelf's name; with one shelf the title "Albums" only when the Songs or Top songs sections are shown, otherwise no title (ui/artist/ArtistScreen.kt:320)
- [x] The first shelf's title line carries the Artist albums sort button when the artist has more than one album (a sort bar with 8dp top padding); other shelf titles are section titles with 8dp top padding (ui/artist/ArtistScreen.kt:325)
- [x] A new album order scrolls back to the albums' first line, counting the header, buttons, Songs and Top songs lines above it (ui/artist/ArtistScreen.kt:252)
- [x] Album cards fill their grid cells and move into place on a new order (ui/artist/ArtistScreen.kt:333)
- [x] "About" section when the server has a biography: section title (8dp top), the text (bodySmall, TextPrimary at 80%) up to 4 lines with an ellipsis, then a bold caption "More" when clipped, which shows the rest (no way to collapse again) (ui/artist/ArtistScreen.kt:417)
- [x] Biography cleanup: the "more" link removed, line breaks kept, tags removed, numbered and named entities decoded, paragraphs separated by one empty line, other runs of space collapsed (core/discovery/Biography.kt:17)
- [x] "Similar artists" section: section title (8dp top) then a sideways row of artist circles (20dp padding, 14dp apart); a library artist opens its library page, any other opens as the server has it and shows the not-in-library mark; the artist itself is left out; each once (ui/artist/ArtistScreen.kt:363)
- [x] With "Library songs only" on, top songs show only library songs and similar artists only library artists (discovery/ArtistExtras.kt:45)
- [x] Without a server, or when it cannot be reached, the extras are absent (no Top songs, About or Similar artists); a failed read is asked again on the next visit (discovery/ArtistExtras.kt:84)
- [x] What the server said about an artist is kept per server and user for as long as the app runs (discovery/ArtistExtras.kt:59)

## 19. Playlists page

- [x] One scrolling list with the standard padding plus the 56dp detail gap, pull to refresh, the floating back button (ui/playlist/PlaylistsScreen.kt:136)
- [x] Title "Playlists" with the Playlists sort button once the list is read (ui/playlist/PlaylistsScreen.kt:139)
- [x] Opening the page asks the server for playlist changes at once (a playlist deleted on another device leaves, one made there comes in) (ui/playlist/PlaylistsScreen.kt:91)
- [x] Lead lines in this order: "New playlist", "New live list", "Import a playlist file", then the import note while there is one (ui/playlist/PlaylistsScreen.kt:107)
- [x] There is no Liked songs line here; hearted songs live on the Favorites page (ui/playlist/PlaylistsScreen.kt:114)
- [x] "New playlist": a playlist line with a 56dp tile (BackgroundTertiary fill, the AddToLibrary plus icon at 40% of the tile in TextPrimary, rim) and no subtitle; opens the new playlist name form with no songs (ui/playlist/PlaylistParts.kt:137) (iPhone: the name is asked in a system alert)
- [x] "New live list": subtitle "Songs picked by rules, always up to date", the live list mark tile; opens the live list editor for a new list (ui/livelists/LiveListParts.kt:54)
- [x] "Import a playlist file": subtitle "M3U or M3U8", a Folder icon tile; opens the system file picker for these types: audio/x-mpegurl, audio/mpegurl, application/x-mpegurl, application/vnd.apple.mpegurl, text/plain, application/octet-stream (ui/playlist/PlaylistImport.kt:27) (iPhone: the Files app's picker, for playlist files, plain text and any file)
- [x] Import note (padding 20 horizontal, 8 vertical, bodySmall TextMuted): "Importing…" while working; "That file couldn't be read." on failure; otherwise the summary (ui/playlist/PlaylistImport.kt:56)
- [x] Import summary: no songs in the file: "\"<name>\" has no songs in it."; none found: "None of the <total> songs in \"<name>\" are in your library."; otherwise "Imported <matched> of <1 song | total songs> into \"<name>\"" (core/ui/playlist/PlaylistAdds.kt:68)
- [x] When some lines were not found, a toggle under the summary (caption TextSecondary, 8dp vertical padding): "Show N not found" / "Hide songs not found", state "Shown" / "Hidden"; open, each missed line in caption TextMuted, up to 2 lines (ui/playlist/PlaylistImport.kt:65)
- [x] The import note lasts until the page closes (ui/playlist/PlaylistsScreen.kt:84)
- [x] Then the live lists, in the order they were made, above the playlists; each a playlist line with subtitle "Live list" and its designed cover (line "Live list") or the live mark tile in mosaic style; tap opens the live list; long press opens the live list options (ui/playlist/PlaylistsScreen.kt:153) (iPhone: a long press opens the live list's options as a system context menu)
- [x] Live list cover colours: the covers of the first albums of the songs it holds now (ui/playlist/PlaylistsScreen.kt:74)
- [x] Then the playlists in the chosen order (the phone's own and the server in use's; another kept server's are hidden until it is in use): playlist line, name, "N songs", cloud mark "On your server" when kept with the server; 56dp cover with the song count as its foot line and the notice glyph; tap opens the playlist; long press opens the playlist's collection menu; rows move into place on a new order (ui/playlist/PlaylistsScreen.kt:156) (iPhone: a long press opens the system context menu)
- [x] No spinner and no empty note: with no playlists only the lead lines show (ui/playlist/PlaylistsScreen.kt:156)

## 20. Playlist page

- [x] No pull to refresh on this page; the floating back button over it (ui/playlist/PlaylistScreen.kt:144)
- [x] When the playlist is deleted (from its menu or elsewhere) the page goes back by itself (ui/playlist/PlaylistScreen.kt:141)
- [x] Header: the cover 240dp, corner radius 10dp, elevation 3 shadow; designed art with the song count foot line and glyph, or the mosaic; centred; padding 20 horizontal, 16 bottom (ui/playlist/PlaylistParts.kt:147) (iPhone: one soft drop shadow)
- [x] 20dp under: the name (OctoType.title, centred) (ui/playlist/PlaylistParts.kt:162)
- [x] 14dp under: the play line: details "0 songs" when empty, otherwise "N songs · <length in words>" (middle dot), and a quiet More button (More icon, label "More") at the right; Play and Shuffle only when it has songs (ui/playlist/PlaylistParts.kt:163)
- [x] More opens the playlist options pop-up: with "Save to server" only when a server is signed in and the playlist is only on the phone; "Download" only when some songs are library songs only on a server (ui/playlist/PlaylistScreen.kt:178) (iPhone: More opens the options as a system menu)
- [x] Under the header: the Keep downloaded line (when it applies) (ui/playlist/PlaylistScreen.kt:191)
- [x] For a playlist kept with the server whose songs include some only on the phone: a centred note (bodySmall TextMuted, padding 32 horizontal 8 vertical): "1 song is only on this phone and is not in the server's copy" or "N songs are only on this phone and are not in the server's copy" (ui/playlist/PlaylistScreen.kt:254)
- [x] Empty playlist note: "This playlist is empty. Long press any song and choose Add to playlist." (ui/playlist/PlaylistScreen.kt:196)
- [x] Song rows: artwork lead, "Artist • Album", a drag handle at the end (two short lines 18 by 8dp, stroke 2dp TextMuted, in a 40dp target, accessibility "Reorder"); the handle is hidden while selecting (ui/common/ListEdits.kt:32) (iPhone: Reorder (Done while reordering) puts the list in edit mode, where each row shows the system's reorder handle; hidden while picking)
- [x] Dragging a row by its handle moves it among the rows at once with a frequent-tick haptic on each step; the dragged row is lifted (elevation 3) on a BackgroundTertiary fill in a 12dp rounded shape (ui/playlist/PlaylistScreen.kt:153) (iPhone: the system list's own drag, lifting the row with its haptic)
- [x] On drop, the song is moved into the place of the song that was at its landing index (no move when it lands where it was); the server's copy follows (ui/playlist/PlaylistScreen.kt:201)
- [x] Swipe a row left to take it out of the playlist at once: behind it a red wash (Error at 25%) in the 12dp row shape with a bin icon 22dp at the end, padding 24dp, accessibility "Remove"; the row gets the Background fill while moving (ui/common/ListEdits.kt:66) (iPhone: the system's trailing swipe action "Remove" in red with the bin symbol; a full swipe takes the row out)
- [x] The swipe is off while dragging or selecting; swipe right does nothing on this page (no play next) (ui/playlist/PlaylistScreen.kt:209)
- [x] Taking a song out says "Removed from <playlist name>" ("the playlist" when the name is unknown) with "Undo", which puts it back in its place (ui/playlist/PlaylistScreen.kt:101)
- [x] Tap plays the playlist from that song; source is the playlist name (ui/playlist/PlaylistScreen.kt:96)
- [x] Play plays from the first; Shuffle shuffles; source is the playlist name (ui/playlist/PlaylistScreen.kt:98)
- [x] Song menus opened here offer "Remove from this playlist" for that row (ui/playlist/PlaylistScreen.kt:236)
- [x] Rows are picked by their playlist row; the selection bar's "Remove from this playlist" removes the picked rows at once with "Removed from <name>" (one) or "Removed N songs from <name>" and one "Undo" that puts them all back, each in its place (ui/playlist/PlaylistScreen.kt:109)
- [x] Changes to a playlist kept with the server are sent there (playback/PlaylistStore.kt:23)

## 21. Keep downloaded line (playlist page and Liked songs)

- [x] Shown only when some songs are library songs only on a server, or the switch is already on (ui/playlist/KeepDownloaded.kt:73)
- [x] Row padding 20 horizontal 6 vertical: "Keep downloaded" (bodySmall TextPrimary) over a caption line, and a switch at the end (ui/playlist/KeepDownloaded.kt:75) (iPhone: the system switch in the accent)
- [x] Caption while off: "Download the songs only on your server, and keep them in step" (ui/playlist/KeepDownloaded.kt:82)
- [x] Caption while on: "Every song is already on this phone" when none is server-only; "All N downloaded" when every server-only song is done; otherwise "<done> of <server-only> downloaded" (ui/playlist/KeepDownloaded.kt:47)
- [x] On, the server-only songs download and the downloads follow the playlist (or Liked songs) as songs come and go; the Liked songs switch is the same as the one in Offline settings (ui/playlist/KeepDownloaded.kt:53)

## 22. Playlist pop-up (options, create, rename, delete, live list options)

- [x] The playlist pop-up opens beside what opened it; its pane title is "Playlist"; closing it puts the keyboard away (ui/playlist/PlaylistSheets.kt:242) (iPhone: the playlist's choices are system menus and alerts, which put the keyboard away as they close)
- [x] Asking for another playlist page while it is open opens that page as the next page with a way back; asking while closed starts fresh (ui/playlist/PlaylistSheets.kt:127) (iPhone: each page opens as its own system alert or menu)
- [x] New playlist form: name form titled "New playlist", placeholder "Playlist name", button "Create"; the name is trimmed; with songs given, it says "Added to <name>" (one) or "Added N songs to <name>" (no Undo) and the playlist becomes the most recent one added to (ui/playlist/PlaylistSheets.kt:267) (iPhone: a system alert with the name field)
- [x] Options page: heading is the playlist name; rows: "Rename" (opens page), "Save to server" (Cloud icon, when allowed; closes), "Download" (when allowed; downloads every song of the playlist only on a server; closes), "Export as M3U" (Share icon), "Delete" (destructive, opens page) (ui/playlist/PlaylistSheets.kt:271) (iPhone: a system menu headed by the playlist's name)
- [x] Export as M3U closes the pop-up and opens the system "create file" picker with type audio/x-mpegurl and the name "<playlist name>.m3u" with characters file systems refuse replaced by spaces ("Playlist.m3u" when nothing is left); a failed write says "Could not export the playlist" (ui/playlist/PlaylistSheets.kt:285) (iPhone: the Files app's save picker)
- [x] Rename page: name form "Rename playlist", "Playlist name", "Save", starting with the current name; saves the trimmed name and closes (ui/playlist/PlaylistSheets.kt:298) (iPhone: a system alert with the name field)
- [x] Delete page: question "Delete \"<name>\"?" with "It is deleted from your server too. The songs stay in your library." for a playlist kept with the server, or "The songs stay in your library." otherwise; buttons "Delete" and "Cancel" (Cancel goes back a page, or closes when it is the first page) (ui/playlist/PlaylistSheets.kt:471) (iPhone: a system alert; Cancel closes it)
- [x] Live list options (long press on a live list line): heading is its name; rows: "Edit rules" (Filter icon; closes and opens the live list editor, closing the player too), "Rename" (opens page), "Duplicate" (closes; says "Made a copy: <copy name>"), "Save a copy as a playlist" (Playlists icon; closes), "Delete" (destructive, opens page) (ui/playlist/PlaylistSheets.kt:306) (iPhone: a system context menu headed by the live list's name)
- [x] Save a copy as a playlist: a playlist named as the live list with the songs it holds now (it does not follow the rules); says "Saved a copy of <name> as a playlist, 1 song" or "..., N songs" (thousands separators); when it holds nothing: "\"<name>\" has no songs right now, so there is nothing to copy." (ui/playlist/PlaylistSheets.kt:214)
- [x] Live list rename: "Rename live list", "Live list name", "Save" (ui/playlist/PlaylistSheets.kt:330) (iPhone: a system alert with the name field)
- [x] Live list delete: "Delete \"<name>\"?" with "The songs stay in your library." (ui/playlist/PlaylistSheets.kt:334) (iPhone: a system alert)

## 23. Add to playlist picker

- [x] Title: "Add to playlist" for one song, otherwise "Add N songs to a playlist"; as a back row when opened from a menu page, otherwise a heading (ui/playlist/PlaylistSheets.kt:391) (iPhone: "Add to playlist" opens a sub-menu; for picked songs a sheet titled "Add to playlist" or "Add N songs to a playlist")
- [x] First row "New playlist" (AddToLibrary plus icon); tapping turns it in place into a name field ("Playlist name", "Create") which makes the playlist with the songs (each once), says "Added to <name>" or "Added N songs to <name>", and closes (ui/playlist/PlaylistSheets.kt:395) (iPhone: "New playlist" asks the name in a system alert, then makes the playlist with the songs)
- [x] Then every playlist shown with this server, the three added to most recently first (newest first), the rest in the store's order (ui/playlist/PlaylistSheets.kt:359)
- [x] Each playlist row: at least 52dp, radius 14dp, padding 10 horizontal 6 vertical, 12dp gap: 36dp cover (radius 6dp, glyph), the name (bodySmall, one line), "N songs" with the cloud mark "On your server" when kept with the server (ui/playlist/PlaylistSheets.kt:422) (iPhone: each playlist as a menu row with its symbol, name and "N songs"; on the sheet with its cover and the cloud)
- [x] Picking a playlist: songs are taken once each in the order given; if none is on it already, they are added at the end and the pop-up closes, saying "Added to <name>" or "Added N songs to <name>" (N = rows actually added) with "Undo", which takes those rows back out (ui/playlist/PlaylistSheets.kt:186)
- [x] If some are on it already, it asks first (ui/playlist/PlaylistSheets.kt:413)
- [x] The question: one song: "Already in <name>. Add again?"; all already there: "These songs are already in <name>. Add them again?"; one of several: "1 of these songs is already in <name>."; several: "N of these songs are already in <name>." (core/ui/playlist/PlaylistAdds.kt:26)
- [x] With several songs and some new ones: the question with an accent "Add new ones" (adds only the new ones) and a glaze "Add all" (adds every song again); there is no Cancel button (tap outside or Back) (ui/playlist/PlaylistSheets.kt:450) (iPhone: a system alert with "Add new ones" and "Add all"; it keeps the system's Cancel)
- [x] Otherwise: a question pop-up with confirm "Add" (one song) or "Add again" (several, all there) and "Cancel", which returns to the list (ui/playlist/PlaylistSheets.kt:459) (iPhone: a system alert with "Add" or "Add again" and "Cancel")
- [x] Adding remembers the playlist as the most recent one added to; only the last three are remembered (core/ui/playlist/PlaylistAdds.kt:49)
- [x] Found-online songs never go into a playlist (only library songs are added) (playback/PlaylistStore.kt:74)
- [x] Starting at a given playlist ("Add to last playlist"): shows "Checking the playlist" until it knows which songs that playlist has, then adds at once or asks the same question (ui/playlist/PlaylistSheets.kt:369) (iPhone: the playlist is checked in the background, then the songs go on at once or the question opens)
- [x] From a collection menu, the picker shows "Gathering the songs" until the collection's songs are read (ui/menu/CollectionMenuPopup.kt:75) (iPhone: the collection's songs are gathered once a playlist is picked)

## 24. Genres page

- [x] Title "Genres" (no sort), standard padding plus the 56dp gap, pull to refresh, back button (ui/genre/GenresScreen.kt:56)
- [x] Before the first read nothing is shown under the title (no spinner) (ui/genre/GenresScreen.kt:59)
- [x] No genres: "None of your songs has a genre yet" (bodySmall TextMuted, 20dp horizontal padding) (ui/genre/GenresScreen.kt:61)
- [x] Genres are the songs' genres grouped case-insensitively, A to Z case-insensitively, empty genres left out; each with its song count and the first artwork by value among its songs (catalog/CatalogDao.kt:103)
- [x] Genre row: 64dp tall, padding 20 horizontal, 12dp gap: artwork 48dp radius 6dp, name (bodySmall, one line), "N songs" (caption TextMuted); tap opens the genre (ui/genre/GenresScreen.kt:81)

## 25. Genre page

- [x] No pull to refresh on this page; back button over it (ui/genre/GenreScreen.kt:110)
- [x] Header: the genre name (OctoType.title, centred), then a play line "N albums • N songs" with Play and Shuffle across; padding 20 horizontal, 20 bottom (ui/genre/GenreScreen.kt:149)
- [x] Albums: every album with a song in the genre (matched case-insensitively), by album title key, as a grid inside the list: as many 150dp minimum columns as fit in the width less 40dp (14dp gaps), every card the same width, a short last row padded with empty cells; rows padded 20 horizontal, 18 bottom (ui/genre/GenreScreen.kt:113)
- [x] Then a sort bar "Songs" with the Genre songs sort button (only when there are songs), then every song of the genre in that order (ui/genre/GenreScreen.kt:135)
- [x] A new song order scrolls back to the Songs line (after the header and the album rows) (ui/genre/GenreScreen.kt:117)
- [x] Song rows: artwork lead, "Artist • Album", tap plays the genre's songs from that one; source is the genre name; Play from the first; Shuffle shuffled (ui/genre/GenreScreen.kt:79)
- [x] Songs are selectable (ui/genre/GenreScreen.kt:119)
- [x] Genre song rows have no letter headings or rail (ui/genre/GenreScreen.kt:139)

## 26. Folders page

- [x] Until both sources are known (the phone's first scan since start, and whether a server is signed in): a centred spinner (ui/folders/FoldersScreen.kt:81)
- [x] Neither the phone has music nor a server is signed in: title "Folders" and the empty library note "Folders show here once there is music on this phone or a server is signed in." with its buttons (ui/folders/FoldersScreen.kt:84)
- [x] With both: the page starts at "Folders" listing both sources; with one, it starts inside it (ui/folders/FoldersViewModel.kt:54)
- [x] Top level: section title "On this phone" and a folder row named for the phone's top with "N songs"; then (16dp top) section title "On <server name>" and a folder row named the server with "Browse the server by folder" (ui/folders/FoldersScreen.kt:134)
- [x] The phone's top is collapsed: folders holding only one other folder and no songs are skipped down, so a library kept inside "Music" starts at "Music"; its name is the last folder skipped into, or "This phone" when nothing was skipped (folders/FolderTree.kt:62)
- [x] Server name: "Octo" for an Octo server, else the server type with its first letter upper-cased, else the host (folders/ServerFolders.kt:79)
- [x] Phone folders: from each phone song's path; folders sorted by name the way people count ("Disc 2" before "Disc 10", case only breaking ties); a folder's own songs album by album (album lower-cased, album id, album order, title key) (folders/FolderTree.kt:33)
- [x] Header on every level: the folder's name as the big title; with any depth, a path line under it: names joined by " / " in caption, the current one TextPrimary, the others TextSecondary and tappable to go back there; it scrolls sideways when long and starts scrolled to its end; padding 20 horizontal, 12 bottom (ui/folders/FoldersScreen.kt:235)
- [x] Place names: the top "Folders"; a phone folder its own name (the phone's top as above); a server folder its name, "Untitled folder" when blank (ui/folders/FoldersScreen.kt:127)
- [x] Phone level: a play line with details "1 folder" or "N folders" (only when it has folders) and "N songs", joined with " • ", Play and Shuffle disabled when no songs; they play every song under the folder: each subfolder in turn, then the folder's own songs, in the tree's own order (ui/folders/FoldersScreen.kt:151)
- [x] Then its subfolders, each a folder row with "N songs" under the name, hairlines between (starting 60dp in) (ui/folders/FoldersScreen.kt:169)
- [x] A phone folder that has gone since (the phone's music changed): "This folder is no longer on the phone." (ui/folders/FoldersScreen.kt:155)
- [x] Server level: Play and Shuffle with no details; they gather every song under the folder (each subfolder in turn, then its songs), at most 2,000 songs and at most 400 folders opened, a folder seen twice opened once (folders/FolderSongs.kt:15)
- [x] While gathering, Play shows its spinner and both buttons are disabled; a second tap is ignored (ui/folders/FoldersViewModel.kt:189)
- [x] Notes under the buttons (caption TextMuted, 10dp top): "Sign in to your server to play this." (no server), "No songs in this folder.", "Playing the first 2,000 songs in this folder." (number in the phone's locale) when the limit was reached, or the server error message; any note clears when moving to another folder (ui/folders/FoldersViewModel.kt:196)
- [x] Server level loading: a spinner with 32dp padding; failure: the message (bodySmall TextMuted) and a glaze "Try again" button, 12dp apart; no server: "Sign in to your server to see this."; empty: "Nothing in this folder." (ui/folders/FoldersScreen.kt:193)
- [x] Server subfolders: folder rows with no subtitle, hairlines between; listed twice by a server they still show twice (ui/folders/FoldersScreen.kt:211)
- [x] Server levels read so far are kept, so going back up shows them at once; each is read the first time it is shown; pull to refresh reads every one read so far again (ui/folders/FoldersViewModel.kt:163)
- [x] Folder row: 56dp, padding 20 horizontal, 16dp gap: Folder icon 24dp in Accent, the name (bodySmall, one line) and optional subtitle (caption TextMuted), chevron 22dp TextMuted (ui/folders/FoldersScreen.kt:284)
- [x] A folder's own songs: a sort bar "Songs" (12dp top) with the Folder songs sort, then song rows; tap plays this folder's songs in the shown order from that one (ui/folders/FoldersScreen.kt:225)
- [x] Server folder songs are the library's songs when held (so the phone's copy plays), finds otherwise (folders/ServerFolders.kt:47)
- [x] Each folder opens at its top (a fresh list per folder); a new song order scrolls back to the Songs line (ui/folders/FoldersScreen.kt:101)
- [x] Folder songs are selectable (ui/folders/FoldersScreen.kt:105)
- [x] System Back goes up one folder while not at the start; the floating back button goes up one folder, or leaves the page at the start (ui/folders/FoldersScreen.kt:75)
- [x] When the start changes (for example the server was signed out), the folders gone into are dropped (ui/folders/FoldersViewModel.kt:124)

## 27. Favorites page (liked songs, favourite albums, favourite artists)

- [x] Title "Favorites" (TitleWithSort) under the 56dp gap and status bar padding; pull to refresh; back button (ui/favourites/FavouritesScreen.kt:174)
- [x] The sort button follows the segment: Songs uses the Liked songs order; Albums and Artists share the Favourites order; no sort button until a segment is chosen (ui/favourites/FavouritesScreen.kt:176)
- [x] A segmented control "Songs", "Albums", "Artists" (one glaze, the chosen one in a gliding pill, its words in Accent, the others TextPrimary), padding 20 horizontal, 12 bottom (ui/favourites/FavouritesScreen.kt:186) (iPhone: the system segmented control)
- [x] Which segment opens: the one asked for by the way in (Liked songs opens Songs; the Favourite albums shelf opens Albums), otherwise, once all three lists are read, Songs when there are liked songs, else Albums when any, else Artists when any, else Songs; then it is kept while the page is open and through configuration changes, so the page never jumps (ui/favourites/FavouriteSegments.kt:18)
- [x] Until the segment is chosen: a centred spinner (ui/favourites/FavouritesScreen.kt:183)
- [x] Songs segment: a play line "N songs" with Play and Shuffle (only when there are liked songs), padding 20 sides 12 bottom; then the Keep downloaded line for Liked songs; then the songs in the Liked order (ui/favourites/FavouritesScreen.kt:226)
- [x] No liked songs: "No liked songs yet. Tap the heart in the player to add the song that is playing, or long press any song and choose Add to Liked songs." (ui/favourites/FavouritesScreen.kt:143)
- [x] Liked songs scope: only liked songs, joined by their like row (core/sort/SortQueries.kt:78)
- [x] Liked song rows: swipe left unlikes at once (red wash and bin behind), saying "Removed from Liked songs" with "Undo", which likes it again with its original time so it returns to its place; swipe right does nothing here; swipes off while selecting (ui/favourites/FavouritesScreen.kt:241)
- [x] Liked song tap plays the liked songs from that one; source "Favorites"; Play from the first; Shuffle shuffled (ui/favourites/FavouritesScreen.kt:115)
- [x] Liked songs are selectable (ui/favourites/FavouritesScreen.kt:223)
- [x] A new liked order scrolls back to the first song (after the play line and the keep line) (ui/favourites/FavouritesScreen.kt:140)
- [x] Liked songs list has no letter headings or rail (ui/favourites/FavouritesScreen.kt:240)
- [x] Albums segment: a grid of album cards (adaptive 150dp columns, 14 and 18dp gaps, padding 20 sides, 4 top, 140 bottom) in the Favourites order; none: "Heart an album from its page or its menu to keep it here." (ui/favourites/FavouritesScreen.kt:267)
- [x] Artists segment: artist rows in the Favourites order; none: "Heart an artist from their page or their menu to keep them here." (ui/favourites/FavouritesScreen.kt:286)
- [x] Albums and Artists segments have no Play buttons (ui/favourites/FavouritesScreen.kt:267)
- [x] Empty notes are bodySmall TextMuted with 20 horizontal 8 vertical padding; each segment shows a spinner until its list is read (ui/favourites/FavouritesScreen.kt:300)

## 28. History page

- [x] Title "History" under the 56dp gap; no pull to refresh; back button (ui/history/HistoryScreen.kt:116)
- [x] Segmented control "Recently played" / "Most played", padding 20 horizontal; opens on Most played when the way in asks for it, else Recently played; the choice survives configuration changes (ui/history/HistoryScreen.kt:122) (iPhone: the system segmented control)
- [x] Recently played: up to the latest 500 plays, newest first, under a heading per day (section title with 8dp extra top); until read a spinner; none: "Nothing played yet" (bodySmall TextMuted, padding 20 horizontal 24 vertical) (ui/history/HistoryScreen.kt:137)
- [x] Day headings: "Today", "Yesterday", the weekday name for the rest of the past week, then "MMMM d" this year, "MMMM d, yyyy" for other years, in the phone's locale (core/listening/PlayDays.kt:35)
- [x] Recently played rows: subtitle "<artist> • <start time>" (the phone's short time format), artwork lead (ui/history/HistoryScreen.kt:152)
- [x] Recently played merges the phone's plays with the server's record: the server adds each song's last play anywhere unless it is one of the phone's own plays sent there (within the song's length plus 1 second), and leaves out server plays older than the oldest phone play loaded when 500 were loaded (listening/History.kt:31)
- [x] Tap plays every song listed, each song once where it first shows, from the first showing of the tapped song; source "History" (ui/history/HistoryScreen.kt:108)
- [x] Most played: a quiet range button at the right (label TextSecondary with a down chevron 14dp, padding 10 horizontal 6 vertical, 8dp top, click label "Change the time range", spoken "Most played, <range>") (ui/history/HistoryScreen.kt:201) (iPhone: a system menu button, its words with the down chevron)
- [x] Ranges: "Last 4 weeks" (28 days, the default each time the page opens), "Last 6 months" (by the calendar), "All time"; picking from a choice titled "Most played in" with the current one ticked (ui/history/HistoryScreen.kt:170) (iPhone: a system menu titled "Most played in" with the current range ticked)
- [x] Most played list: up to 100 songs, most plays first, then the one played last, then by id (listening/History.kt:76)
- [x] All time adds the server's play counts (less plays Octo sent there); within a range a song played elsewhere counts one more play when the server's last play falls in the range and is not the phone's own (listening/History.kt:93)
- [x] Most played rows: subtitle "<artist> • 1 play" or "<artist> • N plays" (ui/history/HistoryScreen.kt:188)
- [x] Most played none: "Nothing played yet" for All time, else "Nothing played in the last 4 weeks" or "Nothing played in the last 6 months" (ui/history/HistoryScreen.kt:183)
- [x] History lists are not selectable and have no letter headings (ui/history/HistoryScreen.kt:147)

## 29. Downloads page (songs downloaded to the phone)

- [x] Title "Downloads" under the 56dp gap; the sort button only when there are downloads; no pull to refresh; back button (ui/offline/DownloadsScreen.kt:151)
- [x] Shows the downloads of the server in use only (offline/OfflineDownloads.kt:133)
- [x] Summary line (when any): "<N songs> · <size>" of the finished downloads (caption TextMuted), then a glaze "Remove all" button (12dp top); padding 20 horizontal, 12 bottom (ui/offline/DownloadsScreen.kt:204)
- [x] "Remove all" asks once more in place: "Remove every download from this phone? Liked songs and playlists stop being kept downloaded too." (bodySmall TextSecondary, 10dp top) with an accent "Remove all" and a glaze "Cancel" (12dp apart); confirming removes every download and switches off every keep-downloaded rule (ui/offline/DownloadsScreen.kt:213)
- [x] Empty: "Songs you download play without a connection. Long press a song and choose Download, or keep a playlist downloaded from its page." (ui/offline/DownloadsScreen.kt:167)
- [x] Row: 60dp, padding 20 horizontal, 12dp gap: artwork 44dp radius 6, title with explicit mark (bodySmall), then "<artist> · <detail>" (caption, one line; TextSecondary when failed, TextMuted otherwise) (ui/offline/DownloadsScreen.kt:266)
- [x] Detail: "Waiting" (queued), "Downloading, N%" (rounded), "Could not download. Tap to try again" (failed), or for a finished one "<size>" plus " · Kept with Liked songs" / " · Kept with <playlist name>" / " · Kept with a playlist" when a rule keeps it and it was not asked for by hand (ui/offline/DownloadsScreen.kt:119)
- [x] Size words here: from 1 GiB "%.1f GB", from 1 MiB "%.1f MB" (binary units, dot decimal), otherwise whole KB rounded up (ui/offline/DownloadsScreen.kt:112)
- [x] A row downloading has a 2dp progress hairline under it (track TextPrimary 8%, fill Accent), starting 76dp in and ending 20dp from the right (ui/offline/DownloadsScreen.kt:284)
- [x] Tap: a failed row tries again; a finished row plays the finished downloads in the order shown from that one; a waiting or downloading row does nothing (ui/offline/DownloadsScreen.kt:186)
- [x] Only downloads asked for by hand can be removed here: swipe left (red wash and bin behind) or long press (with haptic) removes it at once, saying "Download removed" with "Undo" while its file can still come back; one also kept by a rule only loses its by-hand reason; one kept only by a rule goes when the rule is switched off (ui/offline/DownloadsScreen.kt:176) (iPhone: a trailing swipe action, or the long press menu's "Remove download")
- [x] A row kept by a rule springs back from a swipe as it was (ui/offline/DownloadsScreen.kt:178)
- [x] Rows move into place on a new order (ui/offline/DownloadsScreen.kt:184)

## 30. Library health: front page

- [x] Title "Library health" under the 56dp gap; back button; no pull to refresh (ui/library/health/HealthScreens.kt:295)
- [x] The checks run again whenever the library changes, away from the main thread; until the first run a spinner (ui/library/health/HealthScreens.kt:151)
- [x] The server's allowed library actions are refreshed as the page opens (an admin may have changed them) (ui/library/health/HealthScreens.kt:190)
- [x] First line (muted): "Checked N songs." and, when something was found, " One thing could be better." or " N things could be better." (core/health/HealthWords.kt:158)
- [x] Nothing found: "Everything looks right" (OctoType.section, padding 20 sides, 16 top) then "No second copies, no split albums and no missing tags. There is nothing to fix." (ui/library/health/HealthScreens.kt:303)
- [x] One row per check that found something, in this order: "Songs you have twice", "Albums split apart", "Songs with no length", "No track number", "No album artist", "No cover art", "No year", "No genre"; hairlines between (inset 20dp both sides) (core/health/HealthWords.kt:13)
- [x] Row: title (OctoType.body) over the count (caption TextMuted), chevron 22dp at the end; padding 20 horizontal 9 vertical; tap opens that check's page (ui/library/health/HealthScreens.kt:482)
- [x] Counts: "1 song with more than one copy" / "N songs with more than one copy" (sets of copies); "1 album" / "N albums" (split albums); otherwise "1 song" / "N songs" (thousands separators) (core/health/HealthWords.kt:25)
- [x] When the server allows restoring: a 12dp gap then "Recently removed" with "Songs deleted from disk, kept in the server's trash for now"; opens Recently removed (ui/library/health/HealthScreens.kt:314)
- [x] When the last fix or delete can be undone on this server: "Undo the last change" with "Puts back what the last fix or delete changed", no chevron, a hairline above it when Recently removed is shown; tap runs the undo and shows its progress and outcome (ui/library/health/HealthScreens.kt:319)
- [x] Duplicates are looked for among each source's own copies only (a phone file joined with the server's copy is no problem); copies are matched by MusicBrainz recording, then title, artist and length (the phone keeps no ISRC); everything else is checked on the library as shown (ui/library/health/PhoneHealth.kt:23)

## 31. Library health: a check's page

- [x] Title is the check's name; an unknown check shows "This check is not in this version of the app." (muted) (ui/library/health/HealthScreens.kt:347)
- [x] First paragraph: what the finding means (bodySmall TextSecondary, padding 20 horizontal 6 vertical) (core/health/HealthWords.kt:32)
- [x] Second paragraph: what the fix does when a fix-all is offered, otherwise the advice (core/health/HealthWords.kt:52)
- [x] Fix-all button (accent, medium size, padding 20 sides 8 vertical) when the server can fix any of it: "Fix N songs" (twice), "Join N albums" (split), "Find N covers" (no cover), "Find higher quality for N songs" (no length), "Fill in N songs from their albums" (no year, genre, album artist), "Look up N songs" (no track number) (core/health/FixWords.kt:66)
- [x] Fix-all is offered only with the server's permission: duplicates need remove; split albums need join; covers need add cover; no length needs upgrade; year, genre and album artist need edit; track numbers need look up and edit (ui/library/health/HealthFixPlans.kt:52)
- [x] Only songs with a copy on the signed-in server are counted and fixed; duplicates only for sets on that server (ui/library/health/HealthFixPlans.kt:83)
- [x] No lines left: "Nothing to fix here any more." (muted) (ui/library/health/HealthScreens.kt:374)
- [x] Duplicates list: a heading per set ("<title> by <artist>" or the title; under it "<N> copies. <Tagged as the same recording | Same title, artist and length>. <Keep the first, <quality> | They sound alike; the first has fuller tags | They sound alike>.") then its songs, best first, each with "<quality> • <album>" under the title (core/health/HealthWords.kt:79)
- [x] Quality words: format upper-cased, then for lossless "<bits>-bit" and "<rate> kHz" (44.1 kHz, 96 kHz), else "<N> kbps"; "unknown quality" when nothing is known (core/health/HealthWords.kt:139)
- [x] Split albums list: a heading "<title> by <artist>, shown as N albums" with the reasons and differences under it, then every part's songs (core/health/HealthWords.kt:91)
- [x] Headings: title in OctoType.label TextPrimary, detail in caption TextMuted, 2dp apart, padding start 20, end 12, top 20, bottom 4; a row button at the end where it has a fix (ui/library/health/HealthScreens.kt:455)
- [x] Row buttons: a small word button (label, TextSecondary, padding 10 horizontal 8 vertical, circle) with an accessibility label for what it does (ui/library/health/HealthScreens.kt:468)
- [x] Duplicates heading button "Fix" ("Fix this song") when the server can remove and the set is on it; each copy that is not the kept one gets a "Keep" button ("Keep this copy") that opens the same fix keeping that copy (ui/library/health/HealthScreens.kt:380)
- [x] Split album heading button "Join" ("Join this album") when the server can join and has songs to move (ui/library/health/HealthScreens.kt:383)
- [x] Missing-tag checks (not covers) give each song the server has a "Look up" button ("Look up tags") when the server can look up and edit (ui/library/health/HealthScreens.kt:402)
- [x] Song rows play the check's songs (each once) from the tapped one, source "Library health"; long press opens the usual song menu; no swipe-to-select (ui/library/health/HealthScreens.kt:203)
- [x] The fix-all for track numbers looks up at most 25 songs at a time (ui/library/health/HealthFixPlans.kt:28)

## 32. Library health: fix pop-ups

- [x] Pop-ups are 328dp wide, up to 80% of the screen tall, pane title "Library health"; heading (OctoType.body) then a scrolling body then buttons that stay in view (accent confirm then glaze cancel, 10dp apart, 16dp top) (ui/library/health/HealthFixSheets.kt:263) (iPhone: a system sheet, half the screen to begin with, its title in its bar and its buttons kept in view at the bottom)
- [x] One set fix: heading is the set's heading; "Keeps" with the kept copy ("<title> (<quality>), on <album>") and why ("Keeps the <quality> copy, because it sounds best." / "The copies sound alike, so this keeps the one with the fullest tags (<quality>)." / "The copies sound alike and have the same tags, so this keeps the first (<quality>)." / "You picked this copy (<quality>) to keep.") (ui/library/health/HealthFixSheets.kt:123)
- [x] "Moves to the server's trash" lists the others, each with a "Keep" button ("Keep this copy instead") that re-plans the sheet around that copy (ui/library/health/HealthFixSheets.kt:137)
- [x] With edit allowed: "Fills in" lists the kept copy's blank tags another copy can fill, each a ticked checkbox row ("<Tag>: <value>") that can be unticked (ui/library/health/HealthFixSheets.kt:144)
- [x] With edit allowed: "Where the copies disagree" lists each differing tag name (muted) and its values once each as radio rows; the kept copy's value is picked to begin with (ui/library/health/HealthFixSheets.kt:150)
- [x] A note when a removed copy is the only one on its album: "<copy name> is on <album>, so that album will no longer have this song." (core/health/HealthFixes.kt:121)
- [x] Buttons "Fix" and "Cancel"; Fix runs the fills ticked and the picked values, then the removals (ui/library/health/HealthFixSheets.kt:133)
- [x] Fix-all pop-up: the check's name, what the fix does, then one line per set, album or song (at most 100, then "And N more."), buttons "<fix-all label>" and "Cancel" (ui/library/health/HealthFixSheets.kt:174)
- [x] Fix-all lines: duplicates "Keeps <copy name>" over "Removes <names>." plus " Fills in <changes>." when any; split albums the heading over the join words; covers the song title; tags the song title over "<Tag>: <value>" list (ui/library/health/HealthFixPlans.kt:162)
- [x] Join pop-up: the album heading, the join words ("Moves N songs onto <album>, the part with N songs<, since its album artist names every part's artist>." and "Their album artist becomes <artist>." when it changes), buttons "Join" and "Cancel" (ui/library/health/HealthFixSheets.kt:88)
- [x] No-length pop-up: "Songs with no length", the fix meaning, the song titles, buttons "Find higher quality for N songs" and "Cancel"; confirming asks the server and closes (ui/library/health/HealthFixSheets.kt:92)
- [x] Look-up pop-up: title "Look up tags" for one song, else "Looking up N songs"; while running "Looked up X of Y" (live) and a progress bar, with a glaze "Stop" (what was found so far can still be written) (ui/library/health/HealthFixSheets.kt:195) (iPhone: the system progress bar)
- [x] Look-up results: per song (headed by its title when several): the problem, or "Nothing was found for this song." (or the server's own detail), or "<origin> The file says the same already.", or the origin then checkbox rows for each change, ticked or not to begin with by the shared rules (ui/library/health/HealthFixSheets.kt:225)
- [x] Origin words: "A sure match", "A likely match", "A doubtful match" or "Found", then " from the song's fingerprint" / " from MusicBrainz" / " from the catalog" / " from the file's own tags", then ", on <release>" when known, ending with "." (core/health/HealthFixes.kt:216)
- [x] When nothing anywhere would change: "Nothing to change: the tags found say what the files say already, or nothing was found." (ui/library/health/HealthFixSheets.kt:223)
- [x] Look-up buttons when finished: "Write 1 change" / "Write N changes" and "Cancel", or only "Close" when nothing is ticked (ui/library/health/HealthFixSheets.kt:210)
- [x] Running pop-up: "Changing the files", "Starting" until the first answer, then "X of Y done" (live) with a 4dp progress bar (Accent on TextPrimary 10%), the note "Closing this lets it carry on. It says how it went when it is done.", and a glaze "Stop" that stops between two steps (ui/library/health/HealthFixSheets.kt:246) (iPhone: the system progress bar in the accent)
- [x] Done pop-up: "Done" and the outcome (live), with "Undo" and "Close" when the undo can run on the server it went to, else only "Close" (ui/library/health/HealthFixSheets.kt:101)
- [x] Outcome words: a dry-run server says "The server only rehearsed this, because its library actions are in dry run. Nothing changed."; otherwise the parts done ("removed N songs", "changed the tags of N songs", "moved N songs onto their album", "added N covers", "put back N songs", "undid the changes to N songs") joined with commas, first letter capitalised, ending "."; or "Nothing needed changing." / "Nothing was done."; then " Stopped before the end." when stopped, then one failure " <title>: <reason>" or " N songs could not be done, like <title>: <reason>" (core/health/HealthFixes.kt:322)
- [x] Closing a fix or look-up stops a look-up; a run already sent carries on and its outcome pop-up opens when done, if the page is still there (ui/library/health/HealthScreens.kt:214)
- [x] Switching server closes a plan or look-up (they hold the old server's ids) but not a running or done pop-up (ui/library/health/HealthScreens.kt:193)
- [x] Checkbox mark: 20dp, radius 5 (radio: circle); on: Accent fill with a check 14dp in the Background colour; off: 1.5dp TextMuted border; rows at least 44dp, radius 10, 12dp gap (ui/library/health/HealthFixSheets.kt:305) (iPhone: SF Symbols: a checked square, or a checked circle for one of several values, in the accent)
- [x] Outcome special case: putting back one replaced file shows the server's own words for it, or the reason it failed (core/health/HealthFixes.kt:315)
- [x] Look-up change ticks: a tag the file lacks is ticked to be filled; a tag the file has is ticked only when the match is sure and the tag is not the title, artist or album; values equal after trimming are not offered (core/health/HealthFixes.kt:206)
- [x] Tag names in change words: "Title", "Artist", "Album", "Album artist", "Year", "Genre", "Track number", "Disc number", "ISRC"; a change reads "<Tag>: <value>" or "<Tag>: <value>, was <old>" (core/health/HealthFixes.kt:140)
- [x] Fill from album: a missing year or genre is filled when every other song of the album agrees on one value; a missing album artist from the album's agreed album artist or, when none, the one artist every song of the album is by (core/health/HealthFixes.kt:181)

## 33. Library health: Recently removed

- [x] Title "Recently removed" under the 56dp gap; back button (ui/library/health/RecentlyRemoved.kt:134)
- [x] Spinner until the server's trash is read; a failure says "Could not read the server's trash. <message>" (muted) (ui/library/health/RecentlyRemoved.kt:96)
- [x] First line (muted): "The server keeps a song deleted from disk for N days, then deletes it for good." ("1 day") or "The server keeps a song deleted from disk until someone clears its trash." (ui/library/health/RecentlyRemoved.kt:62)
- [x] Empty trash: "Nothing is in the server's trash." (ui/library/health/RecentlyRemoved.kt:143)
- [x] With more than one song and restore allowed: an accent "Put back all" button (medium size, padding 20 sides 8 vertical) (ui/library/health/RecentlyRemoved.kt:144)
- [x] Row: at least 60dp, padding start 20 end 10, 6 vertical: title (OctoType.body), "<artist> • <album>" (caption muted, when any), for a replaced song "Replaced: was <old>, now <new>" (or "Replaced by another copy") in TextSecondary, spoken "Replaced by another copy. Yours was ..., now ...", then the time left (caption muted); a "Put back" row button when allowed ("Put back <title>") (ui/library/health/RecentlyRemoved.kt:162)
- [x] Time left: "Kept until someone clears the trash" (no date), "Deleted for good today" (0 days), "Deleted for good tomorrow" (1), "Deleted for good in N days" (whole days, never below 0), counted from when the page opened (core/health/FixWords.kt:55)
- [x] Putting back removes the songs from the list at once, sends the restore to the server the trash was read from, then reads the trash again (ui/library/health/RecentlyRemoved.kt:113)
- [x] Switching server reads the new server's trash (ui/library/health/RecentlyRemoved.kt:87)

## 34. Song menu: opening and frame

- [x] Any song row, song card, or the player's more button opens the song menu for that song; it floats beside what was pressed, over everything including the player (ui/menu/SongMenu.kt:70) (iPhone: a system context menu on song rows and cards, and the player's More menu)
- [x] Pane title "Song menu"; while the player is open the menu frosts the player, otherwise the page (ui/menu/SongMenuPopup.kt:96) (iPhone: the system context menu dims and blurs what is behind it)
- [x] Each opening starts on the actions page (ui/menu/SongMenu.kt:90) (iPhone: a system menu always opens at its top)
- [x] The menu keeps the last song while it fades away (ui/menu/SongMenu.kt:80) (iPhone: the system menu fades out as it was)
- [x] The song is read live (library song, or a found song shaped like one); nothing shows until it is read (ui/menu/SongMenuPopup.kt:100) (iPhone: the menu builds from the row's song as it opens)
- [x] Header: the song's artwork 40dp radius 6, the title (SemiBold, up to 2 lines) and the artist; then a separator; the header stays while the actions scroll (ui/menu/SongMenuPopup.kt:319) (iPhone: the context menu's preview shows the row itself)
- [x] Context passed from the page: the album id on an album page, the artist id for an artist page's top songs, the playlist id and row id on a playlist page, the list's selection and the row's key (ui/menu/SongMenu.kt:49)
- [x] "Go to album" is left out only on the page of that song's own album; "Go to artist" only for that song's own artist on its page; "Remove from this playlist" only on a playlist row; "Select" only in a list that can pick songs and is not picking already (ui/menu/SongMenu.kt:133)

## 35. Song menu: which actions, in which groups

- [x] Always first: "Play next", "Add to queue"; then "Start radio" (always offered, since the library alone can make one) (ui/menu/SongMenu.kt:169)
- [x] For a song found online: the add action, then "Request a copy" (family members who ask for copies), "Remove from this playlist" (on a playlist row), "Select" (when allowed); then "Song info" and "Find songs" (ui/menu/SongMenu.kt:172)
- [x] For a library song: "Add to last playlist: <name>" (when a playlist was added to lately and still exists), "Add to playlist", "Remove from this playlist", "Select", the download row (when only on a server, or already kept), "Find higher quality" (when the Octo server could replace its lossy copy), "Share file" (phone file), "Share link" (server can share and has a copy), the like row, "Rate", "Go to album", "Go to artist", "Set as ringtone" and "Delete from phone" (phone file), "Remove from my library" (managed family member, song in their own library), "Delete from disk" (server lets this user delete and has a copy); then "Song info" and "Find songs" (ui/menu/SongMenu.kt:177) (iPhone: Set as ringtone is left out, as no app can set system sounds on iPhone)
- [x] "Find songs" is offered when the server can run a song's search again (a server keeping a downloads log) (ui/menu/SongMenuPopup.kt:174)
- [x] Groups top to bottom, hairlines between, empty groups left out: (1) Play next, Add to queue, Start radio; (2) Add to last playlist, Add to playlist, like, Rate, add (find), Request a copy, download, Find higher quality; (3) Go to album, Go to artist; (4) Share link, Share file, Set as ringtone, Song info, Find songs, Select; (5) Remove from this playlist, Delete from phone, Remove from my library, Delete from disk (ui/menu/SongMenu.kt:204) (iPhone: the first group is the menu's row of quick actions)

## 36. Song menu: what each action does

- [x] "Play next" (PlayNext icon): puts the song next and closes; no feedback line (ui/menu/SongMenuPopup.kt:190)
- [x] "Add to queue" (AddToQueue icon): adds it at the end and closes (ui/menu/SongMenuPopup.kt:194)
- [x] "Start radio" (Radio icon): closes, then plays the song followed by up to 50 songs like it (from the library and, with a server, its suggestions, finds among them) in place of the queue, source "<title> radio"; "No similar songs found" when none (ui/menu/SongMenu.kt:360)
- [x] Add action for a find (default): icon AddToLibrary; words "Add to your library", "Adding to your library" (asked), "In your library" (done, Check icon); enabled only before it is asked; tapping asks the server to add it and leaves the menu open (ui/menu/SongMenuPopup.kt:208) (iPhone: the system menu closes after the tap; the row's add button shows the song coming in)
- [x] For a family member whose songs are saved rather than added, the add action is "Save" (Like icon) or "Remove from Saved" (Liked icon); it closes and toggles the saved state (ui/menu/SongMenuPopup.kt:202)
- [x] "Request a copy" (Download icon, chevron): closes and opens the family request for the song (ui/menu/SongMenuPopup.kt:216)
- [x] "Remove from my library" (destructive): closes and takes the song out of this member's own library on the server; "This song is not in your own library" when it cannot be found there (ui/menu/SongMenu.kt:313)
- [x] "Add to last playlist: <name>" (AddToPlaylist icon): opens a picker page started at that playlist, which adds at once or asks first (ui/menu/SongMenuPopup.kt:224)
- [x] "Add to playlist" (AddToPlaylist icon, chevron): opens the playlist picker as a page with a back row (ui/menu/SongMenuPopup.kt:229) (iPhone: a sub-menu)
- [x] "Remove from this playlist" (RemoveFromPlaylist icon): closes; takes that row out with "Removed from <name>" and "Undo" (ui/menu/SongMenu.kt:337)
- [x] "Select" (Select icon): closes and starts selecting with this row picked (ui/menu/SongMenuPopup.kt:241)
- [x] Download row for a library song: "Download" (Download icon) when not kept; "Waiting to download" / "Downloading" (Downloading icon, disabled) on its way; "Remove download" (Downloaded icon) when downloaded by hand, which removes it with "Download removed" and "Undo"; "Kept downloaded" (Downloaded icon, disabled) when a rule keeps it; "Download failed, try again" (Download icon) which retries; the menu stays open (ui/menu/SongMenu.kt:227) (iPhone: the system menu closes after a pick)
- [x] The download row is offered when the song is not on the phone or already has a download row (ui/menu/SongMenuPopup.kt:169)
- [x] "Find higher quality" (Lossless icon): closes and asks the Octo server to look for a better copy of this song (ui/menu/SongMenuPopup.kt:260)
- [x] "Share file" (ShareFile icon): closes and shares the song's phone file through the system share chooser (with read permission granted; MIME type of the file, "audio/*" when mixed audio, "*/*" otherwise) (ui/menu/PhoneFileActions.kt:188) (iPhone: the system share sheet with the file; a song from the Music app's library is copied out as M4A first)
- [x] "Share link" (Share icon, chevron): opens the share page for the server's copy, named by the song title (ui/menu/SongMenuPopup.kt:268) (iPhone: a sub-menu with the expiry choices)
- [x] Like row: "Add to Liked songs" (Like icon) or "Remove from Liked songs" (Liked icon); toggles and leaves the menu open; liking stores the time it was liked (ui/menu/SongMenuPopup.kt:269) (iPhone: the system menu closes after a pick)
- [x] "Rate" (Star icon, StarFilled when rated), detail "1 star" / "N stars" when rated, chevron: opens the rate page (ui/menu/SongMenuPopup.kt:274) (iPhone: a sub-menu picker, the current rating shown beside "Rate")
- [x] "Go to album" (Album icon) and "Go to artist" (Artist icon): close and open the song's album or artist page, closing the player if open (ui/menu/SongMenuPopup.kt:281)
- [~] "Set as ringtone" (Ringtone icon): closes and asks "Set as" with "Ringtone", "Notification sound", "Alarm" (ui/menu/PhoneFileActions.kt:306) (not on iPhone: Apple gives apps no way to set a ringtone, a notification sound or an alarm)
- [x] "Delete from phone" (Delete icon, destructive): closes and deletes the song's phone files, confirmed by the system (ui/menu/SongMenuPopup.kt:293) (iPhone: Octo asks first, then deletes the files in Octo's own folder; a song in the Music app's library can only be removed in the Music app, which a line says)
- [x] "Delete from disk" (Delete icon, destructive, chevron): opens the question page "Delete this song from disk?" with the body naming the song title and the server's trash time; "Delete" deletes it from the server's disk and closes; "Cancel" goes back to the actions (ui/menu/SongMenuPopup.kt:119) (iPhone: a system alert; Cancel closes it)
- [x] "Song info" (Info icon, chevron): opens the info page (ui/menu/SongMenuPopup.kt:300) (iPhone: a system sheet)
- [x] "Find songs" (Search icon): closes and opens the server's Find songs for this song (by its server copy or its found id); "This server has no copy of the song to look for" when it cannot (ui/menu/SongMenu.kt:288)
- [x] Rows that only change a state (add for a find, download row, like) leave the menu open so their new words show (ui/menu/SongMenuPopup.kt:214) (iPhone: system menus close after a pick; the next opening shows the new state)

## 37. Song menu: rate page

- [x] A back row "Rate", the song header, then five 48dp star buttons centred 2dp apart, each star 30dp: lit (StarFilled, white) up to the rating, unlit (Star, TextMuted) after; 10dp space below (ui/menu/SongMenuPopup.kt:326) (iPhone: Rate is a sub-menu picker with "No rating" and 1 to 5 stars, the rating ticked)
- [x] Tapping a star sets that many stars; tapping the star equal to the current rating clears it to 0; the page stays open so the stars show the choice (ui/menu/SongMenuPopup.kt:362) (iPhone: the menu closes after the pick)
- [x] Each star speaks "1 star" or "N stars" and reports selected when it equals the rating (ui/menu/SongMenuPopup.kt:341) (iPhone: each choice reads "1 star" or "N stars", the current one ticked)

## 38. Song menu: share page

- [x] From the song menu: a back row "Share link"; from a page (album Share): a heading "Share \"<title>\"" (ui/server/ShareSheet.kt:153) (iPhone: a sub-menu "Share link"; from the album page a menu headed "Share "<title>"")
- [x] Note "Anyone with the link can listen.", then a quiet title "Link expires" and rows "Never", "1 day", "1 week", "1 month" (at least 46dp, radius 14, padding 14 horizontal) (ui/server/ShareSheet.kt:156) (iPhone: the note and a "Link expires" section in the menu)
- [x] Picking an expiry makes the link (a small spinner on that row; the other rows disabled), then closes the menu and opens the phone's share chooser with the link as text and the title as subject (ui/server/ShareSheet.kt:159) (iPhone: the menu closes as the link is asked for; the share sheet opens once it is made)
- [x] Failures, in the Error colour: "The server made the link but did not say where it is."; "Sharing is switched off on this server." (error 50 or 70, not found, or HTTP 501); otherwise the server error message (ui/server/ShareSheet.kt:105) (iPhone: said in a message line)

## 39. Song menu: song info page

- [x] A back row "Song info"; page 320dp wide; "Reading the song" until read (once, when the page opens); then the song header and the lines; 8dp space at the end (ui/menu/SongInfo.kt:340) (iPhone: a system sheet titled "Song info", "Reading the song" while it reads)
- [x] Each line: label (caption TextMuted, 92dp wide, 2dp top) and value (bodySmall TextPrimary), 10dp apart, padding start 14, end 6, 5 vertical; copyable lines end with a "Copy" button that copies the value and reads "Copied" for 2 seconds (ui/menu/SongInfo.kt:358) (iPhone: each line's label over its value in a list; Copy reads "Copied" for 2 seconds)
- [x] Lines in order, leaving out unknowns: "Title"; "Artist"; "Album"; "Album artist"; "Composer"; "Year"; "Original year" (only when different from Year); "Genre" or "Genres" (the song's genre plus every copy's genres, each once ignoring case, joined ", "); "Track"; "Disc" ("N · <disc title>" when the disc has a title); "BPM"; "Lyrics" ("Explicit" or "Clean"); "Comment" (ui/menu/SongInfo.kt:134)
- [x] Then: "Length" (clock); "Format" ("FLAC, lossless", "ALAC, lossless", "WAV, lossless", "MP3", "AAC", "Opus", "Vorbis", "Ogg"); "File type" (the MIME type); "Bitrate" ("N kbps", rounded); "Sample rate" ("44.1 kHz", "48 kHz"); "Bit depth" ("N-bit"); "File size" (decimal: under 1,000,000 bytes "%.0f KB", under 1,000,000,000 "%.1f MB", else "%.2f GB") (ui/menu/SongInfo.kt:153)
- [x] Then the source: "Source" "This phone" with a copyable "Path" (the file's folder and name in the phone's storage); or "Source" with the server name ("Octo", the server type capitalised, or the host; "Your server" when unknown) and a copyable "Downloaded to" path when downloaded; or "Source" "Found online" for a find (ui/menu/SongInfo.kt:161)
- [x] Then: "Suggested by" (which radio source suggested it); "Added" (date "d MMM yyyy"); "Plays" (always, with thousands separators); "Last played" (date); "Rating" ("1 star" / "N stars") (ui/menu/SongInfo.kt:172)
- [x] Then gains: "Track gain" and "Album gain" ("+1.50 dB", sign always shown), "Track peak" and "Album peak" (3 decimals) (ui/menu/SongInfo.kt:178)
- [x] Then copyable MusicBrainz ids: "Recording MBID", "Release MBID", "Release group MBID", "Artist MBID" or "Artist MBIDs" (one per line) (ui/menu/SongInfo.kt:184)
- [x] Which copy the facts describe: the phone's copy when the song is on the phone, else the server's; a phone file's missing bitrate, sample rate and bit depth are read from the file itself; gains from the playing copy or the first copy that has them; the year shown is this edition's with the original year beside it (ui/menu/SongInfo.kt:236)

## 40. Phone file actions (delete, share, sounds)

- [x] Only files from the phone's own media library can be deleted, shared or set as a sound; songs with no such file are left out of each (device/PhoneFiles.kt:12)
- [x] Deleting removes every phone file each song has, so it leaves the phone completely (device/PhoneFiles.kt:24)
- [x] Newer systems (Android 11 and later): the system's own delete confirmation; only after a yes do the songs leave the queue; a no changes nothing (ui/menu/PhoneFileActions.kt:117) (iPhone: iOS has no system delete confirmation, so Octo asks first as on the next line; only after a yes do the songs leave the queue)
- [x] Older systems (Android 10): Octo asks first with a choice "Delete this song from the phone?" / "Delete N songs from the phone?" offering "Delete" (detail "Its file is removed for good" / "Their files are removed for good") and "Cancel"; on yes the songs leave the queue first, then files go one at a time, asking the system per file where needed (ui/menu/PhoneFileActions.kt:264) (iPhone: a system alert)
- [x] A failed delete says "Could not delete from the phone" (ui/menu/PhoneFileActions.kt:128)
- [x] After any file goes, the phone is scanned again so those songs leave the library or keep only a server copy; when none went, the queue is put back as it was (ui/menu/PhoneFileActions.kt:180)
- [x] One delete at a time; a second request while one runs is ignored (ui/menu/PhoneFileActions.kt:106)
- [~] Setting a sound: when Octo may not change system settings, it asks with a choice titled "Let Octo change your sounds" with one answer "Open settings" (detail "Android asks before an app sets a ringtone. Turn on the switch for Octo, then come back.") opening the system switch; coming back without it says "Octo was not allowed to change sounds" (ui/menu/PhoneFileActions.kt:282) (not on iPhone: no app can set system sounds on iPhone, so there is no permission to ask for)
- [~] Set successfully: "Set as your ringtone" / "Set as your notification sound" / "Set as your alarm" with "Undo", which puts back the sound it replaced; failure "Could not change the ringtone" / "notification sound" / "alarm" (ui/menu/PhoneFileActions.kt:233) (not on iPhone: no app can set system sounds on iPhone)

## 41. Collection menus (album, artist, playlist)

- [x] Long press on an album card, artist row or circle, or playlist line opens its menu beside it; pane title "Menu"; each opening starts on the actions page (ui/menu/CollectionMenuPopup.kt:49) (iPhone: a system context menu)
- [x] Album header: artwork 40dp radius 6, album title, album artist (ui/menu/CollectionMenuPopup.kt:108) (iPhone: the context menu's preview is the card itself)
- [x] Artist header: round artwork 40dp, name, "N albums" (ui/menu/CollectionMenuPopup.kt:136) (iPhone: the context menu's preview is the row or circle itself)
- [x] Playlist header: the playlist's cover 40dp radius 6 (designed or mosaic, with glyph), name, "N songs" (ui/menu/CollectionMenuPopup.kt:148) (iPhone: the context menu's preview is the line itself)
- [x] Album actions: "Play", "Shuffle", "Play next", "Add to queue", "Start radio", "Add to playlist", "Download" (when some of its songs are only on a server and not kept), "Find higher quality for N songs" (when the Octo server could replace N lossy copies), "Add to favorites" or "Remove from favorites", pin rows, "Go to artist" (ui/menu/CollectionMenu.kt:108)
- [x] Artist actions: "Play", "Shuffle", "Play next", "Add to queue", "Start radio", "Add to favorites" or "Remove from favorites", pin rows (ui/menu/CollectionMenu.kt:126)
- [x] Playlist actions: "Play", "Shuffle", "Play next", "Add to queue" (only when it has songs), pin rows, "Rename", "Duplicate", "Delete" (ui/menu/CollectionMenu.kt:135)
- [x] Pin rows: "Pin to Home" when not pinned; when pinned "Unpin", plus "Move to front" unless it is already first (ui/menu/CollectionMenu.kt:94)
- [x] Groups: (1) Play, Shuffle, Play next, Add to queue, Start radio; (2) Add to playlist, favourites, Download, Find higher quality; (3) pin rows; (4) Go to artist; (5) Rename, Duplicate, Delete (ui/menu/CollectionMenu.kt:145) (iPhone: Play, Shuffle and Start radio as the menu's row of quick actions)
- [x] Icons: Play, Shuffle, PlayNext, AddToQueue, AddToPlaylist, Download, Lossless, Radio, Like / Liked, Pin (all three pin rows), Artist, Rename, AddToPlaylist (Duplicate), Delete (ui/menu/CollectionMenuPopup.kt:199) (iPhone: SF Symbols)
- [x] Rows that open a page (Add to playlist, Rename, Delete, Find higher quality) show the chevron; "Delete" is destructive; every other row closes the menu first, then acts (ui/menu/CollectionMenuPopup.kt:218) (iPhone: rows that open a page are sub-menus or alerts; Delete in the destructive role)
- [x] Songs of a collection, in play order: an album's in album order; an artist's album by album (newest year first, then title key), each in album order; a playlist's in its order (ui/menu/CollectionMenu.kt:224)
- [x] Play and Shuffle play those songs from the first or shuffled; Play next and Add to queue act only when there are songs (ui/menu/CollectionMenu.kt:241)
- [x] Album "Start radio": seeds the album's most played song here (else its first), then the album's songs; plays songs like the album leaving the rest of the album out; "No songs to start a radio from" when the album has none (ui/menu/CollectionMenu.kt:263)
- [x] Artist "Start radio": seeds their most played song (else their first), then up to 200 of their songs; plays songs like theirs, theirs among them; "No songs to start a radio from" when none (ui/menu/CollectionMenu.kt:279)
- [x] Album "Download": downloads the album songs only on a server not yet kept (ui/menu/CollectionMenuPopup.kt:119)
- [x] Album "Go to artist": opens the album artist's page (ui/menu/CollectionMenuPopup.kt:120)
- [x] Favourites: add or remove the album or artist (playlists cannot be favourites) (ui/menu/CollectionMenuPopup.kt:165)
- [x] "Pin to Home" pins at the end of Home's row; when Home already holds 12 pins it says "Home holds up to 12 pins. Unpin one first." (ui/menu/CollectionMenu.kt:187)
- [x] "Move to front" moves the pin to the front of Home's row; "Unpin" takes it off (ui/menu/CollectionMenu.kt:193)
- [x] Playlist "Duplicate": a new playlist "<name trimmed> (copy)" with the same songs in the same order; says "Made a copy: <copy name>" (ui/menu/CollectionMenu.kt:232)
- [x] "Add to playlist" page: "Gathering the songs" until read, then the playlist picker for all the collection's songs (ui/menu/CollectionMenuPopup.kt:73) (iPhone: Add to playlist is a sub-menu; the songs are gathered once a playlist is picked)
- [x] "Rename" page (playlist): "Rename playlist", "Playlist name", "Save", starting with the name (ui/menu/CollectionMenuPopup.kt:245) (iPhone: a system alert with the name field)
- [x] "Delete" page (playlist): the delete question as on the playlist pop-up (server copy words when kept with the server); Delete deletes and closes; Cancel goes back (ui/menu/CollectionMenuPopup.kt:275) (iPhone: a system alert; Cancel closes it)
- [x] "Find higher quality" page (album): "Gathering the songs" until read; "Every song here is being looked for already" when none is left; else a question "Look for a higher quality copy of N songs<on source>?" ("1 song"; " on <source>" only when the server names where it looks) with "Each original is kept until its replacement passes.", buttons "Find higher quality" and "Cancel" (back) (ui/menu/CollectionMenuPopup.kt:258) (iPhone: the songs are gathered first; the question is a system alert; "Every song here is being looked for already" is said in a line)
- [x] The album's Find higher quality count is read again when the album's songs change (as after a better copy lands) (ui/menu/CollectionMenuPopup.kt:101)

## 42. Playlist, like and favourite storage rules behind these pages

- [x] Playlists shown: every playlist only on the phone, plus those kept with the server in use; another kept server's playlists wait until it is in use again (catalog/Playlists.kt:54)
- [x] A new playlist gets a fresh random id at once (so it can be marked recent before it is saved), its trimmed name, created and changed times now, and its songs added at the end (playback/PlaylistStore.kt:45)
- [x] Rename saves the trimmed name and bumps the changed time (playback/PlaylistStore.kt:56)
- [x] Adding puts the library songs at the end and reports the new rows so Undo can take exactly those back out (playback/PlaylistStore.kt:72)
- [x] Removing reports the row as it was; Undo puts it back in the same place; several removed together are put back last first so each lands in its place (playback/PlaylistStore.kt:81)
- [x] Moving puts a song into the place of the one it was dropped on (playback/PlaylistStore.kt:128)
- [x] Every change to a playlist kept with the server is sent there; "Save to server" makes a phone playlist on the server too and keeps them in step; deleting one kept with the server deletes the server's copy (playback/PlaylistStore.kt:135)
- [x] Playlist store changes run on their own scope, so they finish even when the page that asked closes (playback/PlaylistStore.kt:23)
- [x] Liking a song stores it with the time; only library songs can be liked (playback/Stores.kt:56)
- [x] Unliking from Liked songs reports the like row so Undo restores it with its own time, keeping its place in a Date liked order (playback/Stores.kt:70)
- [x] Favourite albums and artists are kept by id with a search key (to find them again after a rebuild) and the time they became favourites (favourites/FavouriteStore.kt:38)
- [x] Home pins: albums, artists and playlists, in the order pinned unless moved, at most 12 shown (catalog/Favourites.kt:62)
- [x] Downloads by hand carry the reason "manual"; rules add "liked" or "playlist:<id>"; a download stays while any reason does (offline/DownloadPlan.kt:6)

## 43. Add button on songs found online (as rows in these pages show it)

- [x] Not asked yet: the AddToLibrary plus, white at 60%, no glow; a tap asks the server to download the song into the library (ui/common/AddToLibraryButton.kt:166)
- [x] Waiting (queued, or downloading with no progress yet): a thin 2dp ring track (white 20%) with a 90 degree white arc turning once every 1,600ms, the small plus inside (arm 18% of the width) (ui/common/DownloadRing.kt:45)
- [x] Downloading with progress: the arc fills from the top clockwise to the progress, easing over 1,200ms; the fill never goes back even when an answer does (ui/common/DownloadRing.kt:110)
- [x] Adding to the library: the ring full and pulsing between full and 45% alpha every 900ms (ui/common/DownloadRing.kt:103)
- [x] Done: the ring and plus fade as a check draws in over 300ms with a glow held 500ms then fading over 700ms; a song already in the library when first drawn just shows the check (ui/common/DownloadRing.kt:71)
- [x] Failed: an alert mark; a tap tries again; a long press says "Could not download: <reason>" (ui/common/AddToLibraryButton.kt:150)
- [x] On its way, when the server keeps a downloads log, a tap opens the server downloads sheet following this song (click label "Follow it") (ui/common/AddToLibraryButton.kt:143)
- [x] Not tappable while on its way without a downloads log, or once done (ui/common/AddToLibraryButton.kt:150)
- [x] With reduced motion nothing turns, pulses or morphs; only the states change (ui/common/DownloadRing.kt:67)
- [x] Progress is asked for more often while the button is on screen (ui/common/AddToLibraryButton.kt:136)
- [x] Accessibility: "Add to your library" with state "Not in your library", "Queued", "Downloading, N percent" (or "Downloading"), "Adding to your library", "In your library", or "Could not download"; click label "Try again" when failed; long-press label "Why" when failed (ui/common/AddToLibraryButton.kt:75)
- [x] For a family member whose songs are saved rather than added, the button is a heart: Like icon (white 60%) or Liked (white, glowing), accessibility "Save" with state "Saved" or "Not saved"; a tap toggles saved (ui/common/AddToLibraryButton.kt:91)

## 44. Pop-up pane titles (spoken when each opens)

- [x] Song menu "Song menu"; collection menu "Menu"; playlist pop-up "Playlist"; disk delete question "Delete from disk"; Library health sheets "Library health"; share pop-up "Share"; choice lists their own title; sort list "Sort by" (ui/menu/SongMenuPopup.kt:96, ui/menu/CollectionMenuPopup.kt:61, ui/playlist/PlaylistSheets.kt:260, ui/menu/DiskDelete.kt:87, ui/library/health/HealthFixSheets.kt:80, ui/server/ShareSheet.kt:136, ui/common/ChoiceSheet.kt:148) (iPhone: system menus, alerts and sheets announce themselves to VoiceOver; sheets carry their titles)

## 45. Pages without pull to refresh

- [x] Pull to refresh is on: Library, Albums, Artists, Songs, album page, artist page (also re-asks the server about the artist), Playlists, Genres, Folders (also re-reads server folders), Favorites (ui/common/Refreshable.kt:60)
- [x] Pull to refresh is off: playlist page, genre page, History, Downloads, Library health front, a check's page, Recently removed (ui/playlist/PlaylistScreen.kt:144)

## Shared logic to port line for line

Port these as code with their tests, not as summaries. Paths are full repo paths at origin/main 0f11df0f.

### Shared core (already platform neutral Kotlin; port to Swift line for line)

- [x] `shared/core/src/commonMain/kotlin/app/winters/octo/sort/Sorts.kt`: every list's options, labels, starting directions, defaults, save keys, encode and decode. Tests: `shared/core/src/commonTest/kotlin/app/winters/octo/sort/SortsTest.kt`
- [x] `shared/core/src/commonMain/kotlin/app/winters/octo/sort/SortDirections.kt`: direction words per option and the left-right order of the two directions. Tests: `shared/core/src/commonTest/kotlin/app/winters/octo/sort/SortDirectionsTest.kt`
- [x] `shared/core/src/commonMain/kotlin/app/winters/octo/sort/SortQueries.kt`: the SQL keys, tie breaks, missing-last rules, heading columns and liked scope for songs, albums and artists (port the SQL as is if iOS keeps the catalog in SQLite). Tests: `shared/core/src/commonTest/kotlin/app/winters/octo/sort/SortQueriesTest.kt`
- [x] `shared/core/src/commonMain/kotlin/app/winters/octo/sort/Listening.kt`: orders by plays (played first or last, stable ties). Tests: `shared/core/src/commonTest/kotlin/app/winters/octo/sort/ListeningTest.kt`
- [x] `shared/core/src/commonMain/kotlin/app/winters/octo/sort/ShortLists.kt`: sortedByKey and sortFavourites. Tests: `shared/core/src/commonTest/kotlin/app/winters/octo/sort/FavouriteSortTest.kt`
- [x] `shared/core/src/commonMain/kotlin/app/winters/octo/ui/common/Letters.kt`: letter runs, rail stops, index letter. Tests: `shared/core/src/commonTest/kotlin/app/winters/octo/ui/common/LettersTest.kt`
- [x] `shared/core/src/commonMain/kotlin/app/winters/octo/catalog/Keys.kt`: searchKey, sortKey (article drop), relinkKey, naturalSortKey. Tests: `shared/core/src/commonTest/kotlin/app/winters/octo/catalog/KeysTest.kt`
- [x] `shared/core/src/commonMain/kotlin/app/winters/octo/query/LibraryQuery.kt`, `FilterPresets.kt`, `QueryLabels.kt`, `QueryMatching.kt`, `QuerySorting.kt`, `SongFields.kt`: the Songs filters, chip presets and words, text folding, rule matching, decade and genre choices, query JSON. Tests: `shared/core/src/commonTest/kotlin/app/winters/octo/query/LibraryQueryTest.kt`, `shared/core/src/commonTest/kotlin/app/winters/octo/query/QuerySpeedTest.kt`
- [x] `shared/core/src/commonMain/kotlin/app/winters/octo/livelists/LiveListRules.kt` (liveListQueryFrom, DefaultLiveListSort) for "Save as live list". Tests: `shared/core/src/commonTest/kotlin/app/winters/octo/livelists/LiveListTest.kt`
- [x] `shared/core/src/commonMain/kotlin/app/winters/octo/ui/playlist/PlaylistAdds.kt`: add plan, add-again question and buttons, added words, recent playlists (3), recent-first order, copy name, import summary. Tests: `shared/core/src/commonTest/kotlin/app/winters/octo/ui/playlist/PlaylistAddsTest.kt`
- [x] `shared/core/src/commonMain/kotlin/app/winters/octo/playlists/M3uText.kt`: playlist file name, file reading, ImportReport. Tests: `shared/core/src/commonTest/kotlin/app/winters/octo/playlists/M3uTextTest.kt`
- [x] `shared/core/src/commonMain/kotlin/app/winters/octo/catalog/ReleaseGroups.kt`: artist page shelves. Tests: `shared/core/src/commonTest/kotlin/app/winters/octo/catalog/ReleaseGroupsTest.kt`
- [x] `shared/core/src/commonMain/kotlin/app/winters/octo/catalog/SongIdentity.kt`: title keys, feature stripping and artist matching used by the album highlight and health. Tests: `shared/core/src/commonTest/kotlin/app/winters/octo/catalog/SongIdentityCasesTest.kt`, `SongIdentityIsrcTest.kt`, `SongIdentityStripFeaturesTest.kt`
- [x] `shared/core/src/commonMain/kotlin/app/winters/octo/catalog/ArtworkRef.kt` and `Explicit.kt`: artwork references and the explicit flag. Tests: `shared/core/src/commonTest/kotlin/app/winters/octo/catalog/ArtworkRefTest.kt`, `ExplicitTest.kt`
- [x] `shared/core/src/commonMain/kotlin/app/winters/octo/covers/` (CoverArtwork.kt, CoverBook.kt, CoverColour.kt, CoverDesign.kt, CoverGlyphs.kt, CoverPalette.kt, CoverSwatches.kt, CoverText.kt, CoverVeil.kt, PlaylistCovers.kt) with `shared/core/src/commonMain/resources/app/winters/octo/covers/cover-design.json` and `backgrounds/` (backgrounds.json and the 48 webp images): designed playlist covers, glyphs, palettes, sizes, cache keys. Tests: `shared/core/src/commonTest/kotlin/app/winters/octo/covers/CoverDesignTest.kt`, `CoverGlyphsTest.kt`, `CoverPaletteTest.kt`, `CoverTextTest.kt`, `CoverTitleTest.kt`, `CoverVarietyTest.kt`, `PlaylistCoversTest.kt`, `FakeTypesetter.kt`
- [x] `shared/core/src/commonMain/kotlin/app/winters/octo/health/LibraryHealth.kt`, `HealthFixes.kt`, `HealthWords.kt`, `FixWords.kt`: the checks, duplicate and split-album detection, fixes, every health string. Tests: `shared/core/src/commonTest/kotlin/app/winters/octo/health/HealthFixesTest.kt`, `HealthSpeedTest.kt`, `LibraryHealthCasesTest.kt`, `LibraryHealthTest.kt`, `SplitAcrossArtistsTest.kt`
- [x] `shared/core/src/commonMain/kotlin/app/winters/octo/listening/PlayDays.kt`: History day headings. Tests: `shared/core/src/commonTest/kotlin/app/winters/octo/listening/PlayDaysTest.kt`
- [x] `shared/core/src/commonMain/kotlin/app/winters/octo/discovery/AlbumShare.kt`, `LibraryOnly.kt`, `Biography.kt`: "N of M in your library", "Only my songs" and "Library songs only" words and filter, biography cleanup. Tests: `shared/core/src/commonTest/kotlin/app/winters/octo/discovery/AlbumShareTest.kt`, `LibraryOnlyTest.kt`, `BiographyTest.kt`
- [x] `shared/core/src/commonMain/kotlin/app/winters/octo/ui/upgrade/FlacUpgrades.kt`: Find higher quality words and question. Tests: `shared/core/src/commonTest/kotlin/app/winters/octo/ui/upgrade/FlacUpgradesTest.kt`
- [x] `shared/core/src/commonMain/kotlin/app/winters/octo/ui/downloads/Downloads.kt`: runningCount ("N on the way") and the "Find songs" word. Tests: `shared/core/src/commonTest/kotlin/app/winters/octo/ui/downloads/DownloadsTest.kt`
- [x] `shared/core/src/commonMain/kotlin/app/winters/octo/offline/OfflineKeeping.kt`: keep reasons and wanted copies. Tests: `shared/core/src/commonTest/kotlin/app/winters/octo/offline/OfflineKeepingTest.kt`

### Android app logic that is pure and must be ported the same way

- [x] `app/src/main/java/app/winters/octo/sort/SortSettings.kt` (restorableOrders), `SortedLibrary.kt` (headings only for by-name orders), `TrackQuery.kt` (TrackFields, formatOf, filteredSongs), `ShortListRows.kt` (playlists, downloads, folder songs), `PlayedListening.kt` (song, album, artist listening). Tests: `app/src/test/java/app/winters/octo/sort/SortSettingsTest.kt`, `TrackQueryTest.kt`, `ShortListRowsTest.kt`, `PlayedListeningTest.kt`
- [x] `app/src/main/java/app/winters/octo/catalog/Plays.kt` (byPlayCount, artistSongOrder), `Places.kt` (songsInGroupOrder), `Playlists.kt` (mosaicCovers, summarize, shownWith), `Favourites.kt` (PIN_LIMIT, relinks), and the CatalogDao orders quoted above (recentAlbums, albumTracks, artistTracks, trackPlaces, artistAlbums, genres, genreAlbums). Tests: `app/src/test/java/app/winters/octo/catalog/PlaysTest.kt`, `PlacesTest.kt`, `PlaylistsTest.kt`, `FavouritesTest.kt`
- [x] `app/src/main/java/app/winters/octo/folders/FolderTree.kt` (tree, collapse, natural order), `FolderSongs.kt` (gatherSongs limits), `ServerFolders.kt` (serverName, limits 2,000 songs and 400 folders). Tests: `app/src/test/java/app/winters/octo/folders/FolderTreeTest.kt`, `FolderSongsTest.kt`
- [x] `app/src/main/java/app/winters/octo/listening/History.kt` (recentHistory, historyDays, HistoryRange, rangeStart, mostPlayed) and `ServerPlays.kt` (withServerPlays, sent plays). Tests: `app/src/test/java/app/winters/octo/listening/HistoryTest.kt`, `ServerPlaysTest.kt`
- [x] `app/src/main/java/app/winters/octo/offline/OfflineMarks.kt` (downloaded and out-of-reach marks) and `DownloadPlan.kt` (Reasons, wanted by rules). Tests: `app/src/test/java/app/winters/octo/offline/OfflineMarksTest.kt`, `DownloadPlanTest.kt`, `DownloadUndoTest.kt`
- [x] `app/src/main/java/app/winters/octo/discovery/WholeAlbum.kt`, `AlbumHighlight.kt`, `ArtistExtras.kt` (inLibraryOnly, serverArtistIdOf, ownSongs), `FindLengths.kt` (shownLengthMs). Tests: `app/src/test/java/app/winters/octo/discovery/WholeAlbumTest.kt`, `AlbumHighlightTest.kt`, `ArtistExtrasTest.kt`, `FindLengthsTest.kt`, `LibraryOnlyListsTest.kt`
- [x] `app/src/main/java/app/winters/octo/device/PhoneFiles.kt` (phoneFiles, deletePlan, filesToShare, shareType, PhoneSound). Tests: `app/src/test/java/app/winters/octo/device/PhoneFilesTest.kt`
- [x] `app/src/main/java/app/winters/octo/playback/Copies.kt` (isLossless, bitrateOf) and `Quality.kt` (codec names used by Song info's Format line). Tests: `app/src/test/java/app/winters/octo/playback/CopiesTest.kt`, `QualityTest.kt`
- [x] `app/src/main/java/app/winters/octo/ui/menu/SongMenu.kt` (songActions, menuPlace, songMenuGroups, downloadLabel, keepOfflineLabel, keepOfflineEnabled) and `SongMenuPopup.kt` (nextRating, starsLabel). Tests: `app/src/test/java/app/winters/octo/ui/menu/SongActionsTest.kt`, `MenuGroupsTest.kt`, `MenuPlaceTest.kt`
- [x] `app/src/main/java/app/winters/octo/ui/menu/CollectionMenu.kt` (albumActions, artistActions, playlistActions, collectionMenuGroups, pinSpot). Tests: `app/src/test/java/app/winters/octo/ui/menu/CollectionActionsTest.kt`
- [x] `app/src/main/java/app/winters/octo/ui/menu/SongInfo.kt` (infoLines, formatName, bitrateText, sampleRateText, sizeText, gainText, peakText, dateText). Tests: `app/src/test/java/app/winters/octo/ui/menu/SongInfoTest.kt`
- [x] `app/src/main/java/app/winters/octo/ui/menu/DiskDelete.kt` (deleteNames). Tests: `app/src/test/java/app/winters/octo/ui/menu/DiskDeleteTest.kt`
- [x] `app/src/main/java/app/winters/octo/ui/common/GlassMenu.kt` (menuRowLooks). Tests: `app/src/test/java/app/winters/octo/ui/common/GlassMenuTest.kt` (iPhone: system menu rows draw themselves, so there is no row look to work out)
- [x] `design/src/main/java/app/winters/octo/design/GlassPopup.kt` (placePopup) and `PopupPages.kt` (PageTrail), with `app/src/main/java/app/winters/octo/ui/common/PressSpot.kt` (menuAnchor). Tests: `app/src/test/java/app/winters/octo/ui/common/GlassPopupTest.kt`, `PopupPagesTest.kt` (iPhone: system menus and context menus place themselves beside what opened them)
- [x] `app/src/main/java/app/winters/octo/ui/common/Selection.kt` (Picks). Tests: `app/src/test/java/app/winters/octo/ui/common/SelectionTest.kt`
- [x] `app/src/main/java/app/winters/octo/ui/common/Sorting.kt` (sortArrowTurn, titleFitsBeside). Tests: `app/src/test/java/app/winters/octo/ui/common/SortArrowTest.kt`, `TitleFitTest.kt`
- [x] `app/src/main/java/app/winters/octo/ui/common/SongLength.kt` (rowLength) and `Items.kt` (rowAlbum, songSubtitle). Tests: `app/src/test/java/app/winters/octo/ui/common/SongLengthTest.kt`
- [x] `app/src/main/java/app/winters/octo/ui/common/NotInLibrary.kt` (AddSign, rowAddSign, rowEnd, artworkDescription, albumLibraryNote, addMissingLabel, mark size and inset), `FindSwap.kt` (find faces and timings), `AddToLibraryButton.kt` (downloadStateText). Tests: `app/src/test/java/app/winters/octo/ui/common/NotInLibraryTest.kt`, `FindSwapTest.kt`, `AddToLibraryButtonTest.kt`
- [x] `app/src/main/java/app/winters/octo/ui/album/AlbumExtras.kt` (albumSongsShown, albumGenre, averageRating, starsText, averageRatingSpoken) and `AlbumDownload.kt` (albumDownloadLabel). Tests: `app/src/test/java/app/winters/octo/ui/album/AlbumExtrasTest.kt`, `app/src/test/java/app/winters/octo/ui/offline/OfflineWordsTest.kt`
- [x] `app/src/main/java/app/winters/octo/ui/favourites/FavouriteSegments.kt` (firstSegment, openingSegment). Tests: `app/src/test/java/app/winters/octo/ui/favourites/FavouriteSegmentsTest.kt` (iPhone: the way in carries the segment in its route (Liked songs and the Favorite albums shelf ask for theirs))
- [x] `app/src/main/java/app/winters/octo/ui/offline/DownloadsScreen.kt` (sizeLabel, downloadDetail, keptBy) and `ui/playlist/KeepDownloaded.kt` (keptSummary). Tests: `app/src/test/java/app/winters/octo/ui/offline/OfflineWordsTest.kt`
- [x] `app/src/main/java/app/winters/octo/ui/playlist/AddPlan.kt` (holdingsByPlaylist), `PlaylistsScreen.kt` (playlistsLead), `PlaylistScreen.kt` (phoneOnlyNote). Tests: `app/src/test/java/app/winters/octo/ui/playlist/AddPlanTest.kt`, `PlaylistsLeadTest.kt`, `app/src/test/java/app/winters/octo/playlists/PlaylistPlanTest.kt`
- [x] `app/src/main/java/app/winters/octo/ui/library/health/PhoneHealth.kt` (phone health fields, lines) and `HealthFixPlans.kt` (offers, plans, previews, look-up batch). Tests: `app/src/test/java/app/winters/octo/ui/library/health/PhoneHealthTest.kt`, `HealthFixPlansTest.kt`
- [x] Untested helpers to port exactly and cover with new iOS tests: `app/src/main/java/app/winters/octo/ui/library/LibraryScreen.kt` filteredCount; `app/src/main/java/app/winters/octo/ui/library/health/RecentlyRemoved.kt` goneAtMillis and keepsFor; `app/src/main/java/app/winters/octo/ui/common/LibraryReach.kt` accessButtonLabel; `app/src/main/java/app/winters/octo/ui/common/Layout.kt` asClock, asLength, songs, albums
