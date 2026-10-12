import Observation
import OctoKit
import SwiftUI

// MARK: The pop-up card

/// A free-floating glass card beside the control that opened it, or in the middle of the
/// screen when there is none. It grows from the corner nearest the control, keeps 12 points
/// from every edge, the bars and the keyboard, is at most `maxWidth` wide and `heightShare` of
/// the screen tall, and closes on a tap that starts and ends off it.
struct GlassPopupFrame: View {
    let popup: Overlays.Popup
    let onGone: () -> Void
    @State private var shown = false
    @State private var cardSize: CGSize = .zero
    @Environment(\.motionScale) private var motion
    @Environment(\.accessibilityReduceMotion) private var systemCalm

    var body: some View {
        GeometryReader { box in
            let insets = box.safeAreaInsets
            // The whole screen, with the bars and the keyboard as edges to keep clear of.
            let window = CGSize(width: box.size.width + insets.leading + insets.trailing,
                                height: box.size.height + insets.top + insets.bottom)
            let margin = CGFloat(PopupMeasures.edgeMargin)
            let widest = max(0, min(popup.maxWidth, window.width - margin * 2))
            let room = window.height - insets.top - insets.bottom - margin * 2
            let tallest = max(0, min(window.height * popup.heightShare, room))
            let spot = place(window: window, top: insets.top, bottom: insets.bottom)
            ZStack(alignment: .topLeading) {
                // A tap off the card closes it; a drag does not.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { if popup.visible { popup.dismiss() } }
                    .gesture(edgeBack)
                GlassPopupCard(width: .fit(min: 0, max: widest), maxWidth: widest, maxHeight: tallest) { popup.content }
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { cardSize = $0 }
                    .scaleEffect(scale, anchor: UnitPoint(x: spot.origin.x, y: spot.origin.y))
                    .opacity(cardSize == .zero ? 0 : (shown ? 1 : 0))
                    .offset(x: spot.x, y: spot.y)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(popup.title ?? "")
                    .accessibilityAddTraits(.isModal)
            }
            .ignoresSafeArea(.container)
        }
        .onAppear { if popup.visible { appear() } }
        .onChange(of: popup.visible) { _, visible in visible ? appear() : leave() }
    }

    private var scale: CGFloat {
        if systemCalm || motion.still { return 1 }
        return shown ? 1 : 0.92
    }

    private func place(window: CGSize, top: CGFloat, bottom: CGFloat) -> PopupSpot {
        let spot = placePopup(anchor: popup.anchor.map(PopupRect.init), size: PopupSize(cardSize.width, cardSize.height),
                              window: PopupSize(window.width, window.height), margin: PopupMeasures.edgeMargin,
                              gap: PopupMeasures.anchorGap, top: top, bottom: bottom, keepAbove: popup.placing.keepAbove)
        if cardSize != .zero, popup.placing.keepAbove == nil, !spot.centered {
            popup.placing.keepAbove = spot.above
        }
        return spot
    }

    private var timing: Animation? {
        systemCalm ? nil : .octoTween(OctoDuration.swap, scale: motion)
    }

    private func appear() {
        withAnimation(timing) { shown = true }
        AccessibilityNotification.ScreenChanged().post()
    }

    private func leave() {
        withAnimation(timing) { shown = false } completion: { if !popup.visible { onGone() } }
    }

    /// The screen's left edge still goes back while a pop-up is open.
    private var edgeBack: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { drag in
                guard drag.startLocation.x < 24, drag.translation.width > 60 else { return }
                if !popup.back() { popup.dismiss() }
            }
    }
}

// MARK: Pages

/// The pages of one pop-up. Opening it again starts at its first page.
@MainActor
@Observable
final class PopupPages<Page: Equatable> {
    private(set) var trail: PageTrail<Page>

    init(_ first: Page) { trail = .of(first) }

    var current: Page { trail.current }
    var canGoBack: Bool { trail.canGoBack }

