package app.winters.octo.desktop.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.animation.core.tween
import androidx.compose.foundation.focusGroup
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.Stable
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import app.winters.octo.design.LocalFocusVisibility
import app.winters.octo.design.OctoDuration
import app.winters.octo.design.motionScale
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.BlurredEdgeTreatment
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.isBackPressed
import androidx.compose.ui.input.pointer.isForwardPressed
import androidx.compose.ui.input.pointer.onPointerEvent
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.dp
import app.winters.octo.design.Ambience
import app.winters.octo.design.ControlHeight
import app.winters.octo.design.FloatingGlaze
import app.winters.octo.design.FrameSize
import app.winters.octo.design.GlassField
import app.winters.octo.design.IconAction
import app.winters.octo.design.IconSize
import app.winters.octo.design.LocalPopups
import app.winters.octo.design.MenuFilm
import app.winters.octo.design.MenuFrost
import app.winters.octo.design.MenuShape
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoType
import app.winters.octo.design.PopupLayer
import app.winters.octo.design.Space
import app.winters.octo.design.TextAction
import app.winters.octo.design.Txt
import app.winters.octo.design.chromeFilm
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.setLibraryOnly
import app.winters.octo.discovery.LIBRARY_ONLY_SETTING
import app.winters.octo.desktop.NoticeAction
import app.winters.octo.desktop.actionFor
import app.winters.octo.desktop.library.Cover
import app.winters.octo.desktop.library.LocalCovers
import app.winters.octo.desktop.nav.Page
import app.winters.octo.desktop.pages.LiveRadioPage
import app.winters.octo.desktop.pages.AlbumPage
import app.winters.octo.desktop.pages.AlbumsPage
import app.winters.octo.desktop.pages.ArtistPage
import app.winters.octo.desktop.pages.ChartsPage
import app.winters.octo.desktop.pages.FamilyPage
import app.winters.octo.desktop.pages.ArtistsPage
import app.winters.octo.desktop.pages.FavouritesPage
import app.winters.octo.desktop.pages.FolderPage
import app.winters.octo.desktop.pages.FoldersPage
import app.winters.octo.desktop.pages.GenrePage
import app.winters.octo.desktop.pages.GenresPage
import app.winters.octo.desktop.pages.HistoryPage
import app.winters.octo.desktop.pages.ImportPage
import app.winters.octo.desktop.pages.LibraryHealthPage
import app.winters.octo.desktop.pages.LiveListPage
import app.winters.octo.desktop.pages.NewLiveListPage
import app.winters.octo.desktop.pages.HomePage
import app.winters.octo.desktop.pages.PlaylistPage
import app.winters.octo.desktop.pages.RecentlyAddedPage
import app.winters.octo.desktop.pages.ShelfPage
import app.winters.octo.desktop.pages.SearchPage
import app.winters.octo.desktop.pages.SettingsPage
import app.winters.octo.desktop.pages.SignInPage
import app.winters.octo.desktop.pages.SongsPage
import app.winters.octo.desktop.pages.SoundPage
import app.winters.octo.desktop.settings.AmbienceStyle
import app.winters.octo.desktop.search.omniPanelPlace
import app.winters.octo.desktop.search.railFieldPlace
import app.winters.octo.desktop.window.Frame
import app.winters.octo.desktop.window.MacLightsRoom
import app.winters.octo.desktop.window.ResizeEdges
import app.winters.octo.desktop.window.TitleBarHeight
import app.winters.octo.desktop.window.TitleStrip
import app.winters.octo.desktop.window.WindowButtons
import app.winters.octo.desktop.window.dragsWindow
import app.winters.octo.player.immersive.WashTuning
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeSource
import dev.chrisbanes.haze.rememberHazeState

