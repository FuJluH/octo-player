package app.winters.octo.whatsnew

import android.content.Context
import android.content.pm.PackageManager
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import app.winters.octo.BuildConfig
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

// The one line the card on Home shows. Kept short.
const val WhatsNewSummary = "Arrange Home your way, a new icon and a smoother player"

// What this update brings, part by part, as markdown in the app's assets.
// Rewrite it with each update.
const val WHATS_NEW_FILE = "whats_new.md"

// Whether the card about what is new should show: once after each update,
// but not on a fresh install, which has nothing to compare with.
fun whatsNewDue(lastSeen: Int?, current: Int, freshInstall: Boolean): Boolean =
    if (lastSeen == null) !freshInstall else lastSeen < current

private val Context.whatsNewData by preferencesDataStore("whats_new")

private val LAST_SEEN = intPreferencesKey("last_seen_version")

// Remembers which version's news was last put away.
@Singleton
class WhatsNewStore @Inject constructor(@ApplicationContext private val context: Context) {
    val due: Flow<Boolean> = context.whatsNewData.data.map { whatsNewDue(it[LAST_SEEN], BuildConfig.VERSION_CODE, freshInstall()) }

    // A fresh install starts having seen this version, so later updates
    // know where they stand.
    suspend fun settle() {
        val seen = context.whatsNewData.data.first()[LAST_SEEN]
        if (seen == null && freshInstall()) markSeen()
    }

    suspend fun markSeen() {
        context.whatsNewData.edit { it[LAST_SEEN] = BuildConfig.VERSION_CODE }
    }

    // Installed and never updated since.
    private fun freshInstall(): Boolean = try {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        info.firstInstallTime == info.lastUpdateTime
    } catch (e: PackageManager.NameNotFoundException) {
        true
    }
}
