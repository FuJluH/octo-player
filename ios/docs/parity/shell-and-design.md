# Parity contract: shell and design system

Read from octo-player `origin/main` 0f11df0f (2026-10-11). Every item below is what the Android app does today, with the file and line it comes from.

## How to read this

Path roots used in the references:

- `ui/...`, `ambient/...`, `player/...`, `playback/...`, `family/...`, `data/...`, `MainActivity.kt` are under `app/src/main/java/app/winters/octo/`.
- `design/...` is under `design/src/main/java/app/winters/octo/design/`.
- `shared/...` is under `shared/core/src/commonMain/kotlin/app/winters/octo/`.
- `subsonic/...` is under `subsonic/src/main/kotlin/app/winters/octo/subsonic/`.
- `res/...` is `app/src/main/res/...`; `icons.json` is `tools/icons/icons.json`.

Units: `dp` maps to iOS points one to one; `sp` maps to points that scale with Dynamic Type. Blur values are given as the CSS value the code names, then what Android draws (`shadowBlur(B)` = B x 0.866 dp, a Gaussian of sigma B/2; `backdropBlur(B)` = B x 1.732 dp, a Gaussian of sigma B). A spring written `spring(d, s)` is damping ratio d, stiffness s. A tween with no easing named uses Compose's default FastOutSlowIn, cubic (0.4, 0, 0.2, 1).

Glass on iPhone: the 2026-10-07 decision (octo-ios-native-glass) is that every glaze on iPhone is Apple's native glass. The glass recipes below still fix each surface's shape, size, film darkness, shadow and placement, and which surfaces are glass at all.

## 1. App frame and launch