// The whole window. Behind everything, the window's colours (the playing
// song's, blurred), which the frame frosts. Over them, one frame of dark
// glass: the title bar across the top, the sidebar down the left and the
// side panel down the right when open, meeting at hairlines. The page is
// the one open surface in the middle, with the player floating at its foot;
// the page's lists leave room for it at their end. The full player covers it all when open, with
// the title bar's buttons still over it. `frame` is null when the system
// draws the window's frame.
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun Shell(app: AppState, frame: Frame?, onClose: () -> Unit) {
    val backdrop = rememberHazeState()
    val pointer = remember { PointerSpot() }
    val drag = remember { DragState() }
    val focus = LocalFocusManager.current
    val connection = app.connection
    val key = rememberKeyColour(app)
    KeepAccent(app)
    val keyboard = LocalFocusVisibility.current
    val parts = remember { FrameFocus() }
    // What had the keyboard before a pop-up opened gets it back after: the
    // part it was in remembers the control, or failing that its first.
    SideEffect {
        app.popups.saveFocus = { parts.last?.let { runCatching { it.saveFocusedChild() } } }
        app.popups.returnFocus = {
            parts.last?.let { part -> if (!runCatching { part.restoreFocusedChild() }.getOrDefault(false)) runCatching { part.requestFocus() } }
        }
    }
    CompositionLocalProvider(
        LocalPopups provides app.popups,
        LocalPointer provides pointer,
        LocalCovers provides connection?.client,
        LocalKeyColour provides key,
        LocalDrag provides drag,
    ) {
        Box(
            Modifier
                .fillMaxSize()
                .background(OctoColors.Background)
                // Where the pointer is, for menus, and the mouse's back and
                // forward buttons, before anything else hears them.
                .onPointerEvent(PointerEventType.Move, PointerEventPass.Initial) { pointer.position = it.changes.first().position }
                .onPointerEvent(PointerEventType.Press, PointerEventPass.Initial) { event ->
                    pointer.position = event.changes.first().position
                    // A click: the mouse is in use, so focus rings rest.
                    keyboard.keyboard = false
                    // A click outside the search box closes its list.
                    if (app.omnibox.open && !app.omnibox.holds(pointer.point.x, pointer.point.y)) {
                        app.omnibox.open = false
                        focus.clearFocus()
                    }
                    if (event.buttons.isBackPressed) app.navigator.back()
                    if (event.buttons.isForwardPressed) app.navigator.forward()
                },
        ) {
            // The full player coming in and going out. Once all the way in it
            // covers the window's colours and the frame whole, so they are
            // neither drawn nor moved under it; they stay composed, and are
            // back the moment it starts to go.
            val player = remember { MutableTransitionState(false) }
            player.targetState = connection != null && app.fullPlayer
            val covered = player.isIdle && player.currentState
            val shown = LocalWindowShown.current && !covered
            CompositionLocalProvider(LocalWindowShown provides shown) {
                // The colours the glass frosts. Only these: the page is not under
                // glass, so scrolling never makes the frame blur again.
                Box(Modifier.fillMaxSize().drawnUnless(covered).hazeSource(backdrop)) { AmbientGlow(app) }
            }
            // Everything but the pop-ups, as one group the keyboard can come back to.
            Box(Modifier.fillMaxSize().focusRequester(parts.window).focusGroup()) {
                if (connection == null) {
                    // The sign-in card frosts the colours behind it.
                    Box(Modifier.fillMaxSize().padding(top = FrameSize.TitleBar)) { SignInPage(app, backdrop) }
                } else {
                    CompositionLocalProvider(LocalWindowShown provides shown) {
                        Box(Modifier.fillMaxSize().drawnUnless(covered)) { SignedInFrame(app, backdrop, parts) }
                    }
                    AnimatedVisibility(player, enter = fadeIn(motionFade()), exit = fadeOut(motionFade())) {
                        FullPlayer(app, Modifier.fillMaxSize().part(parts, parts.full, app), top = FrameSize.TitleBar)
                    }
                }
                if (connection != null && app.omnibox.open && !app.fullPlayer) OmniboxOver(app, backdrop)
                Box(Modifier.part(parts, parts.title, app)) { TitleBar(app, frame, onClose) }
            }
            PopupLayer(app.popups, backdrop)
            DragLabel(drag)
            if (frame != null) ResizeEdges(frame)
        }
    }
}

