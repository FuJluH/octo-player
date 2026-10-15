import OctoKit
import SwiftUI

/// The tokens the library pages use beyond the shared palette.
enum LibraryLook {
    /// A selected row: the accent 40% of the way out of black.
    static var accentSelected: Color { Color.black.mix(with: OctoColor.accent, by: 0.4) }
    /// A hairline between rows.
    static let hairline = Color.white.opacity(0.08)
    /// The small bold words of buttons and chips.
    static let label = Font.system(size: 13.5, weight: .semibold)
    static let labelMedium = Font.system(size: 13.5, weight: .medium)
    /// Lifted glass: a little brighter than the resting glass, for the main button of a pair.
    static let lifted = Glass.regular.tint(.white.opacity(0.14)).interactive()
    static var resting: Glass { Glass.octo.interactive() }
}

/// Play and Shuffle across a detail page: two glass capsules of equal width. Play has the lifted
/// glass, Shuffle the resting glass. While loading, Play shows a spinner in place of its icon.
struct PlayShuffle: View {
    var enabled = true
    var loading = false
    let play: () -> Void
    let shuffle: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                capsule("Play", icon: .play, glass: LibraryLook.lifted, spinner: loading, action: play)
                capsule("Shuffle", icon: .shuffle, glass: LibraryLook.resting, spinner: false, action: shuffle)
            }
        }
        .disabled(!enabled || loading)
        .opacity(enabled || loading ? 1 : 0.4)
    }

    private func capsule(_ word: String, icon: OctoIcon, glass: Glass, spinner: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if spinner {
                    Spinner(size: 18).frame(width: 22, height: 22)
                } else {
                    IconView(icon, size: 22)
                }
                Text(word).font(.octoBody)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .glassEffect(glass, in: .capsule)
            .frame(minHeight: 48)
            .contentShape(Capsule())
        }
        .buttonStyle(PressScale(scale: 0.96))
    }
}

/// A detail page's play line: what it holds on the left, up to two lines, and any quieter
/// controls at the right, 8 apart; then Play and Shuffle across the full width 10 below, left out
/// when there is nothing to play.
struct PlayRow<Extras: View>: View {
    let details: String
    var playable = true
    let play: () -> Void
    let shuffle: () -> Void
    @ViewBuilder var extras: Extras

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(details)
                    .font(.octoCaption)
                    .foregroundStyle(OctoColor.textMuted)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                extras
            }
            if playable {
                PlayShuffle(play: play, shuffle: shuffle).padding(.top, 10)
            }
        }
    }
}

extension PlayRow where Extras == EmptyView {
    init(details: String, playable: Bool = true, play: @escaping () -> Void, shuffle: @escaping () -> Void) {
        self.init(details: details, playable: playable, play: play, shuffle: shuffle) { EmptyView() }
    }
}

/// "Keep downloaded" for a playlist, or for Liked songs when `playlistId` is nil: their songs
/// only on a server download to the phone, and the downloads follow the list as songs come and
/// go. Shown only when there is something to download or it is on. Liked songs' switch is the one
/// the Streaming and offline settings have too.
struct KeepDownloadedLine: View {
    let tracks: [LibraryTrack]
    var playlistId: String?
    @Environment(OfflineDownloads.self) private var offline

    var body: some View {
        let prefs = offline.settings.offline
        let checked = playlistId.map { prefs.keptPlaylists.contains($0) } ?? prefs.keepLiked
        let serverOnly = tracks.filter { !$0.onPhone && !$0.isFound }
        if !serverOnly.isEmpty || checked {
            let done = serverOnly.filter { offline.byTrack[$0.id]?.state == .done }.count
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep downloaded").font(.octoBodySmall).foregroundStyle(.white)
                    Text(checked ? keptSummary(serverOnly: serverOnly.count, done: done)
                         : "Download the songs only on your server, and keep them in step")
                        .font(.octoCaption)
                        .foregroundStyle(OctoColor.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 12)
                Toggle("Keep downloaded", isOn: Binding(get: { checked }, set: { on in
                    if let playlistId { offline.setPlaylistKept(playlistId, on) } else { offline.setKeepLiked(on) }
                }))
                .labelsHidden()
                .tint(OctoColor.accent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
    }
}

/// Play as a small glass pill and Shuffle as a round glass button beside it, for list pages.
struct PlayPills: View {
    let play: () -> Void
    let shuffle: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: play) {
                HStack(spacing: 6) {
                    IconView(.play, size: 18)
                    Text("Play").font(LibraryLook.labelMedium)
                }
                .foregroundStyle(.white)
                .padding(.leading, 11)
                .padding(.trailing, 15)
                .frame(height: 34)
                .glassEffect(LibraryLook.lifted, in: .capsule)
                .frame(minHeight: 48)
                .contentShape(Capsule())
            }
            .buttonStyle(PressScale())
            GlassIconButton(icon: .shuffle, label: "Shuffle", action: shuffle)
        }
    }
}

