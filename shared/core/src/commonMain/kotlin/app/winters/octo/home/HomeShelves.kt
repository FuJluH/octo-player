package app.winters.octo.home

import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.Json
import java.io.File
import java.security.MessageDigest

// Home's server shelves (its stations, Made for you lists and chart) as
// each server last gave them, one file per server in `folder`, so Home can
// show them at once at start and on switching back, before the server
// answers. `server` is the key of the kept server; a blank one keeps
// nothing. A file that is missing or cannot be read counts as none.
class HomeShelfStore<T : Any>(private val folder: File, private val serializer: KSerializer<T>) {
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = false
    }

    fun read(server: String): T? {
        val file = fileFor(server) ?: return null
        return runCatching { if (file.isFile) json.decodeFromString(serializer, file.readText()) else null }.getOrNull()
    }

    // Written beside the old file first, so a reader never sees half of one.
    // A write that fails leaves the last one in place.
    @Synchronized
    fun write(server: String, shelves: T) {
        val file = fileFor(server) ?: return
        runCatching {
            folder.mkdirs()
            val next = File(folder, file.name + ".tmp")
            next.writeText(json.encodeToString(serializer, shelves))
            if (!next.renameTo(file)) {
                file.delete()
                next.renameTo(file)
            }
        }
    }

    // The server's key is hashed for the file name, so no name or address
    // shows in it and any key makes a valid one.
    private fun fileFor(server: String): File? =
        server.takeIf { it.isNotBlank() }?.let { File(folder, "${hash(it)}.json") }

    private fun hash(text: String): String =
        MessageDigest.getInstance("SHA-256").digest(text.toByteArray())
            .joinToString("") { ((it.toInt() and 0xff) + 0x100).toString(16).substring(1) }
}

// What a shelf shows once the server answers: what it already shows when
// the answer is equal (the same items in the same order), so nothing on
// screen changes or moves; otherwise the answer.
fun <T> answered(shown: T, answer: T): T = if (shown == answer) shown else answer
