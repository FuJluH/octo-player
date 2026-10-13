package app.winters.octo.di

import app.winters.octo.BuildConfig
import app.winters.octo.liveradio.RadioBrowser
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import okhttp3.OkHttpClient
import java.util.concurrent.TimeUnit
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object LiveRadioModule {
    // The Radio Browser catalog, asked with the app's name. Its client
    // shares the app's connections and threads but none of what the app
    // adds for its servers (their headers, certificates and checks), since
    // the catalog is not one of them.
    @Provides
    @Singleton
    fun radioBrowser(http: OkHttpClient): RadioBrowser = RadioBrowser(
        OkHttpClient.Builder()
            .connectionPool(http.connectionPool)
            .dispatcher(http.dispatcher)
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .build(),
        "Octo/${BuildConfig.VERSION_NAME} (Android)",
    )
}
