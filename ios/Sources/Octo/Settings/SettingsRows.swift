import OctoKit
import SwiftUI

extension Font {
    /// The quiet label size: group titles and small headings.
    static let settingsLabel = Font.system(size: 13.5, weight: .semibold)
}

/// The icons the settings pages use, by what they stand for.
enum SettingsIcon {
    static let playback = "play.circle"
    static let sound = "slider.horizontal.3"
    static let appearance = "paintpalette"
    static let library = "rectangle.stack"
    static let cloud = "cloud"
    static let download = "arrow.down.circle"
    static let audioQuality = "slider.vertical.3"
    static let lyrics = "music.mic"
    static let scrobbling = "chart.line.uptrend.xyaxis"
    static let backup = "archivebox"
    static let info = "info.circle"
    static let phone = "iphone"
    static let radio = "dot.radiowaves.left.and.right"
    static let headphones = "headphones"
    static let cast = "airplay.audio"
    static let layout = "rectangle.3.group"
    static let home = "house"
    static let playlists = "music.note.list"
    static let sparkle = "sparkle"
    static let addToLibrary = "plus"
    static let folder = "folder"
    static let timer = "timer"
    static let wifi = "wifi"
    static let storage = "cylinder.split.1x2"
    static let listeners = "person.3"
    static let key = "key"
    static let sync = "arrow.triangle.2.circlepath"
    static let chevron = "chevron.right"
    static let search = "magnifyingglass"
    static let close = "xmark"
    static let check = "checkmark"
    static let liked = "heart.fill"
}

// MARK: Highlight of a searched-for row

/// The row a search result pointed at, lit briefly once its page opens. Shown once, then done,
/// so coming back to the page does not light it again.
struct SettingsHighlight {
    var id: String?
    var onShown: () -> Void = {}
    var scroll: (String) -> Void = { _ in }
}

private struct SettingsHighlightKey: EnvironmentKey {
    static var defaultValue: SettingsHighlight { SettingsHighlight() }
}

extension EnvironmentValues {
    var settingsHighlight: SettingsHighlight {
        get { self[SettingsHighlightKey.self] }
        set { self[SettingsHighlightKey.self] = newValue }
    }
}

/// How long the pointed-at row waits for the page to settle, and stays lit.
private let settleMs = 350
private let holdMs = 900

/// The accent wash a searched-for row wears for a moment.
private struct HighlightWash: ViewModifier {
    let entry: SettingEntry?
    @Environment(\.settingsHighlight) private var highlight
    @State private var glow = 0.0

    func body(content: Content) -> some View {
        Group {
            if let id = entry?.id {
                content.id(id)
            } else {
                content
            }
        }
        .background(OctoColor.accent.opacity(0.14 * glow))
        .task(id: highlight.id) {
            guard let entry, highlight.id == entry.id else { return }
            // Marking it shown clears the page's highlight, so the light runs on a task of its
            // own that this one ending does not stop.
            let scroll = highlight.scroll
            highlight.onShown()
            Task {
                try? await Task.sleep(for: .milliseconds(settleMs))
                withAnimation(.easeInOut(duration: 0.3)) { scroll(entry.id) }
                withAnimation(.easeOut(duration: 0.25)) { glow = 1 }
                try? await Task.sleep(for: .milliseconds(250 + holdMs))
                withAnimation(.easeInOut(duration: 0.7)) { glow = 0 }
            }
        }
    }
}

// MARK: Page frame

/// A settings page: the back button, the large title, and its groups one under another, 24
/// apart. `highlight` is the row a search result pointed at.
struct SettingsPageFrame<Content: View>: View {
    let title: String
    var highlight: String?
    @ViewBuilder let content: () -> Content
    /// Lit once per visit from search, not again on coming back to the page.
    @State private var shown = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScreenTitle(title)
                    VStack(spacing: 24) { content() }
                }
                .padding(.top, 8 + detailTopGap)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .barClearance()
            .background { PageBackdrop(page: .settingsPage, route: nil) }
            .environment(\.settingsHighlight, SettingsHighlight(
                id: shown ? nil : highlight,
                onShown: { shown = true },
                scroll: { id in proxy.scrollTo(id, anchor: .center) }
            ))
        }
        .detailPage()
    }
}

