# Parity contract: sound

Read from octo-player `origin/main` 0f11df0f (git ref only, not the working tree).

Path roots used in the references below:

- `ui/sound/` = `app/src/main/java/app/winters/octo/ui/sound/`
- `sound/` = `app/src/main/java/app/winters/octo/sound/`
- `shared/sound/` = `shared/core/src/commonMain/kotlin/app/winters/octo/sound/`
- `shared/ui/sound/` = `shared/core/src/commonMain/kotlin/app/winters/octo/ui/sound/`
- `design/` = `design/src/main/java/app/winters/octo/design/`
- `ui/common/`, `ui/settings/`, `playback/`, `player/`, `backup/` = the same folders under `app/src/main/java/app/winters/octo/`

Design tokens referenced: TextPrimary = white; Accent = #97B1B9; TextSecondary = Accent; TextMuted = Accent at alpha 0.8; Error = #EF4444; type `display` 32sp Black (-0.5sp tracking), `section` 18sp Bold, `body` 16sp Medium, `bodySmall` 14sp Normal, `caption` 12sp Normal, `label` 13.5sp SemiBold (design/OctoColors.kt:19-30, design/OctoType.kt:9-16). Glass surfaces are native Liquid Glass on iPhone (owner rule), so the Android Glaze numbers are recorded only where they decide a state.

## Ways in to the Sound page

