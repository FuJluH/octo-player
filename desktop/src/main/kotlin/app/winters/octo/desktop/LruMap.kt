package app.winters.octo.desktop

import java.util.Collections

// A map that keeps the `most` entries used last and lets the rest go, for
// what is remembered a song or an album at a time over a run of days. Safe
// from any thread; walking its keys or values takes `synchronized(map)`.
fun <K, V> lruMap(most: Int): MutableMap<K, V> =
    Collections.synchronizedMap(
        object : LinkedHashMap<K, V>(16, 0.75f, true) {
            override fun removeEldestEntry(eldest: MutableMap.MutableEntry<K, V>?): Boolean = size > most
        },
    )