// The frame's parts, in the order Tab walks them, which is the order they
// are laid out in: the sidebar (search, places, playlists), the page, the
// side panel when open, the player floating at the page's foot, then the
// title bar, and round again. With the full player open only it and the
// title bar take turns; the frame under it is out of reach.
@Stable
internal class FrameFocus {
    val window = FocusRequester()
    val title = FocusRequester()
    val sidebar = FocusRequester()
    val page = FocusRequester()
    val panel = FocusRequester()
    val player = FocusRequester()
    val full = FocusRequester()

    // The part that last had the keyboard.
    var last: FocusRequester? = null

    fun order(app: AppState): List<FocusRequester> = when {
        app.fullPlayer -> listOf(title, full)
        app.sidePanel != null -> listOf(title, sidebar, page, panel, player)
        else -> listOf(title, sidebar, page, player)
    }
}

// Marks a part of the frame: which part last had the keyboard (so it can
// have it back after a pop-up), and, with the full player open, the frame's
// parts cannot be entered at all.
internal fun Modifier.part(parts: FrameFocus, me: FocusRequester, app: AppState): Modifier = this
    .onFocusChanged { if (it.hasFocus) parts.last = me }
    .focusRequester(me)
    .focusProperties { onEnter = { if (me !in parts.order(app)) cancelFocusChange() } }
    .focusGroup()

// Draws nothing while `hidden`, keeping what is inside composed and laid out.
private fun Modifier.drawnUnless(hidden: Boolean): Modifier = drawWithContent { if (!hidden) drawContent() }

// The full player's fade: brief, and briefer still with motion reduced.
@Composable
private fun motionFade() = tween<Float>(motionScale().ms(OctoDuration.Neutral))