- [x] Settings front page, group "Listening", second row: icon Sound, title "Sound", subtitle `soundSummary(settings)`; tapping it opens the Sound page as its own route (SoundRoute), not a settings sub-page (ui/settings/SettingsScreen.kt:126, ui/settings/SettingsScreen.kt:307)
- [x] `soundSummary`: EQ off gives "Equalizer off"; EQ on with a correction gives "Equalizer on, {presetLabel}, with {correction name}"; EQ on without gives "Equalizer on, {presetLabel}" (shared/ui/sound/SoundEdits.kt:126-130)
- [x] A stored route naming SettingsPage.Sound also shows the Sound page (ui/settings/SettingsScreen.kt:338-339)
- [x] Settings search finds five Sound entries: "Sound for each output" / "Headphones and speakers keep their own sound" (words bluetooth, speaker, device, output); "Equalizer" / "Shape the sound, with presets" (eq, bass, treble, presets, bands, filters); "Loudness" / "Even out the volume between songs" (volume, levelling, leveling, normalize, replaygain, preamp); "Balance" / "Left and right" (left, right, channel, mono); "Headphone correction" / "A correction for the headphones in use" (headphones, correction, profile, tuning) (ui/settings/SettingsIndex.kt:126-146)
- [x] Player top line, right side after the cast button: a Sound button, 44dp touch box, no ripple, 22dp glowing Sound icon; full tint and lit glow while the equalizer is on, tint at alpha 0.45 and unlit while off; accessibility name "Sound", state "Equalizer on" or "Equalizer off" (player/PlayerOverlay.kt:497-500, player/PlayerOverlay.kt:1038-1057) (iPhone: a Sound item in the player's More menu, its second line "Equalizer on" or "Equalizer off"; SF Symbol)
- [x] The player's "equalizer on" state is `current.eqEnabled` of the output playing now (player/PlayerViewModel.kt:183-185)
- [x] Tapping the player's Sound button closes the player and pushes the Sound page (ui/nav/MainShell.kt:335-338)

## Page layout

- [x] One vertically scrolling column filling the screen; padding top = status bar + 8dp + 56dp (DetailTopGap), bottom = navigation bar + 120dp (ui/sound/SoundScreen.kt:109-115, ui/common/Layout.kt:25-29, ui/common/Layout.kt:52)
- [x] Title "Sound" in `display`, TextPrimary, padding start 20dp, end 20dp, top 8dp, bottom 16dp (ui/sound/SoundScreen.kt:116, ui/common/Layout.kt:32-39)
- [x] Below the title, five blocks spaced 16dp apart, in this order: output line, Equalizer card, Loudness card, Balance card, Headphone correction card (ui/sound/SoundScreen.kt:117-123)
- [x] A floating round back button over the page: status bar + 8dp from the top, 16dp from the left, 40dp glass icon button, accessibility "Back" (ui/sound/SoundScreen.kt:125, ui/common/Layout.kt:55-66)
- [x] The page shows `vm.draft` when a drag is in flight, otherwise the saved settings of the output playing now (ui/sound/SoundScreen.kt:98-101)
- [x] A single popup host for the preset sheets sits over the page (ui/sound/SoundScreen.kt:126) (iPhone: the preset questions are a system popover and a confirmation dialog on the page)
- [x] There are no level meters, spectrum, or live output readouts anywhere on the page; the only live number is "Level now" (ui/sound/SoundScreen.kt:96-128)

## Cards

- [x] Card (Loudness, Balance, Headphone correction): 20dp outside horizontal margin, full width, raised panel with 20dp corner radius, 20dp padding inside on all sides, children spaced 10dp, title in `section` TextPrimary first (ui/settings/CardLines.kt:28-43)
- [x] Raised panel: surface = #1A1A1B mixed 6% toward Accent, 1dp white border at alpha 0.06, top inner light white 0.06 offset 1dp, half-pixel black 0.40 contour, small two-step drop shadow (design/GlassPanel.kt:29-41)
- [x] Equalizer card is a SwitchCard: same 20dp outside margin and 20dp corner raised panel, but inside padding is 16dp horizontal and 20dp vertical, children spaced 12dp (ui/sound/SoundScreen.kt:67, ui/sound/SoundScreen.kt:145-171)
- [x] SwitchCard title row: padded 4dp horizontally, title "Equalizer" in `section` TextPrimary filling the row and marked as a heading, a switch at the end whose accessibility name is the title (ui/sound/SoundScreen.kt:160-168)
- [x] SwitchLine: row padded 4dp vertically; label in `bodySmall` (TextPrimary, or TextMuted when disabled) above a detail in `caption` TextMuted; 12dp gap before the switch at the end (ui/settings/CardLines.kt:45-60)
- [x] ChoiceLine: whole row clickable with ripple, role Button, padded 4dp vertically; label `bodySmall` TextPrimary over value `caption` TextMuted; 12dp gap; 20dp chevron in TextMuted at the end (ui/settings/CardLines.kt:62-78) (iPhone: a faint press light in place of the ripple)
- [x] Hairline: full width, exactly one physical pixel tall, TextPrimary at alpha 0.08 (ui/sound/SoundControls.kt:68-73)
- [x] TextAction: words in `label`, Accent color, no ripple or press effect, role Button, 6dp vertical padding (ui/sound/SoundScreen.kt:434-445)

## Output line and "each output keeps its own sound"

- [x] Output line padded 20dp horizontally: "Sound for {output label}" in `body` TextPrimary (ui/sound/SoundScreen.kt:131-134)
- [x] Under it a SwitchLine "Each output keeps its own sound", detail "The speaker, headphones and each Bluetooth device remember their own settings.", bound to the per-output flag (ui/sound/SoundScreen.kt:135-140)
- [x] The label follows the output live: it updates when a device is added or removed while the page is open (sound/SoundEngine.kt:106-114, ui/sound/SoundScreen.kt:99)
- [x] The per-output switch writes straight to storage (no draft) (ui/sound/SoundViewModel.kt:105, sound/SoundEngine.kt:133-135)
- [x] Per-output off (default): one shared set, stored under key "all", is used for every output (sound/SoundEngine.kt:97-104, sound/SoundEngine.kt:172)
- [x] Per-output on: the output's own set is used, found under its key or else any of its former keys (current key first); when none is saved, the shared "all" set is used; when that is missing too, defaults (sound/SoundEngine.kt:73-75, sound/SoundEngine.kt:102-104)
- [x] So turning per-output on starts every output from the shared set, and the first edit on an output saves a copy under that output's key (sound/SoundEngine.kt:117-129, sound/SoundEngine.kt:131-132)
- [x] Turning per-output off goes back to the shared set; the per-output sets stay stored (sound/SoundEngine.kt:97-104)
- [x] An edit with per-output on reads the current set the same way, applies the change, removes every former key of this output from the map, and saves under the output's current key (sound/SoundEngine.kt:117-129)
- [x] An edit with per-output off saves under "all" and never removes anything (sound/SoundEngine.kt:125-126, sound/SoundEngine.kt:155)
- [x] Edits always go to the output that is current at the moment the write runs (sound/SoundEngine.kt:122)

## Output detection and naming

- [x] The output is worked out from every listed output device, recomputed on every device added or removed callback (on the main thread) (sound/SoundEngine.kt:89, sound/SoundEngine.kt:106-114, sound/SoundEngine.kt:157-162) (iPhone: worked out from the outputs of the audio route in use, again on every route change and media services reset)
- [x] Device kinds: Bluetooth A2DP, BLE headset, BLE speaker = Bluetooth; USB headset, USB device = USB; wired headphones, wired headset = Wired; everything else (built-in speaker, earpiece, HDMI, Bluetooth SCO, and so on) = Other (sound/SoundEngine.kt:164-169) (iPhone: by AVAudioSession port type: Bluetooth A2DP and LE = Bluetooth; AirPlay and CarPlay keep their own too; USB audio = USB; headphones = Wired; speaker, receiver, HDMI, Bluetooth HFP and the rest = Other)
- [x] Device name = product name trimmed (empty when missing); address = device address (empty when missing) (sound/SoundEngine.kt:159-161) (iPhone: the port name trimmed, and the port uid as the address)
- [x] Rank: Bluetooth 0, USB 1, Wired 2, Other 9; the kind with the lowest rank among the listed devices wins (sound/SoundEngine.kt:48, sound/SoundEngine.kt:55-56) (iPhone: Bluetooth 0, AirPlay 1, car 2, USB 3, Wired 4, Other 9)
- [x] No devices, or only Other: the output is Phone speaker, key "speaker", label "Phone speaker" (sound/SoundEngine.kt:40, sound/SoundEngine.kt:57) (iPhone: labelled "iPhone speaker")
- [x] Devices of the winning kind are sorted with named ones first, then by name, then by address; the first one's name is the output's name (sound/SoundEngine.kt:58-59)
- [x] Bluetooth: every listed device of that kind with the same name counts as the same output (earbuds listed once per bud or per connection, in any order) (sound/SoundEngine.kt:50-54, sound/SoundEngine.kt:62)
- [x] Bluetooth key = "bluetooth:" + name, or "bluetooth:" + first non-empty address when the name is empty (sound/SoundEngine.kt:43, sound/SoundEngine.kt:63-64)
- [x] Bluetooth former keys = "bluetooth:" + each distinct non-empty address of the same-name devices; for a nameless device the first address (used as key) is left out of the former keys (sound/SoundEngine.kt:65-66)
- [x] Bluetooth label = device name, or "Bluetooth" when nameless (sound/SoundEngine.kt:66)
- [x] USB: key "usb:" + name, label = name or "USB audio", no former keys (sound/SoundEngine.kt:68)
- [x] Wired: key "wired", label "Headphones" (sound/SoundEngine.kt:69)
- [x] The rule picks a connected device by kind, not the route the system actually plays to (sound/SoundEngine.kt:50-71) (iPhone: iOS lists only the route in use, so the output is the device that plays now)

## Stored settings and defaults

- [x] Sound settings live in their own store "sound": key "profiles" is a JSON map of output key to settings, key "per_output" is a boolean, default false (sound/SoundEngine.kt:77, sound/SoundEngine.kt:93-99, sound/SoundEngine.kt:171-175) (iPhone: UserDefaults suite "sound", same keys and JSON)
- [x] JSON ignores unknown keys and leaves out fields equal to their defaults; an unreadable profiles value reads as an empty map (sound/SoundEngine.kt:86, sound/SoundEngine.kt:94)
- [x] Settings start from defaults until the stored ones have been read (sound/SoundEngine.kt:101-104)
- [x] Defaults: equalizer off, mode Graphic, ten gains of 0, no filters, preset "Flat", preamp 0 dB, automatic preamp on, no correction, ReplayGain Off, ReplayGain preamp 0 dB, fallback 0 dB, prevent clipping on, limiter on, balance 0, mono off (shared/sound/SoundModel.kt:51-73)
- [x] Because defaults are not written, a stored set with no "preset" key means "Flat", while a stored `"preset": null` means a hand-made curve (shared/sound/SoundModel.kt:58, sound/SoundEngine.kt:86)
- [x] JSON field names: eqEnabled, mode (Graphic/Parametric), graphicGains, filters [type (Peak/LowShelf/HighShelf), frequency, gainDb, q (default 1.41), enabled (default true)], preset, preampDb, autoPreamp, correction {name, source, preampDb, filters}, replayGain (Off/Track/Album/Smart), replayGainPreampDb, replayGainFallbackDb, preventClipping, limiter, balance, mono (shared/sound/SoundModel.kt:13-73)
- [x] The audio path reads the current settings on every change (sound/SoundEngine.kt:79-81, playback/OctoPlaybackService.kt:169)

## Equalizer card

- [x] Order inside the card: title row with switch; Graphic/Parametric segmented control; response graph; filter editor (parametric only); preset bar; "Save as preset…" (graphic only); hairline; preamp block; hairline; "Hold to hear it flat" centered (ui/sound/SoundScreen.kt:186-229)
- [x] The title switch turns the equalizer on and off, saved at once (ui/sound/SoundScreen.kt:186)
- [x] Segmented options "Graphic" and "Parametric"; selected index 1 when mode is Parametric; choosing one calls `withMode`, saved at once; switching mode does not turn the equalizer on (ui/sound/SoundScreen.kt:187-191, shared/ui/sound/SoundEdits.kt:65-74)
- [x] Segmented control: one full-width glass strip, the chosen option in a darker pill that glides between options, option text in `label`, maxLines 1 with ellipsis, color animates between Accent (chosen) and TextPrimary (ui/common/Segmented.kt:14-27)
- [x] The chosen filter index is remembered across configuration changes, starts at 0, and is shown clamped to 0..(filter count - 1), or 0 with no filters (ui/sound/SoundScreen.kt:182-184)

## Response graph: geometry

- [x] Graph box is full width and 242dp tall: a 220dp plot plus a 22dp band under it for frequency labels (ui/sound/ResponseGraph.kt:71-73, ui/sound/ResponseGraph.kt:171-174)
- [x] Plot left edge = 10dp, right edge = width - 10dp, top = 12dp, bottom = height - (22dp + 12dp), so the plot spans 196dp vertically (ui/sound/ResponseGraph.kt:75-76, ui/sound/ResponseGraph.kt:92-96)
- [x] x of a frequency = left + ln(hz / 20) / ln(20000 / 20) * (right - left): a log axis from 20 Hz to 20 kHz (ui/sound/ResponseGraph.kt:99, shared/ui/sound/SoundEdits.kt:24-25)
- [x] Frequency at an x = 20 * 1000^fraction, the fraction clamped to 0..1 (ui/sound/ResponseGraph.kt:100)
- [x] y of a gain = top + (12 - clamp(db, -12, 12)) * pxPerDb, with pxPerDb = (bottom - top) / 24: +12 dB at the top, -12 dB at the bottom, anything past that pinned to the edge (ui/sound/ResponseGraph.kt:97, ui/sound/ResponseGraph.kt:101, shared/sound/SoundModel.kt:38)
- [x] Graphic mode nodes: one per band at 31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000 Hz with that band's gain (ui/sound/ResponseGraph.kt:107-110, shared/sound/SoundModel.kt:32)
- [x] Parametric mode nodes: one per filter at its frequency with its gain, including 0 dB filters (ui/sound/ResponseGraph.kt:109)
- [x] The drawn curve is the response of the filters the equalizer would apply if it were on: headphone correction filters first, then the own curve, leaving out disabled and 0 dB filters (ui/sound/ResponseGraph.kt:160-163, shared/sound/SoundModel.kt:76-83)
- [x] The curve has 192 points at log-spaced frequencies 20 * 1000^(i / 191), drawn at evenly spaced x from left to right (ui/sound/ResponseGraph.kt:69, ui/sound/ResponseGraph.kt:163, ui/sound/ResponseGraph.kt:301-309, shared/sound/SoundModel.kt:160-161)
- [x] Each node sits on the combined curve: its y is the total response (correction plus every own filter) at the node's frequency, not the node's own gain (ui/sound/ResponseGraph.kt:165, ui/sound/ResponseGraph.kt:232, ui/sound/ResponseGraph.kt:279-282)
- [x] The response is computed at 48 kHz, leaving out any filter at or above 0.45 x 48000 Hz (shared/sound/SoundModel.kt:164-165)
- [x] Curve and node values are recomputed only when the settings change (ui/sound/ResponseGraph.kt:162-165)

## Response graph: drawing

- [x] Draw order: grid, tint and curve, nodes, frequency labels, then the reading pill for a held node (ui/sound/ResponseGraph.kt:240-250)
- [x] Grid: vertical lines at 100 Hz, 1 kHz and 10 kHz from plot top to plot bottom, white at alpha 0.06, 1px wide (ui/sound/ResponseGraph.kt:87, ui/sound/ResponseGraph.kt:285-290)
- [x] Grid: a 0 dB line from plot left to plot right, white at alpha 0.14, 1px wide (ui/sound/ResponseGraph.kt:291-292)
- [x] "Lit" animates 0 to 1 over 250ms (tween) as the equalizer turns on, and back as it turns off (ui/sound/ResponseGraph.kt:168)
- [x] Line color = blend from grey #6B7075 (off) to white (on) by lit (ui/sound/ResponseGraph.kt:84, ui/sound/ResponseGraph.kt:169)
- [x] Under the curve a filled area down to the plot bottom, vertical gradient from line color at alpha (0.05 + 0.09 x lit) at the plot top to line color at alpha 0.01 at the plot bottom (ui/sound/ResponseGraph.kt:310-324)
- [x] Glow only while lit > 0: three passes of the same path, white at alpha (0.4 x lit / 3) each, stroke 2dp, blur radii 30px, 12px and 3.6px (12px x 2.5, 1, 0.3), round caps and joins (ui/sound/ResponseGraph.kt:295-299, ui/sound/ResponseGraph.kt:326-337)
- [x] The curve line itself: 2dp stroke in the line color, round caps and joins (ui/sound/ResponseGraph.kt:325, ui/sound/ResponseGraph.kt:338)
- [x] Node radius 5.5dp at rest; 8dp for the active node (the held node, else in parametric mode the chosen filter; graphic mode has no active node unless one is held) (ui/sound/ResponseGraph.kt:80-81, ui/sound/ResponseGraph.kt:233, ui/sound/ResponseGraph.kt:341-342)
- [x] Active node while lit: a halo circle, white at alpha 0.18 x lit, radius twice the node radius (ui/sound/ResponseGraph.kt:343)
- [x] Every node: a dark edge circle, black at alpha 0.45, radius node radius + 1.5px, then the node filled with the line color (so grey when off) (ui/sound/ResponseGraph.kt:344-346)
- [x] Frequency labels in 10sp `caption`, TextMuted, tabular figures, top edge at plot bottom + 12dp + 4dp, centered on their frequency and kept inside the box (x clamped to 0..width - text width) (ui/sound/ResponseGraph.kt:349-357)
- [x] Graphic mode labels: 31, 62, 125, 250, 500, 1k, 2k, 4k, 8k, 16k (ui/sound/ResponseGraph.kt:245, shared/ui/sound/SoundEdits.kt:133-139)
- [x] Parametric mode labels: 20, 100, 1k, 10k, 20k (ui/sound/ResponseGraph.kt:88, ui/sound/ResponseGraph.kt:245)
- [x] While a node is held, a reading pill shows its own gain (graphic: readDb, for example "+3.5 dB") or in parametric "{readHz}   {readDb}" with three spaces between, for example "1.2 kHz   -3 dB" (ui/sound/ResponseGraph.kt:246-250)
- [x] Reading pill: 11sp `caption`, white, tabular figures; padding 8dp across and 3dp up and down; fully rounded ends; fill black at alpha 0.72; 16dp gap from the node; placed above the node, or below it when it would go off the top; x centered on the node and kept inside the box (ui/sound/ResponseGraph.kt:359-374)

## Response graph: touch

- [x] A node is hit when the touch is within 30dp of its drawn point; the nearest such node wins (ui/sound/ResponseGraph.kt:77-78, ui/sound/ResponseGraph.kt:112-121)
- [x] In parametric mode the chosen filter wins whenever it is within reach, even if another node is nearer, so stacked filters can be told apart (ui/sound/ResponseGraph.kt:112-115, ui/sound/ResponseGraph.kt:196)
- [x] Single tap, parametric only: chooses the node under the finger; graphic mode ignores single taps (ui/sound/ResponseGraph.kt:177-181)
- [x] Double tap, both modes: sets the node under the finger to 0 dB (frequency kept), turns the equalizer on, and saves at once (ui/sound/ResponseGraph.kt:182-187, ui/sound/ResponseGraph.kt:125-134)
- [x] A drag is taken only when it starts on a node; a drag that starts elsewhere scrolls the page (ui/sound/ResponseGraph.kt:190-204)
- [x] Graphic mode: only vertical movement past the touch slop picks up the node; a sideways drag on a node is not taken (ui/sound/ResponseGraph.kt:200-204)
- [x] Parametric mode: movement past the touch slop in any direction picks up the node (ui/sound/ResponseGraph.kt:200-202)
- [x] When picked up: the node becomes the held node (grows to 8dp, reading pill shows) and in parametric mode it also becomes the chosen filter (ui/sound/ResponseGraph.kt:205-208)
- [x] The drag is relative, not absolute: new gain = cleanGain(start gain - (finger y - touch-down y) / pxPerDb), so the node does not jump to the finger; start gain is the node's own gain, not its drawn curve value (ui/sound/ResponseGraph.kt:205, ui/sound/ResponseGraph.kt:210-211)
- [x] Gain while dragging snaps to 0.1 dB, clamps to -12..+12, and anything within 0.25 dB of zero becomes exactly 0 (ui/sound/ResponseGraph.kt:211, shared/ui/sound/SoundEdits.kt:36-40)
- [x] Haptic: a light segment tick when the gain lands on exactly 0 from a non-zero value, or crosses from one sign to the other (ui/sound/ResponseGraph.kt:212-216)
- [x] Parametric drag also moves frequency: new x = start node x + (finger x - touch-down x), frequency = plot.hz(new x) rounded to whole hertz, clamped 20..20000 Hz (not tidied) (ui/sound/ResponseGraph.kt:217, shared/ui/sound/SoundEdits.kt:77-83)
- [x] The first update is applied at the position where the slop was crossed, then on every move; each update is a preview (shown at once, saved at most every 100ms) and turns the equalizer on (ui/sound/ResponseGraph.kt:218-225, ui/sound/ResponseGraph.kt:133)
- [x] Graphic drag edits the band gain and clears the preset name; parametric drag edits that filter (clamped and cleaned) and clears the preset name (ui/sound/ResponseGraph.kt:125-134, shared/ui/sound/SoundEdits.kt:52-56, shared/ui/sound/SoundEdits.kt:77-86)
- [x] On lift (or cancel), the held node is released (pill disappears) and the last value is saved at once (ui/sound/ResponseGraph.kt:226-227)
- [x] Because nodes sit on the combined curve, a node can move more or less than the finger when neighboring bands overlap (ui/sound/ResponseGraph.kt:211, ui/sound/ResponseGraph.kt:232)

## Response graph: accessibility

- [x] The whole graph is described as "Equalizer curve" (ui/sound/ResponseGraph.kt:236-238)
- [x] One invisible 32dp target per node, centered on the node's drawn point (ui/sound/ResponseGraph.kt:255-263)
- [x] Target description: describeNode, for example "62 Hz, +3 dB" (hz rounded to whole, gain via readDb) (ui/sound/ResponseGraph.kt:265, shared/ui/sound/SoundEdits.kt:154-155)
- [x] Parametric targets carry a selected state for the chosen filter (ui/sound/ResponseGraph.kt:266)
- [x] Target actions: "Choose" (parametric only), "Raise 1 dB", "Lower 1 dB", "Reset to 0 dB"; each raise, lower or reset turns the equalizer on and saves at once (ui/sound/ResponseGraph.kt:267-272)

## Parametric filter editor (parametric mode only)

- [x] Column padded 4dp horizontally, children spaced 4dp (ui/sound/SoundScreen.kt:237)
- [x] With no filters: caption "No filters yet. Add one, then drag it on the curve." in TextMuted (ui/sound/SoundScreen.kt:238-239)
- [x] With filters: caption "Filter {chosen + 1} of {count}" in TextMuted (ui/sound/SoundScreen.kt:241-245)
- [x] Type segmented control "Peak", "Low shelf", "High shelf", padded 6dp vertically; changing it saves at once and turns the equalizer on (ui/sound/SoundScreen.kt:85-86, ui/sound/SoundScreen.kt:246-251, ui/sound/SoundScreen.kt:300-304)
- [x] "Frequency" slider: 20..20000 Hz on a log scale (fraction = ln(hz / 20) / ln(1000); value = 20 x 1000^fraction), value step 1 Hz, then tidied by tidyHz (1 Hz steps under 100, 10 under 1000, 100 under 10000, 1000 above), reading readHz (ui/sound/SoundScreen.kt:252-262, shared/ui/sound/SoundEdits.kt:110-118)
- [x] "Gain" slider: -12..+12 dB linear, step 0.1, reading readDb; cleaned by cleanGain on save (ui/sound/SoundScreen.kt:263-270)
- [x] "Q" slider: 0.1..10 on a log scale (fraction = ln(q / 0.1) / ln(100)), step 0.01, reading with two decimals and a dot, for example "1.41" (ui/sound/SoundScreen.kt:271-281, shared/ui/sound/SoundEdits.kt:28-29)
- [x] Every slider change is a preview (shown at once, saved at most every 100ms) and turns the equalizer on (ui/sound/SoundScreen.kt:258, ui/sound/SoundScreen.kt:268, ui/sound/SoundScreen.kt:277, ui/sound/SoundScreen.kt:301-304)
- [x] Buttons row, 6dp above, buttons 12dp apart: glass button "Add filter" (enabled while fewer than 16 filters), then "Delete filter" only when a filter exists (ui/sound/SoundScreen.kt:283-296)
- [x] Glass buttons are the Large size: 50dp tall, 24dp side padding, 13.5sp label (design/Buttons.kt:45, design/GlazeButton.kt:23-56)
- [x] "Add filter" adds a flat Peak filter (0 dB, Q 1) at the emptiest frequency, saves at once, and chooses it; it does not turn the equalizer on and clears the preset name (ui/sound/SoundScreen.kt:286-290, shared/ui/sound/SoundEdits.kt:90-94)
- [x] Emptiest frequency: take 20 Hz, 20 kHz and every filter frequency (clamped), sort, find the pair with the widest log gap, take their geometric mean, tidy it; with no filters this is 630 Hz (shared/ui/sound/SoundEdits.kt:103-107)
- [x] "Delete filter" removes the chosen filter, saves at once, clears the preset name; the chosen index stays and is clamped to the new last filter (ui/sound/SoundScreen.kt:293-295, shared/ui/sound/SoundEdits.kt:96-99, ui/sound/SoundScreen.kt:184)
- [x] At most 16 filters (shared/ui/sound/SoundEdits.kt:21)

## Value sliders

- [x] Row: label in `bodySmall` TextSecondary in a fixed 76dp column; the line slider filling the middle; reading in `bodySmall` tabular figures TextPrimary, one line, 12dp gap before it, fixed 64dp wide (ui/sound/SoundControls.kt:189-217)
- [x] Default step 0.5 and linear mapping unless a slider passes its own (ui/sound/SoundControls.kt:180-185)
- [x] A finger position becomes fraction, then value = round(fromFraction(fraction) / step) x step, clamped to the range; it is sent only when it differs from the current value (ui/sound/SoundControls.kt:193-198)
- [x] Values are sent all along the drag (live), and a tap on the line jumps to that point (ui/sound/SoundControls.kt:199, design/LineSlider.kt:80-103)
- [x] The slider line follows the finger smoothly (raw position) while dragging; the stored value moves in steps (design/LineSlider.kt:99-113)
- [x] Line slider look: 48dp touch height; track white at alpha 0.24; filled part from the left edge to the value in white with a three-pass glow (blur 12 at rest, 24 while dragging, times 2.5, 1, 0.3; alpha 0.4 at rest, 0.8 while dragging, split over the three passes); fill drawn even for negative gains (it always starts at the left edge) (design/LineSlider.kt:65-128)
- [x] Line slider while dragging: thickness grows from 3.5dp to 8dp and a white thumb of radius 9dp appears at the value (0dp at rest), both on a spring with damping 0.5 and stiffness 200 (design/LineSlider.kt:65-68)
- [x] A disabled value slider draws at alpha 0.5 and ignores input (not used on this page) (ui/sound/SoundControls.kt:189, ui/sound/SoundControls.kt:194)
- [x] Accessibility: name = label, state = reading, actions "More" and "Less" move one step and stop at the ends (ui/sound/SoundControls.kt:202-209)

## Preset bar

- [x] One full-width glass capsule 44dp tall holding a sideways-scrolling row clipped to the capsule, 4dp padding at both ends, items centered vertically (ui/sound/SoundControls.kt:93-102)
- [x] Choices in order: "Custom" first only when the current label is "Custom", then the 19 built-in presets in their fixed order, then the listener's own presets in saved order (ui/sound/SoundScreen.kt:202-207)
- [x] Built-in order: Flat, Bass Boost, Bass Reducer, Treble Boost, Treble Reducer, Vocal, Rock, Pop, Jazz, Classical, Electronic, Hip-Hop, Metal, Folk, Acoustic, Loudness, Late Night, Spoken Word, Small Speakers (shared/sound/SoundModel.kt:103-123)
- [x] Current label: in graphic mode the stored preset name, or "Custom" when there is none; in parametric mode always "Custom" (shared/ui/sound/SoundEdits.kt:120-123)
- [x] Each item: full height of the strip minus 4dp top and bottom, text in `label`, one line, 14dp padding each side; the chosen one (name equals the label) sits in a darker pill (black at alpha 0.72) with Accent text, others TextPrimary on the glass; selected state exposed to accessibility (ui/sound/SoundControls.kt:103-127, design/Glaze.kt:66-68, design/Glaze.kt:233-238)
- [x] Items have no ripple or press effect; role Button (ui/sound/SoundControls.kt:109-115)
- [x] Tapping a built-in or own preset applies it: the ten gains become the preset's, mode switches to Graphic, the preset name is stored, and the equalizer turns on; saved at once; tapping the already chosen preset applies it again (ui/sound/SoundScreen.kt:211-214, shared/ui/sound/SoundEdits.kt:44-49, ui/sound/SoundViewModel.kt:107)
- [x] Tapping "Custom" does nothing (ui/sound/SoundScreen.kt:211-214)
- [x] Long press on an own preset asks to delete it (accessibility long-press label "Delete"); built-ins have no long press, so a long hold on one acts as a tap (ui/sound/SoundControls.kt:113-115, ui/sound/SoundScreen.kt:215)
- [x] When the page opens, the row starts scrolled so the item before the chosen one is first (chosen at index 0 or 1 in view); this is only the initial position and the row does not auto-scroll later (ui/sound/SoundControls.kt:90-92)
- [x] If the stored label names an own preset that no longer exists, nothing is marked chosen and "Custom" is not shown (ui/sound/SoundScreen.kt:202-207)
- [x] Item identity keys keep own and built-in apart ("own:" or "built:" + name) (ui/sound/SoundControls.kt:103)
- [x] Preset curves (31 Hz to 16 kHz): Flat 0,0,0,0,0,0,0,0,0,0; Bass Boost 6,5.5,4.5,2.5,0.5,0,0,0,0,0; Bass Reducer -6,-5,-4,-2.5,-1,0,0,0,0,0; Treble Boost 0,0,0,0,0,0.5,1.5,3.5,5,6; Treble Reducer 0,0,0,0,0,-0.5,-1.5,-3.5,-5,-6; Vocal -2,-2,-1,0.5,2,3.5,3.5,2.5,1,0; Rock 5,5,4,3,0.5,-0.5,1.5,3,4,5; Pop -1,-1,0.5,2,3.5,4.5,2.5,1,-1,-2; Jazz 4,4,3,2,-0.5,-1.5,0.5,2,4,5; Classical 5,5,4,2.5,0,-1.5,1.5,4,4,4; Electronic 6,6,2.5,0,1,2,3,4,2,1; Hip-Hop 5,5,4,3,1.5,0,0.5,1,2,3; Metal 4,4,2.5,1.5,5.5,8.5,5.5,3,1,0; Folk 3,3,1.5,0,0,0,1,2,0,-1; Acoustic 3,3,2.5,1,1,0.5,1.5,2.5,2.5,1.5; Loudness 6,5,3,1,0,0,0,1,3,4; Late Night -4,-3,-1.5,0,0.5,1,2,1.5,0,-1; Spoken Word -6,-5,-3,-1,1,2.5,3.5,2.5,0,-2; Small Speakers -6,-3,2,3,1.5,0,0,1.5,2.5,1 (shared/sound/SoundModel.kt:103-123)

## Own presets: save and delete

- [x] "Save as preset…" TextAction (with the single ellipsis character) under the preset bar, padded 4dp horizontally, shown only in graphic mode (ui/sound/SoundScreen.kt:217-219)
- [x] It opens a glass popup beside the spot just pressed (the finger point; centered when nothing was pressed in the last 2 s), accessibility pane title "Preset" (ui/sound/SoundScreen.kt:449-460, ui/common/PressSpot.kt:43-51, ui/common/PressSpot.kt:63-70) (iPhone: a system popover anchored to "Save as preset…")
- [x] Popup content: 288dp wide, 6dp padding; heading "Save as preset" in `label` (padding 14dp sides, 10dp top, 6dp bottom); then a name field with placeholder "Preset name", words capitalized, keyboard Done action, autofocused so the keyboard opens; an accent "Save" button 8dp to its right; field row padded 8dp sides, 6dp top, 10dp bottom (ui/sound/SoundScreen.kt:462-474, ui/common/PopupForms.kt:86-147, ui/common/GlassMenu.kt:70, ui/common/GlassMenu.kt:310-319) (iPhone: the popover's name form: heading, field with "Preset name", words capitalized, Done key, keyboard open at once, accent "Save" beside it)
- [x] "Save" is enabled only when the trimmed name is not empty, is not "Custom" in any case, and matches no built-in preset name in any case (ui/sound/SoundScreen.kt:468, ui/sound/SoundViewModel.kt:117-122)
- [x] When the name is not blank but not allowed, a note under the field says "A built-in preset has that name." (caption, TextMuted, 8dp top, 4dp start); this same note shows for "Custom" (ui/sound/SoundScreen.kt:469, ui/common/PopupForms.kt:114-116)
- [x] Keyboard Done saves only when allowed (ui/common/PopupForms.kt:108)
- [x] Saving: trims the name, stores the current ten graphic gains under it, sets the current curve's preset name to it (so it shows chosen), and closes the popup (ui/sound/SoundScreen.kt:470-473, ui/sound/SoundViewModel.kt:109-115)
- [x] An own preset with the same name in any case is replaced, and the saved one moves to the end of the list (sound/UserPresets.kt:41-51)
- [x] Own presets are shared by every output (not per output) and stored in their own store "sound_presets", key "presets", as a JSON list of {name, gains}; entries without exactly ten gains are ignored on read and refused on save (sound/UserPresets.kt:23-39, sound/UserPresets.kt:75-77)
- [x] Delete question popup (from a long press on an own preset): 288dp wide, padding 20dp sides and 18dp top and bottom; title "Delete "{name}"?" (with straight double quotes) in `body` TextPrimary, up to 3 lines, heading; no detail line; buttons 18dp below, 10dp apart: accent "Delete" then glass "Cancel" (ui/sound/SoundScreen.kt:475-484, ui/common/PopupForms.kt:49-81) (iPhone: a system confirmation dialog titled Delete "{name}"? with a destructive Delete and the system Cancel)
- [x] Deleting removes the own preset with exactly that name (case-sensitive) and closes; if the current curve was labelled with it, its preset name is cleared, so the label becomes "Custom" (ui/sound/SoundViewModel.kt:124-127, sound/UserPresets.kt:53-59)
- [x] Tapping outside the popup or Back closes it; the content stays drawn while it fades out (ui/sound/SoundScreen.kt:103-107, ui/sound/SoundScreen.kt:461, design/GlassPopup.kt:143-150) (iPhone: the system popover and dialog close on a tap outside)
- [x] When the popup closes, focus is cleared so the keyboard goes away (ui/sound/SoundScreen.kt:451-452)
- [x] Popup grows in from the corner nearest its anchor over 160ms (scale 0.92 to 1 with fade); with reduced motion it only fades (design/GlassPopup.kt:131-132, design/GlassPopup.kt:200-224) (iPhone: the system popover's own appearing motion)

## Preamp

- [x] Preamp block padded 4dp horizontally (ui/sound/SoundScreen.kt:310)
- [x] SwitchLine "Automatic preamp", detail "Lowers the level by the curve's highest boost, so boosting never distorts.", saved at once (ui/sound/SoundScreen.kt:311-316)
- [x] With automatic preamp off, a "Preamp" slider -12..+6 dB, step 0.5, reading readDb(preampDb), changes as previews (ui/sound/SoundScreen.kt:69-70, ui/sound/SoundScreen.kt:317-325)
- [x] A "Level now" row, 4dp above: "Level now" in `bodySmall` TextSecondary on the left, readDb(effective preamp) in `bodySmall` tabular TextPrimary on the right (ui/sound/SoundScreen.kt:326-329)
- [x] Effective preamp: 0 dB while the equalizer is off; automatic = minus the highest boost of the active curve (never positive), measured on a 512-point curve; manual = the correction's own preamp + the manual preamp (so "Level now" can differ from the slider reading when a correction is loaded) (shared/sound/SoundModel.kt:88-95, shared/sound/SoundModel.kt:171-172)
- [x] "Level now" on the page is worked out at 48 kHz; the audio path uses the real sample rate (ui/sound/SoundScreen.kt:309, sound/OctoDspProcessor.kt:93)

## Hold to hear it flat

- [x] A glass capsule 48dp tall, centered, words "Hold to hear it flat" in `label` TextPrimary with 24dp padding each side (ui/sound/SoundScreen.kt:223-228, ui/sound/SoundControls.kt:133-167)
- [x] Enabled while the equalizer is on or while it is being held; drawn at alpha 0.6 when disabled and not held; a press while disabled does nothing (ui/sound/SoundScreen.kt:225, ui/sound/SoundControls.kt:142, ui/sound/SoundControls.kt:148)
- [x] Pressing down (no slop, no delay) turns the equalizer off and marks it as held; the glass lifts (Lifted light) while held (ui/sound/SoundControls.kt:146-157, ui/sound/SoundControls.kt:164, ui/sound/SoundViewModel.kt:131-135)
- [x] Release or cancel turns the equalizer back on (ui/sound/SoundControls.kt:153-156, ui/sound/SoundViewModel.kt:135-138)
- [x] The press is not cut short when the page redraws because of the change it made (the gesture is not restarted on state changes) (ui/sound/SoundControls.kt:143-145)
- [x] While held, every part of the page that follows `eqEnabled` shows off: the Equalizer switch, the grey curve (250ms dim), the player's Sound button (ui/sound/SoundViewModel.kt:131-139)
- [x] Both changes are saved at once (no draft) (ui/sound/SoundViewModel.kt:63-66)
- [x] Accessibility: role Button, name "Hold to hear it flat" (ui/sound/SoundControls.kt:160-163)
- [x] If the page is closed while held, the equalizer is turned back on (ui/sound/SoundViewModel.kt:172-176)

## Loudness card

- [x] Card title "Loudness" (ui/sound/SoundScreen.kt:336)
- [x] Segmented control "Off", "Song", "Album", "Smart" mapping to Off, Track, Album, Smart; saved at once (ui/sound/SoundScreen.kt:76-77, ui/sound/SoundScreen.kt:337-341)
- [x] Help caption under it in TextMuted, by mode: Off "Songs play at the level they were made."; Song "Evens out volume between songs."; Album "Keeps an album's quiet and loud songs as the artist made them."; Smart "Album while you play an album in order, otherwise song." (ui/sound/SoundScreen.kt:78-83, ui/sound/SoundScreen.kt:342)
- [x] Shown only when the mode is not Off: "Preamp" slider -12..+12 dB step 0.5 (ReplayGain preamp) (ui/sound/SoundScreen.kt:73, ui/sound/SoundScreen.kt:343-350)
- [x] Shown only when not Off: the line "Volume for songs without loudness info" in `bodySmall` TextPrimary, then a "Level" slider -12..+6 dB step 0.5 (fallback level) (ui/sound/SoundScreen.kt:74, ui/sound/SoundScreen.kt:351-358)
- [x] Shown only when not Off: SwitchLine "Prevent clipping", detail "Turns a song down rather than letting a boost distort it.", saved at once (ui/sound/SoundScreen.kt:359-364)
- [x] Always shown, last: SwitchLine "Limiter", detail "Catches any peak that would still distort, just below full volume.", saved at once (ui/sound/SoundScreen.kt:366-371)
- [x] Both loudness sliders send previews (ui/sound/SoundScreen.kt:349, ui/sound/SoundScreen.kt:357)

## Balance card

- [x] Card title "Balance" (ui/sound/SoundScreen.kt:377)
- [x] Row: "Left and right" in `bodySmall` TextSecondary filling the row, the balance in words in `bodySmall` TextPrimary at the end (ui/sound/SoundScreen.kt:378-381)
- [x] Balance in words: percent = round(|value| x 100); 0 gives "Centre", negative "{percent}% left", positive "{percent}% right" (UK spelling "Centre" in the Android string) (ui/sound/SoundControls.kt:305-313)
- [x] Balance slider row: "L" in `caption` TextMuted, the slider box (12dp padding each side, 48dp tall, filling the row), "R" in `caption` TextMuted (ui/sound/SoundControls.kt:247-302)
- [x] Slider changes are previews (ui/sound/SoundScreen.kt:382)
- [x] Dragging sideways: value = (x / width) x 2 - 1, clamped to -1..1; inside 0.05 of the middle it snaps to 0, otherwise it rounds to steps of 0.05 (ui/sound/SoundControls.kt:221-245)
- [x] Haptic segment tick each time the value lands on 0 from a non-zero value (ui/sound/SoundControls.kt:243)
- [x] A drag start does not move the value; the first move does (ui/sound/SoundControls.kt:268-277)
- [x] There is no tap-to-jump; a double tap anywhere on the slider sets it to the centre (ui/sound/SoundControls.kt:263-265)
- [x] Drawing: full-width track, white at alpha 0.24; while dragging thickness 8dp, at rest 3.5dp (spring damping 0.5, stiffness 200) (ui/sound/SoundControls.kt:233, ui/sound/SoundControls.kt:284)
- [x] Drawing: when not centred, a white line from the centre to the value with a three-pass glow (blur 30px, 12px, 3.6px; alpha 0.4 at rest, 0.8 while dragging, spring damping 1 stiffness 200, split over three passes) (ui/sound/SoundControls.kt:235, ui/sound/SoundControls.kt:285-295) (iPhone: the glow follows the same spring as the thickness, held to 0..1)
- [x] Drawing: a centre mark, white at alpha 0.5, 1dp wide, from 7dp above to 7dp below the line (ui/sound/SoundControls.kt:296-297)
- [x] Drawing: a white thumb always visible at the value, radius 4dp at rest and 9dp while dragging (spring damping 0.5, stiffness 200) (ui/sound/SoundControls.kt:234, ui/sound/SoundControls.kt:298)
- [x] While dragging, the drawing follows the local drag value rather than the saved value (ui/sound/SoundControls.kt:283)
- [x] Accessibility: name "Balance", state = balance in words, actions "More to the left" (minus 0.1, stops at -1), "More to the right" (plus 0.1, stops at 1), "Centre" (sets 0) (ui/sound/SoundControls.kt:254-262)
- [x] SwitchLine "Mono", detail "Both ears hear the same thing. Handy with one earbud.", saved at once (ui/sound/SoundScreen.kt:383-388)

## Headphone correction card

- [x] Card title "Headphone correction" (ui/sound/SoundScreen.kt:405)
- [x] Top row: on the left (12dp gap to the right) the correction name or "None" in `bodySmall` TextPrimary, over a caption in TextMuted (ui/sound/SoundScreen.kt:406-418)
- [x] Caption: no correction "Evens out how your headphones colour the sound." (UK spelling "colour" in the Android string); imported "Imported from a file"; any other source "Correction by AutoEq, measured by {source}" (ui/sound/SoundScreen.kt:410-414)
- [x] With a correction loaded, a "Remove" TextAction at the right end of that row; removing clears the correction (the equalizer stays as it was), saved at once (ui/sound/SoundScreen.kt:419, ui/sound/SoundViewModel.kt:155)
- [x] When the last file action failed, its message shows under the row in `caption` Error color, until the next attempt (ui/sound/SoundScreen.kt:421, ui/sound/SoundViewModel.kt:51-53)
- [x] Then a hairline, then "Import correction…" with value "A ParametricEQ.txt file" (ui/sound/SoundScreen.kt:422-423)
- [x] Import opens the system file picker for documents of type text/plain or text/* (ui/sound/SoundScreen.kt:395-397, ui/sound/SoundScreen.kt:423)
- [x] Import reads at most 256 KiB as UTF-8 off the main thread; the correction is named from the file's display name (falling back to the last path segment) (sound/SoundFiles.kt:18-33, sound/SoundFiles.kt:59-75)
- [x] Correction name: file name without the extension, trimmed, with a trailing "ParametricEQ" removed, then trailing "-" and "_" removed and trimmed; if that is empty, the bare name; if that is empty, "Correction" (shared/sound/ParametricEqFile.kt:48-54)
- [x] An imported correction has source "Imported", the file's preamp, and its filters (shared/sound/ParametricEqFile.kt:40-46, shared/sound/ParametricEqFile.kt:69-70)
- [x] A file that cannot be read or has no usable filters shows "That file has no filters Octo can read." and changes nothing (ui/sound/SoundViewModel.kt:143-148)
- [x] A good file clears the message, stores the correction, and turns the equalizer on (a correction plays only through it), saved at once (ui/sound/SoundViewModel.kt:149-151)
- [x] The correction's filters run before the own curve and are not draggable nodes; they shape the drawn curve the nodes sit on (shared/sound/SoundModel.kt:74-83, ui/sound/ResponseGraph.kt:160-165)
- [x] "Export my curve…" with value "Saves it as a ParametricEQ.txt file" opens the system create-document picker for text/plain with the suggested name "Octo ParametricEQ.txt" (ui/sound/SoundScreen.kt:398-400, ui/sound/SoundScreen.kt:424)
- [x] Export writes everything the equalizer would apply as if it were on: the effective preamp (automatic, or correction preamp + manual) and the active filters (correction first, then own, leaving out 0 dB and disabled ones) (ui/sound/SoundViewModel.kt:157-165)
- [x] Export writes UTF-8 replacing the file's contents; on failure it shows "The file could not be saved.", on success it clears the message (ui/sound/SoundViewModel.kt:162-164, sound/SoundFiles.kt:35-40)
- [x] Export file format (see ParametricEqFile below): first line "Preamp: {x.x} dB", then one line per filter "Filter {n}: ON {PK|LSC|HSC} Fc {hz} Hz Gain {x.x} dB Q {x.xx}" (shared/sound/ParametricEqFile.kt:56-67)

## System equalizer link and audio session

- [~] "Open system equalizer" with value "The phone's own sound effects" is shown only when some app on the phone answers the "display audio effect control panel" request (checked once when the card appears) (ui/sound/SoundScreen.kt:402, ui/sound/SoundScreen.kt:425-430, sound/SoundFiles.kt:42-57) (not on iPhone: iOS has no system equalizer panel for apps to open)
- [~] Tapping it builds the request again (so it carries the session in use now) and opens that app's panel; a failure to open is swallowed (ui/sound/SoundScreen.kt:427-428) (not on iPhone: iOS has no audio effect control panel request)
- [~] The request carries Octo's audio session id, Octo's package name, and content type music (sound/SoundFiles.kt:45-48) (not on iPhone: iOS has no audio session ids or effect panels for other apps)
- [~] Both decks play in one audio session made once for the app (0 when the phone would not make one), so an outside equalizer keeps working through crossfades (sound/AudioSession.kt:14-21, playback/OctoPlaybackService.kt:169-171) (not on iPhone: no other app can process Octo's sound on iOS, so there is no shared session for one)
- [~] Octo announces "session opened" to outside equalizer apps when music starts playing on the phone (not when casting), once until it is closed (sound/AudioSession.kt:25-30, playback/OctoPlaybackService.kt:528-531) (not on iPhone: iOS has no audio effect session announcements)
- [~] Octo announces "session closed" when playback goes idle or ends, when it plays on another device, and when the service is destroyed; a pause does not close it (sound/AudioSession.kt:32-37, playback/OctoPlaybackService.kt:287, playback/OctoPlaybackService.kt:501-502) (not on iPhone: iOS has no audio effect session announcements)

## Draft, previews, and save pacing

- [x] Two kinds of change: `change` (switches, taps, segmented, presets) saves at once and also applies to a draft if one exists; `preview` (drags and sliders) updates the draft at once and saves at a limited rate (ui/sound/SoundViewModel.kt:62-75)
- [x] Preview: draft = edit(draft or saved settings); the edit is kept as pending; a writer starts if none is running (ui/sound/SoundViewModel.kt:71-75)
- [x] Writer: saves the pending edit at once (leading edge), waits 100ms, repeats while there is a pending edit (ui/sound/SoundViewModel.kt:28-30, ui/sound/SoundViewModel.kt:85-93)
- [x] Each edit sets values outright (not deltas), so saving only the latest pending edit loses nothing (ui/sound/SoundViewModel.kt:68-70)
- [x] With nothing pending, the writer waits up to 1000ms for the saved settings to equal the draft, then drops the draft (if no new edit arrived and the draft has not changed), so nothing flickers back for a frame (ui/sound/SoundViewModel.kt:94-101)
- [x] Settle (finger lifted): saves the pending edit now (ui/sound/SoundViewModel.kt:77-83)
- [x] Closing the page settles any pending edit (ui/sound/SoundViewModel.kt:172-176)
- [x] All sound edits apply to the output playing now (ui/sound/SoundViewModel.kt:32-33)

## Edit rules (SoundEdits)

- [x] cleanGain: clamp to -12..+12, then under 0.25 dB from zero becomes 0, otherwise round to 0.1 dB (shared/ui/sound/SoundEdits.kt:34-40)
- [x] withPreset: equalizer on, mode Graphic, gains = preset gains, preset = preset name (shared/ui/sound/SoundEdits.kt:42-49)
- [x] withBandGain: out-of-range band changes nothing; otherwise sets cleanGain(gain) on that band and clears the preset name (shared/ui/sound/SoundEdits.kt:51-56)
- [x] seedFromGraphic: the ten bands as Peak filters at the band frequencies with Q 1.41 and the band gains (shared/ui/sound/SoundEdits.kt:58-60, shared/sound/SoundModel.kt:35)
- [x] withMode: same mode changes nothing; to Graphic only switches the mode (graphic gains untouched); to Parametric keeps existing filters only if there are some and every graphic gain is exactly 0, otherwise replaces the filters with the ten seeded bands, so the sound does not change on the switch (shared/ui/sound/SoundEdits.kt:62-74)
- [x] withMode never touches the preset name; but any parametric edit (filter edit, add, delete, drag) clears it, so coming back to Graphic after such an edit shows "Custom" even though the ten bands are unchanged (shared/ui/sound/SoundEdits.kt:65-99, shared/ui/sound/SoundEdits.kt:122-123)
- [x] withFilter: out-of-range index changes nothing; otherwise frequency clamped 20..20000, gain via cleanGain, Q clamped 0.1..10, preset name cleared (shared/ui/sound/SoundEdits.kt:76-86)
- [x] withNewFilter: at 16 filters returns the same settings; otherwise appends Peak at emptiestFrequency, 0 dB, Q 1, clears preset name (shared/ui/sound/SoundEdits.kt:88-94)
- [x] withoutFilter: out-of-range index changes nothing; otherwise removes it and clears preset name (shared/ui/sound/SoundEdits.kt:96-99)
- [x] tidyHz: under 100 Hz to 1 Hz, under 1000 to 10, under 10000 to 100, else to 1000; result clamped 20..20000 (shared/ui/sound/SoundEdits.kt:109-118)

## Readings

- [x] readDb: round to tenths; 0 gives "0 dB" with no sign; otherwise "+" or "-" (ASCII hyphen), the number with no trailing ".0", then " dB" ("+3.5 dB", "-2 dB"; -0.01 gives "0 dB") (shared/ui/sound/SoundEdits.kt:144-152)
- [x] shortHz: under 1000 the rounded whole number; otherwise k = round(hz / 100) / 10, shown as "{k}k" when whole, else one decimal with a dot ("1k", "1.2k", "16k") (shared/ui/sound/SoundEdits.kt:132-139)
- [x] readHz: under 1000 "{rounded} Hz"; otherwise shortHz without the "k" plus " kHz" ("62 Hz", "1.2 kHz") (shared/ui/sound/SoundEdits.kt:141-142)
- [x] describeNode: "{rounded hz} Hz, {readDb}" (shared/ui/sound/SoundEdits.kt:154-155)
- [x] Q reading: two decimals, always a dot (ui/sound/SoundScreen.kt:276)

## Audio path order

- [x] Every deck builds its own audio output with its own Octo shaping step, all reading the same current settings (sound/OctoRenderersFactory.kt:9-39, playback/OctoPlaybackService.kt:168-173)
- [x] The output is asked for 16-bit sound (float output off), because the player only runs these steps on 16-bit sound; the shaping step itself turns it into floats (sound/OctoRenderersFactory.kt:11-13, sound/OctoRenderersFactory.kt:33-37) (iPhone: decks hand the shaping 32-bit float at 48 kHz, which it takes as it is)
- [x] Step order: skip silence, then speed and pitch (Sonic), then Octo's shaping last (sound/OctoProcessorChain.kt:10-18) (iPhone: skip silence works on the decoded sound, then Octo's shaping, then AVAudioUnitTimePitch for speed and pitch)
- [x] Speed changes go to Sonic (speed and pitch) and also to the shaping step, which uses speed to keep song time (sound/OctoProcessorChain.kt:22-27) (iPhone: the shaping runs on the song's own frames before the speed stage, so song time needs no speed)
- [x] Media duration accounts for speed only while Sonic is active; skipped frames come from the silence step (sound/OctoProcessorChain.kt:34-37) (iPhone: song time comes from the ring's song frames, moved on past skipped silence; the speed stage comes after)
- [x] Inside the shaping step, in order: level (ReplayGain factor x equalizer preamp), equalizer filters, mono then balance, limiter, then the crossfade transition (sound/OctoDspProcessor.kt:53-56, sound/OctoDspProcessor.kt:112-117, sound/OctoDspProcessor.kt:312-314)
- [x] The live tap for crossfade planning is fed the step's input, before any shaping, and only while crossfade keeps the step active (sound/OctoDspProcessor.kt:310-312)
- [x] Input samples: 16-bit divided by 32768, or float passed in; samples are interleaved floats with full scale at 1, and boosts may exceed 1 until the limiter (sound/OctoDspProcessor.kt:193-196, sound/OctoDspProcessor.kt:302-308) (iPhone: planar floats, one buffer per channel)

## When the shaping step runs

- [x] The step accepts only 16-bit or float input; anything else bypasses it (sound/OctoDspProcessor.kt:254-256) (iPhone: the decks and the AVPlayer tap hand over 32-bit float only)
- [x] It bypasses entirely (sound untouched, bit for bit) when the settings shape nothing and crossfade is off (sound/OctoDspProcessor.kt:257)
- [x] Settings shape sound when any of: equalizer on, ReplayGain not Off, limiter on, balance not 0, mono on (sound/OctoDspProcessor.kt:17-21)
- [x] With the default settings (limiter on) the step runs; while it runs, the output stays in one format from song to song, so songs join without a gap (sound/OctoDspProcessor.kt:17-21, shared/sound/SoundModel.kt:69) (iPhone: decks always hand over 48 kHz float stereo, so songs join without a gap either way)
- [x] Whether it runs is decided when the output is set up for a stream, not on every settings change (sound/OctoDspProcessor.kt:254-259)
- [x] With crossfade on, the step runs even with nothing to shape, passing sound through unchanged, so a blend can start at any moment (sound/OctoDspProcessor.kt:200-202, playback/OctoPlaybackService.kt:163-169)
- [x] When active, output is float at the input's sample rate and channel count (sound/OctoDspProcessor.kt:258)

## Song hand-over and changes without clicks

- [x] When a song is set up, its loudness is handed to the step as "next song" and taken up only at the flush that comes once the song before has played out, so the level changes exactly between the two songs (sound/OctoDspProcessor.kt:196-198, sound/OctoDspProcessor.kt:249-252, sound/OctoDspProcessor.kt:261-267)
- [x] At a flush: the shaper is kept when sample rate and channels are unchanged, otherwise a new one is made; the limiter's held sound is cleared; settings are applied instantly when the shaper is new or a new song arrived, otherwise with glides (sound/OctoDspProcessor.kt:268-275)
- [x] So a new song's level holds from its very first sample, with no glide from the previous song's level (sound/OctoDspProcessor.kt:275, app/src/test/java/app/winters/octo/sound/OctoDspProcessorTest.kt:31-62)
- [x] During a stream, any new settings object is taken up at the start of the next buffer, with glides (sound/OctoDspProcessor.kt:289-296)
- [x] Glide time is 30ms (frames = round(sampleRate x 0.03), at least 1): 1440 frames at 48 kHz, 1323 at 44.1 kHz (sound/OctoDspProcessor.kt:14-15, sound/OctoDspProcessor.kt:58)
- [x] Each glide is a straight-line ramp per frame to the new value, landing exactly on it; a glide to the current value or with 0 frames jumps (sound/OctoDspProcessor.kt:23-51)
- [x] Glided values: overall level, left level, right level, mono amount (sound/OctoDspProcessor.kt:59-62, sound/OctoDspProcessor.kt:95-102)
- [x] A new filter set is built only when the list of coefficients differs from the running one (sound/OctoDspProcessor.kt:84-85)
- [x] A new filter set first copies the old one's memory when both have the same number of filters and channels, so a small curve change does not restart from silence (sound/OctoDspProcessor.kt:86-87, shared/sound/Biquad.kt:55-61)
- [x] Curve change with glide: old and new filter sets both run on the same input for 30ms, and the output crossfades linearly from old to new; then the old set is dropped (sound/OctoDspProcessor.kt:66-69, sound/OctoDspProcessor.kt:88-90, sound/OctoDspProcessor.kt:138-159)
- [x] Curve change when instant: no crossfade, the new set takes over at once (still with copied memory when it lines up) (sound/OctoDspProcessor.kt:88-89)
- [x] When the gain is at exactly 1 and not moving, the gain stage is skipped (sound/OctoDspProcessor.kt:126-127)

## Gain stage

- [x] Level = ReplayGain factor x 10^(effective preamp dB / 20), with the preamp worked out at the stream's real sample rate (sound/OctoDspProcessor.kt:93-95)
- [x] The same level multiplies every channel of a frame (sound/OctoDspProcessor.kt:126-136)

## Equalizer filters

- [x] The filters run are the active filters (correction first, then the own curve, leaving out disabled and 0 dB ones), in that order, each a cascaded second-order section (shared/sound/SoundModel.kt:76-83, sound/OctoDspProcessor.kt:84)
- [x] Filters at or above 0.45 x sample rate are left out (for example a 21 kHz filter at 44.1 kHz) (shared/sound/Biquad.kt:5-7, shared/sound/Biquad.kt:73-74)
- [x] Coefficients follow the Audio EQ Cookbook peak, low shelf and high shelf formulas with A = 10^(gain / 40), w0 = 2 pi f / rate, alpha = sin(w0) / (2Q), normalized so a0 = 1 (shared/sound/SoundModel.kt:128-154)
- [x] Filtering is transposed direct form II in doubles, with separate memory per filter per channel (shared/sound/Biquad.kt:13-53)
- [x] After each buffer, filter memory smaller than 1e-25 is set to 0 (shared/sound/Biquad.kt:9-11, shared/sound/Biquad.kt:49-52)

## Mono and balance math

- [x] Mono and balance apply only with 2 or more channels; a mono stream ignores both (sound/OctoDspProcessor.kt:97-102, sound/OctoDspProcessor.kt:161-162) (iPhone: the rule is in SoundShaper; decks hand a mono file over as two equal channels)
- [x] Mono amount m (0 to 1, glided): every channel moves toward the average of all channels of that frame by m: sample += (average - sample) x m (sound/OctoDspProcessor.kt:167-173)
- [x] Balance is clamped to -1..1; left level = 1 - balance when balance > 0, else 1; right level = 1 + balance when balance < 0, else 1; the near side is never raised (sound/OctoDspProcessor.kt:98-100)
- [x] Mono is applied first, then left level multiplies channel 0 and right level channel 1; further channels are not balanced (sound/OctoDspProcessor.kt:166-176)
- [x] With mono off and balance centred and nothing moving, the mix stage is skipped (sound/OctoDspProcessor.kt:163-164)
- [x] Example: input left 0.4, right 0, mono on, balance 0.5 gives left 0.1, right 0.2 (app/src/test/java/app/winters/octo/sound/SoundPathTest.kt:102-113)

## Limiter

- [x] The limiter is the last shaping stage, after mono and balance, and before the crossfade transition (sound/OctoDspProcessor.kt:112-117, sound/OctoDspProcessor.kt:312-313)
- [x] It limits only when the Limiter switch is on and the sound is not left as it is: it does nothing when there are no filters, the level is exactly 1, balance is 0, and mono is off (sound/OctoDspProcessor.kt:104-107)
- [x] Ceiling -1 dBFS (linear 10^(-1/20), about 0.891) (shared/sound/Limiter.kt:9-10, shared/sound/Limiter.kt:37)
- [x] Lookahead 1.5ms: the sound always runs that many frames late (max(1, round(rate x 0.0015)): 72 at 48 kHz, 66 at 44.1 kHz), even when the limiter is not limiting, so timing never changes (shared/sound/Limiter.kt:12-14, shared/sound/Limiter.kt:30-35)
- [x] For each frame the needed level is ceiling / peak, where peak is the largest absolute sample across all channels; 1 when the peak is under the ceiling or the limiter is off (shared/sound/Limiter.kt:66-69)
- [x] The level applied to a frame leaving the delay is the lowest need among that frame and every frame still in the lookahead window (a running minimum) (shared/sound/Limiter.kt:45-50, shared/sound/Limiter.kt:114-118, shared/sound/Limiter.kt:129-137)
- [x] Turning down is instant; coming back up is a one-pole release of 100ms: gain += (target - gain) x (1 - exp(-1 / (rate x 0.1))) (shared/sound/Limiter.kt:14, shared/sound/Limiter.kt:38, shared/sound/Limiter.kt:119)
- [x] All channels share one gain, so the stereo picture stays put (shared/sound/Limiter.kt:19)
- [x] When on, every output sample is also hard-clamped to plus or minus the ceiling (shared/sound/Limiter.kt:121-124)
- [x] At end of stream, every frame still in the delay is handed out, so nothing is lost or added between songs (shared/sound/Limiter.kt:89-102, sound/OctoDspProcessor.kt:317-324)
- [x] After a seek (flush) the delayed sound and the lookahead are forgotten; the current gain is kept (shared/sound/Limiter.kt:104-112, sound/OctoDspProcessor.kt:272)
- [x] With everything off (default settings, limiter on but nothing changed) the sound passes through exactly, only delayed (app/src/test/java/app/winters/octo/sound/SoundPathTest.kt:88-100)

## ReplayGain: tags in the sound

- [x] When a song is set up, tags are read from its decoded metadata: ID3 user text frames (TXXX: description as name, first value), Vorbis comments (FLAC, Ogg, Opus), and MP4 free-form tags in the "com.apple.iTunes" domain (any case) (sound/ReplayGainMetadata.kt:11-32) (iPhone: read from the file's own bytes as the deck opens it (LoudnessTagReader))
- [x] An MP3's own encoder header gain is used only when the tags carry no gain: its "radio" field is the track gain, its "audiophile" field the album gain, its peak (when above 0) the track peak (sound/ReplayGainMetadata.kt:30-45) (iPhone: the LAME header in the first MPEG frame, read by LoudnessTagReader)
- [x] Tag names are trimmed and matched in any case: REPLAYGAIN_TRACK_GAIN, REPLAYGAIN_TRACK_PEAK, REPLAYGAIN_ALBUM_GAIN, REPLAYGAIN_ALBUM_PEAK, R128_TRACK_GAIN, R128_ALBUM_GAIN; the first readable value of each wins (shared/sound/ReplayGain.kt:33-49)
- [x] Standard gains win over R128 gains when a song has both (shared/sound/ReplayGain.kt:50)
- [x] A song whose tags give nothing has no info (null) (shared/sound/ReplayGain.kt:51)
- [x] Gain text: trimmed, a trailing "dB" in any case removed, a leading "+" removed, a comma read as a decimal point; must be finite and within plus or minus 64 dB ("-6.54 dB", "+2.1dB", "-6,54 dB", "-4") (shared/sound/ReplayGain.kt:54-59, shared/sound/ReplayGain.kt:69-70)
- [x] Peak text: same number rules, must be above 0 (shared/sound/ReplayGain.kt:61-62)
- [x] R128 gain: a whole number in 256ths of a dB against a level 5 dB quieter, so value / 256 + 5 dB, within plus or minus 64 (-1792 gives -2 dB, 256 gives 6 dB) (shared/sound/ReplayGain.kt:23-24, shared/sound/ReplayGain.kt:64-67)

## ReplayGain: stored and server values

- [x] Each queued song carries the loudness its source keeps (track gain, track peak, album gain, album peak) in its media item extras, when known (playback/MediaItems.kt:38-42, playback/MediaItems.kt:81-84, playback/MediaItems.kt:135-140)
- [x] Stored values come from the playing copy, or failing that the first other copy of the same song that has them (playback/Copies.kt:129-132, playback/PlayableSongs.kt:98)
- [x] Server copies take the OpenSubsonic replayGain fields (track gain, album gain, finite; peaks finite and above 0); phone copies take their parsed file tags (app/src/main/java/app/winters/octo/server/ServerCatalog.kt:137-140, app/src/main/java/app/winters/octo/device/TagParsing.kt:146-149)
- [x] Stored values are checked like tags: a gain that is not finite or beyond plus or minus 64 dB is dropped, a peak that is not finite or not above 0 is dropped; with no gain left there is no stored info (shared/sound/ReplayGain.kt:128-134)
- [x] Choice: the sound's own tags when they carry a gain; else the stored values when they carry a gain; else the sound's tags as they are (peak only, or none) (shared/sound/ReplayGain.kt:118-126, sound/OctoAudioSink.kt:22-28)
- [x] So a stream the server made smaller (which loses its tags) plays at the server's values, and a stream with only a peak still uses the stored gains (sound/OctoAudioSink.kt:11-15, app/src/test/java/app/winters/octo/sound/StoredReplayGainTest.kt:23-31)

## ReplayGain: level and Smart

- [x] Off: factor 1 (shared/sound/ReplayGain.kt:80-81)
- [x] Song (Track): track gain, falling back to album gain when missing (shared/sound/ReplayGain.kt:82, shared/sound/ReplayGain.kt:91-92)
- [x] Album: album gain, falling back to track gain when missing (shared/sound/ReplayGain.kt:83, shared/sound/ReplayGain.kt:89-90)
- [x] Smart: album gain only while this song follows a song from the same album, otherwise track gain (shared/sound/ReplayGain.kt:84)
- [x] The peak used is the one of the chosen gain's kind, falling back to the other kind's peak (shared/sound/ReplayGain.kt:89-92)
- [x] dB = chosen gain + ReplayGain preamp; for a song with no gain at all, dB = the fallback level (the preamp is not added to the fallback) (shared/sound/ReplayGain.kt:94)
- [x] Factor = 10^(dB / 20); with prevent clipping on and a peak above 0, the factor is capped at 1 / peak (a cut is never affected) (shared/sound/ReplayGain.kt:95-96)
- [x] Album identity for Smart: the catalog album id, or "{album title trimmed}/{album artist, else artist, else empty}" when there is no id; no album title means no album (sound/OctoAudioSink.kt:42-49)
- [x] Album run (one per playback service, shared by both decks): a song "follows" when its album is known and equals the album of the last song set up; the same song set up twice in a row keeps its earlier answer; the song key is the media id, empty treated as none (shared/sound/ReplayGain.kt:99-116, sound/OctoAudioSink.kt:25-27, playback/OctoPlaybackService.kt:158-162)

## Live tap feed (crossfade planning)

- [x] The audio thread only copies samples into a ring of 2^18 floats (about 2.7 s of 48 kHz stereo); a buffer that does not fit whole is dropped, never wrapped over unread data (sound/LiveTapFeed.kt:10-12, sound/LiveTapFeed.kt:47-62)
- [x] A worker takes the samples into the tap of the song they belong to every 100ms, on one shared low-priority daemon thread named "octo-live-tap" (sound/LiveTapFeed.kt:14-15, sound/LiveTapFeed.kt:41-45, sound/LiveTapFeed.kt:117-124)
- [x] A new song or new format starts a new tap exactly at its first sample in the ring, even if nothing was drained in between (sound/LiveTapFeed.kt:33-43, sound/LiveTapFeed.kt:70-105)
- [x] The step begins a new tap at a flush only when the song changed or the shaper is new (sound/OctoDspProcessor.kt:277-286)
- [x] A reading drains first, then returns heard length, body level and tempo (its octave picked by the song's tag tempo) only when the tap belongs to the asked queue entry, else nothing (sound/LiveTapFeed.kt:107-115)
- [x] Closing the feed (on reset) stops its worker task; a later begin starts it again (sound/LiveTapFeed.kt:64-68, sound/OctoDspProcessor.kt:326-333)

## Crossfade transition stage (TransitionShaper)

- [x] Each deck keeps song time for every frame it hands on: stream start position (from the player) + frames handed on x (1000 x speed / sample rate) ms (sound/OctoDspProcessor.kt:277-281, sound/OctoDspProcessor.kt:335-348) (iPhone: song frames before the speed stage, so the speed term is 1)
- [x] An armed transition applies to this stream when the transition names no entry, the stream's entry is unknown, or they match; a transition for another song leaves this one untouched (sound/OctoDspProcessor.kt:344-346, app/src/test/java/app/winters/octo/sound/TransitionShaperTest.kt:250-260)
- [x] Progress through the blend: outgoing = (songMs - start) / overlap; incoming = ((songMs - entry) / beat match rate, default 1) / overlap; a zero overlap gives 1 once reached, else -1 (sound/TransitionShaper.kt:60-67)
- [x] Volume: incoming 0 before, 1 after, plan in-gain x headroom inside; outgoing 1 before, 0 after, plan out-gain x headroom inside (sound/TransitionShaper.kt:69-77)
- [x] Headroom = 10^(-headroomDb / 20), ramped in over the first 15% of the blend and out over the last 15% as headroom^w, w = min(1, min(t, 1 - t) / 0.15) (sound/TransitionShaper.kt:32-34, sound/TransitionShaper.kt:58, sound/TransitionShaper.kt:79-84)
- [x] Filters run only inside the blend and only when the plan's filter strength is above 0; outgoing gets a low-pass then high-pass, incoming only a high-pass (sound/TransitionShaper.kt:86-95, sound/TransitionShaper.kt:217-223, sound/TransitionShaper.kt:237-241)
- [x] Outgoing low-pass steps on the beat when the plan is bar-locked: beats are the plan's beat positions, glide between steps = beat ms x 4 / 8 / overlap ms (sound/TransitionShaper.kt:49-56, sound/TransitionShaper.kt:90-92)
- [x] Sweep filters: Butterworth second-order sections (Q 0.7071067811865476), cutoff clamped to 1 Hz..0.45 x rate, direct form I with per-channel state; a cutoff change under 0.1% is ignored (sound/TransitionShaper.kt:104-160)
- [x] Volume and cutoffs are recomputed every 32 frames (sound/TransitionShaper.kt:25-26, sound/TransitionShaper.kt:211-223)
- [x] Volume never moves faster than silence to full in 30ms (per-frame slew 1 / (rate x 0.03)), so arming or dropping a transition never clicks (sound/TransitionShaper.kt:16-18, sound/TransitionShaper.kt:171, sound/TransitionShaper.kt:230)
- [x] Filters fade in and out over 10ms as a wet/dry mix with the dry sound, so their phase shift never steps the waveform; filter state resets once fully dry and off (sound/TransitionShaper.kt:20-23, sound/TransitionShaper.kt:172, sound/TransitionShaper.kt:228-249)
- [x] Early fade: the outgoing song is measured in 10ms windows (mean square of the channel average, before any volume change); once it stays below its gate for 300ms in the blend, it fades out (at the slew rate) and stays out (sound/TransitionShaper.kt:28-30, sound/TransitionShaper.kt:179-185, sound/TransitionShaper.kt:224-227, sound/TransitionShaper.kt:258-280)
- [x] Arming: re-arming the same transition is a no-op; arming resets the early-fade state; an incoming transition armed fresh (no transition before and volume at 1) takes its first volume at once so it starts silent; an outgoing one armed late glides to the curve (sound/TransitionShaper.kt:187-200)
- [x] With no transition, or an outgoing song before its blend, at full volume and fully dry, the sound passes through exactly (sound/TransitionShaper.kt:204-210)
- [x] An incoming song past its blend, back at full and dry, drops the transition and plays untouched (sound/TransitionShaper.kt:252-255)
- [x] The transition math (out-gain, in-gain, low-pass and high-pass curves, beat progress) lives in the shared Automix plan code and is checked against shared vectors (sound/TransitionShaper.kt:3-6, app/src/test/java/app/winters/octo/sound/TransitionShaperTest.kt:34-41)

## Backup and restore

- [x] A backup holds the per-output flag and every stored set by output key, plus the own presets (backup/Backups.kt:75-86, backup/Backup.kt:54)
- [x] Restore merges stored sets (sets in the backup replace those of the same key; others stay) and sets the per-output flag from the backup (sound/SoundEngine.kt:145-153, backup/Backups.kt:167)
- [x] Restore of presets keeps only named ones with ten gains, replaces own presets with the same trimmed name in any case, and appends the restored ones with trimmed names (sound/UserPresets.kt:64-73, backup/Backups.kt:168)
- [x] Backup summary lines: "{n} output with its own sound" / "{n} outputs with their own sound" (only when per-output is on and some key other than "all" exists), and "{n} equalizer preset" / "{n} equalizer presets" (backup/Backup.kt:345-357)

## Tests in the app module to port

- [x] AudioOutputTest: earbuds listed twice are one output in either order (key "bluetooth:Enco X3", label "Enco X3", former keys "bluetooth:AA:01", "bluetooth:AA:02"); a nameless device is known by its first sorted address ("bluetooth:BB:01", label "Bluetooth", former "bluetooth:BB:02"); Bluetooth beats USB beats a cable; nothing connected is the speaker; settings under an old address are found and the current key wins (app/src/test/java/app/winters/octo/sound/AudioOutputTest.kt:8-58)
- [x] OctoDspProcessorTest: a song's gain starts at its first sample (-6.0206 dB on half-scale gives 0.25 through the end of that song, then 0.5 from the first sample after the hand-over); everything off with the limiter off bypasses the step (app/src/test/java/app/winters/octo/sound/OctoDspProcessorTest.kt:31-69)
- [x] SoundPathTest: a 1 kHz +6 dB peak gives 6.0 dB (within 0.05) after settling; channels filter on their own (-12 dB within 0.1, silent right stays exactly 0); a 21 kHz band is dropped at 44.1 kHz but kept at 96 kHz; the limiter never exceeds its ceiling and holds a 4x burst above 0.99 x ceiling; the limiter loses no frames and leaves quiet sound bit-exact; untouched sound passes through exactly; mono and balance mixing (app/src/test/java/app/winters/octo/sound/SoundPathTest.kt:22-113)
- [x] ReplayGainMetadataTest: ID3 TXXX frames (-6.54, 0.988251, -7.10), Vorbis comments with comma decimals (-8.25, 1.02), R128 (-1792 gives -2, 256 gives 6), MP4 free-form only from com.apple.iTunes, MP3 header only as a last resort (-3 dB and peak 0.9 alone; a tag of -5 wins), no tags gives null (app/src/test/java/app/winters/octo/sound/ReplayGainMetadataTest.kt:12-80)
- [x] StoredReplayGainTest: tags in the sound win; stored values stand in when the sound has none or only a peak; an album gain alone is still a gain; with neither the fallback applies (-6 dB gives 0.501); stored values set the level (-8.4 dB gives 0.380); stored values are checked like tags; the playing copy gives its values and other copies fill in (app/src/test/java/app/winters/octo/sound/StoredReplayGainTest.kt:12-78)
- [x] LiveTapFeedTest: a 5 s half-scale sine reads 5000 ms heard and -9.03 dB (within 0.2); a new song starts a new tap where its sound starts; a steady 120 BPM beat gives 120 (within 1); sound that does not fit is dropped; a tag tempo of 61 picks the 60 octave (app/src/test/java/app/winters/octo/sound/LiveTapFeedTest.kt:13-99)
- [x] TransitionShaperTest: sweep coefficients and impulse responses match the shared vectors; volumes and cutoffs follow the shared curves; outgoing follows its own song time; incoming silent until its entry then untouched; headroom dip mid-blend; sweeps cut top and bass; incoming opens up; early fade after 300ms of silence; shorter quiet does not end the song; transition for another song is ignored; nothing to shape passes through; song time runs with speed; dropping midway glides back; filter hand-over over 10ms; outgoing filters engage without a click; late-armed outgoing glides (app/src/test/java/app/winters/octo/sound/TransitionShaperTest.kt:30-344)
- [x] SoundReadingsTest: "+3.5 dB", "-2 dB", "0 dB" for -0.01, "62 Hz, +3 dB", "1k", "16k", "1.2 kHz", "Centre" for 0.004, "30% left" for -0.3 (app/src/test/java/app/winters/octo/ui/sound/SoundReadingsTest.kt:6-19)

## Shared logic to port line for line

The shared model (SoundModel, Biquad, ReplayGain, Limiter, ParametricEqFile) is already ported to Swift; its tests still need porting.

- `shared/core/src/commonMain/kotlin/app/winters/octo/sound/SoundModel.kt`: FilterType, EqFilter, EqMode, ReplayGainMode, GraphicBands, GRAPHIC_Q 1.41, GAIN_RANGE_DB 12, HeadphoneCorrection, SoundSettings (defaults, activeFilters, effectivePreampDb), EqPreset and the 19 built-in presets, Cookbook coefficients, ResponseCurve (frequencies, gainDb, curve, peakDb). Tests: `shared/core/src/commonTest/kotlin/app/winters/octo/sound/SoundModelTest.kt`
- `shared/core/src/commonMain/kotlin/app/winters/octo/sound/Biquad.kt`: HIGHEST_BAND_SHARE 0.45, FilterBank (TDF-II in doubles, per-channel memory, denormal flush, continueFrom, clear), filterBank, bandCoefficients. Tests: `app/src/test/java/app/winters/octo/sound/SoundPathTest.kt` (first three tests)
- `shared/core/src/commonMain/kotlin/app/winters/octo/sound/Limiter.kt`: lookahead limiter (ceiling -1 dBFS, 1.5ms lookahead, 100ms release, running-minimum queue, drain, clear). Tests: `app/src/test/java/app/winters/octo/sound/SoundPathTest.kt` (limiter tests)
- `shared/core/src/commonMain/kotlin/app/winters/octo/sound/ParametricEqFile.kt`: parse, correction, nameFrom, write (dot decimals, no "-0.0", whole Hz when within 0.05), IMPORTED. Tests: `shared/core/src/commonTest/kotlin/app/winters/octo/sound/ParametricEqFileTest.kt`
- `shared/core/src/commonMain/kotlin/app/winters/octo/sound/ReplayGain.kt`: ReplayGainInfo, SongLoudness, fromTags, parseGain, parsePeak, parseR128, replayGainFactor, AlbumRun, chooseReplayGain, storedReplayGain. Tests: `shared/core/src/commonTest/kotlin/app/winters/octo/sound/ReplayGainTest.kt`, `app/src/test/java/app/winters/octo/sound/StoredReplayGainTest.kt`
- `shared/core/src/commonMain/kotlin/app/winters/octo/ui/sound/SoundEdits.kt`: MAX_FILTERS 16, MIN_HZ 20, MAX_HZ 20000, MIN_Q 0.1, MAX_Q 10, CUSTOM "Custom", cleanGain, withPreset, withBandGain, seedFromGraphic, withMode, withFilter, withNewFilter, withoutFilter, emptiestFrequency, tidyHz, presetLabel, soundSummary, shortHz, readHz, readDb, describeNode. Tests: `shared/core/src/commonTest/kotlin/app/winters/octo/ui/sound/SoundEditsTest.kt`, `app/src/test/java/app/winters/octo/ui/sound/SoundReadingsTest.kt`
- `app/src/main/java/app/winters/octo/sound/OctoDspProcessor.kt` (platform-free parts): GLIDE_MS 30, shapesSound, Glide, SoundShaper (apply, process, drain, clearHeld, gain, filter crossfade, mix). Tests: `app/src/test/java/app/winters/octo/sound/SoundPathTest.kt` (last two tests), `app/src/test/java/app/winters/octo/sound/OctoDspProcessorTest.kt`
- `app/src/main/java/app/winters/octo/sound/SoundEngine.kt` (platform-free parts): AudioOutput, PhoneSpeaker, BLUETOOTH_OUTPUT_PREFIX, OutputDevice, OutputKind ranks, outputFor, savedFor, and the per-output read and write rules. Tests: `app/src/test/java/app/winters/octo/sound/AudioOutputTest.kt`
- `app/src/main/java/app/winters/octo/sound/ReplayGainMetadata.kt`: which tag containers are read and the MP3 header fallback order. Tests: `app/src/test/java/app/winters/octo/sound/ReplayGainMetadataTest.kt`
- `app/src/main/java/app/winters/octo/sound/TransitionShaper.kt`: DeckTransition, sweepCoefficients, SweptFilter, TransitionShaper; depends on shared `playback/AutomixCurves.kt`, `playback/AutomixPlan.kt`, `playback/AutomixFilters.kt` (HIGHEST_CUTOFF_SHARE 0.45), `playback/AutomixFeatures.kt` (BEATS_PER_BAR 4). Tests: `app/src/test/java/app/winters/octo/sound/TransitionShaperTest.kt` with vectors `shared/core/src/commonTest/resources/automix-vectors.json`
- `app/src/main/java/app/winters/octo/sound/LiveTapFeed.kt`: ring hand-off to LiveTap (`playback/LiveTap`). Tests: `app/src/test/java/app/winters/octo/sound/LiveTapFeedTest.kt`
- `app/src/main/java/app/winters/octo/sound/UserPresets.kt`: save (case-insensitive replace, append), delete (exact name), restore, read filter. No dedicated tests.
