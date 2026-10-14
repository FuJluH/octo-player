package app.winters.octo.lyrics

import android.content.Context
import androidx.datastore.preferences.core.MutablePreferences
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

// The look itself (LyricsLook, LookDial, LyricsStyle) lives in shared core.

private val STYLE = stringPreferencesKey("lyrics_style")
private val KEEP_COMPLETED = booleanPreferencesKey("lyrics_keep_completed")
private val ARC = booleanPreferencesKey("lyrics_arc")
private val BLOOM_FAST = booleanPreferencesKey("lyrics_bloom_fast")

private fun LookDial.preference(): Preferences.Key<Int> = intPreferencesKey(key)

// The look of the lyrics, saved beside their timing.
@Singleton
class LyricsLookSettings @Inject constructor(@ApplicationContext private val context: Context) {
    val look: Flow<LyricsLook> = context.lyricsData.data.map { stored ->
        LookDial.entries.fold(
            LyricsLook(
                style = LyricsStyle.entries.firstOrNull { it.name == stored[STYLE] } ?: LyricsStyle.Flowing,
                keepCompleted = stored[KEEP_COMPLETED] ?: true,
                arc = stored[ARC] ?: false,
                bloomFast = stored[BLOOM_FAST] ?: true,
            ),
        ) { look, dial -> look.with(dial, stored[dial.preference()] ?: dial.default) }
    }.distinctUntilChanged()

    suspend fun setStyle(style: LyricsStyle) {
        context.lyricsData.edit { it[STYLE] = style.name }
    }

    suspend fun setDial(dial: LookDial, percent: Int) {
        context.lyricsData.edit { it[dial.preference()] = percent.coerceIn(dial.range) }
    }

    suspend fun setKeepCompleted(on: Boolean) {
        context.lyricsData.edit { it[KEEP_COMPLETED] = on }
    }

    suspend fun setArc(on: Boolean) {
        context.lyricsData.edit { it[ARC] = on }
    }

    suspend fun setBloomFast(on: Boolean) {
        context.lyricsData.edit { it[BLOOM_FAST] = on }
    }

    suspend fun current(): LyricsLook = look.first()

    // Puts the whole look back, from a backup.
    suspend fun restore(look: LyricsLook) {
        context.lyricsData.edit { prefs -> write(prefs, look) }
    }

    private fun write(prefs: MutablePreferences, look: LyricsLook) {
        prefs[STYLE] = look.style.name
        prefs[KEEP_COMPLETED] = look.keepCompleted
        prefs[ARC] = look.arc
        prefs[BLOOM_FAST] = look.bloomFast
        LookDial.entries.forEach { prefs[it.preference()] = look.percent(it).coerceIn(it.range) }
    }
}