- [x] The window background before the first frame is `#0C0C0D` (`octo_background`), so launch never flashes (res/values/themes.xml:3, res/values/colors.xml:2) (iPhone: the launch screen's background color LaunchBackground, #0C0C0D)
- [x] The launch screen (Android 12 and up) shows the logo's octopus alone (`splash_octopus`) over `#0C0C0D`, not the icon's lavender tile (res/values-v31/themes.xml:5) (iPhone: the launch screen shows the LaunchOctopus image alone on #0C0C0D)
- [x] The app draws edge to edge: content runs under the status bar and navigation bar, each piece padding itself (MainActivity.kt:56) (iPhone: backgrounds ignore the safe areas; each piece pads itself)
- [x] The app opens straight on the library; there is no sign-in gate, servers are an optional add-on (MainActivity.kt:57)
- [x] The content tree is `OctoTheme { ProvideOfflineMarks { ProvideAdoptedFinds { ProvideLearnedLengths { MainShell(...) } } } }`; `ProvideAdoptedFinds` is where Reduce motion is provided to everything (MainActivity.kt:58, ui/common/NotInLibrary.kt:102) (iPhone: the motion setting reaches every view through the environment (motionScaled))
- [x] The whole shell sits on a full-screen box filled with `OctoColors.Background` `#0C0C0D` (ui/nav/MainShell.kt:264)
- [x] The theme is dark only: Material dark scheme with primary = Accent `#97B1B9`, background `#0C0C0D`, surface `#1A1A1B`, onBackground and onSurface white, error `#EF4444`; every other scheme slot keeps Material's dark baseline (design/OctoTheme.kt:9) (iPhone: dark only (UIUserInterfaceStyle Dark, preferredColorScheme dark), tinted with the accent)
- [x] The theme sets no typography or font family: all app text is the platform's default sans font (Roboto on Android, so SF on iPhone); only playlist covers use Inter Display and codes use JetBrains Mono (design/OctoTheme.kt:9, design/CoverFonts.kt:10, design/MonoFont.kt:10) (iPhone: SF everywhere; Inter Display for playlist covers; SF Mono stands in for JetBrains Mono)
- [x] Each time the app returns to the foreground the shell re-reads the phone library's access, since it can change in system settings while away (`library.refresh()` on resume) (ui/nav/MainShell.kt:226)
- [x] The shell provides to every page: the frosting source (`LocalHaze`), the press spot, the song menu, playlist sheets, disconnect prompt, choice sheet, share sheet, feedback, page artworks, `open(page)` for the current tab, and `NowMark(trackId, isPlaying)` for marking the playing row (ui/nav/MainShell.kt:249) (iPhone: environment objects and values (router, library actions, page artworks, now mark); menus and sheets are the system's)
- [x] `NowMark` defaults to no song and not playing; any list reads it to mark the row of the song on now without watching the player (ui/common/NowPlayingMark.kt:9)
- [x] The app becoming visible connects to the playback service and checks the server for a queue left on another device; going to the background releases it (MainActivity.kt:133) (iPhone: becoming active checks the server for a queue left on another device; the player lives in the app)
- [~] On leaving the app (not a rotation), a ready app update set to "When I leave Octo" installs unless music is playing (MainActivity.kt:144) (not on iPhone: an iPhone app cannot install its own update; a found update says where to get it)
- [x] While casting, the hardware volume buttons step the cast device's volume instead of the phone's (MainActivity.kt:121) (iPhone: with AirPlay the side buttons set the speaker's volume, as iOS does)

## 2. Tabs, back stacks and routes

- [x] There are four tabs in this order: Home (index 0), Search (1), Library (2), Settings (3) (ui/nav/MainShell.kt:137, ui/nav/BottomBar.kt:83)
- [x] Tab names are "Home", "Search", "Library", "Settings" (res/values/strings.xml:3)
- [x] Each tab has its own back stack, starting at its root route (`HomeRoute`, `SearchRoute`, `LibraryRoute`, `SettingsRoute`) (ui/nav/MainShell.kt:137)
- [x] The selected tab survives rotation and process death (saved state), starting at Home (ui/nav/MainShell.kt:143) (iPhone: kept in scene storage, starting at Home)
- [x] Every tab keeps its pages' saved state and view models while another tab is in front, so returning to a tab finds it exactly as it was left (scroll, inputs, loaded data) (ui/nav/MainShell.kt:154)
- [x] Opening a page pushes it onto the current tab's stack; a page opened from inside a page stays in that tab (ui/nav/MainShell.kt:166, ui/nav/MainShell.kt:366)
- [x] Tapping a different tab switches to it with the tab change motion and keeps both stacks as they were (ui/nav/MainShell.kt:213)
- [x] Tapping the tab already selected pops its stack back to its root (removing pages one at a time from the top until one is left) (ui/nav/MainShell.kt:209) (iPhone: the stack pops to its first page in one move, as iOS does)
- [x] Any tab tap also folds the bar's small player back into the round button (`barPlayer = false`) (ui/nav/MainShell.kt:208)
- [x] Back on a page deeper than a tab's root pops that page (ui/nav/MainShell.kt:271) (iPhone: the Liquid Glass back button and the edge swipe pop the page)
- [x] Back at the root of Search, Library or Settings goes to the Home tab instead of leaving the app (ui/nav/MainShell.kt:281) (iPhone: an edge swipe at the first page of Search, Library or Settings goes to Home)
- [x] Back at the root of Home leaves the app (the platform default; nothing handles it) (ui/nav/MainShell.kt:281) (iPhone: iOS has no back out of an app; the edge swipe at Home does nothing)
- [x] With the player open, back closes the player (the player's own back handler, which enters composition when the player opens) (player/PlayerOverlay.kt:187) (iPhone: pulling the player down closes it, as iOS players do)
- [x] While songs are being picked, back clears the picks (ends selection mode) (ui/common/SelectionBar.kt:95)
- [x] A glass popup takes back first: back goes to the popup's previous page if it has one, otherwise closes it (design/GlassPopup.kt:189) (iPhone: system menus and popovers close with a tap outside them)
- [x] A glass sheet that is visible closes on back (design/GlassSheet.kt:71) (iPhone: system sheets close by swiping down)
- [x] Route `HomeRoute` shows the Home screen (ui/nav/MainShell.kt:370)
- [x] Route `SearchRoute` shows Search (ui/nav/MainShell.kt:371)
- [x] Route `LibraryRoute` shows Library (ui/nav/MainShell.kt:372)
- [x] Route `SettingsRoute` shows Settings (ui/nav/MainShell.kt:373)
- [x] Route `SettingsPageRoute(page, highlight)` shows one Settings page, with the row a settings search pointed at highlighted when given (ui/nav/Routes.kt:14, ui/nav/MainShell.kt:374)
- [x] Routes `AlbumRoute(id)` and `ArtistRoute(id)` show a library album or artist (ui/nav/MainShell.kt:375)
- [x] Routes `OnlineAlbumRoute(id)` and `OnlineArtistRoute(id)` show a server album or artist not in the library, by the server's id (ui/nav/Routes.kt:20, ui/nav/MainShell.kt:377)
- [x] Routes `AlbumsRoute`, `ArtistsRoute`, `SongsRoute`, `GenresRoute`, `GenreRoute(name)`, `FoldersRoute`, `PlaylistsRoute` show the library lists (ui/nav/MainShell.kt:379)
- [x] `LikedRoute` and `FavouritesRoute(albums)` both show the one Favourites page; the way in picks which part it opens on (Liked songs, or albums from the Favourite albums shelf) (ui/nav/Routes.kt:41, ui/nav/MainShell.kt:387)
- [x] `DownloadsRoute` shows the phone's downloads page (ui/nav/MainShell.kt:389)
- [x] `PlaylistRoute(id)` shows a playlist; `LiveListRoute(id)` shows a live list (ui/nav/MainShell.kt:390)
- [x] `LiveListEditRoute(id, start)` edits a live list, or makes a new one (id null) begun from a page's filters (`start`); once a new one is saved the editor is popped and the new live list's page is pushed in its place; saving an existing one just pops (ui/nav/Routes.kt:54, ui/nav/MainShell.kt:393) (iPhone: once a new one is saved the editor closes and the new live list's page opens)
- [x] A live list's options sheet can open its editor; that goes through the menu path, closing the player first (ui/nav/MainShell.kt:247)
- [x] `SignInRoute` shows the sign-in form; `EditConnectionRoute` the same form editing the saved connection; `ServerFormRoute(form, id, note)` the form for a kept server with `form` one of Add, Edit, SignIn and an optional note shown first (ui/nav/Routes.kt:55, ui/nav/MainShell.kt:399) (iPhone: the sign-in form as a full screen cover, in each of its modes with the note first)
- [x] `OctoAdminRoute` shows Octo admin; `ImportRoute` shows Import (ui/nav/MainShell.kt:402)
- [x] `FamilyRoute` shows Family; its Import action pushes `ImportRoute` (ui/nav/MainShell.kt:404)
- [x] `FamilyJoinRoute(link)` shows the sign-in form filled in from the parsed family link (ui/nav/MainShell.kt:405) (iPhone: the join form opens as a full screen cover filled in from the link)
- [x] `ChartsRoute`, `SoundRoute`, `SharesRoute`, `RadioStationsRoute` show Charts, Sound, Shares, Radio stations (ui/nav/MainShell.kt:406)
- [x] `HistoryRoute(mostPlayed)` shows plays by day, or most played when true (ui/nav/Routes.kt:97, ui/nav/MainShell.kt:410)
- [x] `LibraryHealthRoute`, `HealthCheckRoute(check)`, `HealthTrashRoute` show Library health, one check's songs, and Recently removed (ui/nav/MainShell.kt:411)
- [x] Routes are serializable values, so every tab's stack survives rotation and process death (ui/nav/Routes.kt:8) (iPhone: routes are Codable and every stack is kept in scene storage)

## 3. Arrivals from outside (family links, shares, widget, shortcuts)

- [x] A family notice tapped (action `OPEN_FAMILY`) opens Family: the shell switches to the Settings tab and pushes `FamilyRoute` on top of whatever that tab shows (MainActivity.kt:100, ui/nav/MainShell.kt:171) (iPhone: a tapped notice switches to Settings and pushes Family)
- [x] A family link opened (`octo://join`, `octo://signin`, `octo://handover`) switches to the Settings tab and pushes `FamilyJoinRoute` with the link in the app's own `octo://` form; the sign-in form opens filled in (MainActivity.kt:101, ui/nav/MainShell.kt:178) (iPhone: the link opens the join form as a full screen cover from its octo:// form)
- [x] The pending family open is consumed once (`opened()`) before navigating, so it never repeats (ui/nav/MainShell.kt:173) (iPhone: the open is taken once and cleared)
- [x] The Settings stack is pushed onto, not reset, so arriving twice pushes two pages (ui/nav/MainShell.kt:175)
- [x] An intent replayed from recents (launched from history) is ignored for family links, the widget's open-player, shares and shortcuts (MainActivity.kt:98, MainActivity.kt:110, ui/imports/ImportShare.kt:87) (iPhone: iOS never replays a link, a share, a widget tap or a quick action)
- [x] The intent the app was started with is not handled again after a rotation (only when there is no saved state) (MainActivity.kt:61) (iPhone: iOS hands each opening once)
- [x] When the app comes to the front, a family link on the clipboard is offered once per distinct clipboard text: a feedback line "A family invite is on the clipboard" (invite) or "A family sign-in link is on the clipboard" (other kinds) with the action "Use it", which opens the join form (MainActivity.kt:87, family/FamilyHub.kt:94) (iPhone: checked when the scene becomes active, after iOS's own pattern check)
- [x] Clipboard text is trimmed; blank or non-family text is ignored silently (family/FamilyHub.kt:95)
- [x] A list shared to Octo (`text/plain`, `text/csv`, `text/comma-separated-values`, as a file or as text) switches to the Settings tab and pushes `ImportRoute` unless Import is already on top; Import itself takes the share (ui/nav/MainShell.kt:185, ui/imports/ImportShare.kt:28)
- [x] A shared file wins over shared text, since apps often add a line of text to a file (ui/imports/ImportShare.kt:36)
- [x] A home screen widget's artwork or title asks for the full player; the request is a counter, so each tap counts even if the value was already set (MainActivity.kt:52, MainActivity.kt:108)
- [x] A request for the player sets the player open; it shows as soon as a song is loaded, and if nothing is loaded it stays pending and the player opens whenever a song next loads (ui/nav/MainShell.kt:203, ui/nav/MainShell.kt:319)
- [x] Launcher shortcuts (Shuffle all, Liked, Recently added, Resume) and "Open with Octo" play once the screen is resumed, then open the player when playback started; an empty source shows "No songs in your library yet", "No liked songs yet", or "Octo cannot open that file" instead (MainActivity.kt:66)
- [x] A voice request ("Play X on Octo") hands the words to the playback service; saying nothing in particular shuffles everything (MainActivity.kt:115) (iPhone: Siri and App Intents hand the words to the voice rules; no words shuffle everything)

## 4. Page motion

- [x] Opening a page: the new page slides in from 32% of the screen width to the right while the old page drifts 12% of the width to the left; slide 380 ms on easing cubic (0.2, 0.8, 0.2, 1) (ui/nav/PageMotion.kt:24, ui/nav/PageMotion.kt:51)
- [x] Opening a page: the new page fades in over 180 ms after a 40 ms delay; the old page fades out over 140 ms; both fades use cubic (0.2, 0.8, 0.2, 1) (ui/nav/PageMotion.kt:28, ui/nav/PageMotion.kt:53)
- [x] Going back (button, or a finished back gesture) runs the same move mirrored: the arriving page comes from 32% to the left, the leaving page drifts 12% to the right, same durations and fades (ui/nav/PageMotion.kt:36)
- [x] Popping a tab to its root by reselecting it uses the back move (ui/nav/MainShell.kt:276)
- [x] While the back gesture is held, the back move runs with linear easing so the page sits exactly where the finger has taken it (interactive back) (ui/nav/PageMotion.kt:40, ui/nav/MainShell.kt:277)
- [x] Changing tab: the new tab fades in over 220 ms after a 40 ms delay (default easing) while scaling from 0.97 to 1 over 260 ms on cubic (0.2, 0.8, 0.2, 1); the old tab fades out over 100 ms (default easing); nothing slides (ui/nav/PageMotion.kt:43)
- [x] A change counts as a tab change only on the frame the selected tab differs from the last one drawn; a family link or share that switches tab and pushes a page together uses the tab motion (ui/nav/MainShell.kt:147, ui/nav/MainShell.kt:275)
- [x] Reduce motion: opening and going back only cross-fade, nothing travels: fade in 90 ms, fade out 70 ms (180 and 140 halved), default easing (ui/nav/PageMotion.kt:49)
- [x] Reduce motion: changing tab has no scale (0.97 becomes 1.0) and its times halve: fade in 110 ms after 20 ms, fade out 50 ms (ui/nav/PageMotion.kt:44, design/OctoMotion.kt:105)
- [~] Turned sideways, pages are padded horizontally clear of the camera cutout and a side navigation bar; the ambient glow behind them still fills the whole screen (ui/nav/MainShell.kt:274, ui/nav/MainShell.kt:357) (not on iPhone: the iPhone app is held upright (portrait only in Info.plist), so there is no sideways layout; Brandon to confirm)

## 5. Shell layers, in drawing order

- [x] Layer 1, inside the frosting source: the ambient glow, then the pages (`NavDisplay`) over it; both are what the bar and other floating glass frost (ui/nav/MainShell.kt:267) (iPhone: the glow sits behind each page; Liquid Glass reads whatever lies beneath it)
- [x] Layer 2: the floating bottom bar, aligned bottom center (ui/nav/MainShell.kt:285)
- [x] Layer 3: the downloads pill, aligned bottom end (ui/nav/MainShell.kt:310)
- [x] Layer 4: the full player, over the bar and pages (ui/nav/MainShell.kt:318)
- [x] Layer 5: the song menu host, which first draws the selection bar (so the selection bar is above the bar, the pill and even the player) and then the song menu popup (ui/nav/MainShell.kt:342, ui/menu/SongMenuPopup.kt:89)
- [x] Layers 6 to 11: playlist sheets, disconnect sheet, choice sheet, share sheet, family request sheet, server downloads sheet, in that order (ui/nav/MainShell.kt:343) (iPhone: system sheets, in iOS's own presentation order)
- [x] Layer 12, last: the feedback toast, above the sheets so an Undo stays reachable while one is open (ui/nav/MainShell.kt:350) (iPhone: messages float in a window of their own above every sheet)
- [x] Glass popups (song menu, choice sheet) are separate windows and so sit above all of these, the toast included (design/GlassPopup.kt:187) (iPhone: system menus and popovers; the message window floats above everything)
- [x] There are two frosting sources: the page layer (`haze`) and the full player (`playerHaze`); the song menu frosts the player while the player is open and showing a song, and the page otherwise (ui/nav/MainShell.kt:133, ui/nav/MainShell.kt:342) (iPhone: Liquid Glass frosts whatever lies beneath it, pages or player)
- [x] Any press anywhere in the shell records the finger's point as the fallback spot for a menu or card it opens (whole-area press spot) (ui/nav/MainShell.kt:264) (iPhone: system menus and popovers anchor to the control that opened them)
- [x] The full player and the bar are wrapped in one shared-transition scope so the artwork can fly between them (ui/nav/MainShell.kt:262) (iPhone: the cover flies between bar and player in a layer above both)

## 6. Bottom bar: frame and geometry

- [x] The bar is 56 dp tall (`BarHeight`) (ui/nav/BottomBar.kt:90)
- [x] It floats 14 dp above the bottom inset (`BarBottomGap`), above the system navigation bar's inset (ui/nav/BottomBar.kt:93, ui/nav/BottomBar.kt:132)
- [x] It has 20 dp side margins and is at most 520 dp wide inside them, centered (so on a wide or sideways screen it stays a centered 520 dp bar) (ui/nav/BottomBar.kt:133, ui/nav/MainShell.kt:289)
- [x] The bar is two separate glass pieces with a 10 dp gap: the tab tray on the left and the now-playing glass on the right (ui/nav/BottomBar.kt:95, ui/nav/BottomBar.kt:138)
- [x] Full tray width = bar width minus 56 minus 10; open, the tray takes that width and the right glass is a 56 dp circle (ui/nav/BottomBar.kt:138)
- [x] Grown into the small player, the tray shrinks to a 56 dp circle and the right glass takes the full tray width; the two swap sizes exactly (ui/nav/BottomBar.kt:139, ui/nav/BottomBar.kt:145)
- [x] The shape change is one value `grown` from 0 to 1 on `spring(0.75, 200)`; it overshoots (goes past 1 and below 0), and the widths follow it unclamped while alphas clamp it to 0..1 (ui/nav/BottomBar.kt:125, ui/nav/BottomBar.kt:139)
- [x] The shape spring is not shortened by Reduce motion (ui/nav/BottomBar.kt:125)
- [x] Both glass pieces are floating glaze capsules (fully round ends) that frost the page layer, with the film described in section 11 (ui/nav/BottomBar.kt:141, ui/nav/BottomBar.kt:198) (iPhone: two Liquid Glass capsules tinted with the film)
- [x] The keyboard does not move the bar: it takes only the navigation bar inset, never the keyboard's, and the keyboard covers it (ui/nav/BottomBar.kt:132)
- [x] While the full player is open the bar is hidden: it fades out over 300 ms as the player opens and fades back in over 300 ms as it closes (default easing) (ui/nav/MainShell.kt:285)
- [x] Rotation keeps whether the small player was showing (`barPlayer` is saved state) (ui/nav/MainShell.kt:193) (iPhone: kept in scene storage)

## 7. Bottom bar: tab tray

- [x] The tray's tabs are laid out in a row of the full tray width with 6 dp side padding, four equal columns; column width = (full tray width - 12) / 4 (ui/nav/BottomBar.kt:211, ui/nav/BottomBar.kt:242)
- [x] Each tab is an icon only, 23 dp, centered in its column, the whole column height (56 dp) tappable, with no press ripple or highlight (ui/nav/BottomBar.kt:94, ui/nav/BottomBar.kt:292)
- [x] Tab icons, Phosphor: Home `house` (selected `house` fill), Search `magnifying-glass` (selected fill), Library `cards` (selected fill), Settings `gear` (selected fill) (ui/nav/BottomBar.kt:83, design/OctoIcons.kt:117, icons.json) (iPhone: SF Symbols house, magnifyingglass, square.stack and gearshape, filled for the selected tab)
- [x] Unselected tabs are white; the selected tab shows its filled icon in the accent `#97B1B9`; the color change animates with Compose's default color spring (damping 1, stiffness 1500) (ui/nav/BottomBar.kt:286)
- [x] The selected tab sits in a darker pill: 62 dp wide, 44 dp tall, black at 72%, fully rounded, unlit (no glass lighting) (ui/nav/BottomBar.kt:212, ui/nav/BottomBar.kt:230, design/Glaze.kt:68)
- [x] The pill's x = 6 + column x index + (column - 62) / 2, centered on its tab, vertically centered (ui/nav/BottomBar.kt:214)
- [x] The pill glides between tabs on `spring(0.8, 350)` (ui/nav/BottomBar.kt:215)
- [x] The pill and tabs are clipped to the tray's capsule shape (ui/nav/BottomBar.kt:224)
- [x] Each tab's accessibility label is its name ("Home", "Search", "Library", "Settings"); the tab has no role and no selected state in code (ui/nav/BottomBar.kt:295, ui/nav/BottomBar.kt:305) (iPhone: each tab is labeled by its name, with iOS's button and selected traits)
- [x] Tabs cannot be tapped while the tray is folded (ui/nav/BottomBar.kt:254)

## 8. Bottom bar: folding the tray

- [x] Folding (as the small player grows), the tabs row keeps its full width and is clipped by the shrinking tray, so tabs slide under the folding edge rather than squeezing (ui/nav/BottomBar.kt:235)
- [x] The tabs row fades with 1 - folded (ui/nav/BottomBar.kt:243)
- [x] The selected pill slides left to x = 0 (lerp from its tab position by folded), widens from 62 to 56 dp, grows from 44 to 56 dp tall, and fades with 1 - folded, so it swells into the whole circle (ui/nav/BottomBar.kt:221)
- [x] While folding, the selected tab's icon is hidden in the row (alpha 0) and instead one copy rides the pill: 23 dp, offset x = pill x + (pill width - 23) / 2, vertically centered (ui/nav/BottomBar.kt:253, ui/nav/BottomBar.kt:260)
- [x] The riding icon is the selected tab's filled icon, tinted from accent to white as folded goes 0 to 1, so the folded circle reads like the white round button at the other end (ui/nav/BottomBar.kt:266)
- [x] "Open" means folded at or below 0 (the spring overshoots below 0); at exactly 0 the row's icon is shown, never both copies hidden (ui/nav/BottomBar.kt:249)
- [x] Folded fully, the tray is one glass circle with the white selected-tab icon (ui/nav/BottomBar.kt:260)
- [x] Tapping the folded circle unfolds the tabs (shows the tab tray, folds the small player back to the round button); no ripple; role Button; label "Show tabs" (ui/nav/BottomBar.kt:202, ui/nav/BottomBar.kt:263, ui/nav/MainShell.kt:218)

## 9. Bottom bar: round now-playing button

- [x] Open, the right glass is a 56 dp circle holding the now-playing face (ui/nav/BottomBar.kt:150, ui/nav/NowPlayingFace.kt:30)
- [x] With artwork: the artwork as a 44 dp circle (56 - 12), with a black 35% circle over it so the sign reads (ui/nav/NowPlayingFace.kt:32)
- [x] With no artwork: no picture and no dim, just the sign on the glass (ui/nav/NowPlayingFace.kt:32)
- [x] The sign is a 22 dp white pause glyph while playing, a 22 dp white play icon (Phosphor `play` fill drawn at 0.8) otherwise (ui/nav/NowPlayingFace.kt:37) (iPhone: SF Symbols pause.fill and play.fill, 22 points, white)
- [x] The pause glyph is two rounded bars on Phosphor's 256 grid scaled by 0.8 about the middle: bars at x 40 and 144, y 32, each 72 x 192, corner radius 16 grid units (design/Glyphs.kt:18) (iPhone: SF Symbol pause.fill)
- [x] With a song loaded, a progress ring is drawn 3 dp in from the 56 dp edge: accent `#97B1B9`, 2 dp stroke, round caps, starting at 12 o'clock and sweeping clockwise 360 x fraction (ui/nav/NowPlayingFace.kt:42, ui/nav/NowPlayingFace.kt:51)
- [x] With no song loaded there is no ring (ui/nav/NowPlayingFace.kt:42)
- [x] Progress fraction = position / duration clamped to 0..1, and 0 when duration is 0 (player/Position.kt:28)
- [x] The position is re-read every frame while playing, so the ring glides; when paused it is read once on each change of song, play state or duration (player/Position.kt:17)
- [x] While casting, a cast mark sits in the bottom-right corner, 2 dp in: an 18 dp black 72% circle holding the Phosphor `screencast` fill icon at 11 dp, white (ui/nav/NowPlayingFace.kt:44, ui/output/OutputSheet.kt:255) (iPhone: while the sound plays on an AirPlay device, an AirPlay mark sits in that corner as described)
- [x] Tapping the round button with a song loaded grows the small player in the bar (does not open the full player) (ui/nav/MainShell.kt:217)
- [x] Tapping the round button with nothing loaded shuffles the whole library (play/pause with an empty queue plays every library song shuffled) (ui/nav/MainShell.kt:217, playback/PlaybackConnection.kt:173)
- [x] The round button has no press ripple or highlight; role Button; accessibility label "Now playing"; no play state is announced (ui/nav/BottomBar.kt:156, ui/nav/BottomBar.kt:163)
- [x] The round button cannot be tapped while the small player is shown (ui/nav/BottomBar.kt:157)
- [x] The round button's face fades with 1 - grown and is removed once grown reaches 1 (ui/nav/BottomBar.kt:150, ui/nav/BottomBar.kt:155)

## 10. Bottom bar: small player (capsule)

- [x] The capsule shows while grown is above 0, filling the right glass, clipped to a capsule, fading in with grown (ui/nav/BottomBar.kt:168, ui/nav/BottomBar.kt:176)
- [x] Its row is laid out at the full tray width and clipped, so it slides out from under the edge as the glass grows; 6 dp start and 4 dp end padding, items vertically centered (ui/nav/BottomBar.kt:335)
- [x] First: a 44 dp box holding the artwork at 36 dp and the progress ring over the box inset 1 dp (42 dp ring, 2 dp accent stroke, round caps, from 12 o'clock) (ui/nav/BottomBar.kt:344)
- [x] The artwork is a circle while the bar is shown (corner 50%); it is the shared element that flies to and from the full player (ui/nav/MainShell.kt:293, ui/nav/MainShell.kt:303) (iPhone: the cover is round in the bar and flies to the player's card in a layer above both)
- [x] A song found online and not in the library carries the "not in your library" mark on that artwork (section 31) (ui/nav/BottomBar.kt:345)
- [x] Then the text column, taking the rest, 10 dp horizontal padding: the title on one line in 13.5 sp SemiBold white, ellipsized before the explicit mark so the mark always shows (ui/nav/BottomBar.kt:348, ui/common/SongTitle.kt:31)
- [x] An explicit song shows the "E" mark 6 dp after the title in TextMuted (section 29) (ui/common/SongTitle.kt:34)
- [x] Under the title the artist, 11 sp regular, TextMuted (accent at 80%), one line, ellipsized; a missing title or artist shows as empty (ui/nav/BottomBar.kt:355)
- [x] Then three 36 dp buttons with 28 dp white icons: Previous (Phosphor `skip-back` fill at 0.8), Play or Pause (`play` / `pause` fill at 0.8, by play state), Next (`skip-forward` fill at 0.8) (ui/nav/BottomBar.kt:363, icons.json) (iPhone: SF Symbols backward.fill, play.fill or pause.fill, forward.fill, 28 points, white)
- [x] The buttons have no ripple or highlight; role Button; labels "Previous", "Pause" or "Play", "Next" (ui/nav/BottomBar.kt:371)
- [x] Previous, play/pause and next call the player directly; previous follows the player's rule (restart or go back) (ui/nav/MainShell.kt:220)
- [x] Tapping anywhere else on the capsule opens the full player; no ripple; role Button with click label "Open player" (ui/nav/BottomBar.kt:327)
- [x] When the queue empties (no song), the small player folds back and the full player closes (ui/nav/MainShell.kt:196)

## 11. Bottom bar: swipes, haptics and glass film

- [x] Swipes work on the right glass in both shapes (round button and capsule); with no song loaded there are no swipes (ui/nav/BottomBar.kt:147, ui/nav/BottomBar.kt:407)
- [x] A drag's axis is decided once, at the first movement past the platform touch slop measured as distance (diagonal counts), the larger component winning and a tie counting as vertical (ui/common/Swipes.kt:22, ui/common/Swipes.kt:67)
- [x] Lifting before the slop is a tap for whatever is under the finger; once an axis is taken the drag is consumed and the tap underneath does not fire (ui/common/Swipes.kt:63, ui/common/Swipes.kt:69)
- [x] Sideways: left skips to the next song, right to the previous one (ui/nav/BottomBar.kt:431)
- [x] Sideways skips when the finger has gone 56 dp or more, or when flicked at 700 dp/s or faster in the same direction it was already going; a flick back toward the start stays (ui/nav/BottomBar.kt:409, ui/common/Swipes.kt:33)
- [x] Past 56 dp it still skips even if let go while moving back (ui/common/Swipes.kt:34)
- [x] Up opens the full player when pulled up 28 dp or more, or flicked up at 700 dp/s or faster while already going up (ui/nav/BottomBar.kt:410, ui/common/Swipes.kt:41)
- [x] While dragging, the contents (not the glass) lean with the finger at 0.3 of its travel, sideways, and upward only (a downward drag does not lean) (ui/nav/BottomBar.kt:403, ui/nav/BottomBar.kt:441)
- [x] One haptic tick (gesture threshold activate) when the finger first passes the point where letting go acts (56 dp sideways either way, 28 dp up); no tick when it comes back under; the tick can fire again after coming back and going past again (ui/nav/BottomBar.kt:414) (iPhone: one sensory feedback impact as the finger passes the point)
- [x] After a sideways release (skip or not) the lean springs back to 0 on `spring(0.8, 400)` (ui/nav/BottomBar.kt:420, ui/nav/BottomBar.kt:436)
- [x] After an up release that opens the player the lean snaps to 0 at once; one that does not springs back on `spring(0.8, 400)` (ui/nav/BottomBar.kt:445)
- [x] A drag taken over by something else ends as if it went nowhere (settles back, no action) (ui/common/Swipes.kt:85)
- [x] There is no haptic on taps of tabs, the round button or capsule buttons (ui/nav/BottomBar.kt:292)
- [x] The glass film of both bar pieces is the glaze tint, black at 16%, by default (design/Glaze.kt:59, ui/nav/BottomBar.kt:123) (iPhone: the black 16% film tints the bar's Liquid Glass)
- [x] With the ambient bar tint on (strength not Off, "Mini player and bar" on) and a song loaded, the film is the song's first mesh colour, clamped to lightness 0.5 and saturation 0.55, at 6% (Subtle) or 10% (Rich), laid over the black 16% film (ambient/AmbientLayer.kt:185, ambient/AmbientLayer.kt:196, ambient/AmbientPrefs.kt:49)
- [x] The bar film changes over 800 ms (default easing) when the song or setting changes; before settings are read it is the plain film (ambient/AmbientLayer.kt:192)

## 12. Opening and closing the full player from the shell

- [x] The player shows only while it is asked open and a song is loaded; it fades in over 400 ms and out over 300 ms (default easing) (ui/nav/MainShell.kt:318)
- [x] Opening from the capsule, the capsule's 36 dp circular artwork flies into the player's artwork card (shared element, Compose's default bounds spring: damping 1, stiffness 400) (ui/nav/MainShell.kt:303, ui/nav/MainShell.kt:325) (iPhone: the cover flies from the capsule into the card in a layer above both)
- [x] During the flight the bar side's corner animates from a circle (50%) to the player's soft square (3% of the side) as the bar leaves, and back to 50% as it returns; the player side mirrors it (3% when shown, 50% when leaving) (ui/nav/MainShell.kt:293, player/PlayerOverlay.kt:672) (iPhone: the flying cover's corners round from a circle to the card's soft square and back)
- [x] Those corner changes use the visibility transition's default spring (damping 1, stiffness 1500) (ui/nav/MainShell.kt:293) (iPhone: the corners follow the flight's own animation)
- [x] The shared key is one constant for whichever song is on, so a song change mid-flight does not break the hand-off (ui/nav/MainShell.kt:362) (iPhone: one flight for whichever song is on)
- [x] Opening by swiping up on the round button (no capsule shown) has no artwork in the bar to fly from; the player just fades in (ui/nav/BottomBar.kt:150, ui/nav/BottomBar.kt:168)
- [x] Closing the player returns the bar in the shape it had (round button or capsule) (ui/nav/MainShell.kt:194)
- [x] The player's artist, album and Sound shortcuts close the player then push Artist, Album or Sound onto the current tab (ui/nav/MainShell.kt:327)
- [x] Going to a page from the song menu also closes the player first (ui/nav/MainShell.kt:242)
- [x] Whether the player is open survives rotation (ui/nav/MainShell.kt:194) (iPhone: kept in scene storage)
- [x] While the player is open the ambient glow stops drifting (it rests under the cover) (ui/nav/MainShell.kt:268)

## 13. Downloads pill

- [x] The pill shows only while one or more songs are on their way into the library and the signed-in server keeps a downloads list (an Octo server listing `octoAcquisitions` at version 2); never on plain Subsonic, never signed out (ui/downloads/DownloadsPill.kt:123, data/ServerDownloads.kt:56)
- [x] It sits at the bottom right, 20 dp from the right edge and 80 dp above the bottom inset (14 gap + 56 bar + 10), just above the bar (ui/nav/MainShell.kt:316)
- [x] It is hidden with the bar while the player is open (fade out 300 ms, fade in 300 ms) (ui/nav/MainShell.kt:310)
- [x] It is 36 dp tall, at most 280 dp wide, a capsule of the floating glaze (bar glass), clipped to the capsule so its outer shadows do not show (ui/downloads/DownloadsPill.kt:128) (iPhone: a Liquid Glass capsule, 36 tall, at most 280 wide)
- [x] Its width changes animate over 200 ms on cubic (0.2, 0.8, 0.2, 1), 100 ms with Reduce motion (ui/downloads/DownloadsPill.kt:136)
- [x] Contents, 8 dp apart, vertically centered: 8 dp start padding; end padding 6 dp when a "+N" chip shows, 14 dp otherwise (ui/downloads/DownloadsPill.kt:139)
- [x] First a 20 dp download ring for the lead song's step (section 33) (ui/downloads/DownloadsPill.kt:143)
- [x] Then the step words in 12 sp white, one line: "Waiting", "Searching", "Downloading 42%" (or "Downloading" with no fraction), "Checking", "Adding" (shared/ui/downloads/Downloads.kt:277)
- [x] With no listed lead song (only asks the server has not listed yet), the words are "1 downloading" or "N downloading" (ui/downloads/DownloadsPill.kt:100)
- [x] The step words cross-fade on change, 160 ms in and 160 ms out (80 ms each with Reduce motion) (ui/downloads/DownloadsPill.kt:144)
- [x] Then the lead song's title in 12 sp, accent colour, one line, ellipsized, shrinking first when space runs out (ui/downloads/DownloadsPill.kt:149)
- [x] Then, when more than one song is coming, a "+N" chip: 12 sp white, white 12% capsule, 7 dp by 2 dp padding; N = the pill's count minus one (ui/downloads/DownloadsPill.kt:152)
- [x] The lead song is the running row furthest along by phase (Adding > Checking > Downloading > Searching > Waiting), ties broken by the earliest start (shared/ui/downloads/Downloads.kt:271)
- [x] The count = the server list's running rows plus songs asked for on this device that no running row shows yet and are still taken as on their way (shared/ui/downloads/Downloads.kt:324)
- [x] An ask not listed counts for at most 2 minutes, and stops counting as soon as a list asked for after it comes back without it (shared/ui/downloads/Downloads.kt:294, shared/ui/downloads/Downloads.kt:309)
- [x] An ask made with its whole album counts for up to 30 minutes regardless of lists (shared/ui/downloads/Downloads.kt:299)
- [x] The count is re-worked at the moment the oldest counted ask runs out, with no new data needed (ui/downloads/DownloadsPill.kt:69, shared/ui/downloads/Downloads.kt:329)
- [x] The ring for the lead row: Downloading with its fraction fills; Checking and Adding show full and pulsing; anything else (Waiting, Searching) turns as waiting (ui/downloads/DownloadsPill.kt:104)
- [x] Tapping opens the server downloads sheet on its list, from any page; nothing opens by itself (ui/downloads/DownloadsPill.kt:91, ui/downloads/DownloadsPill.kt:134)
- [x] The tap shows the platform press ripple clipped to the capsule (ui/downloads/DownloadsPill.kt:134) (iPhone: Liquid Glass's own interactive press)
- [x] Accessibility: one merged element, role Button, click label "Show server downloads", read as "<spoken>. Show server downloads" (ui/downloads/DownloadsPill.kt:134)
- [x] Spoken text with a lead: "<step words>, <title>" plus ". N more on the way" when the server's running rows number more than one (unlisted asks are not counted here, unlike the "+N" chip) (shared/ui/downloads/Downloads.kt:340)
- [x] Spoken text with no lead: "N downloading" (ui/downloads/DownloadsPill.kt:126)
- [x] The ring stays still (no turn, pulse, fill easing or check morph) when Octo's Reduce motion is on or the phone's animations are off (ui/downloads/DownloadsPill.kt:122)
- [x] The feedback toast sits at the same height and draws over the pill when both show (ui/common/Feedback.kt:122, ui/nav/MainShell.kt:350) (iPhone: the message floats in its own window above the pill)

## 14. Feedback toasts

- [x] One message at a time; a new one replaces the one showing at once (the words swap, no exit animation between them); the same text shown twice counts as a new message (ui/common/Feedback.kt:59, ui/common/Feedback.kt:110)
- [x] Kinds: plain text; text with an action (Undo for an undoable change); a done line with a white check icon (ui/common/Feedback.kt:78, ui/common/Feedback.kt:83, ui/common/Feedback.kt:86)
- [x] Only for what the listener did and can undo, or something they asked for that did or did not happen (ui/common/Feedback.kt:70)
- [x] It stays 3.5 s, or 6 s when it has an action, counted from when its entrance finishes (ui/common/Feedback.kt:56, ui/common/Feedback.kt:113)
- [x] It dismisses only itself: a newer message shown meanwhile is not cleared by the old timer (ui/common/Feedback.kt:88)
- [x] Position: bottom center, 20 dp side margins, its bottom 80 dp above the bottom inset (14 + 56 + 10), the same whether the bar is visible or not; at most 520 dp wide; at least 48 dp tall (ui/common/Feedback.kt:96, ui/common/Feedback.kt:122, ui/common/Feedback.kt:138)
- [x] It does not move for the keyboard (ui/common/Feedback.kt:122)
- [x] Glass: the floating glaze (bar glass) as a capsule, frosting the page layer (ui/common/Feedback.kt:124) (iPhone: a floating Liquid Glass capsule)
- [x] Row padding: start 16 dp with an icon, 20 dp without; end 6 dp with an action, 20 dp without; 12 dp top and bottom; items 10 dp apart, centered (ui/common/Feedback.kt:152)
- [x] Icon 18 dp white (ui/common/Feedback.kt:162)
- [x] Text 14 sp Medium white, up to 2 lines, ellipsized, wrapping to its content up to the space left (ui/common/Feedback.kt:164)
- [x] Action: 14 sp SemiBold white, in a capsule touch area with 14 by 8 dp padding and the platform ripple; tapping runs the action then dismisses (ui/common/Feedback.kt:174) (iPhone: a light press highlight in the action's capsule)
- [x] Tapping a message with no action dismisses it (no ripple); a message with an action is only dismissed by its action or its timer (ui/common/Feedback.kt:142)
- [x] Entrance: alpha 0 to 1, scale 0.92 to 1 and a rise from 10 dp lower, from the bottom center, on `spring(0.85, 500)` (ui/common/Feedback.kt:113, ui/common/Feedback.kt:127)
- [x] Exit: back to 0 over 160 ms on FastOutLinearIn, cubic (0.4, 0, 1, 1), then removed (ui/common/Feedback.kt:117)
- [x] With the phone's animations off (only that, not Octo's Reduce motion) it only fades: in and out over 120 ms, no scale or rise (ui/common/Feedback.kt:105, ui/common/Feedback.kt:130) (iPhone: the phone's Reduce Motion stands in for animations off)
- [x] Accessibility: a polite live region, so the line is read out when it appears (ui/common/Feedback.kt:140) (iPhone: a VoiceOver announcement as it appears)

## 15. Selection mode and the selection bar

- [x] A list that can pick songs registers with the shell's selection bar while it is on screen; only the list on screen can be picking (ui/common/Selection.kt:94)
- [x] Nothing picked means not selecting; picking starts with one song, a tap toggles, and taking the last one off ends selection (ui/common/Selection.kt:23)
- [x] A song is picked by its id, or by its row key on a playlist where a song can appear twice (ui/common/Selection.kt:19)
- [x] Songs that leave the list leave the picks (ui/common/Selection.kt:30, ui/common/Selection.kt:112)
- [x] Actions act on the picked songs in the list's order, not the order they were picked (ui/common/Selection.kt:33)
- [x] Leaving the list's page clears its picks (ui/common/Selection.kt:107)
- [x] The selection bar appears whenever a registered list has picks, drawn over the bottom bar in its place (the bottom bar stays underneath) (ui/common/SelectionBar.kt:83, ui/menu/SongMenuPopup.kt:88)
- [x] It enters with a fade plus a slide up from half its height below, and leaves the same way down; both use Compose's default enter and exit spring (damping 1, stiffness 400), not shortened by Reduce motion (ui/common/SelectionBar.kt:100)
- [x] While it leaves it keeps drawing the last picks (ui/common/SelectionBar.kt:97)
- [x] Back, the close button, taking the last song off, or any action ends the picking (ui/common/SelectionBar.kt:83, ui/common/SelectionBar.kt:132)
- [x] Frame: floating glaze (bar glass) with 28 dp corners, 20 dp side margins, 14 dp above the bottom inset, at most 520 dp wide, full width inside; 6 dp padding all round (ui/common/SelectionBar.kt:60, ui/common/SelectionBar.kt:137) (iPhone: floating Liquid Glass with 28 point corners)
- [x] It does not move for the keyboard and is not hidden by the player (it sits above the player) (ui/common/SelectionBar.kt:140, ui/nav/MainShell.kt:342)
- [x] Top row: a 44 dp close button (Phosphor `x`), label "Stop selecting" (ui/common/SelectionBar.kt:148) (iPhone: SF Symbol xmark)
- [x] Top row: the count, 14 sp regular white, 4 dp after the close button, taking the free width: "1 selected" or "N selected"; a polite live region, so changes are read out (ui/common/SelectionBar.kt:149) (iPhone: the count is marked as updating, so VoiceOver reads its changes)
- [x] Top row: when every picked song is a file on the phone (and none is a song found online), a 44 dp share button (Phosphor `file-audio`), "Share file" for one, "Share files" for more (ui/common/SelectionBar.kt:156) (iPhone: SF Symbol square.and.arrow.up.on.square)
- [x] Top row: one delete button (Phosphor `trash`), shown in one of three ways (ui/common/SelectionBar.kt:161) (iPhone: SF Symbol trash)
- [x] Delete when every picked song is on the phone and also on the server's disk (and the server lets this user delete): label "Delete"; tapping ends selection and opens a choice titled "Delete" beside the button with "Delete from phone" and "Delete from disk", none preselected; the first deletes the phone files, the second asks before deleting from the server's disk (ui/common/SelectionBar.kt:162, shared/health/FixWords.kt:8) (iPhone: a system menu titled Delete with Delete from phone and Delete from disk)
- [x] Delete when every picked song is on the phone only: label "Delete from phone", deletes the phone files (ui/common/SelectionBar.kt:171)
- [x] Delete when every picked song is a library song on the server's disk and the server lets this user: label "Delete from disk", asks before deleting (ui/common/SelectionBar.kt:172)
- [x] No delete button otherwise (ui/common/SelectionBar.kt:161)
- [x] Bottom row, equal-width 44 dp tall buttons: Play (Phosphor `play` fill at 0.8), "Play"; plays the picked songs from the first (ui/common/SelectionBar.kt:177) (iPhone: SF Symbol play.fill)
- [x] Bottom row: Play next (`rows-plus-top`), "Play next" (ui/common/SelectionBar.kt:178) (iPhone: SF Symbol for play next)
- [x] Bottom row: Add to queue (`rows-plus-bottom`), "Add to queue" (ui/common/SelectionBar.kt:179) (iPhone: SF Symbol for add to queue)
- [x] Bottom row: Add to playlist (`music-notes-plus`), "Add to playlist", opens the playlist picker for the library songs; dimmed and disabled when only songs found online are picked (ui/common/SelectionBar.kt:180)
- [x] Bottom row: Download (`download-simple`), "Download", downloads the library songs that are only on a server; disabled when none is (ui/common/SelectionBar.kt:183)
- [x] Bottom row: Like, "Add to Liked songs" (`heart`), or "Remove from Liked songs" (`heart` fill) when every picked library song is liked; it sets every one to the same state, touching only those that differ; disabled when only finds are picked (ui/common/SelectionBar.kt:184, ui/common/SelectionBar.kt:78) (iPhone: SF Symbols heart and heart.fill)
- [x] Bottom row: on a playlist page only, Remove (`music-notes-minus`), "Remove from this playlist" (ui/common/SelectionBar.kt:190)
- [x] Each button: 22 dp icon, white, or TextMuted at 35% (accent at 28%) when disabled; platform ripple bounded to the button's rectangle; role Button; labelled for screen readers (ui/common/SelectionBar.kt:201) (iPhone: a light press highlight in the button's rectangle)

## 16. Choice sheet and glass menus

- [x] Any page can ask a question with a few answers; it pops up as a glass popup beside the control that asked, or centered when none did (ui/common/ChoiceSheet.kt:59) (iPhone: a system menu beside the control that asked, or a system confirmation dialog)
- [x] The control that asked is found from an explicit anchor, or the last control marked as a choice anchor pressed within the last 2 s (ui/common/ChoiceSheet.kt:80, ui/common/ChoiceSheet.kt:100) (iPhone: the system menu opens from its own control)
- [x] The popup's accessibility pane title is the question's title, or "Sort by" for a sort (ui/common/ChoiceSheet.kt:148) (iPhone: the system menu carries the question as its title)
- [x] The answers list is 220 to 320 dp wide (as wide as its widest line within that), padded 6 dp, with the title on top (13.5 sp SemiBold, accent colour, padding 14 dp sides, 10 top, 6 bottom) (ui/common/ChoiceSheet.kt:164, ui/common/GlassMenu.kt:89) (iPhone: the system menu with the title over its answers)
- [x] Answers scroll when taller than the popup may be (ui/common/ChoiceSheet.kt:174) (iPhone: the system menu scrolls when long)
- [x] Picking an answer runs it, then closes the list (ui/common/ChoiceSheet.kt:170)
- [x] Each answer row: at least 40 dp tall, 14 dp corners, padding 14 by 10 dp, label 14 sp white, optional detail line 12 sp TextMuted (ui/common/GlassMenu.kt:119, design/OctoTokens.kt:93) (iPhone: system menu items, with the detail as each item's subtitle)
- [x] The chosen answer sits in the darker pill (black 72%, 14 dp corners) with an 18 dp white check at its end; every pickable row keeps the check's 18 dp room so the width never depends on the choice (ui/common/GlassMenu.kt:138, ui/common/GlassMenu.kt:150) (iPhone: the system checkmark on the chosen answer)
- [x] A disabled answer is TextMuted, with its detail saying why, and cannot be picked (ui/common/ChoiceSheet.kt:38, ui/common/GlassMenu.kt:145) (iPhone: a disabled system menu item, its subtitle saying why)
- [x] Hairlines 1 dp, white at 8%, inset 14 dp each side, between rows; no hairline touches the chosen row; the 1 dp is kept even when not drawn so rows never shift (ui/common/GlassMenu.kt:56, ui/common/GlassMenu.kt:99) (iPhone: the system menu's own separators)
- [x] A row under the finger shows the press pill at once (accent selected tint at 55%), not on the chosen row; no ripple (ui/common/GlassMenu.kt:112, ui/common/GlassMenu.kt:126, design/OctoColors.kt:46) (iPhone: the system menu's own press highlight)
- [x] With a chosen answer the rows are radio buttons in a group; with none chosen (selected below 0) they are plain buttons (ui/common/GlassMenu.kt:78, ui/common/GlassMenu.kt:130) (iPhone: picker items with a checkmark when one is chosen, plain buttons when none is)
- [x] Menu kit, width: a glass menu page is 288 dp wide, padded 6 dp, with a fixed header and a scrolling body (ui/common/GlassMenu.kt:70, ui/common/GlassMenu.kt:162) (iPhone: system menus and their submenus)
- [x] Menu kit, action row: at least 40 dp tall, padding 14 by 8 dp, 14 dp gaps, 20 dp white icon (TextMuted when disabled), label 14 sp white (soft red `#FF3B30` at 85% when destructive, TextMuted when disabled, icon stays white), optional 12 sp TextMuted detail, an 18 dp TextMuted chevron (`caret-right`) when it opens a page; press pill as above (ui/common/GlassMenu.kt:202) (iPhone: system menu actions with SF Symbols; destructive ones in red)
- [x] Menu kit, header: picture, then title 14 sp SemiBold white up to 2 lines and subtitle 12 sp TextMuted one line; padding 10 dp sides, 6 top, 8 bottom, 12 dp gap (ui/common/GlassMenu.kt:255) (iPhone: a system menu's title and subtitle)
- [x] Menu kit, back row: an 18 dp white `caret-left` and the page title 13.5 sp SemiBold white one line, a heading for screen readers, click label "Back", padding 6 start 14 end, then a separator (ui/common/GlassMenu.kt:280) (iPhone: a system submenu's own back)
- [x] Menu kit, heading with nothing to go back to: 13.5 sp SemiBold white, up to 2 lines, padding 14 sides, 10 top, 6 bottom, a heading (ui/common/GlassMenu.kt:310) (iPhone: a system menu's title)
- [x] Menu kit, group separator: 1 dp white 8%, inset 14 dp sides, 4 dp above and below; empty groups are left out (ui/common/GlassMenu.kt:177, ui/common/GlassMenu.kt:186) (iPhone: system menu sections and their separators)
- [x] Menu kit, note: 12 sp TextMuted with 14 by 8 dp padding (ui/common/GlassMenu.kt:323) (iPhone: a disabled note row or section footer in the system menu)

## 17. Press spot: where menus open

- [x] Every press records what it landed on, before any click or long press runs, so a menu or card opened by it pops up beside it (ui/common/PressSpot.kt:59, ui/common/PressSpot.kt:103) (iPhone: system menus and popovers anchor to the control that opened them)
- [x] A marked control narrower than half the screen is its own anchor rectangle (ui/common/PressSpot.kt:29) (iPhone: system menus and popovers anchor to the control that opened them)
- [x] A wider marked row is narrowed to the finger's x, keeping the row's top and bottom, so the menu opens under or over the row near where it was held (ui/common/PressSpot.kt:30) (iPhone: a long press on a row opens its context menu over the row)
- [x] An unmarked press keeps only the finger's point (the whole-shell fallback); a marked control inside wins over it (ui/common/PressSpot.kt:107) (iPhone: system menus and popovers anchor to the control that opened them)
- [x] A press counts for 2 s; anything opened later than that without a press opens centered (ui/common/PressSpot.kt:46, ui/common/PressSpot.kt:51) (iPhone: system menus and popovers anchor to the control that opened them)
- [x] The spot is taken at the moment a card becomes visible and held while it stays open and as it closes, so it does not move while fading (ui/common/PressSpot.kt:64) (iPhone: a system popover stays on its anchor while it shows and closes)

## 18. Page frame pieces

- [x] Screen padding: top = status bar + 8 dp (+ any extra), bottom = navigation bar + 120 dp so content ends above the floating bar (ui/common/Layout.kt:25)
- [x] Screen title: 32 sp Black weight, letter spacing -0.5 sp, white, padding 20 dp sides, 8 dp top, 16 dp bottom (ui/common/Layout.kt:32, design/OctoType.kt:9)
- [x] Section title: 18 sp Bold white, padding 20 dp sides, 10 dp top and bottom (ui/common/Layout.kt:42, design/OctoType.kt:12)
- [x] Back button on detail pages: a 40 dp floating glaze circle frosting the page layer, Phosphor `arrow-left` 20 dp white, label "Back", placed below the status bar with 16 dp start and 8 dp top padding (ui/common/Layout.kt:56) (iPhone: a 40 point Liquid Glass circle with the SF Symbol chevron.left, labeled Back)
- [x] The back button presses like a chrome button: the glass pops to 1.05 and the icon dips to 0.96 over 80 ms, no ripple (design/GlazedIconButton.kt:37) (iPhone: Liquid Glass answers the press itself, the icon dips to 0.96 over 80 ms)
- [x] Detail pages start 56 dp lower to clear the back button (`DetailTopGap`) (ui/common/Layout.kt:52)
- [x] Song length as a clock: "3:07", or "1:02:45" from an hour (ui/common/Layout.kt:69)
- [x] Album or playlist length in words, rounded to the nearest minute: "48 min", "1 hr 12 min" (ui/common/Layout.kt:77)
- [x] Counts: "1 song" / "N songs", "1 album" / "N albums" (ui/common/Layout.kt:82)
- [x] Load states: Loading shows a 28 dp accent indeterminate spinner centered (Material 3 default circular indicator) (ui/common/LoadState.kt:45) (iPhone: a 28 point accent spinner that grows and turns, in the middle)
- [x] Load states: Failed shows, centered with 32 dp padding, the message (14 sp regular, accent, centered) and 16 dp below it the accent button "Try again" (ui/common/LoadState.kt:48)
- [x] Failure messages: unreachable "Couldn't reach the server. Check the address, and that you're on the right network." (data/UserMessages.kt:7)
- [x] Failure messages: not Subsonic and busy "The server isn't answering right now. It may be restarting, so try again in a moment."; not Subsonic otherwise "That address answered, but not like a music server. Check the port." (data/UserMessages.kt:9)
- [x] Failure messages: "Wrong username or password."; token sign-in refused with code 41 "This account can't sign in with a token. Turn on Legacy sign-in under Advanced.", other auth "The server doesn't take this way of signing in." (data/UserMessages.kt:12)
- [x] Failure messages: not found "That isn't on the server any more."; server error "The server said: <message>"; anything else "Something went wrong." (data/UserMessages.kt:16)
- [x] A load cancelled is not a failure (no message) (ui/common/LoadState.kt:31)
- [x] Pull to refresh on library pages: Material 3 pull-to-refresh with its default indicator and threshold; the theme does not override its colours (ui/common/Refreshable.kt:66) (iPhone: the system pull to refresh)
- [x] A pull runs the page's own reload and the library refresh together: rescan the phone, copy the server's library afresh when signed in, and ask how downloads on their way are going (ui/common/Refreshable.kt:34, data/LibraryRefresh.kt:24)
- [x] A second pull while one runs is ignored; the spinner shows until both are done (ui/common/Refreshable.kt:35) (iPhone: the system pull to refresh cannot start again while one runs)
- [x] A failed server copy is said in a feedback line in words; other failures are only logged (ui/common/Refreshable.kt:41, ui/common/Refreshable.kt:45)
- [x] Signed out, a pull only rescans the phone (data/LibraryRefresh.kt:28)
- [x] Quiet button ("See all", "Clear all"): 13.5 sp SemiBold accent text, no border or fill, capsule touch area with 10 by 6 dp padding and the platform ripple, role Button (ui/common/QuietButton.kt:18) (iPhone: a light press highlight in its capsule)
- [x] Segmented control: glaze tabs filling the width; each label 13.5 sp SemiBold, one line, ellipsized; chosen label accent, others white, colour on the default color spring (ui/common/Segmented.kt:17)

## 19. Ambient glow

- [x] Behind every page, above the plain background and under the page, a faint field of the artwork's colours (ambient/AmbientLayer.kt:154, ui/nav/MainShell.kt:268)
- [x] The glow follows the page on top of the current tab (ui/nav/MainShell.kt:268)
- [x] Each page belongs to an area: Home area = Home, Charts (ambient/AmbientSource.kt:52)
- [x] Search area = Search (ambient/AmbientSource.kt:53)
- [x] Library area = Library, Albums, Artists, Songs, Genres, Folders, Playlists, Liked, Downloads, Favourites, Album, Artist, Online album, Online artist, Genre, Playlist, wherever they were opened from (ambient/AmbientSource.kt:54)
- [x] Settings area = Settings, Sound, Sign in, Edit connection, Server form, Octo admin, Import, Family, Family join, Shares, Radio stations, any Settings page (ambient/AmbientSource.kt:59)
- [x] Pages with no area get no glow: live list, live list editor, history, library health, health check, recently removed (ambient/AmbientSource.kt:62)
- [x] Source rules in order: settings not read yet means no glow (so a glow turned off never flashes at launch); no area means none; area switched off or strength Off means none (ambient/AmbientSource.kt:78)
- [x] Album, artist, online album and online artist pages glow with their own cover when "use their own artwork" is on and the page has registered its cover, even with nothing playing (ambient/AmbientSource.kt:81)
- [x] Otherwise a page glows with the song on now's artwork when a song is loaded, and nothing when none is (ambient/AmbientSource.kt:82)
- [x] Album and artist pages register their cover by route while shown and remove it when gone (ambient/AmbientLayer.kt:144)
- [x] Colours: the same four the full player uses, from the same cache: dominant, a bright one (vibrant, else light vibrant, else dominant 0.16 lighter), a deep one (dark vibrant, else dark muted, else dominant 0.18 darker), and `#0A0B0F` (player/ArtworkPalette.kt:58)
- [x] Colours are picked from a 128 px copy of the artwork with up to 16 palette colours; dominant falls back to dark muted; artwork with neither, or no artwork, uses the quiet set (player/ArtworkPalette.kt:55)
- [x] The quiet set: `#2A3438`, `#1A1A1B`, `#3A4A50`, `#0A0B0F` (player/ArtworkPalette.kt:31)
- [x] The colour cache keeps the last 32 artworks (player/ArtworkPalette.kt:42)
- [x] Each colour is clamped before it glows: same hue, saturation at most 0.55, lightness at most 0.5 (white becomes `#808080`, pure red `#C63939`) (ambient/AmbientPrefs.kt:57, ambient/AmbientPrefs.kt:65)
- [x] The field shows at 14% (Subtle) or 24% (Rich) over the page background; at Rich, white and accent text keep 4.5:1 contrast over every colour (ambient/AmbientPrefs.kt:41, app/src/test/java/app/winters/octo/ambient/AmbienceTest.kt)
- [x] Toward the bottom it fades: a gradient from clear at 35% of the height to the page background at 40% at the bottom, drawn only while the glow shows (ambient/AmbientLayer.kt:85, ambient/AmbientLayer.kt:270)
- [x] Changes of colour and of strength cross over 800 ms (default easing); turning to none keeps the old colours while their strength fades to 0 (ambient/AmbientLayer.kt:75, ambient/AmbientLayer.kt:169, ambient/AmbientLayer.kt:242)
- [x] Below a strength of 0.002 nothing is drawn (ambient/AmbientLayer.kt:268)
- [x] The field is drawn with the player's mesh shader (four soft pools, section 34) on Android 13 and up; older phones get a still diagonal gradient of the four colours, top left to bottom right (ambient/AmbientLayer.kt:281) (iPhone: the same mesh, drawn small on the CPU and stretched smooth)
- [x] It drifts only while music plays, the app is in view, the player is not covering it, the strength is above 0, and neither Reduce motion nor the phone's animations-off is set (ambient/AmbientLayer.kt:179, ambient/AmbientLayer.kt:246)
- [x] Drift runs at a fifth of the player's pace (time advances 0.2 x real seconds) and redraws ten times a second (every 100 ms) (ambient/AmbientLayer.kt:80)
- [x] Drift time is kept, so the pools carry on from where they stopped (ambient/AmbientLayer.kt:245)
- [x] The glow redraws only its own layer; pages over it are never redrawn for it (ambient/AmbientLayer.kt:232) (iPhone: the glow draws only its own view; pages over it are not redrawn)
- [x] Defaults: strength Subtle, every area on, bar tint on, album and artist pages use their own artwork (ambient/AmbientPrefs.kt:19)
- [x] An unknown strength in a backup reads as the default, Subtle (app/src/test/java/app/winters/octo/ambient/AmbienceTest.kt)
- [x] Settings, Appearance page: a 72 dp preview strip (14 dp corners, page background) showing the glow still at the chosen strength, with the song on now's title (14 sp white) and artist (12 sp accent), or "Nothing playing" and "The glow takes its colours from the song on now."; 16 dp text padding (ambient/AmbientLayer.kt:202, ui/settings/AppearancePage.kt:80)
- [x] Setting "Ambient colour from the artwork" with choices "Off" (The plain dark background everywhere.), "Subtle" (A faint glow of the artwork's colours behind the pages.), "Rich" (A fuller glow, still kept dark enough for text.) (ui/settings/AppearancePage.kt:38, ui/settings/SettingsIndex.kt:149)
- [x] When not Off, a group "Where it shows" with switches "Home", "Library", "Search", "Settings", "Mini player and bar" (helper "A trace of the song's colour in its glass."), "Album and artist pages use their own artwork" (helper "The glow follows the page's album or artist, not the song.") (ui/settings/AppearancePage.kt:91)
- [x] The Settings summary line reads "No glow", "Subtle glow" or "Rich glow" (plus "Live background" when that is on) (ui/settings/SettingsSummaries.kt:44)

## 20. Reduce motion

- [x] Reduce motion is on when Octo's own "Reduce motion" setting is on or the phone's animator duration scale is 0; the phone setting is re-read each time the app returns (ui/common/NotInLibrary.kt:102, ui/common/ReduceMotion.kt:24) (iPhone: Octo's own Reduce motion or the phone's Reduce Motion, read live)
- [x] Octo's setting defaults to off; it lives under Appearance, group "Motion", switch "Reduce motion", helper "Backgrounds and lyrics hold still. On by itself when the phone's animations are off." (player/PlayerSettings.kt:80, ui/settings/AppearancePage.kt:123)
- [x] Reduced, the motion scale makes travel, lift and growth zero and halves every token duration (fades and colour changes still happen, twice as fast) (design/OctoMotion.kt:121)
- [x] A token duration after the scale is rounded to the nearest millisecond (design/OctoMotion.kt:105)
- [x] A scale factor after the scale is 1 + (base - 1) x distance, so 1.05 becomes 1.0 when reduced (design/OctoMotion.kt:111)
- [x] The phone's own animation speed is not applied twice: only its "off" counts, as reduced (design/OctoMotion.kt:129) (iPhone: iOS gives no animation speed; only its Reduce Motion counts)
- [x] Not shortened by Reduce motion (kept as they are): the bar's shape spring, the tab pill spring, the bar swipe lean and settle, the bar and pill fades (300 ms), the player fade (400/300 ms), the sheet's rise spring, the selection bar's enter and exit (ui/nav/BottomBar.kt:125, ui/nav/MainShell.kt:287, design/GlassSheet.kt:85, ui/common/SelectionBar.kt:102)
- [x] The feedback toast only calms for the phone's animations-off, not Octo's setting (ui/common/Feedback.kt:105)

## 21. Colours

- [x] Background `#0C0C0D` (design/OctoColors.kt:14)
- [x] Background secondary: white at 3%, a wash that tints glass panels (design/OctoColors.kt:16)
- [x] Background tertiary `#1A1A1B`: the solid surface under cards and glazed controls, and the artwork placeholder tile (design/OctoColors.kt:18)
- [x] Accent `#97B1B9` (design/OctoColors.kt:19)
- [x] Surface raised: `#1A1A1B` mixed 6% toward the accent, `#222324` (design/OctoColors.kt:22)
- [x] Accent hover `#ADC4CC` (design/OctoColors.kt:23)
- [x] Text primary white; text secondary = accent; text muted = accent at 80% (5.8:1 on the page) (design/OctoColors.kt:24)
- [x] Error `#EF4444` (design/OctoColors.kt:30)
- [x] Accent tonal: `#1E1E1E` mixed 10% toward the accent, `#2A2D2E`, a standard button's resting fill (design/OctoColors.kt:35)
- [x] Accent selected: black mixed 40% toward the accent, `#3C474A`, a selected list row (design/OctoColors.kt:39)
- [x] Focus ring colour: accent at 70% (design/OctoColors.kt:42)
- [x] Menu press: accent selected at 55% (design/OctoColors.kt:46)
- [x] Destructive words: `#FF3B30` at 85% (design/OctoColors.kt:49)
- [x] Signal colours: red `#FF3B30`, orange `#FF9500`, yellow `#FFCC00`, green `#28CD41`, blue `#007AFF` (design/OctoColors.kt:52)
- [x] Mixing is channel by channel in sRGB, like a stylesheet's mix (design/OctoColors.kt:6)
- [x] Accent fill (the filled button): accent mixed 45% toward black, `#536166` (design/AccentButton.kt:19)
- [x] Sheet fill: background mixed 5% toward the accent, `#131416`, at 97% (design/GlassSheet.kt:53) (iPhone: system sheets wear iOS's own sheet material; the token stays for Octo's own panels)
- [x] Ink: white at 85% (primary), 55% (secondary), 25% (tertiary, disabled words and placeholders), 10% (quaternary, hover fills and hairlines), 5% (quinary, resting fills) (design/OctoTokens.kt:26)
- [x] A control that cannot be used right now is drawn at 50% opacity (design/OctoTokens.kt:49)
- [x] Perceived lightness is CIE L* from relative luminance, 0 to 1; words on a fill turn black above 0.58, white at or below (design/OctoTokens.kt:118, design/OctoTokens.kt:125)

## 22. Shapes, type and shadows

- [x] Radii: chrome 10, chrome small 6, list row 12, artwork 3 / 6 / 8 / 12 (XS / S / M / L), dialog 12, misc 2 / 4 / 6 / 8 dp; pill = fully round (design/OctoTokens.kt:53)
- [x] Artwork default corner 6 dp (design/Artwork.kt:11)
- [x] Menu row height: 30 dp for a pointer, 40 dp for touch (the phone uses 40) (design/OctoTokens.kt:91)
- [x] Type: display 32 sp Black, letter spacing -0.5 sp (design/OctoType.kt:9)
- [x] Type: title 24 sp Black (design/OctoType.kt:10)
- [x] Type: headline 20 sp Bold (design/OctoType.kt:11)
- [x] Type: section 18 sp Bold (design/OctoType.kt:12)
- [x] Type: body 16 sp Medium (design/OctoType.kt:13)
- [x] Type: body small 14 sp Normal (design/OctoType.kt:14)
- [x] Type: caption 12 sp Normal (design/OctoType.kt:15)
- [x] Type: label 13.5 sp SemiBold (design/OctoType.kt:16)
- [x] Type colours are set where text is used, never in the scale (design/OctoType.kt:7)
- [x] Raised shadow (hero cover): blur 40 CSS, black 55%, 8 dp down (design/OctoTokens.kt:104)
- [x] Lift shadow (grid artwork): blur 14 CSS, black 10%, 4 dp down (design/OctoTokens.kt:108)
- [x] Chrome shadow: blur 12 CSS black 10% 4 dp down, plus blur 2 CSS black 2% 1 dp down (design/OctoTokens.kt:112)
- [x] Elevation 1: blur 2 CSS black 20% 1 dp down, plus blur 6 CSS black 12% 2 dp down (design/GlassPanel.kt:39)
- [x] Elevation 3: blur 4 CSS black 25% 2 dp down, blur 16 CSS black 20% 8 dp down, blur 32 CSS black 15% 16 dp down (design/GlassPanel.kt:44)
- [x] Focus ring: a 2 dp line just outside the edge in accent 70%, faded in by strength over 300 ms (design/OctoTokens.kt:134, design/Buttons.kt:94) (iPhone: the ring shows for keyboard focus, which an iPhone rarely has)
- [x] Artwork rim: a 1 dp inner line of `#C8C8C8` at 16% on the picture itself, only on covers 96 dp and larger (design/Artwork.kt:15, ui/common/Artwork.kt:28)

## 23. Motion tokens

- [x] Springs: soft (0.75, 400), snappy (0.65, 600), bouncy (0.5, 400), jelly (0.55, 300), smooth (0.75, 1500), calm (0.9, 500) (design/OctoMotion.kt:17)
- [x] Durations (ms, before the scale): press 80, hover 140, swap 160, fill 180, card 200, neutral 300, squeeze 340, scrub 400 (design/OctoMotion.kt:31)
- [x] Easings: Spring cubic (0.2, 0.8, 0.2, 1), the default for every token tween (design/OctoMotion.kt:60, design/OctoMotion.kt:148)
- [x] Easings: Overshoot (0.34, 1.56, 0.64, 1); Bounce (0.45, -0.05, 0.15, 1.05); Smooth (0.65, 0.05, 0.36, 1); Snappy (0, 0, 0, 1); EaseIn (0.4, 0, 1, 1); Sweep (0.5, 0, 0.75, 0) (design/OctoMotion.kt:63)
- [x] Press: a control pressed scales to 0.96; a large surface (row, card) to 0.985; a chrome button's glass pops to 1.05; small lift 1 dp, medium lift 2 dp (design/OctoMotion.kt:82)
- [x] Squeeze: a large surface held goes to 0.985 over 170 ms (half the squeeze) and back (design/Buttons.kt:101)

## 24. Glass: the glaze

- [x] One material, lit two ways: Rest (ring 0.10, inner 0.07, spec 0.34, soft spec 0.14, lift 0) and Lifted under the finger (ring 0.17, inner 0.10, spec 0.46, soft spec 0.19, lift 0.07); every value is an accent alpha (design/Glaze.kt:39) (iPhone: Apple's Liquid Glass lights itself; Octo's rest and lifted recipe is not drawn)
- [x] Default film: black at 16%; clear film (fully transparent) for glass over one smooth field such as the player background (design/Glaze.kt:59, design/Glaze.kt:64) (iPhone: the film tints the Liquid Glass; clear glass where a smooth field lies under it)
- [x] Default frost: backdrop blur 4 CSS (sigma 4), saturation 1.1, no noise; where blur is unavailable the fill falls back to a `#1A1A1B` tint (design/Glaze.kt:78, design/Glaze.kt:90) (iPhone: Liquid Glass's own frost)
- [x] Outside: a 0.5 dp black 38% contour, a black 5% contact line 1 dp down, a blur 3 CSS black 10% drop 1 dp down (design/Glaze.kt:134) (iPhone: Liquid Glass's own edge and contact shadow)
- [x] Fill, clipped to the shape: the frosted backdrop (when it floats over content), then the film, then the accent at the lift alpha (design/Glaze.kt:142) (iPhone: Liquid Glass tinted with the film)
- [x] Lit rim: an accent line along the top inside edge (ring alpha, 1 dp down, no blur), a soft inner glow (blur 6 CSS, 1 dp spread, inner alpha), and a white 10% line along the bottom inside edge (0.5 dp up) (design/Glaze.kt:164) (iPhone: Liquid Glass's own lit rim)
- [x] Specular: two inner rims in accent (blur 1.5 CSS spread 1 dp at spec alpha, blur 3 CSS spread 1 dp at soft spec alpha), masked by a horizontal gradient clear, solid, clear, so it is bright only across the middle (design/Glaze.kt:73, design/Glaze.kt:176) (iPhone: Liquid Glass's own specular highlight)
- [x] With the window out of focus (desktop only) the rim and specular are off; on the phone they are always on (design/Glaze.kt:88) (iPhone: Liquid Glass is always lit)
- [x] Content sits centered on the glass by default (design/Glaze.kt:139)
- [x] Floating glaze (bar, toast, pill, selection bar, back button): the glaze plus a pooled shadow cast by the shape inset 12 dp on every side, blur 24 CSS, black 45%, 8 dp down, so it pools under the glass (design/Glaze.kt:198)
- [x] Floating glaze places its content at the top start of its box unless the content aligns itself (unlike the plain glaze, which centers it) (design/Glaze.kt:210, design/Glaze.kt:229) (iPhone: SwiftUI places content as each view lays it out)
- [x] Floating glaze with halo (menus): also an even dark halo all round (blur 20 CSS, black 50%) and a 1 dp white 6% hairline just inside the rim (design/Glaze.kt:211, design/Glaze.kt:226) (iPhone: system menus draw their own plate; floatingGlass keeps the dark halo for Octo's own)
- [x] Selected pill inside a glaze: black at 72%, unlit (design/Glaze.kt:68, design/Glaze.kt:236)
- [x] Selected list row: accent selected `#3C474A`, 12 dp corners, a white 28% line 1 dp down and a white 12% line 2 dp down inside the top, a black 14% line 1 dp up inside the bottom (design/Glaze.kt:244)
- [x] Dark glass (chrome over artwork or video): film `#282828` at 50%, frost 32 CSS, saturation 1.4, with the glaze's rim, specular and pooled shadow (design/Materials.kt:30) (iPhone: Liquid Glass with a #282828 film at 50% and the pooled shadow)
- [x] LCD glass (compact player): 10 dp corners by default, fill `#161618` at 72%, frost 16 CSS with saturation 1.2, a shade from the bottom inside edge (blur 6 CSS black 35% 2 dp up), a shine along the top (blur 5 CSS white 22% 2 dp down), a faint inner glow (blur 14 CSS white 8%), a 1 dp white border at 18% (8% unfocused), and a blur 24 CSS black 35% drop 8 dp down (design/Materials.kt:55, design/Materials.kt:72) (iPhone: Liquid Glass with a darker film stands in where the compact look is used)
- [x] Glass panel (a card on the page, no blur): 0.5 dp black 40% contour, elevation 1, background secondary fill, a white 8% line 1 dp down inside the top (design/GlassPanel.kt:17)
- [x] Raised panel (settings groups): contour, elevation 1, surface raised `#222324` fill, 1 dp white 6% border, white 6% top inner line (design/GlassPanel.kt:29)
- [x] Glaze inset (glass inside glass, no blur): 0.5 dp black 40% contour, black 5% contact line 1 dp down, blur 3 CSS black 10% drop; inside a 1 dp white 10% rim all round and a white 10% line along the bottom; a specular at three-quarter strength in white (14% sharp, 11% soft) (design/GlazeInset.kt:25) (iPhone: Liquid Glass with the fill as its film, inside the glass around it)

## 25. Glass popup

- [x] A free-floating glass card beside the control that opened it, or centered when there is none (design/GlassPopup.kt:143) (iPhone: a system popover or menu beside its control)
- [x] Card: 20 dp corners, floating glaze with halo, film black 52%, frost 24 CSS, saturation 1.1 (design/GlassPopup.kt:112, design/GlassPopup.kt:125, design/GlassPopup.kt:129) (iPhone: the system popover's own corners and material)
- [x] It keeps 12 dp from every edge and from the status bar, navigation bar and keyboard (design/GlassPopup.kt:114, design/GlassPopup.kt:242) (iPhone: iOS keeps popovers clear of the screen edges, the bars and the keyboard)
- [x] At most 340 dp wide (and never wider than the screen minus 24 dp) (design/GlassPopup.kt:118, design/GlassPopup.kt:243) (iPhone: iOS sizes a popover to its content within the screen)
- [x] At most 60% of the screen height, and never taller than the room between the bars minus 24 dp; its content scrolls within that (design/GlassPopup.kt:121, design/GlassPopup.kt:245) (iPhone: iOS keeps a popover within the screen; its content scrolls)
- [x] Below the control with a 6 dp gap when it fits there; above it when only that fits; otherwise on the roomier side, pushed back inside the screen (design/GlassPopup.kt:115, design/GlassPopup.kt:99) (iPhone: iOS places a popover below or above its control)
- [x] Lined up with the control's start edge, or its end edge when the control's center is on the far half of the screen (design/GlassPopup.kt:97) (iPhone: iOS lines a popover up with its control)
- [x] Too big to fit, it keeps to the start and the top (design/GlassPopup.kt:87) (iPhone: iOS keeps a popover inside the screen)
- [x] With no control, centered between the bars (design/GlassPopup.kt:90) (iPhone: a popover with nothing to point at is centered by iOS)
- [x] The side it opened on is kept while it still fits there, so a menu growing to its next page does not jump to the other side; a fresh opening chooses again (design/GlassPopup.kt:101, design/GlassPopup.kt:181) (iPhone: a popover stays where it opened while its content changes)
- [x] It grows from the corner nearest the control (top-start, top-end, bottom-start or bottom-end by side and alignment), or from its center when centered (design/GlassPopup.kt:60) (iPhone: iOS's own popover motion from its control)
- [x] In: alpha 0 to 1 and scale 0.92 to 1 over 160 ms on cubic (0.2, 0.8, 0.2, 1); out: the reverse, staying drawn until it has shrunk away (design/GlassPopup.kt:201, design/GlassPopup.kt:220) (iPhone: iOS's own popover motion)
- [x] Reduce motion: no scale, fade only, 80 ms; phone animations off: at once (design/GlassPopup.kt:176, design/GlassPopup.kt:220) (iPhone: iOS calms its own motion with Reduce Motion)
- [x] A tap that starts and ends off the card closes it (a drag off the card does not) (design/GlassPopup.kt:230) (iPhone: a tap outside closes it)
- [x] Back goes to the popup's previous page if it has one, else closes it (design/GlassPopup.kt:189) (iPhone: a submenu's own back)
- [x] The screen's edges stay the system's, so the edge back swipe still works while it is open (design/GlassPopup.kt:193) (iPhone: a tap outside closes a popover; the edge swipe stays the page's)
- [x] With the keyboard up it keeps above it, moving over the control when there is no room under it any more; the keyboard never pushes or squashes it (design/GlassPopup.kt:197, design/GlassPopup.kt:198, design/GlassPopup.kt:270) (iPhone: iOS keeps popovers above the keyboard)
- [x] Accessibility: its title is announced as a pane title (design/GlassPopup.kt:226) (iPhone: VoiceOver reads the popover's title)

## 26. Popup pages

- [x] A popup has a trail of pages: always at least one; opening goes deeper with a way back; back on the first page changes nothing and reports it so back closes the popup; replace swaps the page at the same depth (moving as deeper); restart begins again on a first page and counts as a new opening even on the same page (design/PopupPages.kt:30) (iPhone: system submenus)
- [x] A new page slides in from a third of the width on the side it is going (calm spring 0.9, 500) and fades in over 180 ms after 40 ms; the old one slides a third the other way and fades out over 80 ms (design/PopupPages.kt:106) (iPhone: iOS's own submenu motion)
- [x] Back runs it the other way (design/PopupPages.kt:106) (iPhone: iOS's own submenu motion)
- [x] The card eases to the new page's size on the calm spring, clipped (design/PopupPages.kt:109) (iPhone: iOS sizes each submenu itself)
- [x] A page that changes its own height (a list loading in) also eases on the calm spring (design/PopupPages.kt:115) (iPhone: iOS sizes each submenu itself)
- [x] Reduce motion or animations off: pages only fade (in 80 ms, out 40 ms) and the card takes its new size at once (design/PopupPages.kt:103) (iPhone: iOS calms its own motion with Reduce Motion)
- [x] Each page is told whether it has a page to go back to (design/PopupPages.kt:94) (iPhone: a submenu has its own back)

## 27. Glass sheet

- [x] A panel rising from the bottom over a dimmed screen (design/GlassSheet.kt:55) (iPhone: system sheets)
- [x] The dim is black at 45%, fading in and out over 200 ms on cubic (0.2, 0.8, 0.2, 1) (100 ms reduced); tapping it closes the sheet (design/GlassSheet.kt:75) (iPhone: the system dims behind a sheet; a tap outside closes it)
- [x] The sheet rises from fully below on `spring(0.85, 400)` and drops away over 200 ms on EaseIn (0.4, 0, 1, 1) (100 ms reduced) (design/GlassSheet.kt:85) (iPhone: the system sheet's own rise and fall)
- [x] Top corners 28 dp; fill `#131416` at 97%; drop shadow blur 32 CSS black 40%; a white 10% line 1 dp down inside the top (design/GlassSheet.kt:50, design/GlassSheet.kt:98) (iPhone: the system sheet's own corners and material)
- [x] At most 70% of the screen tall; a tall sheet may grow to the status bar and opens all the way at once (design/GlassSheet.kt:96) (iPhone: system detents; a tall sheet opens at full height)
- [x] It pads itself above the navigation bar (design/GlassSheet.kt:105) (iPhone: the system sheet keeps its content above the home indicator)
- [x] Taps on the sheet never reach the dim (design/GlassSheet.kt:104) (iPhone: taps on a system sheet stay on the sheet)
- [x] The handle: a 36 by 4 dp TextMuted capsule centered in a full-width strip with 12 dp above and below (design/GlassSheet.kt:108, design/GlassSheet.kt:127) (iPhone: the system grabber)
- [x] Dragging the handle down moves the sheet with the finger (never above its rest); let go past 96 dp, or faster than 1200 dp/s downward, it closes; otherwise it springs back on `spring(0.8, 400)` (design/GlassSheet.kt:113) (iPhone: iOS's own drag to close)
- [x] Only the handle drags the sheet; content does not (design/GlassSheet.kt:111) (iPhone: the grabber and a pull from the top close it, as iOS sheets do)
- [x] Back closes it while visible (design/GlassSheet.kt:71) (iPhone: swiping down closes it)
- [x] Lines taller than the sheet scroll under the handle; a line with a weight (a list that scrolls itself) shares the room the others leave (design/GlassSheet.kt:131, design/SheetColumn.kt:60) (iPhone: sheet content scrolls as SwiftUI lays it out)
- [x] The sheet's scroll is exposed to screen readers as a vertical scroll range with scroll-by (design/SheetColumn.kt:102) (iPhone: VoiceOver scrolls the sheet as iOS does)

## 28. Buttons and controls

- [x] Button sizes (height, dense height, side padding, icon, font): extra small 24, 20, 8, 14, 12.5 sp; small 30, 24, 12, 16, 13.5 sp; medium 36, 28, 12, 18, 13.5 sp; large 50, 40, 24, 20, 13.5 sp; large is the phone's (design/Buttons.kt:41)
- [x] Every button state animates: pressed scale 0.96 over 80 ms; under the pointer a 1 dp rise over 140 ms; hover shade white 10% over 180 ms; press shade black 10% over 80 ms; focus ring over 300 ms; all on cubic (0.2, 0.8, 0.2, 1) and the motion scale (design/Buttons.kt:73) (iPhone: pressed scale 0.96 over 80 ms; an iPhone has no pointer to hover, and focus rings show for keyboard focus)
- [x] Button label: optional icon 8 dp before the words; words one line, ellipsized, 13.5 sp SemiBold at the size's font size; while loading the words keep their room (hidden) and a spinner of the icon size turns in their place (design/Buttons.kt:140)
- [x] Accent button: a capsule glaze inset filled `#536166`, large by default (50 dp, dense 40); words black or white by the fill's lightness (white on `#536166`); disabled at 50% and not tappable; not tappable while loading; no ripple (design/AccentButton.kt:26) (iPhone: a Liquid Glass capsule with the #536166 film, words by its lightness, disabled at 50%)
- [x] Accent button tonal variant: fill `#2A2D2E` (design/AccentButton.kt:22, design/OctoColors.kt:35)
- [x] Glaze button (the quieter one): the lit glaze capsule, Lifted while pressed, white words; an optional tint lays 20% of a colour into the film over the black 16% (design/GlazeButton.kt:24) (iPhone: lit Liquid Glass with white words; a tint lays a fifth of a color into its film)
- [x] Chrome button: 38 by 38 dp alone, 38 by 30 inside a group; an 18 dp white icon (design/ChromeButtons.kt:35, design/ChromeButtons.kt:67)
- [x] Chrome button pressed: the glass pops to 1.05 while the icon dips to 0.96, over 80 ms; under the pointer the icon grows to 1.05 over 140 ms (design/GlazedIconButton.kt:37)
- [x] Chrome button alone: wears the glaze and chrome shadow, Lifted when pressed, hovered or active; active adds the darker pill inset 3 dp (design/ChromeButtons.kt:129) (iPhone: Liquid Glass with the chrome shadow; active adds the darker pill 3 points in)
- [x] Chrome button in a group: no glass of its own; active shows the darker pill; pressed or hovered shows a faint white 10% circle with no edge (design/ChromeButtons.kt:117)
- [x] Button group: one glaze capsule at least 38 dp tall with the chrome shadow, buttons 4 dp from its ends and 4 dp apart (design/ChromeButtons.kt:48)
- [x] An icon accent, when given, plays on every tap (design/ChromeButtons.kt:97)
- [x] Glazed icon button (lone round control over content): floating glaze circle, 56 dp by default with a 22 dp icon (20 dp below 56); the same pop and dip as chrome; role Button with its label (design/GlazedIconButton.kt:64)
- [x] Glaze tabs: a 40 dp glaze tray with a drop shadow (blur 10 CSS, black 20%, 2 dp down), recessed by an inner shade (blur 2 CSS, 1.6 dp spread, black 15%, 3 dp down) and a 0.5 dp accent 25% hairline (design/GlazeTabs.kt:61, design/GlazeTabs.kt:85) (iPhone: a Liquid Glass tray with its shadow, recess and accent hairline)
- [x] Glaze tabs: tabs inset 4 dp, equal cells across the width (or each as wide as the widest label when not filling, labels then padded 14 dp, else 4 dp) (design/GlazeTabs.kt:114, design/GlazeTabs.kt:149)
- [x] Glaze tabs: the chosen one sits in a black 72% capsule the cell's size, gliding over 300 ms on the Smooth curve (0.65, 0.05, 0.36, 1); with Reduce motion it jumps (design/GlazeTabs.kt:40, design/GlazeTabs.kt:81)
- [x] Glaze tabs: the pill is lit in accent from the side it came from, a gradient over 70% of its width, alpha 0.10 at rest up to 0.22 while moving (design/GlazeTabs.kt:131)
- [x] Glaze tabs: tabs the pill passes over flash accent up to 22%, strongest as the pill's middle crosses them, none a whole tab away; the target tab never flashes; only while the pill moves (design/GlazeTabs.kt:43, design/GlazeTabs.kt:49, design/GlazeTabs.kt:142)
- [x] Glaze tabs: each tab is a selectable with role Tab in a selectable group; a disabled tab shows but ignores presses (design/GlazeTabs.kt:103) (iPhone: each tab a button with the selected trait; a disabled tab ignores presses)
- [x] Text input: 48 dp tall, 12 dp corners, padding 14 dp sides, one line, 16 sp Medium white text, accent cursor, placeholder 16 sp Medium TextMuted (design/GlassInput.kt:34, design/GlassInput.kt:62)
- [x] Text input fill: accent at 10%, rising to 15% while focused; 1 dp accent 10% border (design/GlassInput.kt:82, design/GlassInput.kt:97)
- [x] Text input sunk in: a dark inner shadow from the top left (offset 4 dp, blur 7 CSS, black 50%) and a light one from the bottom right (offset -4 dp, blur 7 CSS, white 10%); focused they deepen to offset 5 dp, blur 9 CSS, black 60% and white 15% (design/GlassInput.kt:85)
- [x] Text input focus: a 1.5 dp accent 60% ring fades in; the focus depth animates over 200 ms on Overshoot (so the shadows briefly pass their focused depth, while ring and fill are clamped) (design/GlassInput.kt:56, design/GlassInput.kt:80)
- [x] Text input: optional leading and trailing pieces around the field (design/GlassInput.kt:101)
- [x] Switch sizes (track width, height, thumb): small 30, 18, 14; default 36, 22, 18; large 44, 26, 22 dp; 2 dp between track edge and thumb (design/OctoSwitch.kt:34)
- [x] Switch off: track white 18%, recessed by a black 22% shade 0.5 dp down inside the top (blur 1.5 CSS) (design/OctoSwitch.kt:62, design/OctoSwitch.kt:116)
- [x] Switch on: accent track with an accent glow beneath (blur 5 CSS, 1 dp down, 30%) (design/OctoSwitch.kt:100)
- [x] Switch: a faint white 5% drop 0.5 dp below, and a 0.5 dp white 6% inner rim (design/OctoSwitch.kt:107, design/OctoSwitch.kt:123)
- [x] Switch thumb: white, with black 18% and black 12% shadows 0.5 and 1 dp down; it slides over 200 ms on cubic (0.2, 0.8, 0.2, 1) (design/OctoSwitch.kt:81, design/OctoSwitch.kt:139)
- [x] Switch held: the thumb stretches up to 1.18 times wide toward where it is going, keeping the edge on the side it is leaving, over 80 ms; no stretch with Reduce motion (design/OctoSwitch.kt:44, design/OctoSwitch.kt:53, design/OctoSwitch.kt:82)
- [x] Switch: role Switch, toggles on tap, no ripple; disabled at 50% (design/OctoSwitch.kt:126) (iPhone: a button with the toggle trait, no ripple; disabled at 50%)

## 29. Sliders, bars and marks

- [x] Glow slider (song progress, volume): 48 dp touch height, full width; a white 24% track line and a white filled part, round caps (design/LineSlider.kt:42, design/LineSlider.kt:76)
- [x] Glow slider: line 3.5 dp, thickening to 8 dp while held, and a white thumb of radius 9 dp appearing while held, both on `spring(0.5, 200)` (design/LineSlider.kt:65)
- [x] Glow slider: the filled part glows with three soft passes of the same line at a third of the glow alpha each, blurred by the glow radius x 2.5, x 1 and x 0.3 in pixels (not dp); glow radius 12 px at rest, 24 px held; glow alpha 0.4 at rest, 0.8 held; both on `spring(1, 200)` (design/LineSlider.kt:67, design/LineSlider.kt:119)
- [x] Glow slider: a tap seeks to that point; a drag shows its own value and sends it only when the finger lifts (so scrubbing does not stutter audio); a cancelled drag sends nothing; a live slider (volume) sends all along (design/LineSlider.kt:81, design/LineSlider.kt:84)
- [x] Sliders snap to `steps` equal steps when given (design/Sliders.kt:40)
- [x] Jewel slider (settings): a 4 dp recessed track (white 10% to 14% top to bottom, a black 25% 1 dp line along its top), accent fill shaded 22% darker at its bottom; the thumb stays inside the track's ends (design/Sliders.kt:99)
- [x] Jewel slider: ticks at each step (when 1 to 40 steps) as 2 dp dots, black 30% on the fill and white 30% on the track (design/Sliders.kt:138)
- [x] Jewel slider thumb: 14 dp, 16 dp while dragged, over 140 ms; white with a highlight toward its top left (white to `#E4E6E8`), a black 35% shadow 1 dp down, and an accent dot 35% of its size (42% dragged) (design/Sliders.kt:68, design/Sliders.kt:165)
- [x] Jewel slider dragged: an accent glow 18 dp around the thumb at 35% and a 4 dp accent 45% ring, fading in over 200 ms (design/Sliders.kt:147)
- [x] Jewel slider dragged: the value in a bubble 14 dp above the thumb, black 85%, 8 dp corners, 6 by 3 dp padding, with a 4 dp arrow, 11 sp SemiBold white, kept inside the slider's width, fading in over 160 ms (design/Sliders.kt:94, design/Sliders.kt:177)
- [x] Jewel slider: a value set from elsewhere slides there linearly over 80 ms; while dragging it follows the finger at once (design/Sliders.kt:81)
- [x] Now playing bars: three bottom-aligned rounded bars, gap = width / 7, bar width = (width - 2 gaps) / 3, fully round ends (design/NowPlayingBars.kt:65)
- [x] Now playing bars paused: still, heights 45%, 80%, 60%, in TextMuted (design/NowPlayingBars.kt:32, design/NowPlayingBars.kt:60)
- [x] Now playing bars playing: white; each height = 25% + 75% x |sin((phase x speed + offset) x pi)| with speeds 2, 3, 4 and offsets 0, 0.3, 0.65, phase looping 0 to 1 linearly every 2.4 s; a copy blurred 4 dp at 70% glows behind (design/NowPlayingBars.kt:45, design/NowPlayingBars.kt:72)
- [x] Now playing bars with Reduce motion while playing: still at the paused heights but white, no glow (design/NowPlayingBars.kt:41)
- [x] Explicit mark: a square tile 14 sp on a side (grows with text size), corners 3/14 of its side, in TextMuted by default, with the letter "E" (9.5 sp Bold) cut out of it so what is behind shows through (design/ExplicitMark.kt:34, design/ExplicitMark.kt:57)
- [x] Explicit mark: 6 dp after the title; read by screen readers as "Explicit"; a clean edit has no mark (design/ExplicitMark.kt:51, design/ExplicitMark.kt:62)
- [x] Song title line: the title on one line, cut short before the mark so the mark always shows; an optional piece before the title (design reference ui/common/SongTitle.kt:20)

## 30. Icon motion and small glyphs

- [x] Icon accents, each 300 ms (scaled), strongest 45% of the way through, rising and settling on cubic (0.2, 0.8, 0.2, 1) (design/IconAccents.kt:66, design/IconAccents.kt:122)
- [x] Lift: up 3 dp; Drop: down 3 dp; Raise: up 2 dp and 8% larger; Slide forward: right 4 dp; Slide back: left 4 dp; Expand: 15% larger; Collapse: 15% smaller; Pulse: 20% larger (design/IconAccents.kt:84)
- [x] Ring: a bell swing of 16 degrees x sin(progress x 6 pi) x (1 - progress), three swings dying away (design/IconAccents.kt:93)
- [x] Spin step: one full turn on cubic (0.2, 0.8, 0.2, 1) (design/IconAccents.kt:94)
- [x] With Reduce motion icons hold still (travel and growth x 0) (design/IconAccents.kt:81)
- [x] Glow icon: when lit, a 10 dp blur copy at 60% and a 3 dp blur copy at 70% behind the sharp icon, fading over 300 ms (design/GlowIcon.kt:23)
- [x] Spinner: a 270 degree arc turning once every 900 ms linearly, stroke 12% of its size, round caps; 18 dp white by default (design/Spinner.kt:23)
- [x] Tooltip bubble is desktop only (no phone surface) (design/Tooltip.kt:41)

## 31. Artwork tile and the not-in-library mark

- [x] Artwork sits on a `#1A1A1B` tile until the picture arrives; no artwork, or one that cannot be had (server has none, offline), keeps the tile; a failed picture is not asked for again until shown again (ui/common/Artwork.kt:30)
- [x] Pictures fill and crop to the shape (ui/common/Artwork.kt:58)
- [x] A song, album or artist found online and not in the library gets a small glass disc in the bottom right with a thin plus (Phosphor `plus` light), white 90% (ui/common/NotInLibrary.kt:196) (iPhone: a Liquid Glass disc with the SF Symbol plus, white 90%)
- [x] The mark is an eighth of the artwork's side, at least 12 dp and at most 20 dp; its plus is 68% of the disc (ui/common/NotInLibrary.kt:171, ui/common/NotInLibrary.kt:208)
- [x] The mark sits in from the bottom and right by 4% of the side (at least 3 dp); on round artwork it sits along the diagonal far enough in that the whole disc stays inside the circle (ui/common/NotInLibrary.kt:180)
- [x] The mark's film is black 42%, on the glaze (ui/common/NotInLibrary.kt:190) (iPhone: the disc's Liquid Glass tinted black 42%)
- [x] Screen readers hear "Not in your library" for such artwork, or "<description>, not in your library" (ui/common/NotInLibrary.kt:41, ui/common/NotInLibrary.kt:151)
- [x] A found song stops counting as outside once its download has landed in the library (ui/common/NotInLibrary.kt:112)

## 32. Icons

- [x] Icons are Phosphor Icons 2.1.1 (MIT), drawn on a 24 grid, filled paths, tinted in place (design/OctoIcons.kt:3, icons.json) (iPhone: SF Symbols in place of Phosphor, tinted in place)
- [x] Transport glyphs are Fill weight drawn at 0.8 of the square: `skip-back` (previous), `skip-forward` (next), `play`, `pause` (icons.json) (iPhone: filled SF Symbols for previous, next, play and pause)
- [x] Fill weight for things that are on: `heart` fill (liked), `star` fill, `push-pin` fill, `arrow-circle-down` fill (downloaded), `screencast` fill (casting), and the selected tabs `house`, `magnifying-glass`, `cards`, `gear` (icons.json) (iPhone: filled SF Symbols for liked, rated, pinned, downloaded, AirPlay and the selected tabs)
- [x] Bold weight: `dots-three` (more); Light weight: `plus` (the not-in-library mark) (icons.json) (iPhone: SF Symbols ellipsis and plus)
- [x] Regular weight, playback: `shuffle`, `repeat`, `repeat-once`, `moon` (sleep timer), `queue`, `playlist`, `speaker-low`, `speaker-high`, `waveform` (lossless), `heart` (like) (icons.json) (iPhone: SF Symbols for each playback action)
- [x] Regular weight, song actions: `rows-plus-top` (play next), `rows-plus-bottom` (add to queue), `music-notes-plus` (add to playlist), `music-notes-minus` (remove from playlist), `pencil-simple` (rename), `trash` (delete), `file-audio` (share file), `bell-ringing` (ringtone), `share-network` (share), `radio`, `info`, `check-circle` (select), `x` (close), `clock-counter-clockwise` (history), `push-pin` (pin) (icons.json) (iPhone: SF Symbols for each song action)
- [x] Regular weight, library: `vinyl-record` (album), `user` (artist), `music-note` (songs), `guitar` (genres), `folder`, `arrows-down-up` (sort), `funnel-simple` (filter), `arrow-up`, `arrow-down`, `cards` (library), `device-mobile` (phone) (icons.json) (iPhone: SF Symbols for each library item)
- [x] Regular weight, navigation: `caret-right`, `caret-left`, `caret-down`, `arrow-left` (back), `house`, `magnifying-glass`, `gear` (icons.json) (iPhone: SF Symbols chevron.right, chevron.left, chevron.down, house, magnifyingglass and gearshape)
- [x] Regular weight, downloads: `cloud`, `check`, `download-simple`, `arrow-circle-down` (downloading), `plus` (add to library) (icons.json) (iPhone: SF Symbols cloud, checkmark and the arrow.down.circle family)
- [x] Regular weight, settings and system: `sliders-horizontal` (sound), `star`, `microphone-stage` (lyrics), `play-circle` (playback), `palette` (appearance), `chart-line-up` (scrobbling), `archive` (backup), `screencast` (cast), `television-simple`, `speaker-hifi`, `devices` (speaker group), `headphones`, `globe-simple`, `lock-simple`, `lock-simple-open`, `key`, `sparkle`, `arrows-clockwise` (sync), `database` (storage), `hard-drives` (servers), `timer`, `users-three` (listeners), `layout`, `wifi-high`, `camera`, `qr-code`, `copy`, `link-simple`, `faders` (audio quality), `eye`, `eye-slash`, `gauge` (loudness), `scales` (balance), `intersect` (crossfade), `keyboard`, `desktop`, `minus`, `square` (icons.json) (iPhone: SF Symbols for each setting and system item)
- [x] The ListenBrainz mark is drawn in its own colours, never tinted (design/OctoIcons.kt:151)

## 33. Download ring (in the pill)

- [x] A thin ring around a small plus: track white 20%, 2 dp strokes, plus arms 18% of the width each side of center (ui/common/DownloadRing.kt:57, ui/common/DownloadRing.kt:62)
- [x] Waiting (queued, or downloading with no fraction): a 90 degree white arc turning once every 1.6 s linearly, starting from 12 o'clock (ui/common/DownloadRing.kt:45, ui/common/DownloadRing.kt:96, ui/common/DownloadRing.kt:133)
- [x] Downloading with a fraction: a white arc from 12 o'clock filling to the fraction, easing over 1.2 s on LinearOutSlowIn (0, 0, 0.2, 1); the fill never goes back even when an answer does (ui/common/DownloadRing.kt:46, ui/common/DownloadRing.kt:110)
- [x] Adding: full ring pulsing between 100% and 45% opacity every 0.9 s each way on FastOutSlowIn (ui/common/DownloadRing.kt:47, ui/common/DownloadRing.kt:103)
- [x] Done while shown: the ring and plus fade as a check draws itself in over 300 ms, short stroke then long, with a glow (10 dp blur at 60% and 3 dp at 70%) rising over 300 ms, held 500 ms, fading over 700 ms; done when first drawn just shows the check (ui/common/DownloadRing.kt:48, ui/common/DownloadRing.kt:72, ui/common/DownloadRing.kt:168)
- [x] The check's points: (24%, 52%), (42%, 70%), (78%, 33%) of the box (ui/common/DownloadRing.kt:174)
- [x] Calm (Reduce motion or animations off): nothing turns, pulses, eases or morphs; only the states change (ui/common/DownloadRing.kt:82, ui/common/DownloadRing.kt:97)

## 34. Mesh shader (used by the glow)

- [x] Four colour pools; each pixel blends them weighted by 1 / (squared aspect-corrected distance + 0.02) (player/MeshBackground.kt:39)
- [x] The coordinates ripple: uv += 0.05 x sin(uv.yx x 3 + time x 0.3) (player/MeshBackground.kt:47)
- [x] Pool centers drift: p0 = (0.20 + 0.18 sin(0.20t), 0.18 + 0.14 cos(0.31t)); p1 = (0.82 + 0.16 cos(0.43t), 0.26 + 0.16 sin(0.37t)); p2 = (0.24 + 0.16 cos(0.53t), 0.78 + 0.14 sin(0.61t)); p3 = (0.80 + 0.14 sin(0.70t), 0.84 + 0.12 cos(0.47t)) (player/MeshBackground.kt:49)
- [x] A grain of +/- 0.004 per channel from fract(sin(dot(coord, (12.9898, 78.233))) x 43758.5453) keeps gradients from banding (player/MeshBackground.kt:60)

## Shared logic to port line for line

Platform-independent Kotlin this area relies on. Port each as written, with its tests.

- `shared/core/src/commonMain/kotlin/app/winters/octo/ui/downloads/Downloads.kt`: the downloads rows and the pill's logic (`pillLead`, `stepWords`, `pillCount`, `pillRecheckMs`, `stillAsked`, `stillAskedForMs`, `pillSpoken`, `runningCount`, `rowOf`, `phaseOf`, `statusOf`). Tests: `shared/core/src/commonTest/kotlin/app/winters/octo/ui/downloads/DownloadsTest.kt`, `app/src/test/java/app/winters/octo/ui/downloads/DownloadsPillTest.kt`.
- `app/src/main/java/app/winters/octo/ui/downloads/DownloadsPill.kt` (pure parts): `comingText`, `ringPhase`. Tests: `app/src/test/java/app/winters/octo/ui/downloads/DownloadsPillTest.kt`.
- `app/src/main/java/app/winters/octo/ambient/AmbientPrefs.kt`: strengths, areas, defaults, `ambientAlpha`, `barTintAlpha`, `ambientColor` (HSL clamp), `composite`, `luminance`, `contrast`, HSL conversions. Tests: `app/src/test/java/app/winters/octo/ambient/AmbienceTest.kt`.
- `app/src/main/java/app/winters/octo/ambient/AmbientSource.kt`: `areaOf`, `hasOwnArtwork`, `ambientSource`. Tests: `app/src/test/java/app/winters/octo/ambient/AmbienceTest.kt`.
- `app/src/main/java/app/winters/octo/ambient/AmbientLayer.kt` (pure part): `barFilm`. Tests: none of its own.
- `app/src/main/java/app/winters/octo/player/MeshBackground.kt` (`MESH` shader source, to Metal). Tests: none.
- `app/src/main/java/app/winters/octo/player/ArtworkPalette.kt`: colour extraction rules and fallbacks; relies on AndroidX Palette's quantizer (dominant, vibrant, light vibrant, dark vibrant, dark muted swatches from 16 colours of a 128 px image), which iOS has no copy of and must reproduce. Tests: none.
- `app/src/main/java/app/winters/octo/player/Position.kt`: `fractionAt`. Tests: none.
- `app/src/main/java/app/winters/octo/ui/common/Swipes.kt`: `dragAxis`, `swipeSkip`, `swipeUp`, and the axis-locking drag. Tests: `app/src/test/java/app/winters/octo/ui/common/SwipesTest.kt`.
- `app/src/main/java/app/winters/octo/ui/common/PressSpot.kt`: `menuAnchor`, the 2 s press window. Tests: `app/src/test/java/app/winters/octo/ui/common/PopupPagesTest.kt` (anchor cases).
- `design/src/main/java/app/winters/octo/design/GlassPopup.kt`: `placePopup`, `PopupSpot.origin`. Tests: `app/src/test/java/app/winters/octo/ui/common/GlassPopupTest.kt`, `desktop-design/src/test/kotlin/app/winters/octo/design/PopupPlacementTest.kt`.
- `design/src/main/java/app/winters/octo/design/PopupPages.kt`: `PageTrail`, `PopupPages`. Tests: `app/src/test/java/app/winters/octo/ui/common/PopupPagesTest.kt`.
- `app/src/main/java/app/winters/octo/ui/common/GlassMenu.kt` (pure part): `menuRowLooks`. Tests: `app/src/test/java/app/winters/octo/ui/common/GlassMenuTest.kt`.
- `app/src/main/java/app/winters/octo/ui/common/Selection.kt`: `Picks`, `SongSelection`, `SelectionTarget`, `SelectionBarState`. Tests: `app/src/test/java/app/winters/octo/ui/common/SelectionTest.kt`.
- `app/src/main/java/app/winters/octo/ui/common/NotInLibrary.kt` (pure parts): `isOutsideLibrary`, `adoptedFinds`, `artworkDescription`, `notInLibraryMarkSize`, `notInLibraryMarkInset`. Tests: `app/src/test/java/app/winters/octo/ui/common/NotInLibraryTest.kt`.
- `design/src/main/java/app/winters/octo/design/OctoMotion.kt`: `MotionScale` (`ms`, `travel`, `scale`, `still`, `of`), springs, durations, easings. Tests: `desktop-design/src/test/kotlin/app/winters/octo/design/TokensTest.kt`.
- `design/src/main/java/app/winters/octo/design/OctoColors.kt` and `OctoTokens.kt`: `mix`, palette, ink, radii, `perceivedLightness`, `LightFillThreshold`, `contentColorFor`. Tests: `desktop-design/src/test/kotlin/app/winters/octo/design/TokensTest.kt`.
- `design/src/main/java/app/winters/octo/design/OctoSwitch.kt` (pure part): `switchThumb`, `SwitchSquish`. Tests: `desktop-design/src/test/kotlin/app/winters/octo/design/ControlStatesTest.kt`.
- `design/src/main/java/app/winters/octo/design/GlazeTabs.kt` (pure part): `gearShiftTint`, `GearShiftTint`. Tests: `desktop-design/src/test/kotlin/app/winters/octo/design/TokensTest.kt`.
- `design/src/main/java/app/winters/octo/design/IconAccents.kt`: `accentStrength`, `accentPose`, `AccentPeak`. Tests: `desktop-design/src/test/kotlin/app/winters/octo/design/TokensTest.kt`.
- `design/src/main/java/app/winters/octo/design/Sliders.kt` (pure part): `snapToSteps`. Tests: `desktop-design/src/test/kotlin/app/winters/octo/design/TokensTest.kt`.
- `design/src/main/java/app/winters/octo/design/Blur.kt`: CSS blur to platform blur conversions. Tests: none.
- `app/src/main/java/app/winters/octo/ui/common/Layout.kt` (pure parts): `asClock`, `asLength`, `songs`, `albums`. Tests: none of their own.
- `app/src/main/java/app/winters/octo/data/UserMessages.kt`: failure words. Tests: none of its own.
- `subsonic/src/main/kotlin/app/winters/octo/subsonic/FamilyLinks.kt`: `parseFamilyLink`, `familyAppLink`, `familyInviteUrl`, `familySignInUrl`, `encodeComponent`, `decodeComponent`. Tests: `subsonic/src/test/kotlin/app/winters/octo/subsonic/FamilyParsingTest.kt`, `shared/core/src/commonTest/kotlin/app/winters/octo/ui/family/HandOverTest.kt`.
- `app/src/main/java/app/winters/octo/ui/imports/ImportShare.kt` (pure parts): `sharedImportOf`, `IMPORT_SHARE_TYPES`, `importFileName`. Tests: `app/src/test/java/app/winters/octo/ui/imports/ImportShareTest.kt`.
- `shared/core/src/commonMain/kotlin/app/winters/octo/health/FixWords.kt`: `DELETE_FROM_DISK` and the other fix words used by the selection bar's delete. Tests: `shared/core/src/commonTest/kotlin/app/winters/octo/health/HealthFixesTest.kt`.
- `tools/icons/icons.json`: the icon set (Phosphor names, weights, per-icon scale); port as the iOS asset list. Tests: none.