/// A round glass button with an icon: 34 across in a 48 target, lit while `lit`.
struct GlassIconButton: View {
    let icon: OctoIcon
    let label: String
    var lit = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconView(icon, size: 17, color: .white)
                .frame(width: 34, height: 34)
                .glassEffect(lit ? LibraryLook.lifted : LibraryLook.resting, in: .circle)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
                .animation(.easeInOut(duration: 0.16), value: icon)
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(label)
    }
}

/// A quiet action: an icon and a word in the secondary color, no glass. As a switch it turns
/// white while on.
struct QuietAction: View {
    let icon: OctoIcon
    let text: String
    var enabled = true
    var checked: Bool?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            QuietActionLabel(icon: icon, text: text, lit: checked == true)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.6)
        .accessibilityAddTraits(checked != nil ? .isToggle : [])
        .accessibilityValue(checked == nil ? "" : (checked == true ? "On" : "Off"))
    }
}

/// A quiet action's icon and words, also the label of a quiet menu button.
struct QuietActionLabel: View {
    let icon: OctoIcon
    let text: String
    var lit = false

    var body: some View {
        HStack(spacing: 6) {
            IconView(icon, size: 18)
            Text(text).font(LibraryLook.label).lineLimit(1)
        }
        .foregroundStyle(lit ? Color.white : OctoColor.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .contentShape(Capsule())
    }
}

/// The plain white icon at 80% in a 48 circle, no glass.
struct QuietIconAction: View {
    let icon: OctoIcon
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconView(icon, size: 22, color: .white.opacity(0.8))
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Centered spinner in the accent color, for a list before its first read.
struct LibrarySpinner: View {
    var body: some View {
        LoadingSpinner(size: 28)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }
}

/// A muted note under a page title, like an empty list's.
struct MutedNote: View {
    let text: String
    var horizontal: CGFloat = 20
    var vertical: CGFloat = 8

    init(_ text: String, horizontal: CGFloat = 20, vertical: CGFloat = 8) {
        self.text = text
        self.horizontal = horizontal
        self.vertical = vertical
    }

    var body: some View {
        Text(text)
            .font(.octoBodySmall)
            .foregroundStyle(OctoColor.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
    }
}

/// "Nothing here yet" and the ways to get music in.
struct EmptyLibraryNote: View {
    var text = "Nothing here yet"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(text).font(.octoBodySmall).foregroundStyle(OctoColor.textMuted)
            LibrarySourceActions()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }
}

/// Ways to get music in: "Allow access" while the phone's music is out of reach ("Open
/// settings" once the system no longer asks), and "Sign in to a server" while none is in use.
/// They wrap 12 apart; nothing shows when neither applies.
struct LibrarySourceActions: View {
    @Environment(Session.self) private var session
    @Environment(Router.self) private var router
    @Environment(DeviceLibrary.self) private var device

    var body: some View {
        let askAccess = device.access != .granted
        let signIn = session.client == nil
        if askAccess || signIn {
            FlowRow(spacing: 12) {
                if askAccess {
                    GlazeButton(accessButtonLabel(deniedForever: device.access == .deniedForever)) {
                        if device.access == .deniedForever { device.openSettings() } else { device.requestAccess() }
                    }
                }
                if signIn {
                    GlazeButton("Sign in to a server") { router.signIn = .signIn }
                }
            }
        }
    }
}

/// The page title with its buttons at the end of the same line. The title is never shortened or
/// wrapped: when the two do not fit side by side, the buttons move to their own line under it.
struct TitleWithButtons<Buttons: View>: View {
    let title: String
    @ViewBuilder var buttons: Buttons

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 0) {
                titleText
                Spacer(minLength: 0)
                buttonsBox
            }
            VStack(alignment: .trailing, spacing: 0) {
                titleText.frame(maxWidth: .infinity, alignment: .leading)
                buttonsBox
            }
        }
    }

    private var titleText: some View {
        Text(title)
            .font(.octoDisplay)
            .tracking(-0.5)
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .accessibilityAddTraits(.isHeader)
    }

    private var buttonsBox: some View {
        HStack(spacing: 2) { buttons }
            .fixedSize()
            .padding(.trailing, 20)
            .padding(.bottom, 8)
    }
}

/// The order a list is in, as a small glass capsule: the sort mark, what it goes by, and an
/// arrow for which way it runs. A tap opens the system menu: the two directions on top, then the
/// options. Picking another option gives it in its own starting direction.
struct SortButton: View {
    let list: SortList
    @Environment(LibraryState.self) private var library

