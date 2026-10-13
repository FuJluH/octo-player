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

// What getPlace asks: a postal code, or else a city's name and state, or
// else a position (the nearest place the server knows, within 30 km), with
// the ISO country code when known. Blank parts are left out, and a position
// goes to two decimals, about a kilometer.
internal fun placeParams(
    code: String?,
    name: String?,
    state: String?,
    country: String,
    latitude: Double? = null,
    longitude: Double? = null,
): Map<String, String> = buildMap {
    val postal = code?.trim().orEmpty()
    val city = name?.trim().orEmpty()
    when {
        postal.isNotEmpty() -> put("code", postal)
        city.isNotEmpty() -> {
            put("name", city)
            state?.trim()?.takeIf { it.isNotEmpty() }?.let { put("state", it) }
        }
        latitude != null && longitude != null -> {
            put("latitude", twoPlaces(latitude))
            put("longitude", twoPlaces(longitude))
        }
    }
    country.trim().uppercase().takeIf { it.isNotEmpty() }?.let { put("country", it) }
}

private fun twoPlaces(value: Double): String = (Math.round(value * 100) / 100.0).toString()