    func open(_ page: Page) { trail = trail.open(page) }
    func replace(_ page: Page) { trail = trail.replace(page) }

    /// Answers whether there was a page to go back to, so back closes the pop-up only from its
    /// first page.
    @discardableResult
    func back() -> Bool {
        let had = trail.canGoBack
        trail = trail.back()
        return had
    }

    func reset(_ first: Page) { trail = trail.restart(first) }
}

/// Shows a pop-up's current page. A new page slides in a third of the width from the side it
/// is going while the card eases to its size; back slides the other way. With Reduce motion the
/// pages only fade and the card takes its new size at once.
struct PopupPager<Page: Equatable, Content: View>: View {
    let pages: PopupPages<Page>
    @ViewBuilder let content: (Page, Bool) -> Content
    @Environment(\.motionScale) private var motion
    @Environment(\.accessibilityReduceMotion) private var systemCalm
    @State private var width: CGFloat = 288

    var body: some View {
        let trail = pages.trail
        let still = motion.still || systemCalm
        let way: CGFloat = trail.deeper ? 1 : -1
        ZStack(alignment: .topLeading) {
            content(trail.current, trail.canGoBack)
                .id(PageKey(opening: trail.opening, depth: trail.pages.count))
                .transition(still ? .opacity : .asymmetric(
                    insertion: .offset(x: way * width / 3)
                        .combined(with: .opacity.animation(.octoTween(OctoDuration.fill, scale: motion, delay: 40))),
                    removal: .offset(x: -way * width / 3)
                        .combined(with: .opacity.animation(.octoTween(OctoDuration.press, scale: motion)))))
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .clipped()
        .animation(still ? .octoTween(OctoDuration.swap, scale: motion) : .octo(OctoSprings.calm), value: PageKey(opening: trail.opening, depth: trail.pages.count))
    }

    private struct PageKey: Hashable {
        let opening: Int
        let depth: Int
    }
}

// MARK: Menu kit

/// A glass menu's measures.
enum GlassMenu {
    static let width = CGFloat(PopupMeasures.menuWidth)
    static let optionShape = RoundedRectangle(cornerRadius: 14, style: .continuous)
}

/// A page of a glass menu: a heading that stays put, then the rest, which scrolls when it is
/// taller than the menu may be.
struct GlassMenuPage<Header: View, Body: View>: View {
    var width: CGFloat = GlassMenu.width
    @ViewBuilder var header: Header
    @ViewBuilder var content: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            HuggingScroll { VStack(alignment: .leading, spacing: 0) { content } }
        }
        .frame(width: width)
        .padding(6)
    }
}

extension GlassMenuPage where Header == EmptyView {
    init(width: CGFloat = GlassMenu.width, @ViewBuilder content: () -> Body) {
        self.init(width: width, header: { EmptyView() }, content: content)
    }
}

/// Content that takes its own height, and scrolls when that is more than there is room for,
/// with a mark at its foot while there is more below.
struct HuggingScroll<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var atBottom = false

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView {
                content
            }
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 2
            } action: { _, bottom in
                atBottom = bottom
            }
            .overlay(alignment: .bottom) { MoreBelow().opacity(atBottom ? 0 : 1).animation(.easeOut(duration: 0.2), value: atBottom) }
        }
    }
}

/// A quiet mark at the foot of a scrolling pop-up or sheet saying there is more under it.
struct MoreBelow: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, Color.black.opacity(0.35)], startPoint: .top, endPoint: .bottom).frame(height: 28)
            Image(systemName: "chevron.compact.down")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(OctoColor.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)
                .background(Color.black.opacity(0.35))
        }
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("More below")
    }
}

/// How wide a pop-up's card is: as wide as its content within a range, or a set width.
enum PopupWidth {
    case fit(min: CGFloat, max: CGFloat)
    case fixed(CGFloat)
}

