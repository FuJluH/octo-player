plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.compose.compiler)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.hilt)
    alias(libs.plugins.ksp)
}

android {
    namespace = "app.winters.octo"
    compileSdk = 37

    defaultConfig {
        applicationId = "app.winters.octo"
        minSdk = 29
        targetSdk = 36
        // A test build passes its number (-PoctoBuild=N), so each one it
        // installs counts as newer than the last and reads as 0.2.0.N.
        // A release (the android-v<version> tag's workflow) also passes its
        // version, -PoctoAndroidVersion=1.2.0 or 1.3.0-beta.1, which the app shows
        // and compares with newer releases; the commit count stays the
        // version code, so every build counts up.
        val testBuild = (project.findProperty("octoBuild") as String?)?.toIntOrNull()
        val release = (project.findProperty("octoAndroidVersion") as String?)?.takeIf(String::isNotBlank)?.trim()
        if (release != null) {
            require(Regex("""(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?""").matches(release)) { "octoAndroidVersion must look like 1.2.0 or 1.3.0-beta.1, not $release" }
            requireNotNull(testBuild) { "A release needs -PoctoBuild=<commit count> for its version code" }
        }
        versionCode = testBuild ?: 2
        versionName = release ?: if (testBuild != null) "0.2.0.$testBuild" else "0.2.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // Trying the updater from a debug build: -Pocto.updates.force=true,
        // and -Pocto.updates.api=<address> for a pretend GitHub.
        buildConfigField("boolean", "UPDATES_FORCED", (project.findProperty("octo.updates.force") == "true").toString())
        buildConfigField("String", "UPDATES_API", "\"${(project.findProperty("octo.updates.api") as String?).orEmpty()}\"")
    }

    // The release key, only where the release workflow provides it (from
    // the repository's secrets): the keystore file and its passwords. Every
    // release must be signed with this same key, or phones refuse the
    // update; without it the release build is left unsigned.
    val releaseKeystore = providers.environmentVariable("OCTO_ANDROID_KEYSTORE").orNull
    signingConfigs {
        if (releaseKeystore != null) {
            create("release") {
                storeFile = file(releaseKeystore)
                storePassword = providers.environmentVariable("OCTO_ANDROID_KEYSTORE_PASSWORD").orNull
                keyAlias = providers.environmentVariable("OCTO_ANDROID_KEY_ALIAS").orNull
                keyPassword = providers.environmentVariable("OCTO_ANDROID_KEY_PASSWORD").orNull
            }
        }
    }

    buildTypes {
        // Debug installs beside the release build instead of over it.
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.findByName("release")
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

// Room writes each database version's schema here, so migrations can be checked.
ksp {
    arg("room.schemaLocation", "$projectDir/schemas")
}

dependencies {
    implementation(project(":design"))
    implementation(project(":subsonic"))
    implementation(project(":shared:core"))
    implementation(platform(libs.compose.bom))
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.viewmodel.navigation3)
    implementation(libs.androidx.navigation3.runtime)
    implementation(libs.androidx.navigation3.ui)
    implementation(libs.androidx.datastore.preferences)
    // Checking family requests now and then, even while the app is closed.
    implementation(libs.androidx.work.runtime)
    // The camera, for scanning a family QR code on the join screen. CameraX
    // is part of Android's own libraries (no Google Play services); the code
    // is read by ZXing, through the shared core.
    implementation(libs.androidx.camera.core)
    implementation(libs.androidx.camera.camera2)
    implementation(libs.androidx.camera.lifecycle)
    implementation(libs.androidx.camera.view)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.hilt.android)
    implementation(libs.hilt.lifecycle.viewmodel.compose)
    ksp(libs.hilt.compiler)
    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)
    ksp(libs.androidx.room.compiler)
    implementation(libs.taglib)
    implementation(libs.androidx.palette)
    implementation(libs.reorderable)
    implementation(libs.media3.exoplayer)
    // Live radio stations that stream as HLS.
    implementation(libs.media3.exoplayer.hls)
    implementation(libs.media3.session)
    implementation(libs.media3.datasource.okhttp)
    implementation(libs.media3.ui.compose)
    implementation(libs.media3.inspector)
    // Casting: Android's list of outputs, and Google Cast (kept to the cast package).
    implementation(libs.androidx.mediarouter)
    implementation(libs.play.services.cast.framework)
    implementation(libs.kotlinx.coroutines.guava)
    implementation(libs.okhttp)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.coil.compose)
    implementation(libs.coil.network.okhttp)
    debugImplementation(libs.compose.ui.tooling)
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.mockwebserver)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.junit)
    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation(libs.compose.ui.test.junit4)
    androidTestImplementation(libs.mockwebserver)
    debugImplementation(libs.compose.ui.test.manifest)
}
