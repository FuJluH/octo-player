package app.winters.octo

import android.app.Application
import app.winters.octo.admin.ServerUpdates
import app.winters.octo.data.ServerDownloads
import app.winters.octo.data.SessionRepository
import app.winters.octo.data.LibraryFiles
import app.winters.octo.data.Upgrades
import app.winters.octo.device.DeviceArtworkFetcher
import app.winters.octo.device.DeviceArtworkKeyer
import app.winters.octo.device.DeviceLibrary
import app.winters.octo.family.FamilyHub
import app.winters.octo.listening.ListenBrainzSync
import app.winters.octo.offline.OfflineDownloads
import app.winters.octo.playback.ServerSwitch
import app.winters.octo.server.ServerArtworkFetcher
import app.winters.octo.server.ServerArtworkKeyer
import app.winters.octo.server.ServerSync
import app.winters.octo.update.AppUpdates
import coil3.ImageLoader
import coil3.PlatformContext
import coil3.SingletonImageLoader
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import coil3.request.crossfade
import dagger.hilt.android.HiltAndroidApp
import okhttp3.Dispatcher
import okhttp3.OkHttpClient
import javax.inject.Inject

// How many cover downloads may be open to one server at once. The lanes in
// CoverTraffic decide which covers go; this only keeps the HTTP client from
// queueing the urgent ones behind the rest, or the app's other calls
// behind covers.
private const val COVER_REQUESTS_PER_HOST = 16

@HiltAndroidApp
class OctoApp : Application(), SingletonImageLoader.Factory {
    @Inject lateinit var http: OkHttpClient
    @Inject lateinit var deviceLibrary: DeviceLibrary
    @Inject lateinit var sessions: SessionRepository
    @Inject lateinit var serverSync: ServerSync
    @Inject lateinit var switcher: ServerSwitch
    @Inject lateinit var offline: OfflineDownloads
    @Inject lateinit var listenBrainz: ListenBrainzSync
    @Inject lateinit var updates: AppUpdates
    @Inject lateinit var upgrades: Upgrades
    @Inject lateinit var serverDownloads: ServerDownloads
    @Inject lateinit var libraryFiles: LibraryFiles
    @Inject lateinit var family: FamilyHub
    @Inject lateinit var serverUpdates: ServerUpdates

    override fun onCreate() {
        super.onCreate()
        // Keep the library in step with the music on the phone.
        deviceLibrary.start()
        // And with the server's, when one is connected.
        serverSync.start()
        // A change of server puts the old one's music away and brings the new one's.
        switcher.start()
        // Downloads left waiting last time carry on.
        offline.start()
        // Plays waiting for ListenBrainz go out.
        listenBrainz.start()
        // New versions of Octo, in the release build only.
        updates.start()
        // FLACs asked for last time are followed until they are done.
        upgrades.start()
        // The server's downloads, for their sheet.
        serverDownloads.start()
        // What the server lets Library health and Delete from disk do.
        libraryFiles.start()
        // Family on the server in use, and its requests checked now and then.
        family.start()
        // A newer Octo for the server in use, for its admin.
        serverUpdates.start()
    }

    override fun newImageLoader(context: PlatformContext): ImageLoader {
        // Covers from a server load through the same connection pool as the
        // API, with calls of their own.
        val covers = http.newBuilder().dispatcher(Dispatcher().apply { maxRequestsPerHost = COVER_REQUESTS_PER_HOST }).build()
        return ImageLoader.Builder(context)
            .components {
                add(OkHttpNetworkFetcherFactory(callFactory = { covers }))
                // Artwork embedded in files on the phone.
                add(DeviceArtworkFetcher.Factory(this@OctoApp))
                add(DeviceArtworkKeyer())
                // Covers on the signed-in server.
                add(ServerArtworkFetcher.Factory(sessions))
                add(ServerArtworkKeyer())
            }
            .crossfade(true)
            .build()
    }
}
