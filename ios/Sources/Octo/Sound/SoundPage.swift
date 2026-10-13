import OctoKit
import SwiftUI
import UniformTypeIdentifiers

/// Everything that shapes the sound: the equalizer and its presets, loudness, balance, a
/// correction for the headphones in use, and crossfeed. Changes go to the output playing now.
struct SoundPage: View {
    @Environment(SoundStore.self) private var store
    @State private var model: SoundPageModel?

    var body: some View {
        Group {
            if let model {
                SoundPageContent(model: model)
            } else {
                OctoColor.background.ignoresSafeArea()
            }
        }
        .onAppear { if model == nil { model = SoundPageModel(store: store) } }
    }
}

private let replayGainModes: [ReplayGainMode] = [.off, .track, .album, .smart]
private let replayGainNames = ["Off", "Song", "Album", "Smart"]
private let replayGainHelp = [
    "Songs play at the level they were made.",
    "Evens out volume between songs.",
    "Keeps an album's quiet and loud songs as the artist made them.",
    "Album while you play an album in order, otherwise song.",
]
private let filterTypes: [FilterType] = [.peak, .lowShelf, .highShelf]
private let filterTypeNames = ["Peak", "Low shelf", "High shelf"]

private struct SoundPageContent: View {
    @Bindable var model: SoundPageModel
    /// The chosen filter in parametric mode.
    @State private var chosen = 0
    @State private var saving = false
    /// The own preset asked about before it is deleted.
    @State private var deleting: String?
    @State private var importing = false
    @State private var exporting = false
    @State private var exportFile = SoundTextFile(text: "")

    private var store: SoundStore { model.store }

