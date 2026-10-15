package app.winters.octo.design

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.FontHinting
import androidx.compose.ui.text.FontRasterizationSettings
import androidx.compose.ui.text.FontSmoothing
import androidx.compose.ui.text.PlatformParagraphStyle
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// The desktop's sizes, in one place, so every page and piece of the frame
// takes them from here rather than choosing its own. Colours and motion
// stay in the shared tokens; these are what a mouse and a big screen need.

// Gaps, from the tightest to the widest.
object Space {
    val None = 0.dp
    val Xxs = 2.dp
    val Xs = 4.dp
    val S = 6.dp
    val M = 8.dp
    val L = 12.dp
    val Xl = 16.dp
    val Xxl = 20.dp
    val Page = 24.dp
    val Section = 32.dp
    val Wide = 40.dp
}

// How tall controls are: small buttons, fields, the default toolbar
// control, and the largest.
object ControlHeight {
    val Xs = 24.dp
    val S = 28.dp
    val M = 32.dp
    val L = 36.dp
}

// How tall a row in a list is, by density. Roomy adds the cover.
object RowHeight {
    val Compact = 34.dp
    val Regular = 44.dp
    val Roomy = 56.dp
    val Nav = 36.dp
}

// Icon sizes: beside words, in a table, in a toolbar, in the transport.
object IconSize {
    val Inline = 14.dp
    val Table = 16.dp
    val Toolbar = 18.dp
    val Transport = 20.dp
}

// The keyboard's mark: the ring round what has the keyboard, a hairline of
// dark just inside it so it still shows on a light cover, and the least a
// thing to click may measure, whatever its glyph.
object Focus {
    val Ring = 2.dp
    val Edge = 1.dp
    val MinTarget = 24.dp
}

// One corner per role.
object Corner {
    val Row = 6.dp
    val Control = 8.dp
    val Panel = 10.dp
    val ArtS = 4.dp
    val ArtM = 6.dp
    val ArtL = 10.dp

    val RowShape = RoundedCornerShape(Row)
    val ControlShape = RoundedCornerShape(Control)
    val PanelShape = RoundedCornerShape(Panel)
    val ArtSShape = RoundedCornerShape(ArtS)
    val ArtMShape = RoundedCornerShape(ArtM)
    val ArtLShape = RoundedCornerShape(ArtL)
}

// The frame around the page: title bar, sidebar, side panel and player.
object FrameSize {
    val TitleBar = 40.dp
    val Hairline = 1.dp
    val Sidebar = 240.dp
    val SidebarMin = 200.dp
    val SidebarMax = 320.dp
    val SidebarRail = 64.dp
    val Panel = 328.dp
    val PanelMin = 280.dp
    val PanelMax = 480.dp
    val Player = 80.dp
    val PlayerCover = 56.dp
    // The floating player: a third of the window wide, but never narrower
    // than its controls need; its cover; and the gap around it.
    val PlayerMin = 640.dp
    val PlayerThumb = 56.dp
    val PlayerGap = 16.dp
    // The narrowest the page may be: a narrow window with the side panel
    // open folds the sidebar to its rail, then narrows the panel, to keep it.
    val PageMin = 560.dp
    // A wide card on a page, at most, so its buttons stay near its words.
    val CardMax = 640.dp
    val PlayButton = 36.dp
    val PlayButtonLarge = 44.dp
    // Play's target in the player bar and the mini player: the sign alone, a
    // touch bigger than the controls' targets beside it.
    val PlayTarget = 40.dp
    // A menu opened from a button.
    val Menu = 280.dp
    // A short text field beside a setting, such as a Discord status line.
    val SettingField = 260.dp
    val PlaylistCover = 32.dp
    // Octo's octopus on the window while the app behind it gets ready.
    val OpeningMark = 112.dp
    // The small dot beside Settings while an update waits to be installed.
    val NavMark = 6.dp
    // A playlist's picture in a menu's line.
    val MenuArt = 20.dp
    // The search field floated out beside the rail.
    val SearchWidth = 360.dp
    // The search box's list: its width, how tall it may grow, a line, and
    // a line's picture.
    val OmniWidth = 640.dp
    val OmniHeight = 580.dp
    val OmniLine = 50.dp
    val OmniArt = 36.dp
    // A song list's filter field.
    val FilterWidth = 260.dp
}