/// The glass card every pop-up sits in: 20 point corners, Liquid Glass with the menu's darker
/// film, a shadow pooled under it, a dark halo and an inner hairline. As wide as its content
/// within `width` (never more than `maxWidth`), and as tall as its content up to `maxHeight`,
/// past which the content's own `HuggingScroll` scrolls.
struct GlassPopupCard<Content: View>: View {
    var width: PopupWidth = .fit(min: 0, max: CGFloat(PopupMeasures.maxWidth))
    let maxWidth: CGFloat
    let maxHeight: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CGFloat(PopupMeasures.corner), style: .continuous)
        CardWidth(width: width, maxWidth: maxWidth, maxHeight: maxHeight) { content }
            // Floating glass with the menu plate's edges: the shadow pooled under it, an even
            // dark halo all round, and a faint light hairline just inside the rim, so its words
            // stay legible over a busy page.
            .floatingGlass(shape, film: OctoColor.popupFilm, halo: true)
            .overlay { shape.strokeBorder(Color.white.opacity(0.06), lineWidth: 1).allowsHitTesting(false) }
    }
}

/// Lays its content out as wide as it would like to be within a range (or at a set width), and
/// then as tall as it needs at that width, so wrapped lines are measured where they wrap.
private struct CardWidth: Layout {
    let width: PopupWidth
    let maxWidth: CGFloat
    let maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let w = chosenWidth(child)
        let size = child.sizeThatFits(ProposedViewSize(width: w, height: maxHeight))
        return CGSize(width: w, height: min(size.height, maxHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }

    private func chosenWidth(_ child: LayoutSubview) -> CGFloat {
        switch width {
        case .fixed(let w): return min(w, maxWidth)
        case .fit(let low, let high):
            let ideal = child.sizeThatFits(.unspecified).width
            return min(min(max(ideal, low), high), maxWidth)
        }
    }
}

/// A row under the finger shows the quiet accent-tinted pill at once, in place of a ripple.
private struct MenuRowPress: ButtonStyle {
    var shows = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if configuration.isPressed && shows { GlassMenu.optionShape.fill(OctoColor.menuPress) }
            }
    }
}

/// One answer to a choice: its name, and a line about it. One not `enabled` shows dimmed, its
/// detail saying why, and cannot be picked.
struct Choice: Hashable, Sendable {
    let label: String
    var detail: String?
    var enabled = true

    init(_ label: String, detail: String? = nil, enabled: Bool = true) {
        self.label = label
        self.detail = detail
        self.enabled = enabled
    }
}

/// The options of a menu, one above the other with hairlines between, the chosen one in the
/// darker pill with a white check. `selected` below zero means none is chosen, as when the menu
/// asks for an action.
struct GlassMenuOptions: View {
    let options: [Choice]
    let selected: Int
    let onPick: (Int) -> Void

    var body: some View {
        let looks = menuRowLooks(count: options.count, selected: selected)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                if index > 0 {
                    // Always 1 point, drawn or not, so the rows never shift.
                    (looks[index].lineAbove ? OctoColor.hairline : Color.clear)
                        .frame(height: 1)
                        .padding(.horizontal, 14)
                }
                MenuOption(option: option, selected: looks[index].selected, pickable: selected >= 0) { onPick(index) }
            }
        }
    }
}

private struct MenuOption: View {
    let option: Choice
    let selected: Bool
    let pickable: Bool
    let onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(option.label)
                        .font(.octoBodySmall)
                        .foregroundStyle(option.enabled ? Color.white : OctoColor.textMuted)
                    if let detail = option.detail {
                        Text(detail).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // The check's room is kept on every line, so the width does not depend on the choice.
                if selected {
                    IconView(.check, size: 18, color: .white)
                } else if pickable {
                    Color.clear.frame(width: 18, height: 18)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: CGFloat(MenuRowHeight.touch))
            .background { if selected { GlazeSelected(shape: GlassMenu.optionShape) } }
            .contentShape(GlassMenu.optionShape)
        }
        .buttonStyle(MenuRowPress(shows: !selected))
        .disabled(!option.enabled)
        .accessibilityAddTraits(pickable && selected ? .isSelected : [])
    }
}