    var body: some View {
        let order = library.order(list)
        Menu {
            // The two directions, the option's own starting one first; another one reorders at once.
            Picker("Direction", selection: Binding(get: { order.descending },
                                                   set: { library.setOrder(list, ListOrder(order.by, descending: $0)) })) {
                ForEach(directionChoices(order.by), id: \.descending) { choice in
                    Label(choice.label, systemImage: choice.descending ? "arrow.down" : "arrow.up").tag(choice.descending)
                }
            }
            .pickerStyle(.palette)
            // Another option comes in its own starting direction.
            Picker("Sort by", selection: Binding(get: { order.by.id }, set: { id in
                guard let option = list.options.first(where: { $0.id == id }), option.id != order.by.id else { return }
                library.setOrder(list, order.picking(option))
            })) {
                ForEach(list.options, id: \.id) { option in Text(option.label).tag(option.id) }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 7) {
                IconView(.sort, size: 16, color: .white.opacity(0.72))
                Text(order.by.label)
                    .font(LibraryLook.labelMedium)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                IconView(.ascending, size: 14, color: .white.opacity(0.72))
                    .rotationEffect(.degrees(sortArrowTurn(descending: order.descending)))
                    .animation(.interpolatingSpring(stiffness: 300, damping: 2 * 0.7 * sqrt(300)), value: order.descending)
            }
            .padding(.leading, 12)
            .padding(.trailing, 11)
            .frame(height: 34)
            .glassEffect(LibraryLook.resting, in: .capsule)
            .frame(minHeight: 48)
            .contentShape(Capsule())
        }
        .menuOrder(.fixed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sorted by \(order.by.label), \(sortScale(order.by).label(descending: order.descending))")
        .accessibilityHint("Change the order")
        .accessibilityAddTraits(.isButton)
    }
}

/// A line above a list inside a page: an optional name on the left and the sort button at the
/// right.
struct SortBar: View {
    var name: String?
    let list: SortList

    var body: some View {
        HStack {
            if let name {
                Text(name).font(.octoSection).padding(.vertical, 10).accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 8)
            SortButton(list: list)
        }
        .padding(.horizontal, 20)
    }
}

/// A run's letter, as a small dark pill that sticks to the top while its rows scroll.
struct LetterHeading: View {
    let letter: Character

    var body: some View {
        HStack {
            Text(String(letter))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(OctoColor.textMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(minWidth: 26, minHeight: 26)
                .background(.black.opacity(0.55), in: Capsule())
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The letter rail along the right edge of a long list ordered by name. Touching or dragging
/// jumps the list to that letter with a light tick, and a glass bubble shows the letter.
struct LetterRail: View {
    let stops: [RailStop]
    let jump: (Int) -> Void
    @State private var touched: Int?
    @State private var shown: Character = "A"
    @State private var tick = 0

    var body: some View {
        GeometryReader { box in
            let slot = box.size.height / CGFloat(max(stops.count, 1))
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                        Text(String(stop.letter))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(touched == index ? Color.white : OctoColor.textMuted)
                            .frame(width: 24, height: slot)
                    }
                }
                .frame(width: 24)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let index = min(max(Int(value.location.y / box.size.height * CGFloat(stops.count)), 0), stops.count - 1)
                        guard stops.indices.contains(index), index != touched else { return }
                        touched = index
                        shown = stops[index].letter
                        tick += 1
                        jump(stops[index].index)
                    }
                    .onEnded { _ in touched = nil })
                if let touched {
                    Text(String(shown))
                        .font(.octoTitle)
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .glassEffect(Glass.octo, in: .circle)
                        .offset(x: -(24 + 16), y: slot * (CGFloat(touched) + 0.5) - 32)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.85).combined(with: .opacity).animation(.easeOut(duration: 0.12)),
                            removal: .scale(scale: 0.85).combined(with: .opacity).animation(.easeIn(duration: 0.18))))
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.12), value: touched == nil)
        }
        .frame(width: 24)
        .sensoryFeedback(.selection, trigger: tick)
        .accessibilityElement()
        .accessibilityLabel("Letters. Drag to jump through the list.")
        .accessibilityAdjustableAction { direction in
            let next = (touched ?? 0) + (direction == .increment ? 1 : -1)
            guard stops.indices.contains(next) else { return }
            touched = next
            jump(stops[next].index)
        }
    }
}

/// The favorite heart on album and artist pages: it beats once when added.
struct FavoriteHeart: View {
    let on: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            IconView(on ? .liked : .like, size: 24, color: on ? .white : .white.opacity(0.6))
                .shadow(color: on ? .white.opacity(0.5) : .clear, radius: 6)
                .iconAccent(on ? .pulse : nil, trigger: on)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Favorite")
        .accessibilityValue(on ? "In favorites" : "Not in favorites")
    }
}

/// A filter chip: the selected pill with white words while on, a faint fill with secondary
/// words while off.
struct FilterChip: View {
    let text: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            chipLabel(text, on: on)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected, .isToggle] : .isToggle)
    }
}

func chipLabel(_ text: String, on: Bool) -> some View {
    Text(text)
        .font(LibraryLook.label)
        .lineLimit(1)
        .foregroundStyle(on ? Color.white : OctoColor.textSecondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 36)
        .background(on ? LibraryLook.accentSelected : Color.white.opacity(0.07), in: Capsule())
}

/// A few choices side by side, as the system's segmented control.
struct GlassSegments<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.value) { option in Text(option.label).tag(option.value) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}
