import Intents
import OctoKit
import OctoSystem
import UIKit

/// Siri's "Play Drake in Octo", on the phone and in the car. The request is handed to the app,
/// which plays it by the voice rules; the app is started in the background for it if need be.
final class SiriMediaHandler: NSObject, INPlayMediaIntentHandling {
    func handle(intent: INPlayMediaIntent, completion: @escaping (INPlayMediaIntentResponse) -> Void) {
        completion(INPlayMediaIntentResponse(code: .handleInApp, userActivity: nil))
    }

    /// What Siri heard, as the voice rules take it.
    static func request(_ intent: INPlayMediaIntent) -> VoiceRequest {
        let search = intent.mediaSearch
        return VoiceRequest(name: search?.mediaName, artist: search?.artistName, album: search?.albumName,
                            genres: search?.genreNames ?? [], kind: kind(search?.mediaType),
                            current: search?.reference == .currentlyPlaying, resume: intent.resumePlayback == true)
    }

    private static func kind(_ type: INMediaItemType?) -> VoiceRequest.Kind {
        switch type {
        case .song: .song
        case .album: .album
        case .artist: .artist
        case .playlist: .playlist
        case .genre: .genre
        case .musicStation, .radioStation, .station, .algorithmicRadioStation: .station
        case .music: .music
        default: .unknown
        }
    }
}

/// Asks once for Siri to be allowed to hand requests to Octo: the first time the app comes to
/// the front with music in the library, and only when this build was signed with Siri.
@MainActor
enum SiriAccess {
    private static var observer: NSObjectProtocol?

    static func askWhenReady(library: Library?) {
        guard observer == nil, INPreferences.siriAuthorizationStatus() == .notDetermined,
              ProvisioningProfile.grants().contains("com.apple.developer.siri") else { return }
        observer = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ask(library) }
        }
    }

    private static func ask(_ library: Library?) {
        Task {
            guard let library, await library.trackCount() > 0, let observer else { return }
            NotificationCenter.default.removeObserver(observer)
            Self.observer = nil
            INPreferences.requestSiriAuthorization { _ in }
        }
    }
}