/// A quiet heading at the top of a menu.
struct GlassMenuTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.octoLabel)
            .foregroundStyle(OctoColor.textSecondary)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One action in a glass menu: a white icon, what it does, and a line about it. One that cannot
/// be chosen right now is dimmed; one that opens a page shows a chevron; a destructive one says
/// so in soft red words, its icon still white.
struct GlassMenuAction: View {
    let icon: OctoIcon?
    let label: String
    var detail: String?
    var enabled = true
    var opensPage = false
    var destructive = false
    let action: () -> Void

    init(_ icon: OctoIcon?, _ label: String, detail: String? = nil, enabled: Bool = true, opensPage: Bool = false,
         destructive: Bool = false, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.detail = detail
        self.enabled = enabled
        self.opensPage = opensPage
        self.destructive = destructive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if let icon { IconView(icon, size: 20, color: enabled ? .white : OctoColor.textMuted) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(label)
                        .font(.octoBodySmall)
                        .foregroundStyle(!enabled ? OctoColor.textMuted : destructive ? OctoColor.destructive : .white)
                    if let detail { Text(detail).font(.octoCaption).foregroundStyle(OctoColor.textMuted) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if opensPage { IconView(.chevron, size: 18, color: OctoColor.textMuted) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: CGFloat(MenuRowHeight.touch))
            .contentShape(GlassMenu.optionShape)
        }
        .buttonStyle(MenuRowPress(shows: enabled))
        .disabled(!enabled)
    }
}

/// What a menu is about, at its top: a small picture, a name, and a line under it.
struct GlassMenuHeader<Picture: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var picture: Picture

    var body: some View {
        HStack(spacing: 12) {
            picture
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.octo(14, .semibold, .subheadline)).foregroundStyle(.white).lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.octoCaption).foregroundStyle(OctoColor.textMuted).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}

/// The top of a page opened from a menu: a small back chevron and the page's name.
struct GlassMenuBack: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    IconView(.chevronBack, size: 18, color: .white)
                    Text(title)
                        .font(.octoLabel)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.leading, 6)
                .padding(.trailing, 14)
                .frame(minHeight: CGFloat(MenuRowHeight.touch))
                .contentShape(GlassMenu.optionShape)
            }
            .buttonStyle(MenuRowPress())
            .accessibilityLabel(title)
            .accessibilityHint("Back")
            GlassMenuSeparator()
        }
    }
}

/// A heading for a menu page that has nothing to go back to.
struct GlassMenuHeading: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.octoLabel)
            .foregroundStyle(.white)
            .lineLimit(2)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The hairline between two groups of a menu.
struct GlassMenuSeparator: View {
    var body: some View {
        OctoColor.hairline
            .frame(height: 1)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
    }
}

/// Groups of rows, a hairline between one group and the next and none inside a group. Empty
/// groups are left out.
struct GlassMenuGroups<Item, Row: View>: View {
    let groups: [[Item]]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        let kept = groups.filter { !$0.isEmpty }
        ForEach(Array(kept.enumerated()), id: \.offset) { index, group in
            if index > 0 { GlassMenuSeparator() }
            ForEach(Array(group.enumerated()), id: \.offset) { _, item in row(item) }
        }
    }
}

/// A quiet line of words inside a menu, for a note or an empty list.
struct GlassMenuNote: View {
    let text: String
    var color: Color = OctoColor.textMuted

    init(_ text: String, color: Color = OctoColor.textMuted) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text).font(.octoCaption).foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
    }
}

// MARK: Questions and choices

