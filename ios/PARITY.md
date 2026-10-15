# iPhone parity with the Android app

What the iPhone app has to match, read from the Android app on `origin/main`
(0f11df0f, 2026-10-11). On iPhone the look is Apple's Liquid Glass and its
native controls; the layout, behaviour, features and words are Octo's.

`[x]` done and seen on the phone, `[~]` built, needs work, `[ ]` not built.

## Shell

- [x] Floating bar: tab capsule (Home, Search, Library, Settings, icons only, sliding selected pill) and the round now-playing button
- [x] The round button grows into the mini player; tabs fold to a circle ("Show tabs"); widths animate
- [x] With nothing loaded the round button shuffles the library
- [x] Mini player: cover with progress ring, title, artist, previous, play, next; swipes skip, swipe up opens
- [x] Every tab keeps its pages; tapping the tab in use goes back to its first page
- [x] Big titles that scroll with the page; floating glass back button; edge swipe back
- [~] Toast above the bar with Undo
- [ ] Downloads pill above the bar (server downloads in progress)
- [ ] Bar tint from the song's colour (ambient option)
- [ ] Selection bar replacing the bar while picking songs

## Full player

- [x] Fills the screen; the cover's wash behind it; words take a readable colour
- [x] Pull down anywhere to close; swipe the cover to skip; cover shrinks when paused
- [~] Top line: close, album name (opens album), AirPlay; Sound button missing
- [ ] Cover flies from the bar into the player; background zooms in on open
- [~] Song row: title marquee, artist (opens artist), heart, More
- [ ] Rating stars row
- [x] Line slider, times, quality badge, speed mark
- [x] Transport
- [ ] Volume row aligned between the speakers, Octo's line slider
- [x] Action row: lyrics, up next, sleep timer, shuffle, repeat
- [~] Lyrics: synced lines follow and tap to seek
- [ ] Lyrics menu: source heading, Find or Choose other lyrics (server candidates, search), Adjust timing (this song, this output), Hide or Show lyrics
- [ ] Lyrics sources in order: pick, server, file tags, .lrc, lrclib
- [ ] Flowing lyrics (default), Classic, Plain; long press shows the time
- [ ] Lyrics bar: menu button, scrub along its bottom edge
- [~] Up next: tools, undo, save as playlist; needs drag handles, group captions, Autoplay tag
- [~] Sleep timer and speed; pitch slider missing
- [ ] Sound page: equalizer with presets and bands, ReplayGain modes, preamp
- [ ] Android's full song menu from the player

## Sign-in and servers

- [x] Opens without a server; Home's empty card signs in
- [x] Sign-in page: scheme button, connection note, Advanced (legacy, API key, home address, headers, client certificate), certificate trust
- [x] Server list: switch, edit, sign out, remove, add
- [ ] Family: QR scan, invite sign-up, hand-over (receive and approve)
- [ ] Octo detection through /api/admin/status checked against a real Octo

## Home

- [~] Shelves in Android's order; empty shelves left out
- [ ] Phone access card, Resume card, What's New card
- [ ] Pinned, Most played, Not played in 6 months, Never finished, Unplayed albums
- [ ] Long press menus on cards; Pin to Home

## Search

- [~] Field, kinds, recent searches, online section
- [ ] Playlists kind, "Top songs" for an artist's name, ranked rows, "See all"
- [ ] "Popular right now" chart under recent searches
- [ ] "Library songs only" chip; add button with download states on online songs
- [ ] Find songs, Find higher quality, Replace anyway

## Library and pages

- [~] Library rows and Recently added
- [ ] Songs (search, filter chips, sorting), Genres, Folders, Downloads, History, Library health
- [ ] Sort capsule and popup on every list; letter rail at 60 or more
- [~] Album page: header, disc separators, More by; missing share, download, add missing, genre, average rating, popular star
- [~] Artist page: header, top songs, albums; missing release-type shelves, about, similar artists
- [~] Playlists: list and detail; missing new playlist, live lists, import, reorder, swipe to remove, More menu, keep downloaded
- [~] Favorites segments; missing swipe to unlike, sort
- [ ] Song, album, artist and playlist menus in full; multi-select

## Music on the phone

- [ ] The phone's own music (Files folders and the Music library) merged with the server's into one library

## Settings

- [ ] Every Android settings page (to be read from Android)

## Widgets and voice

- [~] Now playing widget (small, medium, large): cover, title, artist, play or pause, previous and next, fed by the app
- [~] Quick play widget: Liked songs, Recently added, Album mix, Resume
- [~] Siri: "Play Drake in Octo" (SiriKit media request, in the car too), and App Shortcuts for play, shuffle all, resume, liked songs, recently added, album mix and radio
- [~] Home Screen quick actions play Quick play's lists
