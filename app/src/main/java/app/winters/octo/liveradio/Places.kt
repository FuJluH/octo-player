package app.winters.octo.liveradio

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Address
import android.location.Geocoder
import android.location.Location
import android.location.LocationManager
import android.media.MediaCodecList
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.CancellationSignal
import android.os.SystemClock
import androidx.core.content.ContextCompat
import androidx.core.location.LocationManagerCompat
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume

// What looking for a place gave.
sealed interface PlaceAnswer {
    data class Found(val place: LivePlace) : PlaceAnswer

    // The phone gave no position: its location is off or it found none.
    data object NoFix : PlaceAnswer

    // Nothing by that name or code.
    data object NotFound : PlaceAnswer

    // The phone has no service for looking up places by name.
    data object NoLookup : PlaceAnswer
}

// How long one position, or one lookup, is waited for.
private const val FIX_WAIT_MS = 15_000L
private const val LOOKUP_WAIT_MS = 15_000L

// A position from the last ten minutes is as good as a new one for this.
private const val FRESH_FIX_MS = 10 * 60 * 1000L

// Finds places for Live radio near you: the phone's rough position, and
// places named by a ZIP or postal code or a town. A position is rounded to
// about a kilometer as soon as it is read, before anything else sees it.
@Singleton
class Places @Inject constructor(@ApplicationContext private val context: Context) {
    private val locations = context.getSystemService(LocationManager::class.java)
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)

    // The catalog files states and countries under their English names.
    private val geocoder: Geocoder? by lazy { if (Geocoder.isPresent()) Geocoder(context, Locale.ENGLISH) else null }

    fun allowed(): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    fun online(): Boolean {
        val network = connectivity?.activeNetwork ?: return false
        return connectivity.getNetworkCapabilities(network)?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
    }

    // The country the phone's language is set for, like "US".
    fun localeCountry(): String = Locale.getDefault().country.uppercase()

    // The audio decoders this phone has, by type.
    val decoders: Set<String> by lazy {
        runCatching {
            MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos.filterNot { it.isEncoder }.flatMap { it.supportedTypes.asList() }.mapTo(HashSet()) { it.lowercase() }
        }.getOrDefault(emptySet())
    }

    // Where the phone is, roughly, named by its town and state when the
    // phone can look them up.
    suspend fun here(): PlaceAnswer {
        if (!allowed()) return PlaceAnswer.NoFix
        val fix = fix() ?: return PlaceAnswer.NoFix
        val latitude = rounded(fix.latitude)
        val longitude = rounded(fix.longitude)
        val address = geocoder?.let { reverse(it, latitude, longitude) }
        return PlaceAnswer.Found(
            LivePlace(
                latitude = latitude,
                longitude = longitude,
                label = placeLabel(address?.locality ?: address?.subAdminArea, address?.adminArea, "Your location"),
                state = address?.adminArea.orEmpty(),
                countryCode = address?.countryCode?.uppercase().orEmpty(),
            ),
        )
    }

    // A place by what was typed, in a country (by its code).
    suspend fun named(text: String, countryCode: String): PlaceAnswer {
        val words = text.trim()
        if (words.isEmpty()) return PlaceAnswer.NotFound
        val coder = geocoder ?: return PlaceAnswer.NoLookup
        val country = Locale.Builder().setRegion(countryCode).build().getDisplayCountry(Locale.ENGLISH)
        val found = lookup(coder, if (country.isBlank()) words else "$words, $country") ?: return PlaceAnswer.NotFound
        val address = found.firstOrNull { it.countryCode.equals(countryCode, ignoreCase = true) } ?: found.firstOrNull { it.hasLatitude() } ?: return PlaceAnswer.NotFound
        if (!address.hasLatitude() || !address.hasLongitude()) return PlaceAnswer.NotFound
        return PlaceAnswer.Found(
            LivePlace(
                latitude = rounded(address.latitude),
                longitude = rounded(address.longitude),
                label = placeLabel(address.locality ?: address.subAdminArea ?: words, address.adminArea, words),
                state = address.adminArea.orEmpty(),
                countryCode = address.countryCode?.uppercase() ?: countryCode.uppercase(),
            ),
        )
    }

    // One rough position: a recent one the phone already has, or a new one.
    @SuppressLint("MissingPermission")
    private suspend fun fix(): Location? {
        val manager = locations ?: return null
        if (!LocationManagerCompat.isLocationEnabled(manager)) return null
        val providers = providers(manager)
        if (providers.isEmpty()) return null
        val now = SystemClock.elapsedRealtimeNanos()
        val recent = providers.mapNotNull { runCatching { manager.getLastKnownLocation(it) }.getOrNull() }
            .filter { (now - it.elapsedRealtimeNanos) / 1_000_000 < FRESH_FIX_MS }
            .maxByOrNull { it.elapsedRealtimeNanos }
        if (recent != null) return recent
        return withTimeoutOrNull(FIX_WAIT_MS) {
            suspendCancellableCoroutine { done ->
                val cancel = CancellationSignal()
                done.invokeOnCancellation { cancel.cancel() }
                try {
                    LocationManagerCompat.getCurrentLocation(manager, providers.first(), cancel, ContextCompat.getMainExecutor(context)) { location ->
                        if (done.isActive) done.resume(location)
                    }
                } catch (e: SecurityException) {
                    if (done.isActive) done.resume(null)
                } catch (e: IllegalArgumentException) {
                    if (done.isActive) done.resume(null)
                }
            }
        }
    }

    // The sources of a rough position that are on, the best first. Satellite
    // positions need the precise permission before Android 12.
    private fun providers(manager: LocationManager): List<String> {
        val on = runCatching { manager.getProviders(true) }.getOrDefault(emptyList())
        val order = buildList {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) add(LocationManager.FUSED_PROVIDER)
            add(LocationManager.NETWORK_PROVIDER)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) add(LocationManager.GPS_PROVIDER)
            add(LocationManager.PASSIVE_PROVIDER)
        }
        return order.filter { it in on }
    }

    private suspend fun reverse(coder: Geocoder, latitude: Double, longitude: Double): Address? = withTimeoutOrNull(LOOKUP_WAIT_MS) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            suspendCancellableCoroutine { done ->
                coder.getFromLocation(
                    latitude,
                    longitude,
                    1,
                    object : Geocoder.GeocodeListener {
                        override fun onGeocode(addresses: MutableList<Address>) {
                            if (done.isActive) done.resume(addresses.firstOrNull())
                        }

                        override fun onError(errorMessage: String?) {
                            if (done.isActive) done.resume(null)
                        }
                    },
                )
            }
        } else {
            withContext(Dispatchers.IO) {
                @Suppress("DEPRECATION")
                runCatching { coder.getFromLocation(latitude, longitude, 1)?.firstOrNull() }.getOrNull()
            }
        }
    }

    private suspend fun lookup(coder: Geocoder, text: String): List<Address>? = withTimeoutOrNull(LOOKUP_WAIT_MS) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            suspendCancellableCoroutine { done ->
                coder.getFromLocationName(
                    text,
                    5,
                    object : Geocoder.GeocodeListener {
                        override fun onGeocode(addresses: MutableList<Address>) {
                            if (done.isActive) done.resume(addresses.toList())
                        }

                        override fun onError(errorMessage: String?) {
                            if (done.isActive) done.resume(null)
                        }
                    },
                )
            }
        } else {
            withContext(Dispatchers.IO) {
                @Suppress("DEPRECATION")
                runCatching { coder.getFromLocationName(text, 5)?.toList() }.getOrNull()
            }
        }
    }?.takeIf { it.isNotEmpty() }

    // To two decimals, about a kilometer.
    private fun rounded(value: Double): Double = Math.round(value * 100) / 100.0
}

// Every country, by its code, named in the phone's language and in order.
fun countryChoices(): List<Pair<String, String>> {
    val here = Locale.getDefault()
    return Locale.getISOCountries()
        .map { code -> code to Locale.Builder().setRegion(code).build().getDisplayCountry(here) }
        .filter { it.second.isNotBlank() }
        .sortedBy { it.second.lowercase(here) }
}