/// A question in a glass pop-up: what is asked, a line about it, anything more it needs to
/// show, then the answers as buttons, the first one lit.
struct PopupQuestion<More: View>: View {
    let title: String
    var detail: String?
    let confirm: String
    var cancel = "Cancel"
    var width: CGFloat = GlassMenu.width
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @ViewBuilder var more: More

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.octoBody)
                .foregroundStyle(.white)
                .lineLimit(3)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail).font(.octoBodySmall).foregroundStyle(OctoColor.textMuted).padding(.top, 6)
            }
            more
            HStack(spacing: 10) {
                AccentButton(confirm, action: onConfirm)
                GlazeButton(cancel, action: onCancel)
            }
            .padding(.top, 18)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(width: width, alignment: .leading)
    }
}

extension PopupQuestion where More == EmptyView {
    init(title: String, detail: String? = nil, confirm: String, cancel: String = "Cancel", width: CGFloat = GlassMenu.width,
         onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.init(title: title, detail: detail, confirm: confirm, cancel: cancel, width: width,
                  onConfirm: onConfirm, onCancel: onCancel, more: { EmptyView() })
    }
}

/// A name to type in a glass pop-up, its button beside the field. The keyboard opens as it
/// appears; the button waits until `ready` says the name will do; `note` says why not.
struct PopupNameField: View {
    let placeholder: String
    let action: String
    let onDone: (String) -> Void
    var initial = ""
    var capitalization: TextInputAutocapitalization = .sentences
    var ready: (String) -> Bool = { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    var note: (String) -> String? = { _ in nil }
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        let canDo = ready(name)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                TextField(placeholder, text: $name)
                    .font(.octoBody)
                    .foregroundStyle(.white)
                    .tint(OctoColor.accent)
                    .textInputAutocapitalization(capitalization)
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit { if canDo { onDone(name) } }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(OctoColor.accent.opacity(focused ? 0.15 : 0.10)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(OctoColor.accent.opacity(0.10), lineWidth: 1))
                AccentButton(action, enabled: canDo) { onDone(name) }
            }
            if let line = note(name) {
                Text(line).font(.octoCaption).foregroundStyle(OctoColor.textMuted).padding(.top, 8).padding(.leading, 4)
            }
        }
        .onAppear {
            name = initial
            focused = true
        }
    }
}

/// A page that asks for a name: its heading, or a way back when it was opened from another page,
/// then the field.
struct PopupNameForm: View {
    let title: String
    let placeholder: String
    let action: String
    var onBack: (() -> Void)?
    let onDone: (String) -> Void
    var initial = ""
    var capitalization: TextInputAutocapitalization = .sentences
    var ready: (String) -> Bool = { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    var note: (String) -> String? = { _ in nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let onBack { GlassMenuBack(title: title, onBack: onBack) } else { GlassMenuHeading(title) }
            PopupNameField(placeholder: placeholder, action: action, onDone: onDone, initial: initial,
                           capitalization: capitalization, ready: ready, note: note)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 10)
        }
        .frame(width: GlassMenu.width)
        .padding(6)
    }
}

/// Questions any page can ask over everything, the bar included: a few answers popping up
/// beside the control that asked (marked with `choiceAnchor()`), or in the middle of the screen;
/// or a question with a confirm and a cancel button.
@MainActor
@Observable
final class Prompts {
    struct ChoiceRequest {
        let id = UUID()
        let title: String
        let choices: [Choice]
        /// The chosen answer, or below zero when the answers are actions.
        let selected: Int
        let onPick: (Int) -> Void
        let anchor: CGRect?
    }

    struct QuestionRequest {
        let id = UUID()
        let title: String
        let detail: String?
        let confirm: String
        let cancel: String
        let onConfirm: () -> Void
        let onCancel: () -> Void
        let anchor: CGRect?
    }

    private(set) var choice: ChoiceRequest?
    private(set) var question: QuestionRequest?
    @ObservationIgnored weak var spots: PressSpots?