// How the desktop's words are drawn, set once at start before any text
// style is first read. `colour`: smoothed in colour (subpixel), as the
// system's own text is where it uses ClearType, set together with the
// windows' pixel layout (a surface that does not know its pixels' layout
// draws such text grey). `family`: the face, or null for the system's own
// interface face (Segoe UI on Windows).
object TextLook {
    @Volatile var colour: Boolean = false
    @Volatile var family: FontFamily? = null
}

// How the desktop draws text: glyphs fitted to the pixel grid and placed
// between pixels so words keep their spacing, smoothed in colour where the
// system smooths its own text that way (TextLook), else grey. Text over
// see-through glass, drawn into a layer of its own, stays grey either way.
// Fitting to the grid is what makes small text crisp; turned off, it blurs.
@OptIn(ExperimentalTextApi::class)
val TextDrawing: FontRasterizationSettings by lazy {
    FontRasterizationSettings(
        smoothing = if (TextLook.colour) FontSmoothing.SubpixelAntiAlias else FontSmoothing.AntiAlias,
        hinting = FontHinting.Normal,
        subpixelPositioning = true,
        autoHintingForced = false,
    )
}

// Every desktop text style starts here, so all of it is drawn the same way.
@OptIn(ExperimentalTextApi::class)
private val DesktopText = TextStyle(fontFamily = TextLook.family, platformStyle = PlatformTextStyle(null, PlatformParagraphStyle(TextDrawing)))

// Type on the desktop: denser than the phone's, with page titles that
// orient rather than announce. Whole pixel sizes, which the grid fitting
// draws cleanest.
object DesktopType {
    val label = DesktopText.copy(fontSize = 12.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.6.sp)
    val meta = DesktopText.copy(fontSize = 13.sp, fontWeight = FontWeight.Normal)
    val table = DesktopText.copy(fontSize = 14.sp, fontWeight = FontWeight.Normal)
    val tableTitle = DesktopText.copy(fontSize = 14.sp, fontWeight = FontWeight.Medium)
    val body = DesktopText.copy(fontSize = 15.sp, fontWeight = FontWeight.Normal)
    val emphasis = DesktopText.copy(fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
    val section = DesktopText.copy(fontSize = 17.sp, fontWeight = FontWeight.Bold)
    val pageTitle = DesktopText.copy(fontSize = 24.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.2).sp)
}

// The phone's type names, at the desktop's sizes. The shared controls and
// the pages that name these read them here, so every word on the desktop
// is drawn the same way and a step up from the phone's small print.
object OctoType {
    val display = DesktopText.copy(fontSize = 34.sp, fontWeight = FontWeight.Black, letterSpacing = (-0.5).sp)
    val title = DesktopText.copy(fontSize = 26.sp, fontWeight = FontWeight.Black)
    val headline = DesktopText.copy(fontSize = 21.sp, fontWeight = FontWeight.Bold)
    val section = DesktopText.copy(fontSize = 19.sp, fontWeight = FontWeight.Bold)
    val body = DesktopText.copy(fontSize = 17.sp, fontWeight = FontWeight.Medium)
    val bodySmall = DesktopType.body
    val caption = DesktopType.meta
    val label = DesktopText.copy(fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
}

// The window's colours: the playing song's cover, blurred far past
// recognition, across the top of the window.
object Ambience {
    val Height = 520.dp
    val Blur = 110.dp
}

// The Settings and Sound pages: the list of sections beside the page, the
// widest the settings run, the narrowest they may be before that list is
// left out, a slider's line and the reading beside it, and the equalizer's
// plot without its labels.
object SettingsSize {
    val Nav = 200.dp
    val Column = 720.dp
    val ColumnMin = 520.dp
    val Slider = 200.dp
    val Reading = 60.dp
    val EqPlot = 160.dp
    // The small drawing of a crossfade curve in its menu, and its lines.
    val CurvePreviewWidth = 28.dp
    val CurvePreviewHeight = 16.dp
    val CurveLine = 1.5.dp
    // The tile behind a section's icon at the top of its page.
    val SectionIcon = 36.dp

    // A small form over Settings: adding a server, a new password, and how
    // tall it grows before it scrolls.
    val Sheet = 460.dp
    val SheetMax = 720.dp
}
