package app.winters.octo.subsonic

import kotlinx.serialization.Serializable

// The OpenSubsonic extension an Octo server lists when it can find a place
// by its postal code or its name (getPlace), for finding live radio near a
// listener on a device with no location of its own.
const val OCTO_PLACES = "octoPlaces"

// A place the server knows: its postal code when asked by one, its name,
// state and ISO country code, and where it is, to two decimals.
@Serializable
data class Place(
    val code: String = "",
    val name: String = "",
    val state: String = "",
    val country: String = "",
    val latitude: Double = 0.0,
    val longitude: Double = 0.0,
)

// What getPlace asks: a postal code, or else a city's name and state, with
// the ISO country code either way. Blank parts are left out.
internal fun placeParams(code: String?, name: String?, state: String?, country: String): Map<String, String> = buildMap {
    val postal = code?.trim().orEmpty()
    if (postal.isNotEmpty()) {
        put("code", postal)
    } else {
        name?.trim()?.takeIf { it.isNotEmpty() }?.let { put("name", it) }
        state?.trim()?.takeIf { it.isNotEmpty() }?.let { put("state", it) }
    }
    put("country", country.trim().uppercase())
}
