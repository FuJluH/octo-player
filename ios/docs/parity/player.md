# Parity contract: full player

Read from octo-player `origin/main` 0f11df0f (Android app, the design module and the shared Kotlin core). Every line is a behavior the iPhone player must match. Lyrics content (the lyrics pane, the lyrics bar's insides, the lyrics chooser) and sound (equalizer, crossfade, loudness) are covered by their own contracts and only appear here where the player's layout depends on them.

Path shorthand used in the citations:

- `app:` is `app/src/main/java/app/winters/octo/`
- `design:` is `design/src/main/java/app/winters/octo/design/`
- `shared:` is `shared/core/src/commonMain/kotlin/app/winters/octo/`
- `sharedTest:` is `shared/core/src/commonTest/kotlin/app/winters/octo/`
- `appTest:` is `app/src/test/java/app/winters/octo/`

Values marked "Compose default", "Material3 default", "Media3 default" or "reorderable default" are not written in Octo's code; they come from the library at the version origin/main pins (Compose BOM 2026.09.00, Media3 1.11.1, sh.calvin.reorderable 3.1.0, Haze 2.0.0). Dimensions in `dp` map to iOS points one to one; `sp` maps to points before Dynamic Type.

## 1. Opening, closing and the shared artwork

- [x] The full player shows only while `playerOpen` is true and a song is loaded (`now.trackId != null`); it lies over every page, the bottom bar and the downloads pill (app:ui/nav/MainShell.kt:318-322)
- [x] Way in 1: tapping the bar's small player capsule anywhere off its three buttons; TalkBack click label "Open player" (app:ui/nav/BottomBar.kt:326-333) (iPhone: a tap on the small player; VoiceOver action "Open player")
- [x] Way in 2: a swipe up on the bar's round button or capsule: opens when the finger has gone 28dp up, or when it is moving up and flicked faster than 700dp/s at release (app:ui/nav/BottomBar.kt:409-411, 439-452, app:ui/common/Swipes.kt:41-42)
- [x] The swipe up ticks a GestureThresholdActivate haptic as the finger passes 28dp up (once per crossing, re-armed below it); the bar's contents lean with the finger at 0.3x (up only); let go short, they spring back with spring(damping 0.8, stiffness 400) (app:ui/nav/BottomBar.kt:400-423, 439-452) (iPhone: a rigid impact haptic at the 28 pt crossing)
- [x] Way in 3: a home screen widget request (an `openPlayer` counter that goes above 0) opens it once a song is loaded (app:ui/nav/MainShell.kt:202-205) (iPhone: the widget opens the player through its link once a song is loaded)
- [x] Ways out: system back, the close chevron, the pull down (section 3), and every navigation from inside the player: the artist name, the album name, the Sound button and any page opened from the song menu each set `playerOpen = false` first and then push their page on the current tab (app:player/PlayerOverlay.kt:187, app:ui/nav/MainShell.kt:241-245, 326-338) (iPhone: pull down and VoiceOver escape close it; album, artist, Sound and every page opened close it first)
- [x] When the queue empties (no track), both the bar's small player and the full player fold away (app:ui/nav/MainShell.kt:195-201)
- [x] `playerOpen` survives rotation and process recreation (saved state) (app:ui/nav/MainShell.kt:194) (iPhone: scene storage)
- [x] Player enter: whole overlay fades in over tween(400) (Compose tween default easing FastOutSlowIn, cubic-bezier(0.4, 0, 0.2, 1)) (app:ui/nav/MainShell.kt:318-321)
- [x] Player exit: whole overlay fades out over tween(300) (app:ui/nav/MainShell.kt:321)
- [x] The bottom bar fades out over tween(300) as the player opens and back in over tween(300) as it closes (app:ui/nav/MainShell.kt:285-290)
- [x] The downloads pill does the same fade out and in over 300ms (app:ui/nav/MainShell.kt:310-317)
- [x] The ambient glow behind the pages rests (`awake = false`) while the player is open (app:ui/nav/MainShell.kt:268)
- [x] Shared artwork: one shared element key, `"now-playing-art"`, on the bar capsule's 36dp artwork and on the player's artwork card, inside one shared-transition root at the app's top, so the cover flies between them (app:ui/nav/MainShell.kt:262, 303, 325, 360-362)
- [x] The key is the same whatever song is on, so a song change mid-flight cannot break the hand-off (app:ui/nav/MainShell.kt:360-362)
- [x] The flight uses the Compose shared element defaults: bounds move with spring(damping 1, stiffness 400), and the flying cover draws in an overlay above everything while it flies (app:ui/nav/MainShell.kt:303, 325) (iPhone: one flight layer above the bar and the player, spring(1, 400))
- [x] Player side corner morph: the card's corner radius is 50% of its side (a circle) while the overlay is entering or exiting and 3% (`PlayerArtCorner`) once visible, animated as a whole-number percent on the overlay's visibility (Compose default spring, damping 1, stiffness 1500) (app:player/PlayerOverlay.kt:671-687)
- [x] Bar side corner morph (the mirror): the capsule's artwork is 50% (a circle) while the bar is visible and 3% while it is hidden, so it is a soft square while it flies back and rounds into a circle as it lands (app:ui/nav/MainShell.kt:291-306) (iPhone: the flight carries the mirror morph, 3% to a circle)
- [x] The bar only has the shared artwork while it shows the small player capsule; opened by a swipe up on the round button (capsule not shown) there is nothing to fly from and the player's artwork just fades in with the overlay (app:ui/nav/BottomBar.kt:150-179, app:ui/nav/NowPlayingFace.kt:30-46)
- [x] The artwork card stays laid out (only faded) in lyrics mode, so closing from lyrics mode still flies the cover back to the bar (app:player/PlayerOverlay.kt:504-507)
- [x] Bar capsule artwork: 36dp inside a 44dp box, the progress ring over it (2dp accent stroke, round cap, from 12 o'clock, inset 1dp) (app:ui/nav/BottomBar.kt:344-347, app:ui/nav/NowPlayingFace.kt:50-61)
- [x] Background dolly: a 0 to 1 value that follows the overlay's target visibility on its own clock, never extending how long a closed player stays on screen: in = tween(800ms, delay 20ms, cubic-bezier(0.22, 1, 0.36, 1)); out = tween(500ms, cubic-bezier(0.64, 0, 0.78, 0)); starts at 0 (app:player/immersive/PlayerInk.kt:36-55)
- [x] Dolly as a scale: 0.9 + 0.1 x dolly, so the background grows from 90% to 100% on the way in and shrinks back to 90% on the way out (shared:player/immersive/WashClock.kt:79-84)
- [x] The dolly scale applies to the Immersive wash's magnification and to the still Artwork background's scale; it does not apply to the Colour fill or to the Classic background (app:player/immersive/ImmersiveWash.kt:122, app:player/immersive/PlayerBackground.kt:149-153, 164-184)
- [x] Controls rise in as the player opens: the whole controls column slides up from 28dp below with spring(damping 0.68, stiffness 400, threshold 1px) and fades in over tween(380, delay 80); no exit animation of their own (they leave with the overlay fade) (app:player/PlayerOverlay.kt:605-614)
- [x] The rise is tied to the overlay's visibility wherever the controls are placed (upright or sideways); controls that appear later while the player is already open (lyrics mode turned off) do not rise again (app:player/PlayerOverlay.kt:321-327)
- [x] Each opening starts fresh: queue sheet, time card and lyrics chooser closed, pull at 0 (all held inside the overlay, dropped when it closes) (app:player/PlayerOverlay.kt:178-185)
- [x] Lyrics mode survives closing and reopening the player during the app session: the player's view model lives as long as the activity, outside any navigation entry; it is never saved to disk (app:player/PlayerOverlay.kt:168, app:player/PlayerViewModel.kt:207-213)

## 2. Frame, colours and word colour

- [x] Layer order inside the player: a full-screen fill of `base`, then the background (the glass's only source), then all controls (app:player/PlayerOverlay.kt:195-273)
- [x] `base` animates to each new base colour over tween(600) (default easing) (app:player/PlayerOverlay.kt:173)
- [x] The word and icon colour (`ink`) animates to `colors.content` over tween(500) (default easing) and is handed down as the content colour of every word and icon in the player (app:player/PlayerOverlay.kt:174, 253)
- [x] The glass in the player (close button, quality badge, popups over the player) frosts only the background, never the controls (app:player/PlayerOverlay.kt:247-251) (iPhone: Liquid Glass samples what is under it)
- [x] Colours follow the artwork reference, not the song id, so an album plays through without the background flickering (app:player/PlayerViewModel.kt:115-123)
- [x] Colours are worked out again when the artwork reference, the background settings or the Live background switch change; a newer request cancels an older one (app:player/PlayerViewModel.kt:120-135)
- [x] Before colours are ready, and for music with no artwork: `Quiet` = mesh #2A3438, #1A1A1B, #3A4A50, #0A0B0F; base #0C0C0D; no dominant; words white; background fully shown (app:player/ArtworkPalette.kt:28-35, app:player/PlayerViewModel.kt:135)
- [x] Colour picking: the artwork decoded at 128px; Android Palette with at most 16 colours (app:player/ArtworkPalette.kt:53-56) (iPhone: Octo's own palette picker with Palette's rules)
- [x] main = the dominant swatch, else the dark muted swatch, else give up and use `Quiet` (app:player/ArtworkPalette.kt:58)
- [x] bright = the vibrant swatch, else the light vibrant swatch, else main with HSL lightness +0.16 (clamped 0..1) (app:player/ArtworkPalette.kt:59, 70-76)
- [x] deep = the dark vibrant swatch, else the dark muted swatch, else main with HSL lightness -0.18 (app:player/ArtworkPalette.kt:60)
- [x] base = (dark muted swatch, else main) blended 70% toward black (app:player/ArtworkPalette.kt:61)
- [x] mesh = [main, bright, deep, #0A0B0F]; dominant = the dominant swatch (may be absent) (app:player/ArtworkPalette.kt:63-67)
- [x] Colours are cached per artwork reference, the last 32 (app:player/ArtworkPalette.kt:42-51)
- [x] Word colour choice: take the darkest and brightest of what the chosen background draws (`drawnRange`), then `inkOver(range, base)` (app:player/PlayerViewModel.kt:124-134, app:player/immersive/BackgroundPrefs.kt:72-78)
- [x] inkOver: `white` = how much of the background can show over `base` with white words still at 4.5:1 against the brightest part (binary search, 20 halvings, 0..1); dark words (#141416) are used only when they reach 4.5:1 on the darkest part AND `white` < 1; then the background shows in full (show = 1); otherwise white words and show = `white` (shared:player/immersive/WashReading.kt:63-86, 115-131)
- [x] A background both light and dark in places gets white words and some dimming, never dark words over its dark half (shared:player/immersive/WashReading.kt:76-81)
- [x] Until the background's range is known (cover still being prepared): white words, background in full (app:player/immersive/BackgroundPrefs.kt:72-77)
- [x] Range for Immersive: the prepared cover's darkest and brightest block, each channel multiplied by FinalGain (about 0.8765) (app:player/immersive/BackgroundPrefs.kt:63, shared:player/immersive/WashReading.kt:15-18, 58-61)
- [x] Range for Artwork: the prepared cover's range as it is (app:player/immersive/BackgroundPrefs.kt:64)
- [x] Range for Colour: the dominant colour put through the same tuning (contrast, saturation, brightness cap), or `base` when there is no dominant colour (app:player/immersive/BackgroundPrefs.kt:65)
- [x] Range for Classic: the four mesh colours when the mesh is live; when it is not, each mesh colour laid at 60% over base (as the blurred artwork then shows) (app:player/immersive/BackgroundPrefs.kt:66-69)
- [x] Classic counts as live for this when Live background is on and the phone can draw the mesh (app:player/PlayerViewModel.kt:133)
- [x] `show` animates over tween(500, easeInOutCubic) and is the background layer's alpha over `base` (app:player/immersive/PlayerBackground.kt:101-105)
- [x] A colour counts as dark ink when its luminance is under 0.5 (app:player/immersive/PlayerInk.kt:23-24)
- [x] mutedInk (times, album name, volume icons): the dark ink at 60% alpha over a light background; otherwise TextMuted = accent #97B1B9 at 80% (app:player/immersive/PlayerInk.kt:26-29, design:OctoColors.kt:19, 29)
- [x] accentInk (artist name, explicit mark): the dark ink at 75% alpha over a light background; otherwise Accent #97B1B9 (app:player/immersive/PlayerInk.kt:31-34)
- [x] Status bar and navigation bar icons turn dark while the words are dark ink and light otherwise, for as long as the player is open; the previous appearance is put back when it closes (app:player/PlayerOverlay.kt:188, 1095-1117) (iPhone: the status bar style follows the words while the player shows; the home indicator adapts by itself)

## 3. Pull down to close

- [x] A downward drag from anywhere on the player starts the pull (app:player/PlayerOverlay.kt:205-217)
- [x] Only a downward crossing of the vertical touch slop starts it; an upward crossing is ignored and the slop keeps being watched (app:player/PlayerOverlay.kt:212-217)
- [x] Drags that a control already took do not start it: the sliders' sideways drags, the artwork's sideways swipe, scrolling lists (app:player/PlayerOverlay.kt:206-209)
- [x] Cap: 45% of the player's height (app:player/PlayerOverlay.kt:191)
- [x] Resistance: the pull moves 0.82x the finger (the over-slop at the start too), clamped from 0 to the cap; it follows the finger up and down during the drag (app:player/PlayerOverlay.kt:215, 220-222)
- [x] `pulled` = pull / cap, 0 to 1 (app:player/PlayerOverlay.kt:192)
- [x] While pulled: the whole player moves down by the pull (app:player/PlayerOverlay.kt:239)
- [x] While pulled: it shrinks to 1 - 0.06 x pulled (94% at the cap) (app:player/PlayerOverlay.kt:240-241)
- [x] While pulled: it is clipped to a rounded rectangle whose corners reach 28dp a fifth of the way to the cap (radius = 28dp x min(pulled x 5, 1)); no clip at pull 0 (app:player/PlayerOverlay.kt:193-194, 242-243)
- [x] The finger is tracked on the screen, not on the moving player (app:player/PlayerOverlay.kt:236-237)
- [x] Nothing is decided until the finger lifts (app:player/PlayerOverlay.kt:224-226)
- [x] Closes when the release velocity is downward faster than 1200dp/s (app:player/PlayerOverlay.kt:201, 228)
- [x] Also closes when pulled past half the cap (22.5% of the height) and the release is not upward faster than 150dp/s (app:player/PlayerOverlay.kt:199-204, 228)
- [x] Otherwise springs back to 0 with spring(damping 0.8, stiffness 400) (app:player/PlayerOverlay.kt:232)
- [x] A close by pull is not first put back: the player fades out (300ms) from where it was pulled to (app:player/PlayerOverlay.kt:229-231)
- [x] No haptic anywhere in the pull (app:player/PlayerOverlay.kt:198-234)
- [x] The queue sheet, the time card and the menus are outside the pulled layer and never move with it (app:player/PlayerOverlay.kt:275-297) (iPhone: system sheet, popover and menu, outside the pulled layer)

## 4. Layout

- [x] Controls keep clear of the status bar, the navigation bar and the display cutout (app:player/PlayerOverlay.kt:329-335)
- [x] Sideways layout when that inset area is wider than tall; upright otherwise (app:player/PlayerOverlay.kt:337)
- [x] `roomy` = the inset area is at least 360dp tall; only the sideways layout uses it (upright always passes roomy) (app:player/PlayerOverlay.kt:336, 372, 396)
- [x] Upright: 24dp side padding; a column of the top line (56dp), the artwork stage (all the height left, full width), then the controls block (controls, then a 16dp gap) aligned to the bottom (app:player/PlayerOverlay.kt:382-401) (iPhone: the top line is 40 pt and holds only the album name)
- [x] Upright lyrics mode: the artwork folds away in place; the controls block is replaced by the small lyrics bar (64dp tall) with 12dp under it; the bar reaches 12dp past each side margin (app:player/PlayerOverlay.kt:378-393, 416-418, app:player/LyricsBar.kt:57-58)
- [x] Upright lyrics layer: laid out at full size from the start, filling from under the top line (56dp) to above the lyrics bar (64 + 12 = 76dp), with 8dp more padding top and bottom, reaching 24dp past the side padding to the screen's margins (app:player/PlayerOverlay.kt:402-411, 436-456)
- [x] Upright lyrics layer fade: to 1 over tween(360, delay 120) when lyrics open; to 0 over tween(360) when they close; it is only composed while its alpha is above 0; reduced motion snaps (app:player/PlayerOverlay.kt:439-445)
- [x] Lyrics fold (both layouts): the old controls fade out over tween(160), the new ones fade in over tween(240, delay 120) (app:player/PlayerOverlay.kt:430)
- [x] Lyrics fold, upright: the block's height eases over tween(360, FastOutSlowIn), not clipped; sideways the size snaps (app:player/PlayerOverlay.kt:431-433)
- [x] Lyrics fold with reduced motion: everything changes at once, sizes snap (app:player/PlayerOverlay.kt:429)
- [x] Sideways: 24dp side padding, a row with 32dp between its halves, vertically centred (app:player/PlayerOverlay.kt:342-346)
- [x] Sideways left half: the artwork stage, max 420dp, 12dp vertical padding, never folded (lyrics never hide the artwork sideways) (app:player/PlayerOverlay.kt:347-355)
- [x] Sideways right half, normal: the top line then the controls, centred vertically (app:player/PlayerOverlay.kt:369-374)
- [x] Sideways right half, lyrics mode: the top line, the lyrics pane filling the rest with 4dp vertical padding, then the lyrics bar with 8dp under it (app:player/PlayerOverlay.kt:362-368)
- [x] Sideways on a short screen (not roomy): no volume line (the phone's buttons still set it) and the gaps in the controls shrink from 12dp to 4dp (app:player/PlayerOverlay.kt:338-341, 606, 626-629)
- [x] Reduced motion for the player = Octo's Reduce motion setting OR the phone's animator duration scale at 0; the phone's setting is read again every time the app resumes (app:player/PlayerOverlay.kt:320, app:ui/common/ReduceMotion.kt:24-32) (iPhone: iOS Reduce Motion stands in for the animator scale, followed live)

## 5. Top line

- [x] A 56dp tall full-width box: close button at the start, album name centred, Cast then Sound at the end (app:player/PlayerOverlay.kt:458-501) (iPhone: a 40 pt line with the album name centered; close, AirPlay and Sound as below)
- [x] Close button: 44dp circular glaze with a clear film (no dim), frosting the background (4 CSS px frost = 6.93dp blur, saturation 1.1) with the glaze rim and specular, a chevron-down icon 20dp in the content colour (app:player/PlayerOverlay.kt:990-1003, design:Glaze.kt:59-64, 77-83, 112-161, design:Blur.kt:14-15) (iPhone: no close button: pull down and the VoiceOver escape gesture close the player)
- [x] Close button tap closes the player; no ripple or press motion; TalkBack "Close player", role Button (app:player/PlayerOverlay.kt:994-997) (iPhone: pull down and the VoiceOver escape gesture close the player)
- [x] Album name: caption (12sp normal) in mutedInk, one line, ellipsized, centred, kept 104dp from each side, with 8dp vertical padding inside its tap area; no press look (app:player/PlayerOverlay.kt:478-495, design:OctoType.kt:15) (iPhone: the line holds no buttons, so the name keeps 24 pt from each side)
- [x] Album name shows only when: the album name is not blank (app:player/AlbumLabel.kt:9)
- [x] and the album has more than 1 song in the library (app:player/AlbumLabel.kt:10, app:player/PlayerViewModel.kt:89)
- [x] and the album name, trimmed and lowercased, does not end with "- single" (app:player/AlbumLabel.kt:11)
- [x] and the album's bare name differs from the song title's bare name: a trailing "- Single" or "- EP" (any spacing, any case) removed, bracketed extras like "(feat. x)" or "[Remastered]" removed, then compared ignoring case, accents, punctuation, spacing and lookalike letters, with "&" read as "and" (app:player/AlbumLabel.kt:12-21, app:catalog/CatalogMerger.kt:276-284)
- [x] No album id (empty) means no album name; songs found online have no library album, so they never show one (app:player/PlayerViewModel.kt:80-92)
- [x] Tapping the album name opens that album's page (closing the player) only when the song has a non-empty album id and its id does not start with `find:`; otherwise the name is not tappable; click label "Open album", role Button (app:player/PlayerOverlay.kt:474-494) (iPhone: "Open album" is a VoiceOver hint)
- [x] Sound button: 44dp box, tune icon 22dp (app:player/PlayerOverlay.kt:1035-1057) (iPhone: a "Sound" row with its SF Symbol in the player's More menu)
- [x] Sound button lit (glow, full content colour) while the equalizer is on; 45% content colour, no glow while off (app:player/PlayerOverlay.kt:1050-1055, app:player/PlayerViewModel.kt:182-185) (iPhone: the Sound row's subtitle says "Equalizer on" or "Equalizer off")
- [x] Sound button tap closes the player and opens the Sound page; no press look; TalkBack "Sound", state "Equalizer on" or "Equalizer off" (app:player/PlayerOverlay.kt:1043-1047, app:ui/nav/MainShell.kt:335-338) (iPhone: the Sound row closes the player and opens the Sound page)
- [x] Cast button: see section 23 (app:player/PlayerOverlay.kt:497-500) (iPhone: an "AirPlay" row in the More menu opens the system route picker)

## 6. Artwork stage

- [x] Card side = the smaller of maxSide and the stage's width and height; maxSide 312dp upright, 420dp sideways; centred in the stage (app:player/PlayerOverlay.kt:352, 385, 523-524)
- [x] Card: a square of that side, corners 3% of the side once settled (app:player/PlayerOverlay.kt:671-672, 687-688)
- [x] Card shadow (elevation3), three drop shadows in the card's shape: blur 3.46dp black 25% 2dp down; blur 13.86dp black 20% 8dp down; blur 27.71dp black 15% 16dp down (CSS 4/16/32px blur converted at 0.866) (app:player/PlayerOverlay.kt:695, design:GlassPanel.kt:43-47, design:Blur.kt:11-12)
- [x] The picture sits on a #1A1A1B tile until it loads, center-cropped, with a 1dp inner rim of #C8C8C8 at 16% (covers 96dp and up); no "not in library" mark and no TalkBack label in the player (app:player/PlayerOverlay.kt:697, app:ui/common/Artwork.kt:28-67, design:Artwork.kt:15-16)
- [x] Playing: full size. Paused: scaled to 0.84. Animated with spring(damping 0.6, stiffness 300) (app:player/PlayerOverlay.kt:682-694)
- [x] Upright lyrics mode fold: 0 to 1 over tween(300) (snap with reduced motion); alpha = 1 - fold; scale = 1 - 0.08 x fold (app:player/PlayerOverlay.kt:518, 558-563)
- [x] Swipe sideways to skip, only while not folded (app:player/PlayerOverlay.kt:528-529)
- [x] The swipe's axis is decided once, at the first movement past the touch slop: the larger of across and down wins, a tie counts as down; a downward drag is left for the pull to close (app:ui/common/Swipes.kt:14-26, 53-72)
- [x] Once taken, the sideways drag is consumed, so a tap under it does not fire (app:ui/common/Swipes.kt:69, 78)
- [x] The card follows the finger at 0.55x the finger's travel (a nudge, not a page turn) (app:player/PlayerOverlay.kt:539-540)
- [x] While swiped, the card's alpha is also multiplied by 1 - 0.5 x min(|card offset| / half the stage width, 1) (app:player/PlayerOverlay.kt:560)
- [x] Threshold: 88dp of finger travel (not card travel); crossing it outward fires one GestureThresholdActivate haptic; going back under re-arms it (app:player/PlayerOverlay.kt:530, 541-545) (iPhone: a rigid impact haptic at the crossing)
- [x] At release: next when the finger offset is at or past -88dp, or it is left of start and the velocity is -900dp/s or faster (app:ui/common/Swipes.kt:33-34, app:player/PlayerOverlay.kt:531, 548)
- [x] At release: previous when the finger offset is at or past +88dp, or it is right of start and the velocity is +900dp/s or faster (app:ui/common/Swipes.kt:35)
- [x] A skip by flick (threshold not reached) still fires the haptic once, at release (app:player/PlayerOverlay.kt:549)
- [x] Stay: the card springs back to 0 with spring(damping 0.8, stiffness 400) (app:player/PlayerOverlay.kt:581-584)
- [x] Skip: the card carries on the way it was going to half the stage width over tween(120) (left for next, right for previous), then the song changes, then the card starts 20% of the width out on the other side and springs to 0 with spring(damping 0.8, stiffness 300) (app:player/PlayerOverlay.kt:585-588)
- [x] A new swipe cancels a settle still under way and takes over from where the card is (app:player/PlayerOverlay.kt:533-539)
- [x] A drag taken over by something else ends as a drag of 0 with velocity 0, so it stays (app:ui/common/Swipes.kt:82-87)
- [x] Previous here is the player's previous: restart the song when more than 3 s in (Media3 default), otherwise the song before (app:playback/PlaybackConnection.kt:221)
- [x] The swipe has no TalkBack action (app:player/PlayerOverlay.kt:526-566)

## 7. Song, rating, heart and More

- [x] Order under the artwork: [title block (fills) + heart or add button + More], rating, 12dp, progress line, gap, transport, (8dp + volume when roomy), gap, switch row, gap; gap = 12dp when roomy, else 4dp (app:player/PlayerOverlay.kt:606-667)
- [x] The title block cross-fades when the song changes (keyed by track id): fade in tween(250) with fade out tween(150) (app:player/PlayerOverlay.kt:704-708)
- [x] Title: 24sp Bold (the title style is 24sp Black; the player overrides it to Bold), content colour, one line, clipped (no ellipsis) (app:player/PlayerOverlay.kt:712-720, design:OctoType.kt:10)
- [x] A title too long for its line scrolls as a marquee with the Compose defaults: 3 runs, 1.2 s pause before each, a gap of a third of the width, 30dp/s (app:player/PlayerOverlay.kt:718)
- [x] An explicit song's "E" stays put after the title (it does not scroll), 6dp after it: a square tile 14sp on a side, corners 3/14 of its side, the letter "E" (9.5sp Bold) cut out so the background shows through, tile in accentInk; TalkBack "Explicit" (app:player/PlayerOverlay.kt:711-717, app:ui/common/SongTitle.kt:20-36, design:ExplicitMark.kt:34-62)
- [x] Artist: body style (16sp Medium) in accentInk, one line, ellipsized (app:player/PlayerOverlay.kt:721-726, design:OctoType.kt:13)
- [x] Artist tap opens the artist page (closing the player) only when the song has a non-empty artist id; no press look; role Button; no click label (app:player/PlayerOverlay.kt:727-733)
- [x] Library song: heart button, 44dp box, icon 24dp (app:player/PlayerOverlay.kt:765-791)
- [x] Heart in Liked songs: filled heart, full content colour, glowing (app:player/PlayerOverlay.kt:783-788)
- [x] Heart not liked: outline heart at 60% content colour, no glow (app:player/PlayerOverlay.kt:784-786)
- [x] Heart tap toggles Liked songs; liking (not unliking) plays the Pulse gesture: the icon grows to 1.2x at 45% of 300ms and back (linear progress shaped by cubic-bezier(0.2, 0.8, 0.2, 1) up and down); none with reduced motion (app:player/PlayerOverlay.kt:768-776, design:IconAccents.kt:63-76, 91, 115-125)
- [x] Heart TalkBack: "Like", state "In Liked songs" or "Not in Liked songs"; no ripple (app:player/PlayerOverlay.kt:773-780)
- [x] Liking ignores songs found online (ids starting `find:`) (app:player/PlayerViewModel.kt:98-100, app:catalog/Online.kt:17-21)
- [x] Song found online: the add-to-library button (44dp, icon 24dp) stands where the heart would be, once the find record for this very song has loaded; until then an empty 44dp space, never the previous song's button (app:player/PlayerOverlay.kt:744-748, app:player/PlayerViewModel.kt:102-110)
- [x] Add button, not added: a plus at 60% white (always white, not the word colour), no glow (app:ui/common/AddToLibraryButton.kt:165-171) (iPhone: SF Symbol plus)
- [x] Add button tap asks the server to add the song; while it is on its way and the server keeps a download log, a tap follows it in the server downloads sheet instead; disabled once added (app:ui/common/AddToLibraryButton.kt:140-155)
- [x] Add button queued or downloading with no progress: a white 2dp arc covering 90 degrees, turning once per 1600ms linear, over a white 20% track ring, a small plus inside (arm 18% of the width) (app:ui/common/DownloadRing.kt:42-63, 95-101, 125-160)
- [x] Add button downloading with progress: the arc fills from 12 o'clock to the progress, easing over tween(1200, LinearOutSlowIn), never going backwards (app:ui/common/DownloadRing.kt:110-123, 143-153)
- [x] Add button adding to the library: a full ring pulsing its alpha between 1 and 0.45 every 900ms (FastOutSlowIn, reversing) (app:ui/common/DownloadRing.kt:103-108)
- [x] Add button done while shown: the ring and plus fade as a check draws itself in over tween(300, FastOutSlowIn) from its short stroke to its long one (points 24%,52% to 42%,70% to 78%,33%), with a glow that rises over 300ms, holds 500ms and fades over 700ms; a song already added when first drawn shows the check at once (app:ui/common/DownloadRing.kt:69-93, 165-189)
- [x] Add button with reduced motion: no turning, pulsing or drawing in; only the states change (app:ui/common/DownloadRing.kt:65-68, 82-86, 97, 103, 121)
- [x] Add button failed: a white circle with an exclamation mark; tap tries again; long press shows "Could not download: <reason>" (app:ui/common/AddToLibraryButton.kt:150-155, app:ui/common/DownloadRing.kt:191-207)
- [x] Add button TalkBack: "Add to your library", state "Not in your library" / "Queued" / "Downloading" / "Downloading, N percent" / "Adding to your library" / "In your library" / "Could not download"; click labels "Try again" or "Follow it", long-click label "Why" (app:ui/common/AddToLibraryButton.kt:74-85, 152-158)
- [x] A family member whose songs are saved gets a heart instead of the add button: tap toggles Saved; white when saved and glowing, white 60% otherwise; TalkBack "Save" (label constant), state "Saved"/"Not saved" (app:ui/common/AddToLibraryButton.kt:87-130)
- [x] The add button restarts its ring when the player moves on to another song (keyed by song) (app:ui/common/AddToLibraryButton.kt:162-175)
- [x] More button: 44dp box, three-dots icon 24dp in the content colour at 60%, no press look; marks its own bounds as where the menu opens; tap opens the song menu for the song on now (section 12); TalkBack "More", role Button (app:player/PlayerOverlay.kt:752-762) (iPhone: a system Menu from the More button)
- [x] Rating line: 2dp under the title row, one 12dp filled star per point (1 to 5), 2dp apart, colour TextMuted (not the word colour); nothing when the rating is 0 (app:player/PlayerOverlay.kt:619-621, app:ui/common/RatingStars.kt:18-31)
- [x] The rating is the library song's, followed live (a change in the song menu shows at once); 0 for a song found online (app:player/PlayerViewModel.kt:198-205)
- [x] Rating TalkBack: "Rated 1 star" or "Rated N stars" (app:ui/common/RatingStars.kt:24)

## 8. Progress line, times, quality badge and speed mark

- [x] The progress line: a 48dp tall touch area across the full width (app:player/PlayerOverlay.kt:804-813, design:LineSlider.kt:76-79)
- [x] At rest: a 3.5dp round-capped track in the content colour at 24%, the played part in the content colour (app:player/PlayerOverlay.kt:811-812, design:LineSlider.kt:65, 113-126)
- [x] The played part glows: three extra passes of the same line under it, each in the content colour at (glow alpha / 3), blurred by glow blur x 2.5, x 1 and x 0.3 (in pixels); glow alpha 0.4 and glow blur 12 at rest (design:LineSlider.kt:67-68, 115-125)
- [x] Held: the line thickens to 8dp and a thumb of radius 9dp appears at the end, both with spring(damping 0.5, stiffness 200); glow blur goes to 24 and glow alpha to 0.8 with spring(damping 1, stiffness 200) (design:LineSlider.kt:62-68, 128)
- [x] While playing the position is read every frame, so the line glides; it is set at once by a seek; it is taken afresh when the song, the playing state or the duration change (app:player/Position.kt:11-26)
- [x] fraction = position / duration, clamped 0 to 1; 0 when the duration is unknown (app:player/Position.kt:28-29)
- [x] A tap anywhere on the line seeks there (fraction = finger x / width) (design:LineSlider.kt:80-82)
- [x] A drag starts after the horizontal touch slop; the line shows the finger's x (absolute, not relative); the seek is sent once when the finger lifts, so scrubbing never stutters the audio; a cancelled drag sends nothing (design:LineSlider.kt:83-103)
- [x] Seek target = fraction x duration in ms; the shown position jumps there at once (app:player/PlayerOverlay.kt:806-810)
- [x] While the line is dragged the times do not follow the finger; they change after the release (app:player/PlayerOverlay.kt:796-802, 815)
- [x] The line has no TalkBack label or value (as built) (app:player/PlayerOverlay.kt:804-813)
- [x] Duration shown = the player's measured length once it is believable (1 s to 24 h, and the song has not played more than 1 s past it), else the listed length (corrected by lengths learned earlier), and stretched to the position when the song has played past it (app:playback/PlaybackConnection.kt:287, 334-336, app:playback/MediaItems.kt:142-145, shared:playback/SongLength.kt:15-37)
- [x] Times row: pulled 8dp up into the line's touch area (app:player/PlayerOverlay.kt:814)
- [x] Left: elapsed time; right: "-" then the time left; both caption (12sp) with tabular numbers in mutedInk (app:player/PlayerOverlay.kt:803, 815, 825-830)
- [x] Elapsed seconds = floor(position clamped to 0..duration / 1000); left = floor(duration / 1000) - elapsed, never under 0; the texts redraw only once a second (app:player/PlayerOverlay.kt:797-802, 826)
- [x] Time format: "h:mm:ss" when there are hours, else "m:ss" (minutes not zero-padded) (app:ui/common/Layout.kt:68-74)
- [x] Centre of the times row: the quality badge then the speed mark, 8dp apart, vertically centred (app:player/PlayerOverlay.kt:816-824)
- [x] The quality badge only shows once the song's encoding is known (app:player/PlayerOverlay.kt:821)
- [x] Badge: a 24dp tall pill glaze with a clear film, frosting the background; contents padded 10dp each side (app:player/PlayerOverlay.kt:847-857) (iPhone: Liquid Glass capsule)
- [x] Badge, lossless song: a waveform icon 13dp in the content colour, 5dp before the text (app:player/PlayerOverlay.kt:859-866) (iPhone: SF Symbol waveform)
- [x] Badge text, closed: "HI-RES" for lossless above 48 kHz; "LOSSLESS" for FLAC, ALAC and WAV; otherwise the codec in capitals: "MP3", "AAC", "OPUS", "VORBIS", "OGG" (app:player/PlayerOverlay.kt:868, app:playback/Quality.kt:14-28, 63-87)
- [x] Badge closed style: 10.5sp SemiBold, letter spacing 1sp, content colour, one line (app:player/PlayerOverlay.kt:869-872, 892)
- [x] Badge tap opens the full line: codec, then specs, then "plays at X kHz" when the phone's output runs at another rate than the song, joined by " · "; style 11sp normal (app:player/PlayerOverlay.kt:868-869, 893, app:playback/Quality.kt:30-36)
- [x] The full line closes by itself after 4 s; a second tap closes it sooner; a new song's encoding starts it closed (app:player/PlayerOverlay.kt:840-846)
- [x] The badge's width eases between the two texts with spring(damping 0.8, stiffness 400) (app:player/PlayerOverlay.kt:856)
- [x] Lossless specs: bit depth ("8-bit", "16-bit", "24-bit", "32-bit" for 32-bit int or float) and rate; lossy specs: average bitrate (else peak) as "N kbps" (bits / 1000, whole), else the rate (app:playback/Quality.kt:62-71, 89-96)
- [x] Rate text: whole kHz without decimals ("48 kHz"), otherwise one decimal ("44.1 kHz") (app:playback/Quality.kt:98-100)
- [x] Codec from what the decoder reports once the song is open, else from the file's type (app:playback/Quality.kt:39-53)
- [~] While casting there is no "plays at" part (the output rate is unknown) (app:playback/PlaybackConnection.kt:284-285) (not on iPhone: Chromecast dropped; on AirPlay the phone's own output rate is what the session reports)
- [x] Badge TalkBack: "<label>, <full>" with the label not in capitals, e.g. "Lossless, FLAC · 24-bit · 48 kHz"; tappable (app:player/PlayerOverlay.kt:850-851)
- [x] Speed mark: shown only while the speed is not 1x (a pitch shift alone shows nothing) (app:player/PlayerOverlay.kt:822-823)
- [x] Speed mark look: the speed label (e.g. "1.25x"), 10.5sp SemiBold, tabular numbers, letter spacing 0, content colour, one line, padded 4dp all round, no press look (app:player/PlayerOverlay.kt:877-890)
- [x] Speed mark tap opens the time card straight at its Speed page, with no back row (app:player/PlayerOverlay.kt:267-270, 294) (iPhone: popover opening on the Speed page)
- [x] Speed mark TalkBack: "Playback speed 1.25x", role Button (app:player/PlayerOverlay.kt:886-888)

## 9. Transport

- [x] A full-width row, buttons spread evenly, vertically centred: Previous, Play or Pause, Next (app:player/PlayerOverlay.kt:895-911)
- [x] Each button is a 72dp touch box with no ripple (app:player/PlayerOverlay.kt:951-963)
- [x] Icons in the content colour: previous (rewind glyph) 44dp, play or pause 56dp, next (fast-forward glyph) 44dp (app:player/PlayerOverlay.kt:902-909, design:OctoIcons.kt:9-12) (iPhone: SF Symbols at the same sizes)
- [x] Press: the icon shrinks to 0.82 while held and springs back, spring(damping 0.45, stiffness 600) (app:player/PlayerOverlay.kt:946-948, 980-982)
- [x] Previous nudges 8dp left and Next 8dp right on every tap: out over tween(90), back with spring(damping 0.5, stiffness 400); play and pause do not nudge (app:player/PlayerOverlay.kt:902, 909, 955-961, 983)
- [x] Play and pause swap with a pop: the new icon fades in over tween(150) growing from 0.6, the old fades out over tween(100) shrinking to 0.6 (app:player/PlayerOverlay.kt:966-972)
- [x] TalkBack: "Previous", "Play" or "Pause", "Next" (app:player/PlayerOverlay.kt:902-909, 963)
- [x] Play with nothing queued shuffles the whole library; from idle it prepares, then plays (app:playback/PlaybackConnection.kt:170-180)
- [x] Next = Media3 seekToNext; Previous = Media3 seekToPrevious (restart when more than 3 s in, else the song before) (app:playback/PlaybackConnection.kt:219-221)

## 10. Volume

- [x] Shown only when roomy (always upright), 8dp under the transport (app:player/PlayerOverlay.kt:626-629)
- [x] Row: volume-down icon 20dp in mutedInk, the line (10dp padding each side, fills), volume-up icon 20dp in mutedInk (app:player/PlayerOverlay.kt:915-933) (iPhone: SF Symbols speaker icons)
- [x] The line in the content colour at 85%, its track at 24% (same line look as progress) (app:player/PlayerOverlay.kt:928-929)
- [x] Live: every drag step and every tap sets the volume at once (app:player/PlayerOverlay.kt:921-923, design:LineSlider.kt:99-101)
- [x] The value is the phone's media volume as 0 to 1 between the stream's lowest and highest index; it follows the hardware buttons and other apps (the system's volume-changed broadcast) (app:playback/DeviceVolume.kt:23-50) (iPhone: AVAudioSession output volume, followed as the buttons or Control Center move it)
- [x] While casting the value is the TV or speaker's volume, when the device reports one; otherwise the phone's (app:player/PlayerViewModel.kt:144-146, app:playback/PlaybackConnection.kt:296-301) (iPhone: on AirPlay the system volume is the speaker's volume, the same line sets it)
- [x] Setting the phone volume: index = lowest + round(fraction x (highest - lowest)); no system volume panel shows (app:playback/DeviceVolume.kt:44-47) (iPhone: a hidden MPVolumeView sets the system volume, so no volume panel shows)
- [~] Setting a cast device's volume: round(fraction x 20) of 20 steps; the same step sent again is ignored (app:player/PlayerViewModel.kt:148, app:playback/PlaybackConnection.kt:193-197, app:output/RemotePlayer.kt:25-26, 208-215) (not on iPhone: Chromecast dropped; AirPlay speakers take the system volume the line sets)
- [x] Hardware volume buttons while casting move the device one step of 20 instead of the phone (app:MainActivity.kt:122, app:playback/PlaybackConnection.kt:199-206, app:output/RemotePlayer.kt:217-219) (iPhone: on AirPlay the side buttons move the speaker's volume through the system)
- [x] TalkBack: "Volume", no value (app:player/PlayerOverlay.kt:927) (iPhone: VoiceOver "Volume", adjustable, with the level as its value)

## 11. The row of switches

- [x] A full-width row, centred, 20dp between: Lyrics, Up next, Sleep timer, Shuffle, Repeat (app:player/PlayerOverlay.kt:631-666)
- [x] Each: 44dp box, icon 22dp, no ripple, no press motion (app:player/PlayerOverlay.kt:1008-1033)
- [x] On: full content colour with the glow; off: content colour at 45%, no glow (app:player/PlayerOverlay.kt:1026-1031)
- [x] Glow (shared by every lit icon): two blurred copies under the sharp icon, 10dp blur at 60% x glow and 3dp blur at 70% x glow, unbounded edges; the glow fades in and out over tween(300, cubic-bezier(0.2, 0.8, 0.2, 1)), 150ms with reduced motion (design:GlowIcon.kt:17-53, design:OctoMotion.kt:48, 60, 103-149)
- [x] TalkBack for each: its name and a state; the state is "On"/"Off" unless given (app:player/PlayerOverlay.kt:1020-1023)
- [x] Lyrics: lyrics icon; lit while lyrics mode is on; state "Showing"/"Hidden"; tap toggles lyrics mode (app:player/PlayerOverlay.kt:635-641, app:player/PlayerViewModel.kt:209-213)
- [x] Up next: queue icon; never lit; tap opens the queue sheet; TalkBack "Up next", state "Off" (as built) (app:player/PlayerOverlay.kt:642-647)
- [x] Sleep timer: bedtime icon; lit whenever any timer is set (app:player/PlayerOverlay.kt:1064-1067)
- [x] Sleep timer TalkBack state: "N min left" while counting (minutes rounded up), else "Off", "At the end of this song", "After N songs" or "After <song title>" (app:player/PlayerOverlay.kt:1068-1071, shared:playback/SleepPlan.kt:51-57)
- [x] Sleep timer tap opens the time card at its Sleep page (app:player/PlayerOverlay.kt:262-265) (iPhone: popover opening on the Sleep page)
- [x] Sleep badge while counting: the whole minutes left rounded up ((ms + 59,999) / 60,000) (app:player/PlayerOverlay.kt:1062)
- [x] Sleep badge look: white 10sp SemiBold tabular number padded 6dp each side in an 18dp tall pill inset glaze filled with AccentFill (the accent mixed 45% toward black), at the button's top end moved 6dp right and 4dp up; hidden from TalkBack (app:player/PlayerOverlay.kt:1074-1090, design:AccentButton.kt:18-19, design:GlazeInset.kt:22-56) (iPhone: a glass capsule filled with the accent fill)
- [x] Shuffle: shuffle icon; lit while shuffle is on; state "On"/"Off"; tap toggles (app:player/PlayerOverlay.kt:649-654, app:playback/PlaybackConnection.kt:208)
- [x] Turning shuffle on plays by the queue's existing random play order (drawn when the queue was built from nothing), not a fresh draw; songs added later take places by the rules in ShuffleQueue (app:playback/QueueShuffleOrder.kt:24-52, shared:playback/ShuffleQueue.kt:1-65)
- [x] Repeat: repeat icon, or the repeat-one icon in "this song" mode; lit unless off; state "All songs", "This song" or "Off" (app:player/PlayerOverlay.kt:655-665)
- [x] Repeat tap cycles Off, then All, then One, then Off (app:playback/PlaybackConnection.kt:210-217)

## 12. The song menu opened from the player

- [x] It opens over the player as a glass card beside the More button (anchor = the button's bounds), frosting the player's background; TalkBack pane title "Song menu" (app:ui/menu/SongMenuPopup.kt:66-98, app:ui/nav/MainShell.kt:341-342, app:player/PlayerOverlay.kt:756) (iPhone: a system Menu from the More button)
- [x] Opened from the player with no page context, so a library song always offers Go to album and Go to artist (app:player/PlayerOverlay.kt:757, app:ui/menu/SongMenu.kt:131-138)
- [x] Every opening starts at the actions page (app:ui/menu/SongMenu.kt:87-95) (iPhone: a system Menu always opens at its first level)
- [x] Card: 288dp wide, 6dp padding (app:ui/common/GlassMenu.kt:68-70, 161-172) (iPhone: system Menu)
- [x] Header: 40dp artwork with 6dp corners, 12dp gap, title 14sp SemiBold white up to 2 lines, artist caption muted one line; padding 10dp sides, 6dp top, 8dp bottom; then a hairline (white 8%, 14dp in from the sides, 4dp above and below) (app:ui/menu/SongMenuPopup.kt:182-186, 317-321, app:ui/common/GlassMenu.kt:184-194, 252-275) (iPhone: system Menu; the song is the one on screen)
- [x] Rows: at least 40dp, padding 14dp sides and 8dp top and bottom, white icon 20dp, 14dp gap, label 14sp; a quiet accent pill (corners 14dp) shows under the finger instead of a ripple; a row that leads to a page has a 18dp muted chevron (app:ui/common/GlassMenu.kt:196-250, design:OctoTokens.kt:90-94) (iPhone: system Menu rows with SF Symbols; pages are submenus)
- [x] Library song, group 1: Play next; Add to queue; Start radio (app:ui/menu/SongMenu.kt:168-171, 204-205) (iPhone: the first group is a ControlGroup row)
- [x] Library song, group 2: "Add to last playlist: <name>" (only when a playlist was added to lately and still exists); "Add to playlist" (chevron); "Add to Liked songs" or "Remove from Liked songs"; "Rate" (chevron, detail "1 star"/"N stars" when rated); the download row (only for a song not on the phone or one kept downloaded); "Find higher quality" (only when an Octo server can find a FLAC for it) (app:ui/menu/SongMenu.kt:178-187, 206, app:ui/menu/SongMenuPopup.kt:224-280) (iPhone: Add to playlist and Rate are submenus; Rate shows the stars picked)
- [x] Download row words and states: "Download" (tap downloads), "Waiting to download" and "Downloading" (disabled), "Remove download" (downloaded by hand, tap removes with "Download removed" and Undo), "Kept downloaded" (kept by a rule, disabled), "Download failed, try again" (tap retries) (app:ui/menu/SongMenu.kt:224-237, 265-267, app:ui/menu/SongMenuPopup.kt:245-259)
- [x] Library song, group 3: Go to album; Go to artist (app:ui/menu/SongMenu.kt:188-189, 207)
- [x] Library song, group 4: "Share link" (chevron, only when the server can share and has a copy); "Share file" (song file on the phone); "Set as ringtone" (on the phone); "Song info" (chevron); "Find songs" (when the server can run the song's search again) (app:ui/menu/SongMenu.kt:184-185, 190-198, 208, app:ui/menu/SongMenuPopup.kt:264-304) (iPhone: Share link is a submenu; Set as ringtone is left out, iOS lets no app set a ringtone)
- [x] Library song, group 5 (soft red words, white icons): "Remove from my library" (managed family member); "Delete from phone" (on the phone); "Delete from disk" (chevron, when the server lets this user) (app:ui/menu/SongMenu.kt:190-195, 209, app:ui/menu/SongMenuPopup.kt:220-223, 289-299, design:OctoColors.kt:48-49) (iPhone: destructive menu rows)
- [x] Song found online: Play next, Add to queue, Start radio / "Add to your library" ("Adding to your library" and "In your library" disabled with a check; or Save / "Remove from Saved" for a saving family member), "Request a copy" (family, chevron) / "Song info", "Find songs" (when supported) (app:ui/menu/SongMenu.kt:168-199, 216-222, app:ui/menu/SongMenuPopup.kt:202-219)
- [x] Play next: the song goes right after the one on (under shuffle too), menu closes (app:ui/menu/SongMenuPopup.kt:190-193, app:playback/PlaybackConnection.kt:223-227)
- [x] Add to queue: the song goes at the end (before songs Autoplay added), menu closes (app:ui/menu/SongMenuPopup.kt:194-197, app:playback/PlaybackConnection.kt:229, shared:playback/ShuffleQueue.kt:38-45)
- [x] Start radio: menu closes; plays the song then songs like it in place of the queue, named "<title> radio" in the queue; "No similar songs found" when there are none (app:ui/menu/SongMenuPopup.kt:198-201, app:ui/menu/SongMenu.kt:356-374)
- [x] Like toggles in place, the menu stays open (app:ui/menu/SongMenuPopup.kt:269-273)
- [x] Go to album and Go to artist close the menu and the player and open the page on the current tab (app:ui/menu/SongMenuPopup.kt:281-288, app:ui/nav/MainShell.kt:241-245)
- [x] Rate page: a back row "Rate", the song header, then five star targets of 48dp (icons 30dp, 2dp apart, centred): lit stars filled white, others outlined muted; tapping star N sets N, tapping the star the song already has clears the rating to 0; the page stays open; 10dp under the row; TalkBack "1 star"/"N stars" with the selected state on the current one (app:ui/menu/SongMenuPopup.kt:323-362) (iPhone: Rate submenu: the five stars as a picker with the current one ticked, "No rating" clears it)
- [x] The other pages (Add to playlist, Share link, Song info, Delete from disk) follow the song menu's own contract (app:ui/menu/SongMenuPopup.kt:105-127)

## 13. The time card (sleep timer and speed)

- [x] One glass card holds two pages, Sleep timer and Speed; TalkBack pane title "Sleep timer and speed" (app:player/PlayerOverlay.kt:181-184, 283-297, 301-302) (iPhone: the popover carries the VoiceOver label "Sleep timer and speed")
- [x] From the sleep button it opens at the Sleep page as a fresh start (app:player/PlayerOverlay.kt:262-265, design:PopupPages.kt:48-49, 81-83)
- [x] From the speed mark it opens at the Speed page as its first page, so there is no back row (app:player/PlayerOverlay.kt:267-270, 291-295)
- [x] Both pages are 320dp wide (room for three buttons in a row) (app:player/SleepSheet.kt:52-53)
- [x] Where it opens: beside the last press made in the past 2 s; the switch row and speed mark are not marked, so that is the finger's point; with no recent press it is centred (app:ui/common/PressSpot.kt:121-159, app:ui/nav/MainShell.kt:263-264) (iPhone: a popover anchored to the button pressed)
- [x] Placement: 12dp from every screen edge and clear of the status bar, navigation bar and keyboard; under the anchor 6dp away when it fits, else over it when that fits, else on the roomier side pushed back inside (design:GlassPopup.kt:64-110, 114-115) (iPhone: the system popover's placement)
- [x] Horizontal placement: lined up with the anchor's left edge, or with its right edge when the anchor's middle is on the right half of the screen (design:GlassPopup.kt:97-98) (iPhone: the system popover's placement)
- [x] Once open it keeps its side while it still fits there, so turning to the other page does not flip it (design:GlassPopup.kt:69-71, 101-106, 180-181, 247-250) (iPhone: the system popover keeps its arrow while it resizes)
- [x] Size: at most 340dp wide (and the screen width minus 24dp), at most 60% of the screen's height (and the room between the bars); the page scrolls inside (design:GlassPopup.kt:117-121, 242-247)
- [x] Look: corners 20dp, film black 52%, frost 24 CSS px (41.6dp blur) of the player's background, saturation 1.1; glaze rim and specular; an even dark halo (blur 17.3dp, black 50%); a 1dp white hairline at 6% just inside the rim; a pooled shadow under it (blur 20.8dp, black 45%, 8dp down, cast by a shape 12dp smaller all round) (design:GlassPopup.kt:112, 124-129, 209-228, design:Glaze.kt:198-231) (iPhone: a Liquid Glass popover)
- [x] Grows in: alpha 0 to 1 and scale 0.92 to 1 from the corner nearest the anchor (the middle when centred), tween(160, cubic-bezier(0.2, 0.8, 0.2, 1)); shrinks away the same way (design:GlassPopup.kt:47-62, 199-226) (iPhone: the system popover's own motion)
- [x] Reduced motion: fades only, over 80ms; phone animations off: appears at once (design:GlassPopup.kt:174-207) (iPhone: the system popover follows Reduce Motion)
- [x] Closes on a tap outside the card (when the finger lifts) or on back (design:GlassPopup.kt:186-189, 230-239) (iPhone: a tap outside closes the popover; VoiceOver escape too)
- [x] Back from the Speed page (opened from Sleep) goes back to Sleep instead of closing (app:player/PlayerOverlay.kt:289, design:PopupPages.kt:73-79) (iPhone: the back row, or the VoiceOver escape gesture, goes back to Sleep)
- [x] Turning a page: the new page slides in from a third of its width on the side it goes (deeper comes from the right) with spring(damping 0.9, stiffness 500) and fades in over tween(180, delay 40, cubic-bezier(0.2, 0.8, 0.2, 1)); the old one slides a third the other way and fades out over tween(80); the card eases to the new size with the same spring, clipped (design:PopupPages.kt:89-117, design:OctoMotion.kt:26, 33-42) (iPhone: pages push from the side they go, on a spring)
- [x] Turning a page with reduced motion or animations off: fade in 80ms, fade out 40ms, the size snaps (design:PopupPages.kt:95-104) (iPhone: with Reduce motion pages cross-fade)
- [x] A page whose own height changes eases to it with spring(damping 0.9, stiffness 500), snapping with reduced motion (design:PopupPages.kt:114-115) (iPhone: the popover eases to the page's size)

## 14. Sleep timer page

- [x] Column 320dp wide that scrolls, padding 20dp sides, 18dp top, 10dp bottom (app:player/SleepSheet.kt:66-71)
- [x] "Sleep timer" in body style (16sp Medium) white (app:player/SleepSheet.kt:72)
- [x] With a timer set: 12dp, then a row (app:player/SleepSheet.kt:73-76)
- [x] Counting: a large clock of the seconds left rounded up ((ms + 999) / 1000) as "m:ss" or "h:mm:ss", 32sp Black, -0.5sp tracking, tabular numbers, white, filling the row (app:player/SleepSheet.kt:77-83, design:OctoType.kt:9)
- [x] Song-based timer: its summary in body style white, at most 2 lines, ellipsized: "At the end of this song", "After 2 songs", "After <title>" (app:player/SleepSheet.kt:84-92, shared:playback/SleepPlan.kt:51-57)
- [x] Then a "Cancel" glaze button: turns the timer off and closes the card (app:player/SleepSheet.kt:94-97)
- [x] Counting: 12dp, then "+5 min" and "+10 min" glaze buttons 10dp apart; each adds that much and the card stays open (app:player/SleepSheet.kt:99-107, shared:playback/SleepPlan.kt:24-25)
- [x] The clock moves once per whole second, and ten times a second over the last 30 s (app:playback/SleepTimer.kt:97-109, shared:playback/SleepPlan.kt:43-48)
- [x] 20dp, then a wrapping row (10dp gaps across and down) of glaze buttons: "5 min", "15 min", "30 min", "45 min", "1 hour", "Custom" (app:player/SleepSheet.kt:109-121, shared:playback/SleepPlan.kt:21-22)
- [x] A length starts a countdown of that many minutes (replacing any timer) and closes the card (app:player/SleepSheet.kt:115-118)
- [x] "Custom" shows the custom minutes field below (app:player/SleepSheet.kt:120, 136-142)
- [x] 16dp, "Stop after" in label style (13.5sp SemiBold) in the accent, 10dp, then a wrapping row (10dp gaps) of "This song", "2 songs", "3 songs", "5 songs"; each starts that timer and closes the card (app:player/SleepSheet.kt:122-135, shared:playback/SleepPlan.kt:27-28, design:OctoType.kt:16)
- [x] Custom field: 16dp, then a row: a sunken text field (digits only, at most 3 characters typed, placeholder "Minutes, 1 to 720", number keyboard with a Done key) that takes focus and opens the keyboard as it appears; 10dp; an accent "Start" button enabled only for 1 to 720 (app:player/SleepSheet.kt:173-194, shared:playback/SleepPlan.kt:30-31) (iPhone: numbers keyboard with a Done key)
- [x] Done on the keyboard, or Start, starts the countdown and closes the card; an invalid value does nothing (app:player/SleepSheet.kt:138-141, 188, 192)
- [x] The custom field is hidden again whenever the Sleep page is shown afresh (a new opening, or coming back from Speed) (app:player/SleepSheet.kt:64, design:PopupPages.kt:98-116)
- [x] 16dp, then the "Playback speed" line: full width, 12dp padding top and bottom, a ripple on tap; "Playback speed" 14sp white (fills), the current speed 14sp tabular (muted at 1x, white otherwise), a chevron-right 20dp muted 6dp after it; tap opens the Speed page with a way back (app:player/SleepSheet.kt:143-171) (iPhone: a soft wash under the finger)
- [x] Glaze button look: 50dp tall pill, 24dp side padding, 13.5sp SemiBold white words, glaze film black 16% (no blur of its own), brighter rim light under the finger, shrinks to 0.96 over 80ms when pressed (design:GlazeButton.kt:18-56, design:Buttons.kt:41-46, 73-96, design:Glaze.kt:38-59) (iPhone: glass buttons)
- [x] Accent button look: 50dp tall pill filled with AccentFill, words white or black by the fill's lightness, 50% alpha when disabled, shrinks to 0.96 when pressed (design:AccentButton.kt:18-60)
- [x] Sunken field look: 48dp tall, corners 12dp, accent fill 10% (15% while typing), inner shadows, a 1.5dp accent ring at 60% fading in while focused, body text white, accent cursor, muted placeholder, 14dp side padding (design:GlassInput.kt:34-112) (iPhone: a glass input field)

### Sleep timer behavior

- [x] The countdown runs on the device's elapsed-time clock (keeps counting while the phone sleeps); starting replaces any timer of any kind (app:playback/SleepTimer.kt:51, 97-109)
- [x] Last 30 s: the phone player's volume follows (time left / 30 s) squared down to silence (app:playback/SleepTimer.kt:163-167, shared:playback/SleepPlan.kt:33-41)
- [x] At 0 the music pauses, the timer turns off and the volume returns to full (app:playback/SleepTimer.kt:147-156, 140-145)
- [x] Adding time only works while counting, and lifts a fade already begun (app:playback/SleepTimer.kt:117-122)
- [x] While casting the fade does not change the device's volume (only the phone's); the pause at 0 still pauses the device (app:output/OutputSwitch.kt:44-49) (iPhone: on AirPlay the fade is the player's own gain, never the speaker's volume; pause pauses)
- [x] "This song" = end of this song: the player pauses when the current song ends; the timer turns off when that pause happens (app:playback/SleepTimer.kt:63-67, 111-115, 124-126)
- [x] 2, 3 or 5 songs: counts songs that end on their own (a natural move on, a repeat, or the queue changing while a crossfade runs); skips do not count; with 2 left it becomes "end of this song", otherwise one fewer (app:playback/SleepTimer.kt:36-41, 69-76, 124-130)
- [x] Stop after a song in the queue (from the queue row menu): pauses when that queue entry ends; when it is the song on now it is "end of this song"; it turns off if that entry leaves the queue (app:playback/SleepTimer.kt:77-81, 132-138, 169-173)
- [x] Cancel: off, full volume, no pause at the end of the song (app:playback/SleepTimer.kt:140-145)
- [x] The timer goes when the playback service stops (app:playback/SleepTimer.kt:90-95) (iPhone: the timer goes when the player stops (Close on the lock screen, sign out, the app ending))

## 15. Speed and pitch page

- [x] Column 320dp wide that scrolls (app:player/SpeedSheet.kt:80)
- [x] Opened from the Sleep page: a back row first (6dp padding round it): a white chevron-left 18dp, 4dp, "Sleep timer" in label style, at least 40dp tall, quiet pill under the finger, click label "Back", heading for TalkBack; then a hairline (app:player/SpeedSheet.kt:81-83, app:ui/common/GlassMenu.kt:277-306)
- [x] Controls padded 20dp sides, 8dp top, 18dp bottom (app:player/SpeedSheet.kt:105)
- [x] A 48dp tall row: "Speed" body style white (fills), and a "Reset" glaze button while speed, keep pitch or pitch differ from 1x, on, 0 (app:player/SpeedSheet.kt:106-109, app:player/PlayerSettings.kt:100-101)
- [x] Reset puts all three back to their defaults (app:player/SpeedSheet.kt:67-69, app:player/PlayerSettings.kt:277-284)
- [x] 8dp, then the speed label large: 32sp Black, tabular numbers, white (app:player/SpeedSheet.kt:110-111)
- [x] Speed slider: the glowing line (white on white 24%), live; the speed from 0.5x at the left to 2x at the right, linear (app:player/SpeedSheet.kt:112-123, shared:playback/Pace.kt:7-9, 33-39)
- [x] The slider snaps: within 0.04 of 0.75, 1, 1.25 or 1.5 it lands on that speed; otherwise on the nearest 0.05, kept to two decimals (app:player/SpeedSheet.kt:114-117, shared:playback/Pace.kt:11-31)
- [x] A new speed is saved only when it differs from the current one (app:player/SpeedSheet.kt:116)
- [x] Speed slider TalkBack: "Playback speed", state the speed label (app:player/SpeedSheet.kt:119-122)
- [x] Under the slider, the common speeds "0.75x", "1x", "1.25x", "1.5x", each centred under its spot on the line (kept inside the width), caption tabular, white for the current speed and muted otherwise, padded 6dp across and 4dp down, no press look; a tap jumps straight to it (app:player/SpeedSheet.kt:163-191)
- [x] Speed label format: "1x", "2x", "0.75x", "1.25x", "1.1x" (whole number alone; one decimal when the hundredths are 0; two otherwise) then "x" (shared:playback/Pace.kt:60-71)
- [x] 16dp, then a row padded 4dp top and bottom: "Keep pitch" 14sp white with a caption under it (muted): "Voices sound as usual at any speed." when on, "Pitch rises and falls with the speed, like a record." when off; 12dp before the switch (app:player/SpeedSheet.kt:126-137)
- [x] The switch: 36 by 22dp track, 18dp white thumb, accent track glowing faintly when on, white 18% recessed track when off, slides over 200ms, the thumb stretches to 1.18x toward where it goes while held (design:OctoSwitch.kt:34-38, 41-58, 68-151) (iPhone: Octo's switch)
- [x] 12dp, then a row: "Pitch" 14sp white (fills) and the pitch label 14sp tabular ("+2 st", "0 st", "-3 st"), muted at 0 and white otherwise (app:player/SpeedSheet.kt:139-147, shared:playback/Pace.kt:73-74)
- [x] Pitch slider: live, from -6 semitones at the left to +6 at the right in whole steps (round(fraction x 12) - 6); saved only when different; TalkBack "Pitch", state the label (app:player/SpeedSheet.kt:148-159, shared:playback/Pace.kt:20-21, 41-46)
- [x] What the player is told: speed = the snapped speed; pitch = (1 with Keep pitch on, else the speed) x 2^(semitones / 12) (shared:playback/Pace.kt:48-58)
- [x] Every change is heard at once and kept for every song and after restarts; defaults 1x, Keep pitch on, 0 semitones (app:player/PlayerSettings.kt:56-60, 265-275, app:playback/OctoPlaybackService.kt:229)
- [x] Stored speed is snapped again when read, stored pitch is held to -6..+6 (app:player/PlayerSettings.kt:201-204)
- [~] While casting the speed and pitch do not apply (the device player has no speed command) (app:output/RemotePlayer.kt:44-50, 558-585) (not on iPhone: Chromecast dropped; on AirPlay speed and pitch apply as on the phone)
- [x] The same page also opens on its own as a card titled "Speed" from the playback settings, with no back row (app:player/SpeedSheet.kt:88-101) (iPhone: a popover from the Speed row in Playback settings, with no back row)

## 16. Queue sheet: container

- [x] The "Up next" button opens a panel rising from the bottom over a dimmed screen, inside the player (outside the pulled layer) (app:player/PlayerOverlay.kt:275, app:player/QueueSheet.kt:95) (iPhone: a system sheet with detents)
- [x] Dim: black 45% over the whole screen, fading in and out over tween(200, cubic-bezier(0.2, 0.8, 0.2, 1)) (100ms with reduced motion); a tap on it closes the sheet (design:GlassSheet.kt:74-82) (iPhone: the system sheet's dim; a tap on it closes)
- [x] Panel in: slides up from its full height with spring(damping 0.85, stiffness 400) (the spring is not reduced by Reduce motion) (design:GlassSheet.kt:83-86) (iPhone: the system sheet's own motion)
- [x] Panel out: slides down by its full height over tween(200, cubic-bezier(0.4, 0, 1, 1)) (100ms with reduced motion) (design:GlassSheet.kt:86, design:OctoMotion.kt:75) (iPhone: the system sheet's own motion)
- [x] Panel: full width, at most 70% of the screen's height, top corners 28dp, fill = page colour #0C0C0D mixed 5% toward the accent at 97% alpha (no blur), a shadow (blur 27.7dp, black 40%), a 1dp white 10% light line along the top inside edge, clear of the navigation bar (design:GlassSheet.kt:50-53, 94-105) (iPhone: a system sheet)
- [x] Taps on the panel never reach the dim area (design:GlassSheet.kt:103-104)
- [x] Handle: a 36 by 4dp pill in the muted colour, centred, in a full-width strip padded 12dp top and bottom (app:player/QueueSheet.kt:95, design:GlassSheet.kt:107-128) (iPhone: the sheet's drag indicator)
- [x] Dragging the handle strip down moves the panel with the finger (never above its rest); let go past 96dp, or flicked down faster than 1200dp/s, it closes; otherwise it springs back with spring(damping 0.8, stiffness 400) (design:GlassSheet.kt:108-123) (iPhone: the system sheet's drag to close)
- [x] Back closes the sheet before the player (design:GlassSheet.kt:71, app:player/PlayerOverlay.kt:187, 275) (iPhone: the sheet sits over the player; it closes first)
- [x] Its lines are laid out as a column; the list takes the room left; when everything is taller than the room the whole column scrolls (design:GlassSheet.kt:129-131, design:SheetColumn.kt:60-154) (iPhone: the heading and tools stay, the list takes the room left and scrolls)

## 17. Queue sheet: heading, summary and tools

- [x] "Up next" in section style (18sp Bold) white, padded 20dp each side (app:player/QueueSheet.kt:186-187, design:OctoType.kt:12)
- [x] Under it, a caption in the muted colour: "<songs> · <length>" of the listener's own songs still to come (after the song on now), plus " · N from Autoplay" when Autoplay added songs (app:player/QueueSheet.kt:188, 310-316)
- [x] Song count words: "1 song", "N songs"; length: total seconds rounded to the nearest minute, "N min", or "H hr M min" from 60 minutes (app:ui/common/Layout.kt:76-82)
- [x] The summary counts the rows as drawn, so it changes at once while a row is dragged or swiped away (app:player/QueueSheet.kt:169, 188)
- [x] A row of tools that scrolls sideways when it does not fit, padded 8dp sides and 4dp top and bottom, 2dp between: "Now playing", "Clear", "Remove played", "Save as playlist" (app:player/QueueSheet.kt:190-198)
- [x] Tool look: label style (13.5sp SemiBold), one line, padded 12dp across and 10dp down; the accent when it can act, muted and untappable when not; a ripple on tap (app:player/QueueSheet.kt:318-330) (iPhone: a soft wash under the finger)
- [x] "Now playing": enabled while a song is on; scrolls the list (animated) so the song on now is at the top (app:player/QueueSheet.kt:194)
- [x] "Clear": enabled when anything other than the song on is in the queue; takes out everything but the song on; shows "Queue cleared" with Undo (app:player/QueueSheet.kt:195, app:player/PlayerViewModel.kt:159-163)
- [x] "Remove played": enabled when songs were played before the one on; takes them out; "Played songs removed" with Undo (app:player/QueueSheet.kt:196, app:player/PlayerViewModel.kt:165-168)
- [x] "Save as playlist": enabled while a song is on; opens the save form (section 21) (app:player/QueueSheet.kt:197)

## 18. Queue sheet: the list

- [x] The list opens with the song on now at the top (the played songs are above it, scrolled out of view) (app:player/QueueSheet.kt:172)
- [x] List padding: 4dp at the top, 12dp at the bottom (app:player/QueueSheet.kt:199-203)
- [x] Order: songs already played (oldest first), the song on now, the shuffle note, then the songs to come in the order they will play, under their part headings (app:player/QueueSheet.kt:204-296, app:playback/UpNext.kt:138-149)
- [x] The order shown follows the play order (shuffled when shuffle is on), not the queue's stored order, and never runs longer than the queue (app:playback/PlaybackConnection.kt:303-332, app:playback/UpNext.kt:151-161)
- [x] Each song keeps one key for as long as it is in the queue, so the same song twice is two rows (app:playback/UpNext.kt:126-136, app:playback/QueueEntries.kt:112-126)
- [x] Song row: 56dp tall, full width, 12dp between parts, vertically centred: artwork 44dp with 6dp corners (with the "not in library" corner mark for songs outside the library), then title and artist (fills), then an "Autoplay" tag for a song Autoplay added, then the drag handle when it can move (app:player/QueueSheet.kt:367-384)
- [x] Row title: 14sp normal white, one line, ellipsized before the explicit "E" (muted), which always shows (app:player/QueueSheet.kt:378, app:ui/common/SongTitle.kt:16-36)
- [x] Row artist: caption muted, one line, ellipsized (app:player/QueueSheet.kt:379)
- [x] "Autoplay" tag: caption muted (app:player/QueueSheet.kt:381)
- [x] Played rows: at 50% opacity, padded 20dp each side; tap plays that song (click label "Play"); long press opens its menu (long-click label "Song options") (app:player/QueueSheet.kt:79-80, 204-217) (iPhone: long press opens a context menu; VoiceOver "Play" action)
- [x] The song on now: in an inset glaze card, corners 12dp, filled with #1A1A1B mixed 12% toward the accent, 12dp in from the sides and 4dp above and below; the row inside padded 8dp each side; tap does nothing (no click label); long press opens its menu (app:player/QueueSheet.kt:76-77, 218-237) (iPhone: a glass card; long press opens a context menu)
- [x] Shuffle note: while shuffle is on and songs are to come, "Turn off shuffle to reorder" as a muted caption padded 20dp across and 8dp down (app:player/QueueSheet.kt:239-248)
- [x] Part headings: the songs to come are cut into runs by where they came from, in play order; songs from one source that are apart get runs of their own (app:player/QueueSheet.kt:249-254, shared:playback/QueueSources.kt:30-40)
- [x] Heading words: "Next from you" (the listener's own picks), "Next from Autoplay", "Next from <list name>" (e.g. "Next from OK Computer", "Next from <title> radio"), or "Up next" for a list with no name (shared:playback/QueueSources.kt:3-28)
- [x] Headings show only when there is more than one run, or the only run is from a named source or the listener or Autoplay (a single unnamed list needs no heading under "Up next") (app:player/QueueSheet.kt:249-252)
- [x] Heading look: caption muted, padded 20dp sides, 12dp top, 4dp bottom (app:player/QueueSheet.kt:299-308)
- [x] Rows to come: an opaque fill (#0C0C0D mixed 5% toward the accent) in a 12dp rounded shape so a moving row hides what is under it; padded 20dp each side; tap plays that song (label "Play"); long press opens its menu (label "Song options") (app:player/QueueSheet.kt:71-74, 274-285) (iPhone: long press opens a context menu; VoiceOver "Play" action)
- [x] Tapping a played or coming song jumps straight to it and plays (app:player/QueueSheet.kt:213, 283, app:playback/PlaybackConnection.kt:235-239)
- [x] Long press on any row: a LongPress haptic from the code, plus the long-press haptic Compose's combined click gives by default (as built); then the row's menu (app:player/QueueSheet.kt:181-184) (iPhone: the context menu's own haptic)
- [x] Rows have the default ripple on tap (app:player/QueueSheet.kt:209-214, 279-284) (iPhone: no ripple on iOS rows)
- [x] A song's source tag stays with it when it is moved on the phone (the shared rule that re-tags a moved song is used by the desktop only) (shared:playback/QueueSources.kt:42-56)

## 19. Queue sheet: drag to reorder

- [x] Only songs to come can move, and only while shuffle is off (no handle while shuffle is on) (app:player/QueueSheet.kt:256, 286-290)
- [x] Handle: a 40dp box at the row's end with two 18dp lines 8dp apart, 2dp round-capped, muted; TalkBack "Reorder" (app:ui/common/ListEdits.kt:30-44)
- [x] Dragging starts from the handle at once (no long press) (app:player/QueueSheet.kt:289)
- [x] While dragged the row floats with the elevation3 shadow in its rounded shape over its opaque fill (app:player/QueueSheet.kt:277-278)
- [x] The rows move at once as the dragged row passes them; each swap ticks a SegmentFrequentTick haptic; only song rows swap (headings, played rows and the song on now are passed over) (app:player/QueueSheet.kt:168-180) (iPhone: a selection haptic on each swap)
- [x] The list scrolls by itself when the dragged row nears its top or bottom (reorderable default: within 48dp) (app:player/QueueSheet.kt:173)
- [x] Other rows slide to their new places (reorderable default item animation) (app:player/QueueSheet.kt:256)
- [x] The queue changes only on drop: the song goes to the queue position of the song that was at the place it landed; nothing is sent when it lands where it started (app:player/QueueSheet.kt:257-262, app:playback/PlaybackConnection.kt:231-233)
- [x] While a row is dragged it cannot be swiped (app:player/QueueSheet.kt:267)
- [x] The rows as drawn reset to the queue whenever the queue changes (app:player/QueueSheet.kt:168-169)

## 20. Queue sheet: swipe to remove

- [x] Rows to come swipe left only (right does nothing) (app:player/QueueSheet.kt:263-266)
- [x] Behind a row being swiped left: a red wash (#EF4444 at 25%) in the row's 12dp shape, padded 24dp across, a white bin icon 22dp at the end (TalkBack "Remove") (app:player/QueueSheet.kt:272, app:ui/common/ListEdits.kt:27-28, 131-141)
- [x] It removes when let go past the threshold or flicked (Material3 swipe-to-dismiss defaults: 56dp, or faster than 125dp/s) (app:player/QueueSheet.kt:263-271)
- [x] The row leaves the drawn list at once, then the song comes out of the queue by its key (so a quick second swipe never takes the wrong song) and "Removed from the queue" shows with Undo (app:player/QueueSheet.kt:268-271, app:player/PlayerViewModel.kt:152-157)
- [x] Played rows and the song on now cannot be swiped (app:player/QueueSheet.kt:204-237)

## 21. Queue row menu and saving the queue

- [x] A long press opens a glass card (same card as section 13) titled for TalkBack "Song in the queue", beside the finger's point (rows are not marked, so the anchor is the finger), frosting the player's background (app:player/QueueSheet.kt:116-125, app:ui/nav/MainShell.kt:263-264) (iPhone: a context menu on the row, the row lifted above it)
- [x] The song stays in the card while it fades away after closing (app:player/QueueSheet.kt:87-89, 123) (iPhone: the context menu's own fade)
- [x] Card: 288dp wide, 6dp padding; header: 40dp artwork with 6dp corners (with the "not in library" mark when outside the library), title 14sp SemiBold up to 2 lines, artist caption one line; then a hairline (app:player/QueueSheet.kt:332-343) (iPhone: the context menu's lifted row shows the song)
- [x] Played song: "Play next", a hairline, "Remove from queue" (app:player/QueueSheet.kt:345-364)
- [x] Song on now: only "Stop after this song" (app:player/QueueSheet.kt:345-357)
- [x] Song to come: "Play next", "Stop after this song", a hairline, "Remove from queue" (app:player/QueueSheet.kt:345-364)
- [x] Icons: play-next icon, bedtime icon, bin icon; "Remove from queue" is in white words (not the red destructive style) (app:player/QueueSheet.kt:346, 352, 359)
- [x] "Play next" moves that same queue entry to right after the song on now (under shuffle too); no message; card closes (app:player/QueueSheet.kt:346-349, app:player/PlayerViewModel.kt:170, app:playback/QueueEditor.kt:72-82)
- [x] "Stop after this song" sets the sleep timer to stop after that entry and shows "Stops after <title>" with Undo (Undo turns the timer off); card closes (app:player/QueueSheet.kt:352-355, app:player/PlayerViewModel.kt:192-196)
- [x] "Remove from queue" removes it with "Removed from the queue" and Undo; card closes (app:player/QueueSheet.kt:359-362, app:player/PlayerViewModel.kt:152-157)
- [x] Save as playlist: a glass card titled for TalkBack "Save as playlist", beside the finger, 288dp wide, 6dp padding: heading "New playlist" (13.5sp SemiBold white, padded 14dp sides, 10dp top, 6dp bottom, a TalkBack heading), then padded 8dp sides, 6dp top, 10dp bottom: a sunken text field (placeholder "Playlist name", sentence capitals, Done key) that takes focus and opens the keyboard, 8dp, an accent "Create" button enabled once the name is not blank (app:player/QueueSheet.kt:126-137, app:ui/playlist/PlaylistSheets.kt:466, app:ui/common/PopupForms.kt:83-147) (iPhone: a popover beside the button)
- [x] Create (or Done with a name): a new playlist of the played songs, the song on now and the songs to come, in play order, leaving out songs Autoplay added and radio stations; "Saved as <name trimmed>" shows; the card closes and the keyboard goes away (app:player/PlayerViewModel.kt:172-178, app:player/QueueSheet.kt:90-93, 133-136)

## 22. Queue edits, undo and messages

- [x] Every edit goes by the song's queue key, never its position (app:player/PlayerViewModel.kt:152-157, app:playback/QueueEditor.kt:53-58)
- [x] An edit with nothing to do (song already gone, nothing played) does nothing and shows no message (app:playback/QueueEditor.kt:94-103, app:player/PlayerViewModel.kt:155, 161, 166)
- [x] Undo puts every song back at its old position and restores the shuffle order, but only when the queue has not changed some other way since; otherwise Undo does nothing (app:playback/QueueEditor.kt:84-92, shared:playback/QueueRuns.kt:3-23)
- [x] Songs are taken out in runs from last to first, so taking one out never moves the next (shared:playback/QueueRuns.kt:25-34)
- [x] Messages show as a glass pill above where the bottom bar sits (navigation bar + 14 + 56 + 10dp up), over the player too, frosting the page behind the player, at most 520dp wide, at least 48dp tall, 20dp from the sides (app:ui/common/Feedback.kt:95-140) (iPhone: a glass pill in a window of its own, over the player)
- [x] Message words 14sp Medium white, up to 2 lines; "Undo" 14sp SemiBold white in a pill padded 14dp across and 8dp down; padding 20dp start, 6dp end when there is an action, 12dp top and bottom (app:ui/common/Feedback.kt:149-186)
- [x] A message stays 3.5 s, or 6 s when it offers Undo; a new message replaces the one showing; tapping a message without an action puts it away; tapping Undo undoes and puts it away (app:ui/common/Feedback.kt:55-91, 141-147, 180-183)
- [x] Message motion: grows in from 0.92 and 10dp lower with spring(damping 0.85, stiffness 500), anchored at its bottom middle; leaves over tween(160, FastOutLinearIn); with the phone's animations off it only fades, 120ms each way (app:ui/common/Feedback.kt:98-137)
- [x] TalkBack reads messages politely as they appear (app:ui/common/Feedback.kt:140)

## 23. Cast button and where music plays

- [x] Cast button: 44dp box in the top line, no press look; tap opens the device list as a glass card anchored to the button's own bounds (app:ui/output/OutputSheet.kt:84-116) (iPhone: an "AirPlay" row in the player's More menu opens the system route picker)
- [x] Icon 22dp: the cast icon while on the phone; the cast-connected icon while connecting or casting (app:ui/output/OutputSheet.kt:108-113) (iPhone: the AirPlay row's SF Symbol, its subtitle saying where the music plays)
- [x] Lit (glow, full content colour) only while casting; 45% content colour while on the phone or still connecting (app:ui/output/OutputSheet.kt:91, 108-113) (iPhone: the AirPlay row's subtitle says where the music plays)
- [x] TalkBack "Cast", state "Playing on <device>", "Connecting to <device>" or "Playing on this phone" (app:ui/output/OutputSheet.kt:98-105) (iPhone: VoiceOver reads "AirPlay" and "Playing on <device>" or "Playing on this iPhone")
- [x] Device list card: TalkBack title "Play on", 300dp wide, scrolls, 6dp padding (app:ui/output/OutputSheet.kt:132-133) (iPhone: the system AirPlay picker)
- [x] It looks for devices only while open; "looking" lasts the first 8 s (app:ui/output/OutputSheet.kt:123-126, app:output/Outputs.kt:23-25, 126-145) (iPhone: the system AirPlay picker looks for speakers while it is open)
- [x] Group titles: label style (13.5sp SemiBold) in the accent, padded 14dp sides, 10dp top, 6dp bottom (app:ui/output/OutputSheet.kt:196-204) (iPhone: the system AirPlay picker)
- [x] "This phone" group: a "This phone" row (phone icon), the chosen pill while playing on the phone; tap brings the music back to the phone and closes the card (app:ui/output/OutputSheet.kt:134-142) (iPhone: the system AirPlay picker lists this iPhone and brings the music back to it)
- [x] "Other outputs" row (headphones icon, detail "Bluetooth, headphones or the speaker"), never chosen; tap opens the system's own output picker (Bluetooth settings where there is none) and closes the card (app:ui/output/OutputSheet.kt:143-146, app:output/SystemOutputs.kt:9-21) (iPhone: the system AirPlay picker lists Bluetooth, headphones and the speaker)
- [~] "Cast" group (Chromecasts, Google TVs, Nest speakers, groups), shown when any are found (app:ui/output/OutputSheet.kt:148-153, app:output/RemoteOutput.kt:5-12) (not on iPhone: Chromecast dropped by the owner, AirPlay instead)
- [~] "TVs and speakers" group (media renderers), shown when any are found and the setting allows them (app:ui/output/OutputSheet.kt:154-157, app:output/Outputs.kt:69-75) (not on iPhone: DLNA dropped by the owner, AirPlay instead)
- [x] Device icon by kind: TV, speaker, speaker group (app:ui/output/OutputSheet.kt:180-184, app:output/RemoteOutput.kt:14-15) (iPhone: the system AirPlay picker shows each device's own icon)
- [x] Device row detail: "Connecting" while connecting to it, else its own line (such as "Group" or maker and model) (app:ui/output/OutputSheet.kt:186, app:output/RemoteOutput.kt:17-25) (iPhone: the system AirPlay picker)
- [x] A device row is chosen only while casting to it (not while connecting); tapping a device connects to it and closes the card (app:ui/output/OutputSheet.kt:176-192) (iPhone: the system AirPlay picker ticks the device in use; a tap moves the music there)
- [~] Nothing found: "Looking for devices" while looking; then "No devices found. TVs and speakers show up here when they are on the same Wi-Fi as this phone." (or "Cast devices" in place of "TVs and speakers" when renderers are off) (app:ui/output/OutputSheet.kt:158-166) (not on iPhone: Chromecast and DLNA dropped, AirPlay instead; the system picker says when it finds nothing)
- [~] Devices found and still looking: "Looking for more devices" (app:ui/output/OutputSheet.kt:167-169) (not on iPhone: Chromecast and DLNA dropped, AirPlay instead)
- [~] Not on the phone: "Sound settings apply on this phone only" (app:ui/output/OutputSheet.kt:170) (not on iPhone: Chromecast dropped; on AirPlay the phone sends the sound, so Octo's sound settings still apply)
- [~] Quiet lines: caption muted, padded 14dp across and 10dp down (app:ui/output/OutputSheet.kt:206-214) (not on iPhone: Chromecast and DLNA dropped, AirPlay instead)
- [x] Device row: at least 52dp tall, corners 14dp, a ripple, TalkBack radio button; padding 14dp across, 10dp down, 12dp gaps; icon 20dp (white when chosen, accent otherwise); name 14sp white; detail caption muted; a white check 18dp when chosen (the same room kept empty otherwise); the chosen row in the darker pill (black 72%) (app:ui/output/OutputSheet.kt:216-251, design:Glaze.kt:66-68, 233-238) (iPhone: the system AirPlay picker)
- [x] Choosing the device already casting or connecting does nothing (app:output/Outputs.kt:147-153) (iPhone: the system AirPlay picker)
- [~] Connecting gives up after 20 s: back to where it played before and "Couldn't connect to <device>" (app:output/Outputs.kt:27-28, 155-161, 223-230) (not on iPhone: Chromecast dropped; the system connects AirPlay speakers itself)
- [~] On connect the queue, the song, the place in it, whether it was playing, repeat and shuffle all move to the device; the phone's player stops and empties (app:output/Casting.kt:36-41, 77-100) (not on iPhone: Chromecast dropped; with AirPlay the queue stays on the phone and the sound goes out)
- [~] Back to the phone by choice: the phone picks up the device's queue and place, and plays only if it was playing (app:output/Outputs.kt:164-165, app:output/Casting.kt:102-120, app:output/RemoteQueue.kt:203-204) (not on iPhone: Chromecast dropped; with AirPlay the queue never leaves the phone)
- [~] The device ends the connection itself: the music comes back to the phone and plays on only when "Keep playing on the phone when casting ends" is on and it was playing; otherwise paused; a lost connection says "Lost the connection to <device>" (app:output/Outputs.kt:209-221, app:output/RemoteQueue.kt:203-204) (not on iPhone: Chromecast dropped; an AirPlay speaker that goes away pauses the music like any output that goes away)
- [~] Moving from one device to another: the music waits paused for the new one, then carries on as it was (app:output/Outputs.kt:90-92, 209-217) (not on iPhone: Chromecast dropped; the system moves AirPlay audio between speakers)
- [~] Songs the device cannot play are passed over, with one message per cast: "Songs <device> can't play are skipped" or "Files opened from other apps are skipped while casting" (app:output/Casting.kt:136-144) (not on iPhone: Chromecast dropped; every song plays over AirPlay)
- [~] While casting: no speed, equalizer, crossfade or loudness levelling (app:output/RemotePlayer.kt:44-50, app:output/OutputSwitch.kt:41-42) (not on iPhone: Chromecast dropped; on AirPlay speed, the equalizer, crossfade and loudness all apply)
- [~] Settings: "Show TVs and speakers (DLNA)" default on, switching it off stops looking for them at once; "Keep playing on the phone when casting ends" default off (app:player/PlayerSettings.kt:81-85, app:output/Outputs.kt:99-106, app:ui/settings/SettingsIndex.kt:117-124) (not on iPhone: Chromecast and DLNA dropped, so neither setting is offered)

## 24. Background: modes and what each phone draws

- [x] Four modes: Immersive (`Default`, the drifting wash), Artwork (the cover blurred and still), Colour (a flat fill of the cover's main colour), Classic (the four-colour moving mesh); default Immersive (app:player/immersive/BackgroundPrefs.kt:8-22, 26-28)
- [x] Android draws Immersive only on Android 13+, showing Artwork in its place before that; Classic's live mesh also needs Android 13. Every iPhone can draw both, so the iPhone always draws the chosen mode (app:player/immersive/PlayerBackground.kt:86-89, app:player/MeshBackground.kt:115-116)
- [x] Immersive moves only when Live background is on AND Octo's Reduce motion is off AND the phone's animations are on; otherwise it is the same wash held still (covers still fade into each other) (app:player/immersive/PlayerBackground.kt:112-117)
- [x] Classic moves when Live background is on (Reduce motion is not checked for Classic, as built); when off it shows the blurred cover at 60% (app:player/immersive/PlayerBackground.kt:123-129)
- [x] The tempo and the prepared cover are only worked out while a background that uses them shows (app:player/immersive/PlayerBackground.kt:55-84)
- [x] Tempo: the song's beats a minute from its files' tags or its server, when any copy has one (app:player/immersive/PlayerBackground.kt:67-73)

## 25. Background: preparing the cover (Immersive and Artwork)

- [x] The cover follows the artwork reference and the tuning (contrast, saturation, brightness cap), not the song, so an album plays through without a fade (app:player/immersive/PlayerBackground.kt:75-83)
- [x] One cover is made at a time (the background and the word colour ask for the same one); the last 4 are kept, keyed by reference, contrast, saturation and cap (app:player/immersive/WashArtwork.kt:33-57)
- [x] The cover is decoded at 512px, cropped to its middle square and drawn to a 512 by 512 square with filtering (app:player/immersive/WashArtwork.kt:48, 59-70, shared:player/immersive/WashLayers.kt:7-9)
- [x] Music without artwork gets the four mesh colours as a straight gradient from the top-left corner to the bottom-right corner (app:player/immersive/WashArtwork.kt:78-89)
- [x] Contrast and saturation in one colour matrix: per output channel, contrast x ((1 - saturation) x luma weight + saturation for its own channel), plus 127.5 x (1 - contrast); luma weights 0.299, 0.587, 0.114; channels 0 to 255, rounded and clamped (shared:player/immersive/WashColour.kt:16-57)
- [x] Then the brightness cap per pixel: when the mean of R, G, B (0 to 1) is over the cap, the colour is multiplied by 1 - (mean - cap) / cap (clamped 0 to 1) (shared:player/immersive/WashColour.kt:59-74)
- [x] Defaults: contrast 1.3, saturation 1.8 (180%), cap 0.5 (50%) (shared:player/immersive/WashColour.kt:10-14, app:player/immersive/BackgroundPrefs.kt:26-47)
- [x] The cover's range: the square averaged in 32 by 32 blocks (16px each), the darkest and brightest block by relative luminance (sRGB curve) (app:player/immersive/WashArtwork.kt:51-53, shared:player/immersive/WashReading.kt:27-56, shared:player/immersive/WashColour.kt:80-87)

## 26. Background: Immersive wash drawing

- [x] Three steps each frame: the layered composite with its warp into the 512 square; that square blurred; the square turned and magnified over the screen, brightened with a speck of noise (app:player/immersive/WashRenderer.kt:16-22)
- [x] Composite: starting from black, eight copies of the cover are laid on in order, each mixed over the result so far at its opacity (shared:player/immersive/WashLayers.kt:49-51, shared:player/immersive/WashShaders.kt:96-100)
- [x] Copy "Base": opacity 1.0, zoom 3.0, does not breathe, no offset, no turn (shared:player/immersive/WashLayers.kt:52)
- [x] Copy "Parallax 1": opacity 0.60, zoom 3.0, breathes, x0 0.10, xAmp 0.08, xSpeed 0.25, y0 0.10, yAmp 0.06, ySpeed 0.25, spin 0.5 (shared:player/immersive/WashLayers.kt:53-57)
- [x] Copy "Parallax 2": opacity 0.30, zoom 3.8, breathes, x0 0.25, xAmp 0.08, xSpeed 0.25, xPhase 2.39996 (golden angle), y0 0.25, yAmp 0.06, ySpeed 0.25, yPhase 2.39996, spin 0.5, tilt 0.15 (shared:player/immersive/WashLayers.kt:41-43, 58-63)
- [x] Copy "Parallax 3": opacity 0.20, zoom 4.6, breathes, x0 0.40, xAmp 0.08, xSpeed 0.25, xPhase 4.79992, y0 0.40, yAmp 0.06, ySpeed 0.25, yPhase 4.79992, spin 0.5, tilt 0.30 (shared:player/immersive/WashLayers.kt:64-69)
- [x] Copy "Primary": opacity 0.85, zoom 2.4, breathes, xAmp 0.05, xSpeed 0.5, yAmp 0.04, ySpeed 0.5, spin 1, wobble 0.02, wobbleSpeed 0.5 (shared:player/immersive/WashLayers.kt:45-47, 70-74)
- [x] Copy "Secondary": opacity 0.70, zoom 2.0, breathes, x0 0.30, xAmp 0.06, xSpeed 0.5, xPhase 1, y0 0.30, yAmp 0.05, ySpeed 0.5, yPhase 1, spin -0.5, wobble 0.02, wobbleSpeed 0.7, wobblePhase 1 (shared:player/immersive/WashLayers.kt:75-80)
- [x] Copy "Tertiary": opacity 0.55, zoom 1.8, breathes, x0 -0.20, xAmp 0.07, xSpeed 0.4, y0 0.40, yAmp 0.05, ySpeed 0.3, spin 0.8, wobble 0.02, wobbleSpeed 0.8, wobblePhase 2 (shared:player/immersive/WashLayers.kt:81-86)
- [x] Copy "Fourth": opacity 0.40, zoom 2.2, breathes, x0 0.40, xAmp 0.08, xSpeed 0.35, xPhase 3, y0 -0.10, yAmp 0.06, ySpeed 0.25, yPhase 3, spin 1.5, wobble 0.02, wobbleSpeed 0.6, wobblePhase 3 (shared:player/immersive/WashLayers.kt:87-92)
- [x] Copy offset at time t: x = x0 + xAmp sin(xSpeed t + xPhase), y = y0 + yAmp cos(ySpeed t + yPhase); turn = spin x rotation + tilt + wobble sin(wobbleSpeed t + wobblePhase); magnification = zoom x breathing for copies that breathe, else zoom (shared:player/immersive/WashLayers.kt:11-39)
- [x] Copy sampling: p = uv - 0.5 + offset; sample point = [[cos a, -sin a], [sin a, cos a]] / magnification applied to p, + 0.5, in the cover's 0..1 space; the cover repeats outside 0..1, linear filtering (shared:player/immersive/WashLayers.kt:95-120, shared:player/immersive/WashShaders.kt:65-68, app:player/immersive/WashRenderer.kt:105-107)
- [x] Each copy samples the old and the new cover mixed by the cover fade (shared:player/immersive/WashShaders.kt:60-63)
- [x] Warp before sampling: uv.x is remapped by three upright dividers at rest at 0.25, 0.5, 0.75 that swing by 0.17578 (60/512 x 1.5) x sin(warp phase + [0, 2π/3, 4π/3] + y x 0.1 x rotation x scale x 10), with y in pixels down the 512 square and scales 0.0175, 0.0105, 0.021 (shared:player/immersive/WashLayers.kt:122-148, shared:player/immersive/WashShaders.kt:70-73, 92)
- [x] Divider order rules: d0 held to [0.01, 0.97]; d1 at least d0 + 0.01; d2 at least d1 + 0.01 and at most 0.99; then d1 at most d2 - 0.01 and d0 at most d1 - 0.01 (shared:player/immersive/WashLayers.kt:140-147)
- [x] Remap: a point between two dividers samples the matching quarter of the picture, linearly (shared:player/immersive/WashLayers.kt:150-163)
- [x] Blur of the 512 square: a platform Gaussian blur, mirrored at the edges, radius about 16.81px across and 23.13px down (spread about 10.20px and 13.86px), derived from a 9-tap bell curve (taps 0.1027, 0.0984, 0.0867, 0.0702, 0.0523, 0.0358, 0.0225, 0.0130, 0.0069) spaced 0.9 and 1.2 texels, run twice, then widened 2.5x (shared:player/immersive/WashShaders.kt:5-31, app:player/immersive/WashRenderer.kt:28-37) (iPhone: a Metal Gaussian blur of the same spread, mirrored at the edges)
- [x] Screen step: the blurred square is centred, turned by the slow `turn`, then stretched over the screen (x by width/512, y by height/512, so to the screen's shape) and magnified by 2 x breathing x dolly scale about the middle (app:player/immersive/WashRenderer.kt:79-91)
- [x] Final pass: colour x FinalGain (1.5 x 0.8743^4 = about 0.8765), plus fresh noise each frame of (a + b - 1)/255 with a, b two hashed values (a triangle spread of plus or minus 1/255), clamped, opaque; a new random seed (0 to 64) every frame (shared:player/immersive/WashShaders.kt:33-36, 102-121, app:player/immersive/WashRenderer.kt:92-93)
- [x] The wash starts transparent and fades in over tween(500) once its first frame is drawn, or after 1.5 s if that is slow (app:player/immersive/ImmersiveWash.kt:40-43, 92-98, 131-133)
- [x] It draws only once a cover has arrived (app:player/immersive/WashRenderer.kt:61-62)
- [x] Covers fade: the very first cover shows at once; a new cover fades in over 500ms, or 300ms when the last change was under 1.5 s ago (skipping through), with easeInOutCubic (shared:player/immersive/WashFade.kt:3-48)
- [x] A cover arriving mid-fade starts its fade from the two as they show at that moment (mixed into one picture), so nothing jumps (shared:player/immersive/WashClock.kt:51-77, app:player/immersive/ImmersiveWash.kt:85-90, 162-170)

## 27. Background: Immersive wash timing and motion

- [x] One clock drives the motion and the cover fade; it runs while the app is in view (stops when hidden or the screen is off) and while there is something to move: the motion, or a cover still fading in (app:player/immersive/ImmersiveWash.kt:100-115, shared:player/immersive/WashClock.kt:3-14)
- [x] It restarts on every new cover so a still wash still fades covers (app:player/immersive/ImmersiveWash.kt:73-90, 105)
- [x] Frame rate wanted: the set limit while the player's window has focus (at most 30 with battery saver on), 10 when the window has lost focus, none while hidden (shared:player/immersive/WashMotion.kt:84-93, app:player/immersive/ImmersiveWash.kt:76-80) (iPhone: Low Power Mode stands in for battery saver)
- [x] Any focusable popup over the player (the time card, the song menu, the queue row menu, the device list, the save form) takes window focus, so the wash runs at 10 fps while one is open (as built) (app:player/immersive/ImmersiveWash.kt:76-80, design:GlassPopup.kt:187-195) (iPhone: the wash slows to 10 fps while the sleep and speed cards, the lyrics timing or the chooser are open)
- [x] Battery saver changes are followed live (app:player/immersive/ImmersiveWash.kt:139-160)
- [x] The frame limit eases toward the wanted rate by 8% of the gap per drawn frame, snapping within 0.01; a wanted rate of 0 leaves it as it is; it starts at the first wanted rate (shared:player/immersive/WashMotion.kt:95-107, app:player/immersive/ImmersiveWash.kt:83)
- [x] A frame is drawn when at least 0.8 of a frame interval at the current limit has passed since the last one (shared:player/immersive/WashMotion.kt:109-113)
- [x] Per drawn frame, k = (bpm / 120) x (60 / limit) x framesElapsed x speed, where framesElapsed = seconds since the last drawn frame x limit, held to 0.5..3 (shared:player/immersive/WashMotion.kt:24-27, 115-119, shared:player/immersive/WashClock.kt:25-33)
- [x] Tempo used: the song's bpm held to 40..240 when "Move with the beat" is on and one is known, else 120 (shared:player/immersive/WashMotion.kt:19-22)
- [x] Speed = drift speed setting / 100 (default 0.25) (app:player/immersive/PlayerBackground.kt:116)
- [x] time += 0.016 k, wrapping at 40π (shared:player/immersive/WashMotion.kt:15-17, 68)
- [x] warp phase += 0.016 k x (bpm / 120 held to 1..2), wrapping at 2π (shared:player/immersive/WashMotion.kt:69)
- [x] rotation += 0.001 k x breathing x direction x pulse boost; past +2π it turns back, past -2π forward again (shared:player/immersive/WashMotion.kt:70-72)
- [x] turn += 0.002 k, wrapping at 2π (shared:player/immersive/WashMotion.kt:73)
- [x] breath phase += 0.016 k² / 120, wrapping at 2π; breathing = 1 + 0.1 sin(breath phase) (0.9 to 1.1) (shared:player/immersive/WashMotion.kt:59-60, 74)
- [x] pulse fades by 1 per second; pulse boost = min(1 + pulse, 10); a beat would add 2 but nothing calls it yet (shared:player/immersive/WashMotion.kt:54-63, 75-80)
- [x] Not moving: the motion values hold where they are; the fade still advances (shared:player/immersive/WashClock.kt:30-31)

## 28. Background: Artwork, Colour and Classic

- [x] Artwork: the prepared 512 cover drawn center-cropped over the whole player, blurred with radius 80dp (sharp edges, not faded), scaled 1.12 x dolly scale so the way in never shows an edge (app:player/immersive/PlayerBackground.kt:133-161)
- [x] Artwork covers cross-fade on the same timing as the wash (first at once, 300ms quick, 500ms otherwise, easeInOutCubic) (app:player/immersive/PlayerBackground.kt:137-139)
- [x] Colour: a flat fill of the dominant colour put through the tuning (contrast, saturation, brightness cap), or the base colour when there is none, easing to each new colour over tween(500, easeInOutCubic) (app:player/immersive/PlayerBackground.kt:163-169)
- [x] Classic, live: four soft pools of the mesh colours whose blend weights are 1 / (distance² + 0.02) with the distance's x scaled by the aspect ratio, so the colours flow with no edges (app:player/MeshBackground.kt:26-64)
- [x] Classic pool paths: p0 = (0.20 + 0.18 sin(0.20t), 0.18 + 0.14 cos(0.31t)); p1 = (0.82 + 0.16 cos(0.43t), 0.26 + 0.16 sin(0.37t)); p2 = (0.24 + 0.16 cos(0.53t), 0.78 + 0.14 sin(0.61t)); p3 = (0.80 + 0.14 sin(0.70t), 0.84 + 0.12 cos(0.47t)) (app:player/MeshBackground.kt:49-52)
- [x] Classic ripple: uv += 0.05 sin(uv.yx x 3 + 0.3t) before weighting; grain of plus or minus 0.004 per pixel from a fixed hash (app:player/MeshBackground.kt:47, 60-61)
- [x] Classic time moves forward at 1x while playing and 0.15x while paused, the rate easing over tween(1200); it stops while the app is out of view (app:player/MeshBackground.kt:66-93)
- [x] Classic colours ease to each song's over tween(520) (app:player/MeshBackground.kt:72-75)
- [x] Classic, not live: the song's own artwork, center-cropped, blurred 80dp, at 60% over the base (app:player/immersive/PlayerBackground.kt:171-184)

## 29. Background settings (Settings, Appearance, "Player" group)

- [x] "Player background" choice row ("What fills the player behind the lyrics"), opening a choice sheet: "Immersive" ("The artwork torn into drifting layers, blurred into a slow wash of its colours."), "Artwork" ("The artwork, blurred and still."), "Colour" ("A flat fill of the artwork's main colour."), "Classic" ("Four of the artwork's colours, flowing into each other.") (app:ui/settings/PlayerBackgroundSection.kt:36-41, 70-78, app:ui/settings/SettingsIndex.kt:178-181) (iPhone: a choice sheet)
- [x] "Live background" switch ("The player's background drifting slowly"), default on; usable only for Immersive and Classic; for Artwork and Colour it shows off and disabled with "This background stays still." (app:ui/settings/PlayerBackgroundSection.kt:63-90, app:ui/settings/SettingsIndex.kt:182-185)
- [x] For every mode but Classic: "Brightness cap" 20% to 100% in steps of 5 (default 50%); "Saturation" 0% to 300% in steps of 10 (default 180%); "Contrast" 0.50 to 2.00 in steps of 0.05, shown with two decimals (default 1.30); each saved only when it changes (app:ui/settings/PlayerBackgroundSection.kt:91-99, 123-153, shared:player/immersive/WashReading.kt:5-12)
- [x] For Immersive only: "Drift speed" 5% to 100% in steps of 5 (default 25%); "Move with the beat" switch, default on, helper "Drifts with the song's tempo, when it's known."; "Frame rate" choice "30 fps" ("Easiest on the battery."), "60 fps" (default), "90 fps", "120 fps" (app:ui/settings/PlayerBackgroundSection.kt:100-119, shared:player/immersive/WashReading.kt:11-12)
- [x] Stored values read back are held to those ranges, and a frame rate not on the list reads as 60 (app:player/immersive/BackgroundPrefs.kt:38-45)
- [x] Reduce motion ("What moves only for show holds still"), default off, also holds the Immersive wash still (app:player/PlayerSettings.kt:78-80, app:ui/settings/SettingsIndex.kt:214-217)
- [x] All of these are kept across restarts and in backups (app:player/PlayerSettings.kt:153-159, 232-239, 360-402)

## Shared logic to port line for line

- `shared:player/immersive/WashClock.kt`: the one frame clock (frame due, motion step, cover fade), the two-cover swap with a mid-fade blend, and the dolly scale. Tests: `sharedTest:player/immersive/WashClockTest.kt`
- `shared:player/immersive/WashFade.kt`: cover fade lengths (0, 300, 500ms, 1.5 s window), easeInOutCubic, the fade's progress and mix. Tests: `sharedTest:player/immersive/WashFadeTest.kt`
- `shared:player/immersive/WashMotion.kt`: tempo pacing, frame factor, the motion values and their step, wanted frame rate by visibility and battery saver, the easing frame limit, frame due, frames elapsed. Tests: `sharedTest:player/immersive/WashMotionTest.kt`
- `shared:player/immersive/WashLayers.kt`: the 512 size, the eight copies table, copy placement and sampling, the warp dividers and remap. Tests: `sharedTest:player/immersive/WashLayersTest.kt`
- `shared:player/immersive/WashShaders.kt`: blur taps and the blur sizes derived from them, FinalGain, and the composite and final shader sources (port to Metal keeping the maths). Tests: `sharedTest:player/immersive/WashShadersTest.kt`
- `shared:player/immersive/WashColour.kt`: tuning, the contrast and saturation colour matrix, the brightness cap, relative luminance and contrast ratio. Tests: `sharedTest:player/immersive/WashColourTest.kt`
- `shared:player/immersive/WashReading.kt`: the settings ranges and frame rates, a background's range, the block range of a picture, dark ink, the 4.5 contrast, `inkOver`, `readableAlpha`, `overlay`, `washPeak`. Tests: `sharedTest:player/immersive/WashReadingTest.kt`
- `shared:playback/Pace.kt`: speed range, detents, snapping, slider mapping, semitones, the pace sent to the player, speed and pitch labels. Tests: `sharedTest:playback/PaceTest.kt`
- `shared:playback/SleepPlan.kt`: sleep states, the offered lengths, extensions and song counts, 720 minute maximum, the 30 s squared fade, tick timing, the summary words. Tests: `sharedTest:playback/SleepPlanTest.kt`
- `shared:playback/QueueSources.kt`: queue sources, heading words, cutting into runs, saved encoding (and `movedSource`, desktop only). Tests: `sharedTest:playback/QueueSourcesTest.kt`
- `shared:playback/QueueRuns.kt`: undo put-back runs, removal runs, positions of songs. Tests: `sharedTest:playback/QueueRunsTest.kt`
- `shared:playback/QueueUndo.kt`: finding songs put in together to take them back out. Tests: `sharedTest:playback/QueueUndoTest.kt`
- `shared:playback/ShuffleQueue.kt`: keeping the shuffled play order in step as songs are added, removed and moved, and where the listener's own songs go before Autoplay's. Tests: `sharedTest:playback/ShuffleQueueTest.kt`
- `shared:playback/SongLength.kt`: the believable measured length and the playing length the progress line uses. Tests: `sharedTest:playback/SongLengthTest.kt`
- `app:player/AlbumLabel.kt` with `app:catalog/CatalogMerger.kt:276-284` (`matchKey`, over `shared:catalog/SongIdentity.kt` `key`): when the album name shows. Tests: `appTest:player/AlbumLabelTest.kt`, `appTest:catalog/CatalogMergerTest.kt`
- `app:player/immersive/BackgroundPrefs.kt`: modes, defaults, `sane`, `tuning`, `drawnRange`, `over`. Tests: `appTest:player/immersive/BackgroundPrefsTest.kt`, `appTest:player/immersive/WashInkTest.kt`
- `app:player/Position.kt` (`fractionAt`): progress fraction. No test of its own.
- `app:playback/Quality.kt`: badge label, full line, codec names, bit depth, kHz text. Tests: `appTest:playback/QualityTest.kt`
- `app:playback/UpNext.kt`: queue keys and the played and up-next orders. Tests: `appTest:playback/UpNextTest.kt`
- `app:playback/QueueEditor.kt`: remove, clear, remove played, play next by key, undo. Tests: `appTest:playback/QueueEditorTest.kt`
- `app:playback/SleepTimer.kt`: the timer's state machine over the player's events. Tests: `appTest:playback/SleepTimerTest.kt`
- `app:ui/common/Swipes.kt`: drag axis, swipe skip, swipe up. Tests: `appTest:ui/common/SwipesTest.kt`
- `app:ui/common/PressSpot.kt` (`menuAnchor`, the 2 s press window) and `design:GlassPopup.kt` (`placePopup`): where cards open. Tests: `appTest:ui/common/PopupPagesTest.kt`, `appTest:ui/common/GlassPopupTest.kt`
- `design:PopupPages.kt` (`PageTrail`): page trail, back, restart. Tests: `appTest:ui/common/PopupPagesTest.kt`
- `design:IconAccents.kt` (`accentStrength`, `accentPose`): the like pulse. No phone test; desktop tests in `desktop-design/src/test/kotlin/app/winters/octo/design/TokensTest.kt`
- `app:ui/common/Layout.kt` (`asClock`, `asLength`, `songs`): time and length words. No test of its own.
- `app:output/RemoteQueue.kt` (`playsOnReturn`): whether music plays on coming back to the phone. Tests: `appTest:output/RemoteQueueTest.kt`
- `app:ui/menu/SongMenu.kt` (`songActions`, `songMenuGroups`, `menuPlace`, `nextRating`, `keepOfflineLabel`, `keepOfflineEnabled`, `downloadLabel`): the song menu's rows. Tests: `appTest:ui/menu/SongActionsTest.kt`, `appTest:ui/menu/MenuGroupsTest.kt`, `appTest:ui/menu/MenuPlaceTest.kt`