    /// Asks `title` with `choices`; `onPick` gets the index picked. Picking closes the list.
    func choose(_ title: String, _ choices: [Choice], selected: Int = -1, anchor: CGRect? = nil,
                onPick: @escaping (Int) -> Void) {
        choice = ChoiceRequest(title: title, choices: choices, selected: selected, onPick: onPick,
                               anchor: anchor ?? spots?.takeRecentChoice())
    }

    /// Asks before doing something: `confirm` runs `onConfirm`; cancel or a tap outside does nothing.
    func confirm(_ title: String, detail: String? = nil, confirm: String, cancel: String = "Cancel",
                 anchor: CGRect? = nil, onCancel: @escaping () -> Void = {}, onConfirm: @escaping () -> Void) {
        question = QuestionRequest(title: title, detail: detail, confirm: confirm, cancel: cancel,
                                   onConfirm: onConfirm, onCancel: onCancel, anchor: anchor ?? spots?.recent())
    }

    func closeChoice() { choice = nil }
    func closeQuestion() { question = nil }
}

/// Puts the open choice and question on screen, through the shell's pop-ups.
struct PromptsHost: View {
    @Environment(Prompts.self) private var prompts
    @State private var lastChoice: Prompts.ChoiceRequest?
    @State private var lastQuestion: Prompts.QuestionRequest?

    var body: some View {
        Color.clear
            .glassPopup(isPresented: Binding(get: { prompts.choice != nil }, set: { if !$0 { prompts.closeChoice() } }),
                        title: (prompts.choice ?? lastChoice)?.title, anchor: (prompts.choice ?? lastChoice)?.anchor,
                        usesPressSpot: false, revision: prompts.choice?.id) {
                if let request = prompts.choice ?? lastChoice {
                    PromptChoiceList(request: request) { prompts.closeChoice() }
                }
            }
            .glassPopup(isPresented: Binding(get: { prompts.question != nil }, set: { if !$0 { prompts.closeQuestion() } }),
                        title: (prompts.question ?? lastQuestion)?.title, anchor: (prompts.question ?? lastQuestion)?.anchor,
                        usesPressSpot: false, revision: prompts.question?.id) {
                if let request = prompts.question ?? lastQuestion {
                    PopupQuestion(title: request.title, detail: request.detail, confirm: request.confirm, cancel: request.cancel,
                                  onConfirm: {
                                      prompts.closeQuestion()
                                      request.onConfirm()
                                  },
                                  onCancel: {
                                      prompts.closeQuestion()
                                      request.onCancel()
                                  })
                }
            }
            .onChange(of: prompts.choice?.id, initial: true) { if let choice = prompts.choice { lastChoice = choice } }
            .onChange(of: prompts.question?.id, initial: true) { if let question = prompts.question { lastQuestion = question } }
            .allowsHitTesting(false)
    }
}

/// The answers under the question, 220 to 320 points wide, as wide as the widest line, the
/// current one in the darker pill. Picking one runs it and closes the list.
private struct PromptChoiceList: View {
    let request: Prompts.ChoiceRequest
    let close: () -> Void

    var body: some View {
        ClampedWidth(min: CGFloat(PopupMeasures.choiceMinWidth), max: CGFloat(PopupMeasures.choiceMaxWidth)) {
            VStack(alignment: .leading, spacing: 0) {
                GlassMenuTitle(request.title)
                HuggingScroll {
                    GlassMenuOptions(options: request.choices, selected: request.selected) { index in
                        request.onPick(index)
                        close()
                    }
                }
            }
            .padding(6)
        }
    }
}

/// Lays its content at its natural width, kept between `min` and `max`.
struct ClampedWidth: Layout {
    let min: CGFloat
    let max: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let view = subviews.first else { return .zero }
        let width = Swift.min(Swift.max(view.sizeThatFits(.unspecified).width, min), Swift.min(max, proposal.width ?? max))
        let height = view.sizeThatFits(ProposedViewSize(width: width, height: proposal.height)).height
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}