// The frame and the page inside it.
@Composable
private fun SignedInFrame(app: AppState, backdrop: HazeState, parts: FrameFocus) {
    val settings by app.settings.state.collectAsState()
    val saved = settings.frame
    // Widths follow a drag at once, and are saved when it ends.
    var sidebar by remember { mutableStateOf(saved.sidebarWidth.dp) }
    var panelWidth by remember { mutableStateOf(saved.panelWidth.dp) }
    val shade = rememberPageShade(app)
    val panel = app.sidePanel
    LaunchedEffect(panel) {
        if (panel == null && app.panelHasKeyboard) {
            app.panelHasKeyboard = false
            runCatching { parts.page.requestFocus(FocusDirection.Enter) }
        }
    }
    // The window's width, which decides how the frame shares it (FrameFit.kt).
    val window = with(LocalDensity.current) { LocalWindowInfo.current.containerSize.width.toDp() }
    val fit = frameFit(
        window,
        sidebar.coerceIn(FrameSize.SidebarMin, FrameSize.SidebarMax),
        saved.sidebarRail,
        if (panel != null) panelWidth.coerceIn(FrameSize.PanelMin, FrameSize.PanelMax) else null,
    )
    // Under the full player the frame is out of a screen reader's reach too.
    Column(Modifier.fillMaxSize().then(if (app.fullPlayer) Modifier.clearAndSetSemantics { } else Modifier)) {
        // Room for the title bar, in the frame's glass; its buttons are drawn
        // over it, last, so they stay over the full player too.
        Box(Modifier.fillMaxWidth().height(FrameSize.TitleBar).chromeFilm(backdrop))
        Seam(vertical = false)
        Box(Modifier.weight(1f).fillMaxWidth()) {
            Row(Modifier.fillMaxSize()) {
                Box(Modifier.width(fit.sidebar).fillMaxHeight().part(parts, parts.sidebar, app)) {
                    Sidebar(app, backdrop, Modifier.fillMaxSize(), rail = fit.rail)
                    if (!fit.rail) {
                        ResizeHandle(
                            onDrag = { sidebar = (sidebar + it).coerceIn(FrameSize.SidebarMin, FrameSize.SidebarMax) },
                            onDone = { app.updateFrame { f -> f.copy(sidebarWidth = sidebar.value) } },
                            modifier = Modifier.align(Alignment.CenterEnd),
                        )
                    }
                }
                Seam(vertical = true)
                CompositionLocalProvider(LocalBottomRoom provides FrameSize.Player + FrameSize.PlayerGap, LocalFrameBackdrop provides backdrop) {
                    Box(Modifier.weight(1f).fillMaxHeight()) {
                        // The page is glass's backdrop too, over the window's colours, so
                        // the floating player (and menus over the page) frost what
                        // scrolls beneath them. Under the page's words lies a soft shade
                        // where a bright cover would wash out the quietest of them
                        // (PageShade.kt); the glass over the page frosts it with the rest.
                        Column(
                            Modifier
                                .fillMaxSize()
                                .clipToBounds()
                                .hazeSource(backdrop)
                                .pageShade(shade, FrameSize.TitleBar + FrameSize.Hairline)
                                .part(parts, parts.page, app),
                        ) {
                            app.notice?.let { Notice(it, app.noticeDetail, app.actionFor(it)) { app.notice = null; app.noticeDetail = null } }
                            Box(Modifier.weight(1f)) { PageHost(app) }
                        }
                    }
                }
                if (panel != null && fit.panel != null) {
                    Seam(vertical = true)
                    // Escape in the panel closes it; the page then has the keyboard.
                    Box(
                        Modifier
                            .width(fit.panel)
                            .fillMaxHeight()
                            .onFocusChanged { app.panelHasKeyboard = it.hasFocus }
                            .part(parts, parts.panel, app),
                    ) {
                        ContextPanel(app, panel, backdrop, Modifier.fillMaxSize())
                        ResizeHandle(
                            onDrag = { panelWidth = (panelWidth - it).coerceIn(FrameSize.PanelMin, FrameSize.PanelMax) },
                            onDone = { app.updateFrame { f -> f.copy(panelWidth = panelWidth.value) } },
                            modifier = Modifier.align(Alignment.CenterStart),
                        )
                    }
                }
            }
            // The player floats over the foot of the page, a third of the window
            // wide in its middle. It is laid out after the side panel, so Tab
            // comes to it last, after the panel.
            val start = fit.sidebar + FrameSize.Hairline
            val end = fit.panel?.let { it + FrameSize.Hairline } ?: Space.None
            Box(Modifier.fillMaxSize().padding(start = start, end = end)) {
                val width = playerWidth(fit.page, window)
                PlayerBar(app, backdrop, Modifier.align(Alignment.BottomCenter).padding(bottom = FrameSize.PlayerGap).width(width).height(FrameSize.Player).part(parts, parts.player, app), compact = playerIsCompact(width))
                // Songs on their way: a small pill at the page's foot, level
                // with the player where there is room beside it, else just
                // above it, so it never covers the player.
                val beside = (fit.page - width) / 2 >= DownloadsPillRoom
                val pillBottom = if (beside) FrameSize.PlayerGap + (FrameSize.Player - DownloadsPillHeight) / 2 else FrameSize.PlayerGap + FrameSize.Player + Space.M
                DownloadsPill(app, backdrop, Modifier.align(Alignment.BottomEnd).padding(end = Space.Page, bottom = pillBottom))
            }
        }
    }
}