// MARK: Group

/// Rows in one raised panel, a hairline between each. A row that draws nothing takes no place
/// and gets no line. The lines start under the text, so rows with icon tiles pass a deeper
/// inset. A title sits above the panel as a quiet capitalized label, led by the group's icon
/// (a brand mark keeps its own colors).
struct SettingsGroup<Content: View, Mark: View>: View {
    var title: String?
    var footer: String?
    var inset: CGFloat = 16
    @ViewBuilder var mark: () -> Mark
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack(spacing: 7) {
                    mark()
                    Text(title.uppercased())
                        .font(.settingsLabel)
                        .tracking(0.6)
                        .foregroundStyle(OctoColor.textMuted)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityAddTraits(.isHeader)
            }
            Group(subviews: content()) { rows in
                if !rows.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            if index > 0 { Hairline(inset: inset) }
                            row
                        }
                    }
                    .raisedPanel()
                }
            }
            if let footer {
                Text(footer)
                    .font(.octoCaption)
                    .foregroundStyle(OctoColor.textMuted)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
    }
}

extension SettingsGroup where Mark == EmptyView {
    init(title: String? = nil, footer: String? = nil, inset: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, footer: footer, inset: inset, mark: { EmptyView() }, content: content)
    }
}

extension SettingsGroup where Mark == AnyView {
    /// A group led by a tinted icon.
    init(title: String, icon: String, footer: String? = nil, inset: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, footer: footer, inset: inset, mark: {
            AnyView(Image(systemName: icon).font(.system(size: 13)).frame(width: 15, height: 15).foregroundStyle(OctoColor.textMuted))
        }, content: content)
    }
}

/// One physical pixel, starting under the rows' text.
private struct Hairline: View {
    let inset: CGFloat
    @Environment(\.displayScale) private var scale

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(height: 1 / scale)
            .padding(.leading, inset)
    }
}

extension View {
    /// The raised panel settings rows sit in: a surface a step above the page, a faint rim and a
    /// light along its top edge, and a soft shadow under it.
    func raisedPanel(cornerRadius: CGFloat = 20) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(OctoColor.surfaceRaised, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
            .overlay(alignment: .top) {
                shape.stroke(Color.white.opacity(0.06), lineWidth: 1).offset(y: 1).mask(shape).allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.20), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
    }
}

// MARK: Rows

/// What every row shares: its height and padding, and the brief light when search pointed at it.
struct RowFrame<Content: View>: View {
    var entry: SettingEntry?
    var minHeight: CGFloat = 56
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 12) { content() }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .contentShape(Rectangle())
            .modifier(HighlightWash(entry: entry))
    }
}

/// A title with an optional line under it, taking the row's spare width.
private struct RowLabel: View {
    let title: String
    var below: String?
    var enabled = true
    var titleColor: Color = OctoColor.textPrimary
    var belowColor: Color = OctoColor.textMuted

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.octoBody).foregroundStyle(enabled ? titleColor : OctoColor.textMuted).fixedSize(horizontal: false, vertical: true)
            if let below {
                Text(below).font(.octoCaption).foregroundStyle(belowColor).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Which share of a row's spare width a part takes: the title 1, the value 0.8, and nothing set
/// for parts that keep their own size (a chevron, a spinner).
struct RowShare: LayoutValueKey {
    static let defaultValue: CGFloat? = nil
}

/// A row's title and value side by side, sharing the room the fixed parts leave 1 to 0.8, as
/// the other apps divide it. Each wraps within its share, so neither is ever cut short.
struct TitleValueLayout: Layout {
    var spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widths = widths(proposal.width, subviews)
        var height: CGFloat = 0
        for (index, part) in subviews.enumerated() {
            height = max(height, part.sizeThatFits(ProposedViewSize(width: widths[index], height: nil)).height)
        }
        let used = widths.reduce(0, +) + spacing * CGFloat(max(subviews.count - 1, 0))
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = widths(bounds.width, subviews)
        var x = bounds.minX
        for (index, part) in subviews.enumerated() {
            let size = part.sizeThatFits(ProposedViewSize(width: widths[index], height: nil))
            part.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: widths[index], height: size.height))
            x += widths[index] + spacing
        }
    }

    private func widths(_ total: CGFloat?, _ subviews: Subviews) -> [CGFloat] {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }
        guard let total else { return ideal }
        let shares = subviews.map { $0[RowShare.self] }
        let fixed = zip(shares, ideal).reduce(CGFloat(0)) { $0 + ($1.0 == nil ? $1.1 : 0) }
        let spare = max(0, total - fixed - spacing * CGFloat(max(subviews.count - 1, 0)))
        let whole = shares.compactMap { $0 }.reduce(0, +)
        return zip(shares, ideal).map { share, width in
            guard let share else { return width }
            return whole > 0 ? spare * share / whole : 0
        }
    }
}