    var body: some View {
        let settings = model.settings
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScreenTitle("Sound")
                    VStack(spacing: 16) {
                        outputLine
                        equalizerCard(settings)
                        loudnessCard(settings).id("loudness")
                        balanceCard(settings).id("balance")
                        correctionCard(settings).id("correction")
                        crossfeedCard(settings).id("crossfeed")
                    }
                }
                .padding(.top, 8 + detailTopGap)
            }
            .barClearance()
            .onChange(of: store.pageRequest, initial: true) { _, request in
                guard let request else { return }
                store.pageRequest = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    take(request, scroller: scroller)
                }
            }
        }
        .background { PageBackdrop(page: .sound, route: nil) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .text]) { result in
            if case .success(let url) = result { model.importCorrection(url) }
        }
        .fileExporter(isPresented: $exporting, document: exportFile, contentTypes: [.plainText],
                      defaultFilename: "Octo ParametricEQ.txt") { result in
            switch result {
            case .success: model.exportFinished(saved: true)
            case .failure: model.exportFinished(saved: false)
            }
        }
        .onAppear { store.pagesShown += 1 }
        .onDisappear {
            store.pagesShown -= 1
            model.close()
        }
    }

    // MARK: Output

    /// Which output these settings are for, and whether each keeps its own.
    private var outputLine: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sound for \(store.output.label)").font(.octoBody).foregroundStyle(OctoColor.textPrimary)
            SoundSwitchLine(label: "Each output keeps its own sound",
                            detail: "The speaker, headphones and each Bluetooth device remember their own settings.",
                            isOn: Binding(get: { store.perOutput }, set: { model.setPerOutput($0) }))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }

    // MARK: Equalizer

    private func equalizerCard(_ settings: SoundSettings) -> some View {
        let parametric = settings.mode == .parametric
        let selected = min(max(chosen, 0), max(settings.filters.count - 1, 0))
        let label = SoundEdits.presetLabel(settings)
        return SoundSwitchCard(title: "Equalizer", isOn: Binding(get: { settings.eqEnabled }, set: { on in
            model.change { var s = $0; s.eqEnabled = on; return s }
        })) {
            SoundSegmented(options: ["Graphic", "Parametric"], selected: parametric ? 1 : 0) { index in
                model.change { SoundEdits.withMode($0, index == 1 ? .parametric : .graphic) }
            }
            SoundResponseGraph(settings: settings, selected: selected, onSelect: { chosen = $0 },
                               onPreview: { model.preview($0) }, onSettle: { model.settle() })
            if parametric {
                filterEditor(settings, selected: selected).id("editor")
            }
            SoundPresetBar(choices: PresetChoice.row(label: label, own: store.presets), selected: label,
                           onPick: pick, onLongPress: { choice, _ in deleting = choice.name })
                .confirmationDialog("Delete \"\(deleting ?? "")\"?",
                                    isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                    titleVisibility: .visible, presenting: deleting) { name in
                    Button("Delete", role: .destructive) { model.deletePreset(name) }
                }
            if !parametric {
                SoundTextAction("Save as preset\u{2026}") { saving = true }
                    .padding(.horizontal, 4)
                    .namePopover(isPresented: $saving, title: "Save as preset", placeholder: "Preset name", action: "Save",
                                 capitalization: .words, autocorrects: false, ready: { UserPresetRules.canSaveAs($0) },
                                 note: { name in
                                     !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !UserPresetRules.canSaveAs(name)
                                         ? "A built-in preset has that name." : nil
                                 }) { name in
                        model.savePreset(name)
                        saving = false
                    }
            }
            SoundHairline()
            preamp(settings)
            SoundHairline()
            SoundHoldButton(text: "Hold to hear it flat", enabled: settings.eqEnabled || model.heldFlat) { model.hearFlat($0) }
                .frame(maxWidth: .infinity)
        }
        .id("equalizer")
    }

    private func pick(_ choice: PresetChoice) {
        let preset = choice.own ? store.presets.first { $0.name == choice.name } : eqPresets.first { $0.name == choice.name }
        if let preset { model.applyPreset(preset) }
    }

    /// Type, frequency, gain and width of the chosen filter, with adding and deleting filters.
    private func filterEditor(_ settings: SoundSettings, selected: Int) -> some View {
        let filter = settings.filters.indices.contains(selected) ? settings.filters[selected] : nil
        return VStack(alignment: .leading, spacing: 4) {
            if let filter {
                Text("Filter \(selected + 1) of \(settings.filters.count)").font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                SoundSegmented(options: filterTypeNames, selected: filterTypes.firstIndex(of: filter.type) ?? 0) { index in
                    model.change { Self.edit($0, selected) { $0.type = filterTypes[index] } }
                }
                .padding(.vertical, 6)
                SoundValueSlider(label: "Frequency", value: filter.frequency, range: SoundEdits.minHz...SoundEdits.maxHz,
                                 reading: SoundEdits.readHz(filter.frequency), step: 1,
                                 toFraction: SoundSliders.hzFraction, fromFraction: SoundSliders.hzValue) { hz in
                    model.preview { Self.edit($0, selected) { $0.frequency = SoundEdits.tidyHz(hz) } }
                }
                SoundValueSlider(label: "Gain", value: filter.gainDb, range: -gainRangeDb...gainRangeDb,
                                 reading: SoundEdits.readDb(filter.gainDb), step: 0.1) { db in
                    model.preview { Self.edit($0, selected) { $0.gainDb = db } }
                }
                SoundValueSlider(label: "Q", value: filter.q, range: SoundEdits.minQ...SoundEdits.maxQ,
                                 reading: SoundSliders.readQ(filter.q), step: 0.01,
                                 toFraction: SoundSliders.qFraction, fromFraction: SoundSliders.qValue) { q in
                    model.preview { Self.edit($0, selected) { $0.q = q } }
                }
            } else {
                Text("No filters yet. Add one, then drag it on the curve.").font(.octoCaption).foregroundStyle(OctoColor.textMuted)
            }
            HStack(spacing: 12) {
                Button("Add filter") {
                    let next = settings.filters.count
                    model.change { SoundEdits.withNewFilter($0) }
                    chosen = next
                }
                .buttonStyle(SoundGlassButtonStyle())
                .disabled(settings.filters.count >= SoundEdits.maxFilters)
                if filter != nil {
                    Button("Delete filter") { model.change { SoundEdits.withoutFilter($0, index: selected) } }
                        .buttonStyle(SoundGlassButtonStyle())
                }
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 4)
    }

    /// Changes one filter, and turns the equalizer on so the change is heard.
    private static func edit(_ settings: SoundSettings, _ index: Int, _ change: (inout EqFilter) -> Void) -> SoundSettings {
        guard settings.filters.indices.contains(index) else { return settings }
        var filter = settings.filters[index]
        change(&filter)
        var s = SoundEdits.withFilter(settings, index: index, filter)
        s.eqEnabled = true
        return s
    }

    /// The level before the equalizer: automatic, or set by hand.
    private func preamp(_ settings: SoundSettings) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SoundSwitchLine(label: "Automatic preamp",
                            detail: "Lowers the level by the curve's highest boost, so boosting never distorts.",
                            isOn: Binding(get: { settings.autoPreamp }, set: { on in model.change { var s = $0; s.autoPreamp = on; return s } }))
            if !settings.autoPreamp {
                SoundValueSlider(label: "Preamp", value: settings.preampDb, range: -12...6, reading: SoundEdits.readDb(settings.preampDb)) { db in
                    model.preview { var s = $0; s.preampDb = db; return s }
                }
            }
            HStack {
                Text("Level now").font(.octoBodySmall).foregroundStyle(OctoColor.textSecondary)
                Spacer(minLength: 0)
                Text(SoundEdits.readDb(settings.effectivePreampDb())).font(.octoBodySmall.monospacedDigit()).foregroundStyle(OctoColor.textPrimary)
            }
            .padding(.top, 4)
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 4)
    }

    // MARK: Loudness, balance, correction

    private func loudnessCard(_ settings: SoundSettings) -> some View {
        let mode = replayGainModes.firstIndex(of: settings.replayGain) ?? 0
        return SoundCard(title: "Loudness") {
            SoundSegmented(options: replayGainNames, selected: mode) { index in
                model.change { var s = $0; s.replayGain = replayGainModes[index]; return s }
            }
            Text(replayGainHelp[mode]).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
            if settings.replayGain != .off {
                SoundValueSlider(label: "Preamp", value: settings.replayGainPreampDb, range: -12...12,
                                 reading: SoundEdits.readDb(settings.replayGainPreampDb)) { db in
                    model.preview { var s = $0; s.replayGainPreampDb = db; return s }
                }
                Text("Volume for songs without loudness info").font(.octoBodySmall).foregroundStyle(OctoColor.textPrimary)
                SoundValueSlider(label: "Level", value: settings.replayGainFallbackDb, range: -12...6,
                                 reading: SoundEdits.readDb(settings.replayGainFallbackDb)) { db in
                    model.preview { var s = $0; s.replayGainFallbackDb = db; return s }
                }
                SoundSwitchLine(label: "Prevent clipping", detail: "Turns a song down rather than letting a boost distort it.",
                                isOn: Binding(get: { settings.preventClipping }, set: { on in model.change { var s = $0; s.preventClipping = on; return s } }))
            }
            SoundSwitchLine(label: "Limiter", detail: "Catches any peak that would still distort, just below full volume.",
                            isOn: Binding(get: { settings.limiter }, set: { on in model.change { var s = $0; s.limiter = on; return s } }))
        }
    }

    private func balanceCard(_ settings: SoundSettings) -> some View {
        SoundCard(title: "Balance") {
            HStack {
                Text("Left and right").font(.octoBodySmall).foregroundStyle(OctoColor.textSecondary)
                Spacer(minLength: 0)
                Text(SoundEdits.readBalance(settings.balance)).font(.octoBodySmall).foregroundStyle(OctoColor.textPrimary)
            }
            SoundBalanceSlider(value: settings.balance) { value in
                model.preview { var s = $0; s.balance = value; return s }
            }
            SoundSwitchLine(label: "Mono", detail: "Both ears hear the same thing. Handy with one earbud.",
                            isOn: Binding(get: { settings.mono }, set: { on in model.change { var s = $0; s.mono = on; return s } }))
        }
    }

    /// The headphone correction, and moving curves in and out as files.
    private func correctionCard(_ settings: SoundSettings) -> some View {
        let correction = settings.correction
        let credit: String = if let correction {
            correction.source == ParametricEqFile.imported ? "Imported from a file" : "Correction by AutoEq, measured by \(correction.source)"
        } else {
            "Evens out how your headphones color the sound."
        }
        return SoundCard(title: "Headphone correction") {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(correction?.name ?? "None").font(.octoBodySmall).foregroundStyle(OctoColor.textPrimary)
                    Text(credit).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 12)
                if correction != nil {
                    SoundTextAction("Remove") { model.removeCorrection() }
                }
            }
            if let problem = model.fileProblem {
                Text(problem).font(.octoCaption).foregroundStyle(OctoColor.error)
            }
            SoundHairline()
            SoundChoiceLine(label: "Import correction\u{2026}", value: "A ParametricEQ.txt file") { importing = true }
            SoundChoiceLine(label: "Export my curve\u{2026}", value: "Saves it as a ParametricEQ.txt file") {
                exportFile = SoundTextFile(text: model.curveFile())
                exporting = true
            }
        }
    }

    /// Crossfeed for headphones: a preset, or the cut and feed set by hand. It stays off on the
    /// speaker, a car and AirPlay, and rests while mono is on.
    private func crossfeedCard(_ settings: SoundSettings) -> some View {
        let crossfeed = settings.crossfeed
        let headphones = store.output.takesCrossfeed
        let presets = CrossfeedPreset.allCases
        return SoundSwitchCard(title: "Crossfeed", isOn: Binding(get: { headphones && crossfeed.on }, set: { on in
            model.change { var s = $0; s.crossfeed.on = on; return s }
        }), enabled: headphones) {
            Text(CrossfeedWords.about).font(.octoCaption).foregroundStyle(OctoColor.textMuted).padding(.horizontal, 4)
            if !headphones {
                Text(CrossfeedWords.headphonesOnly).font(.octoBodySmall).foregroundStyle(OctoColor.textSecondary).padding(.horizontal, 4)
            } else {
                if settings.mono && crossfeed.on {
                    Text(CrossfeedWords.monoOn).font(.octoCaption).foregroundStyle(OctoColor.textSecondary).padding(.horizontal, 4)
                }
                SoundSegmented(options: presets.map(\.label), selected: presets.firstIndex(of: crossfeed.preset) ?? 0) { index in
                    // Picking a strength turns crossfeed on, so the change is heard.
                    model.change { var s = $0; s.crossfeed.preset = presets[index]; s.crossfeed.on = true; return s }
                }
                Text("\(crossfeed.preset.detail) \(CrossfeedWords.values(crossfeed)).")
                    .font(.octoCaption)
                    .foregroundStyle(OctoColor.textMuted)
                    .padding(.horizontal, 4)
                if crossfeed.preset == .custom {
                    let cutRange = Double(Crossfeed.cutRange.lowerBound)...Double(Crossfeed.cutRange.upperBound)
                    SoundValueSlider(label: "Cut", value: Double(crossfeed.cutHz), range: cutRange,
                                     reading: SoundEdits.readHz(Double(crossfeed.cutHz)), step: 10,
                                     toFraction: CrossfeedWords.cutFraction, fromFraction: CrossfeedWords.cutValue) { hz in
                        model.preview { var s = $0; s.crossfeed.cutHz = Int(hz.rounded()); s.crossfeed.on = true; return s }
                    }
                    SoundValueSlider(label: "Feed", value: crossfeed.feedDb, range: Crossfeed.feedRange,
                                     reading: CrossfeedWords.readFeed(crossfeed.feedDb), step: 0.5) { db in
                        model.preview { var s = $0; s.crossfeed.feedDb = db; s.crossfeed.on = true; return s }
                    }
                    Text(CrossfeedWords.customHelp)
                        .font(.octoCaption)
                        .foregroundStyle(OctoColor.textMuted)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    /// A state asked for from outside the page.
    private func take(_ request: SoundPageRequest, scroller: ScrollViewProxy) {
        switch request {
        case .editor:
            withAnimation { scroller.scrollTo("editor", anchor: .top) }
        case .card(let name):
            withAnimation { scroller.scrollTo(name, anchor: .top) }
        case .savePreset:
            withAnimation { scroller.scrollTo("equalizer", anchor: .top) }
            saving = true
        case .deletePreset(let name):
            withAnimation { scroller.scrollTo("equalizer", anchor: .top) }
            deleting = name
        }
    }
}