// What the open search box lays over the page: its list, under the field
// and lined up with its start, reaching over the page as far as the window
// allows. With the sidebar folded to a rail, the field floats beside the
// rail's search button too.
@Composable
private fun OmniboxOver(app: AppState, backdrop: HazeState) {
    val box = app.omnibox
    val density = LocalDensity.current
    val window = LocalWindowInfo.current.containerSize.width
    // The rail's search button marks where it is while the rail shows.
    if (box.trigger != IntRect.Zero) {
        val gap = with(density) { Space.M.roundToPx() }
        val inset = with(density) { Space.Xs.roundToPx() }
        FloatingGlaze(
            backdrop,
            Modifier
                .offset { railFieldPlace(box.trigger, gap).let { IntOffset(it.x, it.y - inset) } }
                .width(FrameSize.SearchWidth),
            shape = MenuShape,
            film = MenuFilm,
            frost = MenuFrost,
            halo = true,
        ) {
            OmniField(app, Modifier.fillMaxWidth().padding(Space.Xs))
        }
        // The field is new each time it floats in, so the keyboard goes to it here.
        LaunchedEffect(Unit) { runCatching { app.searchFocus.requestFocus() } }
    }
    val place = with(density) { omniPanelPlace(box.field, FrameSize.OmniWidth.roundToPx(), window, Space.S.roundToPx(), Space.M.roundToPx()) }
    OmniPanel(
        app,
        backdrop,
        Modifier
            .offset { IntOffset(place.left, place.top) }
            .width(with(density) { place.width.toDp() })
            .onGloballyPositioned { box.panel = it.windowRect() },
    )
}

// The strip along the top: back and forward, room to drag the window by,
// and the window's buttons when the app draws its frame. It paints nothing
// itself; the frame's glass is under it.
@Composable
private fun TitleBar(app: AppState, frame: Frame?, onClose: () -> Unit) {
    // Over the full player, its ink, so they read on a light loop too.
    val ink = app.playerInk.takeIf { app.fullPlayer }
    TitleStrip {
        if (app.mac) Spacer(Modifier.width(MacLightsRoom)) else Spacer(Modifier.width(Space.M))
        if (app.connection != null) {
            IconAction(OctoIcons.Back, "Back", { app.navigator.back() }, size = ControlHeight.S, iconSize = IconSize.Toolbar, enabled = app.navigator.canGoBack, tint = ink ?: Color.White)
            IconAction(OctoIcons.Forward, "Forward", { app.navigator.forward() }, size = ControlHeight.S, iconSize = IconSize.Toolbar, enabled = app.navigator.canGoForward, tint = ink ?: Color.White)
            val settings by app.settings.state.collectAsState()
            IconAction(
                OctoIcons.Library,
                LIBRARY_ONLY_SETTING,
                { app.setLibraryOnly(!settings.libraryOnly) },
                size = ControlHeight.S,
                iconSize = IconSize.Toolbar,
                active = settings.libraryOnly,
                tint = ink ?: Color.White,
                toggled = settings.libraryOnly,
            )
        }
        Box(Modifier.weight(1f).fillMaxHeight().then(if (frame != null) Modifier.dragsWindow(frame) else Modifier))
        if (frame != null) WindowButtons(frame, onClose, ink)
    }
}

// A single quiet line above the page, closed with its cross. When there
// is more to say (the engine's own words for a failure), Details shows it;
// an `action` (Undo after a queue edit) sits beside the words.
@Composable
private fun Notice(text: String, detail: String?, action: NoticeAction?, onClose: () -> Unit) {
    var open by remember(text) { mutableStateOf(false) }
    // A screen reader that follows live regions reads a new notice out.
    Column(Modifier.fillMaxWidth().padding(start = PageSide, end = PageSide, top = Space.M).semantics { liveRegion = LiveRegionMode.Polite }) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.M)) {
            Txt(text, OctoType.bodySmall, OctoColors.TextSecondary, Modifier.weight(1f), maxLines = 2)
            if (action != null) TextAction(action.label, action.run)
            if (detail != null) TextAction(if (open) "Hide details" else "Details", { open = !open })
            IconAction(OctoIcons.Close, "Dismiss this notice", onClose, size = ControlHeight.S, iconSize = IconSize.Inline, tint = OctoColors.TextSecondary)
        }
        if (open && detail != null) Txt(detail, OctoType.caption, OctoColors.TextMuted, maxLines = 4)
    }
}