/// A row's current value on its right: quieter than the title, kept to the end of the line,
/// at most two lines, in its share of the row.
private struct Reading: View {
    let value: String
    var enabled = true

    var body: some View {
        Text(value)
            .font(.octoBodySmall)
            .foregroundStyle(enabled ? OctoColor.textSecondary : OctoColor.textMuted)
            .multilineTextAlignment(.trailing)
            .lineLimit(2)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// A setting that is on or off. The whole row flips it, and it reads once as a switch.
struct ToggleRow: View {
    let entry: SettingEntry?
    var title: String?
    let isOn: Bool
    var helper: String?
    var enabled = true
    let onChange: (Bool) -> Void

    init(_ entry: SettingEntry?, title: String? = nil, isOn: Bool, helper: String? = nil, enabled: Bool = true,
         onChange: @escaping (Bool) -> Void) {
        self.entry = entry
        self.title = title
        self.isOn = isOn
        self.helper = helper
        self.enabled = enabled
        self.onChange = onChange
    }

    var body: some View {
        RowFrame(entry: entry) {
            RowLabel(title: title ?? entry?.title ?? "", below: helper, enabled: enabled)
            Toggle("", isOn: Binding(get: { isOn }, set: { onChange($0) }))
                .labelsHidden()
                .tint(OctoColor.accent)
                .disabled(!enabled)
                // The row takes every tap, so one tap flips it once.
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onTapGesture { if enabled { onChange(!isOn) } }
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title ?? entry?.title ?? "")
        .accessibilityHint(helper ?? "")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        .accessibilityAction { if enabled { onChange(!isOn) } }
    }
}

/// A setting with a few answers: its title on the left, the current one on the right, and a
/// chevron. Tapping it opens the answers as a system menu beside the row.
struct ChoiceRow: View {
    let entry: SettingEntry?
    var title: String?
    let value: String
    var helper: String?
    var enabled = true
    let question: SettingsQuestion

    init(_ entry: SettingEntry?, title: String? = nil, value: String, helper: String? = nil, enabled: Bool = true,
         question: SettingsQuestion) {
        self.entry = entry
        self.title = title
        self.value = value
        self.helper = helper
        self.enabled = enabled
        self.question = question
    }

    var body: some View {
        Menu {
            QuestionMenuItems(question: question)
        } label: {
            RowFrame(entry: entry) {
                TitleValueLayout {
                    RowLabel(title: title ?? entry?.title ?? "", below: helper, enabled: enabled).layoutValue(key: RowShare.self, value: 1)
                    Reading(value: value, enabled: enabled).layoutValue(key: RowShare.self, value: 0.8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .foregroundStyle(OctoColor.textMuted)
                        .opacity(enabled ? 1 : 0.5)
                        .accessibilityHidden(true)
                }
            }
        }
        .menuStyle(.button)
        .buttonStyle(SettingsRowPress())
        .menuOrder(.fixed)
        .disabled(!enabled)
        .accessibilityLabel(title ?? entry?.title ?? "")
        .accessibilityValue(value)
        .accessibilityHint(helper ?? "")
    }
}

/// A setting along a range: its title and value, and the line to drag.
struct SliderRow: View {
    let entry: SettingEntry?
    var title: String?
    let value: String
    let fraction: Double
    let onSeek: (Double) -> Void

    init(_ entry: SettingEntry?, title: String? = nil, value: String, fraction: Double, onSeek: @escaping (Double) -> Void) {
        self.entry = entry
        self.title = title
        self.value = value
        self.fraction = fraction
        self.onSeek = onSeek
    }

    var body: some View {
        RowFrame(entry: entry) {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title ?? entry?.title ?? "")
                        .font(.octoBody)
                        .foregroundStyle(OctoColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(value).font(.octoBodySmall.monospacedDigit()).foregroundStyle(OctoColor.textSecondary).fixedSize()
                }
                JewelSlider(fraction: fraction, label: title ?? entry?.title ?? "", valueText: value, onSeek: onSeek)
            }
        }
    }
}

/// Something to do, or another page to open: its title, and a chevron, a word on the right, or
/// a spinner while it works.
struct ActionRow: View {
    let entry: SettingEntry?
    var title: String?
    var helper: String?
    var trailing: String?
    var chevron: Bool
    var busy = false
    var enabled = true
    var destructive = false
    let action: () -> Void

