import Contacts
import CoreLocation
import Foundation
import OctoKit

/// Finds a place to look for radio stations around: the phone's own location, asked for only
/// when the listener taps for it (while the app is in use), or a ZIP or postal code, or a city,
/// in a country. An Octo server that lists the place look-up is asked, so nothing goes to
/// Apple's place service; any other server, or none, means the phone's own place service. A
/// location is named from its rounded coordinates only, so the precise spot never leaves the
/// phone; when nothing can name it, the stations are found by radius alone.
@MainActor
final class PlaceFinder: NSObject, CLLocationManagerDelegate {
    enum Problem: Error, Equatable {
        case denied
        case unavailable
        case notFound
    }

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var waiting: CheckedContinuation<CLLocation, Error>?
    private var asking: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Whether the listener turned location off for Octo, so the page can say where to turn it on.
    var denied: Bool {
        let status = manager.authorizationStatus
        return status == .denied || status == .restricted
    }

    /// Where the phone is now, asking for permission first if it was never asked. `server` is
    /// the Octo server that looks up places, when there is one.
    func here(server: SubsonicClient?) async throws -> LivePlace {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { continuation in
                asking = continuation
                manager.requestWhenInUseAuthorization()
            }
        }
        guard !denied else { throw Problem.denied }
        let location = try await withCheckedThrowingContinuation { continuation in
            waiting?.resume(throwing: Problem.unavailable)
            waiting = continuation
            manager.requestLocation()
        }
        let at = LivePlace(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, label: "Your location").rounded
        if let server {
            // The server names the nearest place for the state and country; the coordinates stay
            // the phone's own, rounded.
            guard let named = try? await server.place(.near(latitude: at.latitude, longitude: at.longitude)) else { return at }
            let found = named.livePlace
            return LivePlace(latitude: at.latitude, longitude: at.longitude, label: found.label.isEmpty ? at.label : found.label,
                             state: found.state, countryCode: found.countryCode)
        }
        let rounded = CLLocation(latitude: at.latitude, longitude: at.longitude)
        guard let mark = try? await geocoder.reverseGeocodeLocation(rounded).first else { return at }
        return place(at: rounded.coordinate, mark: mark, fallback: at.label)
    }

    /// A ZIP or postal code, or a city ("Austin, TX" with its state), in the country with ISO
    /// code `country`, looked up on `server` when there is one.
    func place(for text: String, country: String, server: SubsonicClient?) async throws -> LivePlace {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { throw Problem.notFound }
        let query = PlaceQuery.typed(words, country: country)
        if let server {
            guard let found = try await server.place(query) else { throw Problem.notFound }
            return found.livePlace
        }
        let address = CNMutablePostalAddress()
        switch query {
        case .code(let code, _): address.postalCode = code
        case .city(let name, let state, _):
            address.city = name
            address.state = state
        case .near: break
        }
        address.isoCountryCode = country
        let marks = (try? await geocoder.geocodePostalAddress(address)) ?? []
        guard let mark = marks.first, let location = mark.location else { throw Problem.notFound }
        return place(at: location.coordinate, mark: mark, fallback: words)
    }

    private func place(at coordinate: CLLocationCoordinate2D, mark: CLPlacemark?, fallback: String) -> LivePlace {
        let country = mark?.isoCountryCode ?? ""
        let state = catalogStateName(mark?.administrativeArea ?? "", countryCode: country)
        let label = [mark?.locality, mark?.administrativeArea].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return LivePlace(latitude: coordinate.latitude, longitude: coordinate.longitude, label: label.isEmpty ? fallback : label,
                         state: state, countryCode: country).rounded
    }

    // MARK: Location delegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard status != .notDetermined else { return }
            asking?.resume()
            asking = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in
            waiting?.resume(returning: last)
            waiting = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        Task { @MainActor in
            waiting?.resume(throwing: denied ? Problem.denied : Problem.unavailable)
            waiting = nil
        }
    }
}

/// The countries a postal code or city can be looked up in, by name in the phone's language.
func placeCountries() -> [(code: String, name: String)] {
    let notCountries: Set<String> = ["EU", "EZ", "UN", "QO", "XA", "XB", "ZZ"]
    return Locale.Region.isoRegions
        .filter { $0.identifier.count == 2 && $0.identifier.allSatisfy(\.isLetter) && !notCountries.contains($0.identifier) }
        .compactMap { region in Locale.current.localizedString(forRegionCode: region.identifier).map { (region.identifier, $0) } }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}

/// The phone's own country, for the postal code's country to start at.
func phoneCountry() -> String { Locale.current.region?.identifier ?? "US" }