// The page for where the listener is. Each visit is its own composition, so
// its scroll spot is its own.
@Composable
private fun PageHost(app: AppState) {
    val visit = app.navigator.current
    key(visit.id) {
        when (val page = visit.page) {
            Page.Home -> HomePage(app, visit)
            Page.Search -> SearchPage(app, visit)
            Page.Songs -> SongsPage(app, visit)
            Page.Albums -> AlbumsPage(app, visit)
            Page.Artists -> ArtistsPage(app, visit)
            Page.Genres -> GenresPage(app, visit)
            Page.Folders -> FoldersPage(app, visit)
            Page.Favourites -> FavouritesPage(app, visit)
            Page.History -> HistoryPage(app, visit)
            Page.RecentlyAdded -> RecentlyAddedPage(app, visit)
            Page.LibraryHealth -> LibraryHealthPage(app, visit)
            Page.Imports -> ImportPage(app, visit)
            Page.Charts -> ChartsPage(app, visit)
            Page.Family -> FamilyPage(app, visit)
            Page.LiveRadio -> LiveRadioPage(app, visit)
            Page.Settings -> SettingsPage(app, visit)
            Page.Sound -> SoundPage(app, visit)
            is Page.Album -> AlbumPage(app, visit, page.id)
            is Page.Artist -> ArtistPage(app, visit, page.id, page.name)
            is Page.Genre -> GenrePage(app, visit, page.name)
            is Page.Folder -> FolderPage(app, visit, page.id, page.name)
            is Page.Playlist -> PlaylistPage(app, visit, page.id)
            is Page.Shelf -> ShelfPage(app, visit, page.shelf)
            is Page.LiveList -> LiveListPage(app, visit, page.id, page.editing)
            is Page.NewLiveList -> NewLiveListPage(app, visit, page)
        }
    }
}

// The key colour: the main colour of the playing song's cover, or Octo's
// own while nothing with a cover plays.
@Composable
private fun rememberKeyColour(app: AppState): Color {
    val state by app.player.state.collectAsState()
    val settings by app.settings.state.collectAsState()
    val coverId = state.current?.song?.coverArt
    val connection = app.connection
    val wash = settings.appearance.wash
    val tuning = WashTuning(wash.contrast, wash.saturation / 100f, wash.brightnessCap / 100f)
    val key by produceState(OctoKey, coverId, connection, tuning) {
        if (coverId == null || connection == null) value = OctoKey
        else app.washCovers.follow(connection.client, coverId, tuning).collect { value = it.keyColour() }
    }
    return key
}

// The window's colours, behind everything. The glow: a soft wash of the
// playing song's colours across the top of the window, its cover blurred
// far past recognition and kept faint. Garnish, and off when the listener
// turns it off. With no cover to show, Octo's own colours stand in, still
// and very dim, so the glass has something behind it. Before signing in
// they move, behind the sign-in card. Immersive instead lays the full
// player's moving wash behind the whole window.
@Composable
private fun BoxScope.AmbientGlow(app: AppState) {
    val settings by app.settings.state.collectAsState()
    val look = settings.appearance
    val state by app.player.state.collectAsState()
    val cover = state.current?.song?.coverArt
    if (app.connection == null) {
        OctoAmbience(app, moving = true, veil = 0.2f)
        return
    }
    if (!look.ambientGlow) return
    if (look.ambience == AmbienceStyle.Immersive) {
        ImmersiveAmbience(app)
        return
    }
    if (cover == null) {
        OctoAmbience(app, moving = false, veil = 1f - quietOpacity(look.glowStrength))
        return
    }
    CoverGlow(look.glowStrength) { blurred -> Cover(cover, blurred, shape = RectangleShape) }
}

// The glow itself: `picture` draws the cover into the blurred modifier it
// is given, faint and fading into the page below.
@Composable
internal fun CoverGlow(strength: Float, picture: @Composable (Modifier) -> Unit) {
    Box(
        Modifier
            .fillMaxWidth()
            .height(Ambience.Height)
            .alpha(glowOpacity(strength)),
    ) {
        picture(Modifier.fillMaxSize().blur(Ambience.Blur, BlurredEdgeTreatment.Unbounded))
        // Fades into the page below, so there is no edge.
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Transparent, OctoColors.Background))))
    }
}
