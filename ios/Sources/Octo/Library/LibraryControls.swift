import OctoKit
import SwiftUI

/// The tokens the library pages use beyond the shared palette.
enum LibraryLook {
    /// A selected row: the accent 40% of the way out of black.
    static let accentSelected = Color.black.mix(with: OctoColor.accent, by: 0.4)
    /// A hairline between rows.
    static let hairline = Color.white.opacity(0.08)
    /// The small bold words of buttons and chips.
    static let label = Font.system(size: 13.5, weight: .semibold)
    static let labelMedium = Font.system(size: 13.5, weight: .medium)
    /// Lifted glass: a little brighter than the resting glass, for the main button of a pair.
    static let lifted = Glass.regular.tint(.white.opacity(0.14)).interactive()
    static let resting = Glass.regular.interactive()
}

/// Pressed, a control shrinks a little on a quick spring; no ripple or highlight.
struct PressScale: ButtonStyle {
    var amount: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? amount : 1)
            .animation(.interpolatingSpring(stiffness: 600, damping: 2 * 0.45 * sqrt(600)), value: configuration.isPressed)
    }
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
                capsule("Play", icon: "play.fill", glass: LibraryLook.lifted, spinner: loading, action: play)
                capsule("Shuffle", icon: "shuffle", glass: LibraryLook.resting, spinner: false, action: shuffle)
            }
        }
        .disabled(!enabled || loading)
        .opacity(enabled || loading ? 1 : 0.4)
    }

    private func capsule(_ word: String, icon: String, glass: Glass, spinner: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if spinner {
                    ProgressView().tint(.white).controlSize(.small).frame(width: 22, height: 22)
                } else {
                    Image(systemName: icon).font(.system(size: 18, weight: .semibold)).frame(width: 22, height: 22)
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
        .buttonStyle(PressScale(amount: 0.96))
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
                    Image(systemName: "play.fill").font(.system(size: 14, weight: .semibold)).frame(width: 18, height: 18)
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
            GlassIconButton(icon: "shuffle", label: "Shuffle", action: shuffle)
        }
    }
}

/// A round glass button with an icon: 34 across in a 48 target, lit while `lit`.
struct GlassIconButton: View {
    let icon: String
    let label: String
    var lit = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
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
    let icon: String
    let text: String
    var enabled = true
    var checked: Bool?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 15)).frame(width: 18, height: 18)
                Text(text).font(LibraryLook.label).lineLimit(1)
            }
            .foregroundStyle(checked == true ? Color.white : OctoColor.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.6)
        .accessibilityAddTraits(checked != nil ? .isToggle : [])
        .accessibilityValue(checked == nil ? "" : (checked == true ? "On" : "Off"))
    }
}

/// A small text button: the label words in the secondary color, no fill.
struct QuietButton: View {
    let text: String
    let action: () -> Void

    init(_ text: String, action: @escaping () -> Void) {
        self.text = text
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(LibraryLook.label)
                .foregroundStyle(OctoColor.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The plain white icon at 80% in a 48 circle, no glass.
struct QuietIconAction: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 19))
                .foregroundStyle(.white.opacity(0.8))
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
        ProgressView()
            .tint(OctoColor.accent)
            .controlSize(.regular)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }
}

/// A failure in place of a page: the message, then "Try again".
struct LibraryFailure: View {
    let message: String
    let retry: () async -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(message)
                .font(.octoBodySmall)
                .foregroundStyle(OctoColor.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await retry() } }
                .buttonStyle(.glassProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
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
    @Environment(Session.self) private var session
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(text).font(.octoBodySmall).foregroundStyle(OctoColor.textMuted)
            LibrarySourceActions()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }
}

/// Ways to get music in: "Sign in to a server" while none is set up, and the phone's music
/// once the phone's library can be asked for. Nothing when neither applies.
struct LibrarySourceActions: View {
    @Environment(Session.self) private var session
    @Environment(Router.self) private var router

    var body: some View {
        if session.servers.isEmpty || session.client == nil && session.active == nil {
            Button("Sign in to a server") { router.signIn = .signIn }
                .buttonStyle(.glass)
                .font(.octoBodySmall)
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
/// arrow for which way it runs. A tap opens the sort list beside it: the two directions on top,
/// then the options. Picking another option gives it in its own starting direction.
struct SortButton: View {
    let list: SortList
    @Environment(LibraryState.self) private var library

    var body: some View {
        let order = library.order(list)
        Menu {
            Section {
                Picker("Direction", selection: Binding(
                    get: { order.descending },
                    set: { library.setOrder(list, ListOrder(order.by, descending: $0)) })
                ) {
                    ForEach(directionChoices(order.by), id: \.descending) { choice in
                        Label(choice.label, systemImage: choice.descending ? "arrow.down" : "arrow.up").tag(choice.descending)
                    }
                }
                .pickerStyle(.palette)
            }
            Section {
                Picker("Sort by", selection: Binding(
                    get: { order.by.id },
                    set: { id in
                        guard let option = list.options.first(where: { $0.id == id }) else { return }
                        library.setOrder(list, order.picking(option))
                    })
                ) {
                    ForEach(list.options, id: \.id) { option in Text(option.label).tag(option.id) }
                }
                .pickerStyle(.inline)
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 16, height: 16)
                Text(order.by.label)
                    .font(LibraryLook.labelMedium)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 14, height: 14)
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
        .buttonStyle(PressScale())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sorted by \(order.by.label), \(sortScale(order.by).label(descending: order.descending))")
        .accessibilityHint("Change the order")
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
                        .glassEffect(.regular, in: .circle)
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
            Image(systemName: on ? "heart.fill" : "heart")
                .font(.system(size: 22))
                .foregroundStyle(on ? .white : .white.opacity(0.6))
                .shadow(color: on ? .white.opacity(0.5) : .clear, radius: 6)
                .symbolEffect(.bounce, value: on)
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

/// Segments in one glass, the chosen one in a gliding pill with its words in the accent.
struct GlassSegments<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let chosen = option.value == selection
                Button {
                    withAnimation(.interpolatingSpring(stiffness: 350, damping: 2 * 0.8 * sqrt(350))) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(LibraryLook.label)
                        .foregroundStyle(chosen ? OctoColor.accent : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if chosen {
                                Capsule().fill(LibraryLook.accentSelected).matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
    }
}
