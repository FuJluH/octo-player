import Contacts
import CoreLocation
import Foundation
import OctoKit

/// Finds a place to look for radio stations around: the phone's own location, asked for only
/// when the listener taps for it (while the app is in use), or a ZIP or postal code, or a city,
/// in a country. Where each is looked up, and what is sent, is `PlaceResolver`'s: an Octo server
/// that lists the place look-up, else the phone's own place service, and only ever the rounded
/// coordinates of a location.
@MainActor
final class PlaceFinder: NSObject, CLLocationManagerDelegate {
    enum Problem: Error, Equatable {
        case denied
        case unavailable
    }

    private let manager = CLLocationManager()
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

    /// How places are found for the server in use: on it when it lists the look-up and can be
    /// reached (`client`), refused when it lists it but cannot, else by the phone.
    static func resolver(extensions: [String], client: SubsonicClient?) -> PlaceResolver {
        PlaceResolver(lookup: PlaceLookup(extensions: extensions, reachable: client != nil),
                      server: { query in
                          guard let client else { throw PlaceProblem.serverUnreachable }
                          return try await client.place(query)
                      },
                      phoneTyped: { query in await PhonePlaces.typed(query) },
                      phoneNear: { place in await PhonePlaces.near(place) })
    }

    /// Where the phone is now, asking for permission first if it was never asked.
    func here(_ resolver: PlaceResolver) async throws -> LivePlace {
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
        return await resolver.near(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
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

/// The phone's own place service, for a server that does not look up places. Each call makes its
/// own geocoder, so nothing is shared between threads.
enum PhonePlaces {
    /// A ZIP or postal code, or a city, in a country.
    static func typed(_ query: PlaceQuery) async -> LivePlace? {
        let address = CNMutablePostalAddress()
        switch query {
        case .code(let code, let country):
            address.postalCode = code
            address.isoCountryCode = country
        case .city(let name, let state, let country):
            address.city = name
            address.state = state
            address.isoCountryCode = country
        case .near:
            return nil
        }
        guard let mark = (try? await CLGeocoder().geocodePostalAddress(address))?.first, let location = mark.location else { return nil }
        return place(at: location.coordinate, mark: mark)
    }

    /// The names for a rounded place: its city, state and country.
    static func near(_ place: LivePlace) async -> LivePlace? {
        let rounded = CLLocation(latitude: place.latitude, longitude: place.longitude)
        guard let mark = (try? await CLGeocoder().reverseGeocodeLocation(rounded))?.first else { return nil }
        return Self.place(at: rounded.coordinate, mark: mark)
    }

    private static func place(at coordinate: CLLocationCoordinate2D, mark: CLPlacemark) -> LivePlace {
        let country = mark.isoCountryCode ?? ""
        let state = catalogStateName(mark.administrativeArea ?? "", countryCode: country)
        let label = [mark.locality, mark.administrativeArea].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return LivePlace(latitude: coordinate.latitude, longitude: coordinate.longitude, label: label, state: state,
                         countryCode: country).rounded
    }
}
