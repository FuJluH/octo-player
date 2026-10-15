import OctoKit
import SwiftUI
import UIKit

/// Live radio near you: the place, the order and the radius, then every station the Radio
/// Browser catalog lists around the place that this app plays. Tapping a station plays it; its
/// menu keeps it on the phone, or, for a server's admin, adds it to the server.
struct LiveRadioPage: View {
    @Environment(Player.self) private var player
    @State private var radio = LiveRadioStore.shared
    @State private var choosing = false
    @State private var adding: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ScreenTitle("Live radio near you")
                if let place = radio.place {
                    placeLine(place)
                    controlsRow
                    content(place)
                } else {
                    PlaceChooser { radio.choose($0) }
                        .padding(.top, 4)
                }
                Text("Station list from Radio Browser, a free catalog kept by its listeners.")
                    .font(.octoCaption)
                    .foregroundStyle(OctoColor.textMuted)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
            }
            .padding(.top, detailTopGap)
            .animation(.easeInOut(duration: 0.2), value: radio.found)
            .animation(.easeInOut(duration: 0.2), value: radio.sort)
        }
        .barClearance()
        .refreshable { await radio.refresh() }
        .onAppear { radio.shownAgain() }
        .sheet(isPresented: $choosing) {
            PlaceChooser(inSheet: true) { place in
                choosing = false
                radio.choose(place)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: The place and the choices

    private func placeLine(_ place: LivePlace) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "location.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(OctoColor.accent)
                .accessibilityHidden(true)
            Text(place.label)
                .font(.octoBody)
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            GlazeButton("Change", size: .small) { choosing = true }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
    }

    private var controlsRow: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Order", selection: Binding(get: { radio.sort }, set: { radio.setSort($0) })) {
                    ForEach(LiveSort.allCases, id: \.self) { sort in
                        Label(sort.label, systemImage: sort == .distance ? "location" : "flame").tag(sort)
                    }
                }
            } label: {
                ChoiceChip(text: radio.sort.label, systemImage: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Order: \(radio.sort.label)")
            Menu {
                Picker("Within", selection: Binding(get: { radio.radiusIndex }, set: { radio.setRadius($0) })) {
                    ForEach(Array(radio.radiusChoices.enumerated()), id: \.offset) { index, choice in
                        Text("Within \(choice.label)").tag(index)
                    }
                }
            } label: {
                ChoiceChip(text: "Within \(radio.radius.label)", systemImage: "scope")
            }
            .accessibilityLabel("Within \(radio.radius.label)")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // MARK: The stations

    @ViewBuilder
    private func content(_ place: LivePlace) -> some View {
        switch radio.found {
        case .noPlace, .loading:
            LoadingSpinner(size: 22).frame(maxWidth: .infinity).padding(.top, 24)
        case .failed(let words):
            Text(words).font(.octoBodySmall).foregroundStyle(OctoColor.textMuted).padding(.horizontal, 20)
            GlazeButton("Try again", size: .medium) { radio.load() }
                .padding(.horizontal, 20)
                .padding(.top, 12)
        case .ready:
            let shown = radio.shown
            if shown.stations.isEmpty {
                Text("No stations Octo can play within \(radio.radius.label) of \(place.label). Try a wider radius.")
                    .font(.octoBodySmall)
                    .foregroundStyle(OctoColor.textMuted)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
            } else {
                ForEach(shown.stations) { station in row(station, among: shown.stations) }
            }
            if let note = hiddenStationsNote(shown.hidden) {
                Text(note + ".")
                    .font(.octoCaption)
                    .foregroundStyle(OctoColor.textMuted)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }
        }
    }

    private func row(_ station: LiveStation, among stations: [LiveStation]) -> some View {
        LiveStationRow(station: station, miles: radio.miles, kept: radio.isKept(station.uuid), adding: adding == station.uuid,
                       play: { radio.play(station, among: stations, on: player) }) {
            LiveStationMenuItems(station: station, adding: $adding)
        }
    }
}

/// A station on the near-you page: its logo, name, where it is and how far, its tags, and its
/// codec and bitrate. Tapping it plays it; the menu at its end and a long press give `menu`.
struct LiveStationRow<Items: View>: View {
    let station: LiveStation
    let miles: Bool
    let kept: Bool
    var adding = false
    let play: () -> Void
    @ViewBuilder let menu: Items

    var body: some View {
        HStack(spacing: 12) {
            Button(action: play) {
                HStack(spacing: 14) {
                    StationLogo(address: station.favicon, name: station.name, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(station.name).font(.octoBodySmall).foregroundStyle(OctoColor.textPrimary).lineLimit(1)
                            if kept {
                                Image(systemName: "bookmark.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(OctoColor.accent)
                                    .accessibilityLabel("Kept")
                            }
                        }
                        if !whereLine.isEmpty {
                            Text(whereLine).font(.octoCaption).foregroundStyle(OctoColor.textSecondary).lineLimit(1)
                        }
                        if !detailLine.isEmpty {
                            Text(detailLine).font(.octoCaption).foregroundStyle(OctoColor.textMuted).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Plays the station")
            Menu { menu } label: {
                ZStack {
                    if adding {
                        LoadingSpinner(size: 16)
                    } else {
                        Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold))
                    }
                }
                .foregroundStyle(OctoColor.textMuted)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("More for \(station.name)")
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .contextMenu { menu }
    }

    /// Where the station is, and how far.
    private var whereLine: String {
        [station.placeLine.isEmpty ? nil : station.placeLine,
         station.distanceMeters.map { liveDistanceText($0, miles: miles) }].compactMap { $0 }.joined(separator: " • ")
    }

    /// Its first tags, and its codec and bitrate.
    private var detailLine: String {
        let tags = station.tags.prefix(3).joined(separator: ", ")
        return [tags.isEmpty ? nil : tags, station.formatLine.isEmpty ? nil : station.formatLine].compactMap { $0 }
            .joined(separator: " • ")
    }
}

/// A station's menu: Keep (or stop keeping) it on the phone, and, for the server's admin, Add to
/// your server.
struct LiveStationMenuItems: View {
    let station: LiveStation
    @Binding var adding: String?
    @Environment(Router.self) private var router
    @Environment(Session.self) private var session
    @Environment(ServerControls.self) private var controls
    @State private var radio = LiveRadioStore.shared

    var body: some View {
        if radio.isKept(station.uuid) {
            Button("Stop keeping", systemImage: "bookmark.slash") {
                radio.drop(station.uuid)
                router.undoable("No longer kept: \(station.name)") { radio.keep(station) }
            }
        } else {
            Button("Keep", systemImage: "bookmark") {
                radio.keep(station)
                router.done("Kept \(station.name). It shows on Home under Live radio.")
            }
        }
        if session.client != nil && controls.isAdmin {
            Button("Add to your server", systemImage: "plus.circle") { addToServer() }
        }
    }

    /// Adds the station to the server's own stations; only an admin may.
    private func addToServer() {
        guard adding == nil, controls.isAdmin else { return }
        adding = station.uuid
        let station = station
        Task {
            defer { adding = nil }
            await addStationToServer(station, controls: controls, router: router)
        }
    }
}

/// Adds a catalog station to the server's own stations, saying how it went; only an admin may.
@MainActor
func addStationToServer(_ station: LiveStation, controls: ServerControls, router: Router) async {
    do {
        try await controls.createStation(streamUrl: station.streamUrl, name: station.name, homepageUrl: nil)
        router.done("Added \(station.name) to the server")
    } catch {
        if stationChangeRefused(error) {
            router.show("The server refused: only an admin can add stations.")
        } else {
            router.show("Couldn't add \(station.name). \(userMessage(plainError(error)))")
        }
    }
}

/// A choice shown as a glass chip: its icon, what is chosen, and a chevron saying it opens a list.
private struct ChoiceChip: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).font(.system(size: 13, weight: .semibold))
            Text(text).font(.octoBodySmall).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(OctoColor.textSecondary)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .glassEffect(Glass.octo.interactive(), in: .capsule)
        .contentShape(Capsule())
    }
}

/// Where to look for stations: the phone's location, asked for only when tapped, or a ZIP or
/// postal code, or a city, in a country.
struct PlaceChooser: View {
    var inSheet = false
    let chosen: (LivePlace) -> Void
    @Environment(Session.self) private var session
    @State private var finder = PlaceFinderHolder()
    @State private var text = ""
    @State private var country = phoneCountry()
    @State private var locating = false
    @State private var looking = false
    @State private var problem: String?
    @State private var denied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if inSheet {
                Text("Find stations near").font(.octoHeadline).foregroundStyle(.white)
            } else {
                Text("Hear what's on the air around you. Octo finds the stations near a place.")
                    .font(.octoBodySmall)
                    .foregroundStyle(OctoColor.textSecondary)
            }
            AccentButton("Use my location", size: .medium, loading: locating) { useLocation() }
            Text("Octo uses your location only to find radio stations near you, and sends just the area, never your exact spot. "
                 + lookupNote)
                .font(.octoCaption)
                .foregroundStyle(OctoColor.textMuted)
            Text("Or type a ZIP or postal code, or a city")
                .font(.octoBodySmall)
                .foregroundStyle(OctoColor.textSecondary)
                .padding(.top, 8)
            GlassInput("ZIP, postal code or city", text: $text, submitLabel: .search) { find() }
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            HStack(spacing: 12) {
                Picker("Country", selection: $country) {
                    ForEach(placeCountries(), id: \.code) { entry in Text(entry.name).tag(entry.code) }
                }
                .pickerStyle(.menu)
                .tint(.white)
                .labelsHidden()
                .accessibilityLabel("Country")
                Spacer(minLength: 0)
                GlazeButton("Find", size: .medium, enabled: !text.trimmingCharacters(in: .whitespaces).isEmpty, loading: looking) { find() }
            }
            if let problem {
                Text(problem).font(.octoCaption).foregroundStyle(OctoColor.error)
            }
            if denied {
                GlazeButton("Open Settings", size: .small) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(ChooserBackground(inSheet: inSheet))
    }

    /// How places are looked up for the server in use.
    private var resolver: PlaceResolver { PlaceFinder.resolver(extensions: session.extensions, client: session.client) }

    /// Where the page says places are looked up.
    private var lookupNote: String {
        switch resolver.lookup {
        case .server: "Places are looked up on your Octo server."
        case .serverUnreachable: "Places are looked up on your Octo server, which can't be reached right now."
        case .phone: "Places are looked up by your phone's place service."
        }
    }

    private func useLocation() {
        guard !locating else { return }
        problem = nil
        denied = false
        locating = true
        let resolver = resolver
        Task {
            defer { locating = false }
            do {
                chosen(try await finder.finder.here(resolver))
            } catch PlaceFinder.Problem.denied {
                denied = true
                problem = "Location is off for Octo. Turn it on in Settings, or type a place instead."
            } catch {
                problem = "Couldn't find where you are. Try again, or type a place instead."
            }
        }
    }

    private func find() {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, !looking else { return }
        problem = nil
        looking = true
        let resolver = resolver
        Task {
            defer { looking = false }
            do {
                chosen(try await resolver.typed(words, country: country))
            } catch PlaceProblem.serverUnreachable {
                problem = "Your Octo server can't be reached right now, so the place can't be looked up. Try again once it's back."
            } catch {
                problem = "Couldn't find \"\(words)\" there. Check the spelling or the country."
            }
        }
    }
}

/// Keeps one place finder for the chooser while it shows.
@MainActor
private final class PlaceFinderHolder {
    let finder = PlaceFinder()
}

/// The chooser on the page sits on a glass card; in a sheet it sits on the sheet.
private struct ChooserBackground: ViewModifier {
    let inSheet: Bool

    func body(content: Content) -> some View {
        if inSheet {
            content
        } else {
            content
                .glassEffect(Glass.octo, in: .rect(cornerRadius: 20))
                .padding(.horizontal, 20)
        }
    }
}

/// The first card on Home's Live radio shelf, as wide as a station card: the way to the stations
/// near the listener.
struct FindNearbyCard: View {
    private static let size: CGFloat = 150

    var body: some View {
        NavigationLink(value: Route.liveRadioNear) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: OctoRadius.artS, style: .continuous).fill(OctoColor.accent.opacity(0.16))
                    VStack(spacing: 10) {
                        Image(systemName: "location.magnifyingglass").font(.system(size: 34, weight: .semibold))
                        Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(OctoColor.textSecondary)
                    }
                    .foregroundStyle(.white)
                }
                .frame(width: Self.size, height: Self.size)
                .glassEffect(Glass.octo, in: .rect(cornerRadius: OctoRadius.artS))
                Text("Find stations near you").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
            }
            .frame(width: Self.size, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale(scale: 0.97))
        .accessibilityLabel("Find stations near you")
    }
}

/// A station kept on the phone, on Home's Live radio shelf: its logo and name. Tapping it plays
/// it; a long press offers to stop keeping it.
struct KeptStationCard: View {
    let station: LiveStation
    let play: () -> Void
    @Environment(Router.self) private var router
    private static let size: CGFloat = 150

    var body: some View {
        Button(action: play) {
            VStack(alignment: .leading, spacing: 8) {
                StationLogo(address: station.favicon, name: station.name, size: Self.size)
                Text(station.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                if !station.placeLine.isEmpty {
                    Text(station.placeLine).font(.octoBodySmall).foregroundStyle(OctoColor.textSecondary).lineLimit(1)
                }
            }
            .frame(width: Self.size, alignment: .leading)
        }
        .buttonStyle(PressScale(scale: 0.97))
        .accessibilityLabel("Play \(station.name)")
        .contextMenu {
            Button("Stop keeping", systemImage: "bookmark.slash") {
                let radio = LiveRadioStore.shared
                radio.drop(station.uuid)
                router.undoable("No longer kept: \(station.name)") { radio.keep(station) }
            }
        }
    }
}