    init(_ entry: SettingEntry?, title: String? = nil, helper: String? = nil, trailing: String? = nil, chevron: Bool? = nil,
         busy: Bool = false, enabled: Bool = true, destructive: Bool = false, action: @escaping () -> Void) {
        self.entry = entry
        self.title = title
        self.helper = helper
        self.trailing = trailing
        self.chevron = chevron ?? (trailing == nil)
        self.busy = busy
        self.enabled = enabled
        self.destructive = destructive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            RowFrame(entry: entry) {
                TitleValueLayout {
                    RowLabel(title: title ?? entry?.title ?? "", below: helper, enabled: enabled,
                             titleColor: destructive ? OctoColor.error : OctoColor.textPrimary)
                        .layoutValue(key: RowShare.self, value: 1)
                    if busy {
                        ProgressView().controlSize(.small).tint(OctoColor.accent).frame(width: 18, height: 18)
                    } else if let trailing {
                        Reading(value: trailing, enabled: enabled).layoutValue(key: RowShare.self, value: 0.8)
                    }
                    if chevron && !busy {
                        Image(systemName: SettingsIcon.chevron)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 20, height: 20)
                            .foregroundStyle(OctoColor.textMuted)
                            .opacity(enabled ? 1 : 0.5)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .buttonStyle(SettingsRowPress())
        .disabled(!enabled || busy)
    }
}

/// A fact to read: a title and its value.
struct InfoRow: View {
    let entry: SettingEntry?
    var title: String?
    let value: String
    var helper: String?

    init(_ entry: SettingEntry?, title: String? = nil, value: String, helper: String? = nil) {
        self.entry = entry
        self.title = title
        self.value = value
        self.helper = helper
    }

    var body: some View {
        RowFrame(entry: entry) {
            TitleValueLayout {
                RowLabel(title: title ?? entry?.title ?? "", below: helper).layoutValue(key: RowShare.self, value: 1)
                Reading(value: value).layoutValue(key: RowShare.self, value: 0.8)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A few words inside a group: what a part does, or what went wrong.
struct NoteRow: View {
    let text: String
    var entry: SettingEntry?
    var color: Color = OctoColor.textMuted

    init(_ text: String, entry: SettingEntry? = nil, color: Color = OctoColor.textMuted) {
        self.text = text
        self.entry = entry
        self.color = color
    }

    var body: some View {
        RowFrame(entry: entry, minHeight: 0) {
            Text(text).font(.octoCaption).foregroundStyle(color).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A row that opens a page on the tab's stack, drawn like an action row with a chevron.
struct LinkRow<Value: Hashable>: View {
    let entry: SettingEntry?
    var title: String?
    var helper: String?
    let value: Value

    init(_ entry: SettingEntry?, title: String? = nil, helper: String? = nil, to value: Value) {
        self.entry = entry
        self.title = title
        self.helper = helper
        self.value = value
    }

    var body: some View {
        NavigationLink(value: value) {
            RowFrame(entry: entry) {
                RowLabel(title: title ?? entry?.title ?? "", below: helper)
                Image(systemName: SettingsIcon.chevron)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .foregroundStyle(OctoColor.textMuted)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(SettingsRowPress())
    }
}

/// A way into a page: its icon, title, and one line on how it is set now. It opens a settings
/// page on the tab's stack, or runs `action` when given one instead.
struct CategoryRow: View {
    let icon: String
    let title: String
    let summary: String
    var route: CategoryDestination?
    var action: (() -> Void)?
    /// Marks a server update waiting on the page the row opens.
    var badged = false

    init(icon: String, title: String, summary: String, to route: SettingsRoute, badged: Bool = false) {
        self.icon = icon
        self.title = title
        self.summary = summary
        self.route = .settings(route)
        self.badged = badged
    }

    init(icon: String, title: String, summary: String, to route: Route) {
        self.icon = icon
        self.title = title
        self.summary = summary
        self.route = .app(route)
    }

    init(icon: String, title: String, summary: String, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.summary = summary
        self.action = action
    }

    var body: some View {
        if case .settings(let route) = route {
            NavigationLink(value: route) { label }.buttonStyle(SettingsRowPress())
        } else if case .app(let route) = route {
            NavigationLink(value: route) { label }.buttonStyle(SettingsRowPress())
        } else {
            Button { action?() } label: { label }.buttonStyle(SettingsRowPress())
        }
    }

    private var label: some View {
        Group {
            RowFrame(entry: nil) {
                IconTile(icon: icon)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.octoBody).foregroundStyle(OctoColor.textPrimary).fixedSize(horizontal: false, vertical: true)
                    if !summary.isEmpty {
                        Text(summary).font(.octoCaption).foregroundStyle(OctoColor.textMuted).lineLimit(1).truncationMode(.tail)
                    }
                }
                .padding(.leading, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                if badged { ServerUpdateDot() }
                Image(systemName: SettingsIcon.chevron)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .foregroundStyle(OctoColor.textMuted)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Where a category row goes: a settings page, or a page of the app's own routes.
enum CategoryDestination {
    case settings(SettingsRoute)
    case app(Route)
}

/// A row's icon on a small tinted tile, so a list of pages reads at a glance.
struct IconTile: View {
    let icon: String

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 17))
            .frame(width: 20, height: 20)
            .foregroundStyle(OctoColor.accent)
            .frame(width: 34, height: 34)
            .background(OctoColor.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The inset for a group of rows with icon tiles: the lines start under the titles.
let iconRowInset: CGFloat = 66

/// A row under the finger takes a faint light, at once.
struct SettingsRowPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.06 : 0))
            .contentShape(Rectangle())
    }
}

/// ListenBrainz's mark in its own navy and orange, never tinted.
struct ListenBrainzMark: View {
    var size: CGFloat = 15

    var body: some View {
        Canvas { context, box in
            let s = box.width / 30
            var left = Path()
            left.move(to: CGPoint(x: 14.5 * s, y: 1 * s))
            left.addLine(to: CGPoint(x: 2.5 * s, y: 8 * s))
            left.addLine(to: CGPoint(x: 2.5 * s, y: 22 * s))
            left.addLine(to: CGPoint(x: 14.5 * s, y: 29 * s))
            left.closeSubpath()
            var right = Path()
            right.move(to: CGPoint(x: 15.5 * s, y: 1 * s))
            right.addLine(to: CGPoint(x: 27.5 * s, y: 8 * s))
            right.addLine(to: CGPoint(x: 27.5 * s, y: 22 * s))
            right.addLine(to: CGPoint(x: 15.5 * s, y: 29 * s))
            right.closeSubpath()
            context.fill(left, with: .color(Color(hex: 0x353070)))
            context.fill(right, with: .color(Color(hex: 0xEB743B)))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
