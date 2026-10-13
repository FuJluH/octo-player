package app.winters.octo.desktop.ui

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

// Pages and parts moved onto the desktop's sizes take every size from the
// tokens in desktop-design (Space, ControlHeight, FrameSize and the rest),
// never a number of their own. Each phase adds the files it moves over.
class SizesTest {
    private val converted = listOf(
        "ui/Shell.kt",
        "ui/Sidebar.kt",
        "ui/Menus.kt",
        "ui/NowPlayingBar.kt",
        "ui/InfoPanel.kt",
        "ui/FrameParts.kt",
        "ui/Omnibox.kt",
        "ui/FilterBar.kt",
        "library/SongFilters.kt",
        "ui/SidePanels.kt",
        "pages/AlbumPage.kt",
        "pages/ArtistPage.kt",
        "pages/GenrePages.kt",
        "pages/FolderPages.kt",
        "pages/EntityParts.kt",
        "pages/HomePage.kt",
        "pages/ShelfPage.kt",
        "pages/HistoryPage.kt",
        "pages/LibraryHealthPage.kt",
        "pages/SettingsPage.kt",
        "pages/SettingsParts.kt",
        "pages/AboutRows.kt",
        "pages/SoundPage.kt",
        "pages/LiveListPage.kt",
        "ui/LiveListParts.kt",
        "livelists/LiveSongs.kt",
        "system/MiniPlayer.kt",
        "system/MoreSystemRows.kt",
        "hotkeys/ShortcutRows.kt",
        "ui/FrameFit.kt",
        "ui/PlaylistPictures.kt",
        "pages/ServersSection.kt",
        "ui/Opening.kt",
        "pages/LiveRadioPage.kt",
        "pages/RadioStationsSection.kt",
        "ui/LiveRadioParts.kt",
    )

    private val root = File("src/main/kotlin/app/winters/octo/desktop")

    // A size written as a number: 12.dp, 0.5.dp, 14.sp.
    private val literal = Regex("""\b\d+(\.\d+)?\.(dp|sp)\b""")

    @Test
    fun movedFilesUseOnlyTheTokens() {
        val found = converted.flatMap { name ->
            File(root, name).readLines().mapIndexedNotNull { i, line ->
                if (!line.trimStart().startsWith("//") && literal.containsMatchIn(line)) "$name:${i + 1}: ${line.trim()}" else null
            }
        }
        assertTrue("Sizes that should come from the tokens:\n" + found.joinToString("\n"), found.isEmpty())
    }
}
