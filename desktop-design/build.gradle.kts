// The desktop app's design system: the same tokens, glass and icons as the
// phone app, for Compose on the desktop JVM.
//
// The Android design module stays an Android library, untouched. Its files
// that use nothing but Compose and Haze (the tokens for colour, motion
// and shape, the glaze and the other materials, panels, the artwork rim,
// and the controls: buttons, chrome buttons and groups, the switch,
// segmented tabs, sliders, the scrubber, tooltips) are compiled here as
// they are, from the same source files, so the two apps cannot drift
// apart. The icons are the same Phosphor vector files, read
// into ImageVectors at run time. What only makes sense on a desktop
// (menus at the pointer, hover, the slider, text fields) lives in this
// module's own sources.
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.compose.compiler)
    alias(libs.plugins.compose.multiplatform)
}

kotlin { jvmToolchain(17) }

// The Android design files that compile unchanged on the desktop. A file
// added here must not import anything from Android; the build fails loudly
// if one does. OctoType.kt is not among them: the desktop keeps the same
// type names at its own sizes, in DesktopMetrics.kt.
val sharedDesignFiles = listOf(
    "AccentButton.kt",
    "AccentSwatches.kt",
    "Artwork.kt",
    "Blur.kt",
    "Buttons.kt",
    "ChromeButtons.kt",
    "ExplicitMark.kt",
    "GlassPanel.kt",
    "Glaze.kt",
    "GlazeButton.kt",
    "GlazedIconButton.kt",
    "GlazeInset.kt",
    "GlazeTabs.kt",
    "GlowIcon.kt",
    "Glyphs.kt",
    "IconAccents.kt",
    "Materials.kt",
    "NowPlayingBars.kt",
    "OctoColors.kt",
    "OctoMotion.kt",
    "OctoSwitch.kt",
    "OctoTokens.kt",
    "PlaylistArt.kt",
    "Scrubber.kt",
    "Sliders.kt",
    "Spinner.kt",
    "Tooltip.kt",
)

val shareDesign by tasks.registering(Sync::class) {
    from(rootProject.file("design/src/main/java/app/winters/octo/design")) { include(sharedDesignFiles) }
    into(layout.buildDirectory.dir("generated/sharedDesign/kotlin"))
}

// The phone app's icon vectors (Phosphor Icons), packaged as resources
// under octo-icons/ with their licence.
val shareIcons by tasks.registering(Sync::class) {
    from(rootProject.file("design/src/main/res/drawable")) {
        include("sym_*.xml")
        into("octo-icons")
    }
    from(rootProject.file("design/licenses")) {
        include("Phosphor-MIT.txt")
        into("octo-icons")
    }
    into(layout.buildDirectory.dir("generated/sharedDesign/resources"))
}

// The fonts playlist covers are set in (Inter Display, OFL) and the one
// codes are set in (JetBrains Mono, OFL), from the phone's font resources,
// packaged under octo-fonts/ with their licences.
val shareFonts by tasks.registering(Sync::class) {
    from(rootProject.file("design/src/main/res/font")) {
        include("*.ttf")
        into("octo-fonts")
    }
    from(rootProject.file("design/licenses")) { into("octo-fonts") }
    into(layout.buildDirectory.dir("generated/sharedFonts/resources"))
}

sourceSets.main {
    kotlin.srcDir(shareDesign)
    resources.srcDir(shareIcons)
    resources.srcDir(shareFonts)
}

dependencies {
    api(compose.desktop.common)
    api(libs.haze)
    api(libs.haze.blur)
    // The playlist covers' design, which PlaylistArt.kt paints.
    implementation(project(":shared:core"))
    testImplementation(libs.junit)
}
