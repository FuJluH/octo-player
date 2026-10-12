import OctoKit
import SwiftUI

// MARK: Menu items

/// One pick in a system menu: its name, a line under it, a check when it is the one chosen,
/// and dimmed when it cannot be picked now (its line saying why).
struct MenuPick: View {
    let label: String
    var detail: String?
    var checked = false
    var enabled = true
    var role: ButtonRole?
    let action: () -> Void

    init(_ label: String, detail: String? = nil, checked: Bool = false, enabled: Bool = true, role: ButtonRole? = nil,
         action: @escaping () -> Void) {
        self.label = label
        self.detail = detail
        self.checked = checked
        self.enabled = enabled
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            if checked {
                Label {
                    Text(label)
                    if let detail { Text(detail) }
                } icon: {
                    Image(systemName: "checkmark")
                }
            } else {
                Text(label)
                if let detail { Text(detail) }
            }
        }
        .disabled(!enabled)
    }
}

// MARK: Popovers

/// The top of a popover's second page: a back chevron and the name of the page it goes back to.
struct PopoverBack: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        Button(action: onBack) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.octoLabel)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(OctoColor.textPrimary)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint("Back")
        .accessibilityAddTraits(.isHeader)
    }
}

/// A name to type: a heading, the field with its button beside it, and a line under them saying
/// why the name will not do yet. The keyboard opens as it appears; the button waits until
/// `ready` says the name will do.
struct NameForm: View {
    let title: String
    let placeholder: String
    let action: String
    var initial = ""
    var capitalization: TextInputAutocapitalization = .sentences
    var autocorrects = true
    var ready: (String) -> Bool = { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    var note: (String) -> String? = { _ in nil }
    let onDone: (String) -> Void
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        let canDo = ready(name)
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.octoLabel)
                .foregroundStyle(OctoColor.textPrimary)
                .lineLimit(2)
                .padding(.horizontal, 4)
                .padding(.bottom, 10)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 8) {
                TextField(placeholder, text: $name)
                    .font(.octoBody)
                    .foregroundStyle(.white)
                    .tint(OctoColor.accent)
                    .textInputAutocapitalization(capitalization)
                    .autocorrectionDisabled(!autocorrects)
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit { if canDo { onDone(name) } }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(OctoColor.accent.opacity(focused ? 0.15 : 0.10)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(OctoColor.accent.opacity(0.10), lineWidth: 1))
                AccentButton(action, size: .medium, enabled: canDo) { onDone(name) }
            }
            if let line = note(name) {
                Text(line).font(.octoCaption).foregroundStyle(OctoColor.textMuted).padding(.top, 8).padding(.leading, 4)
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .onAppear {
            name = initial
            focused = true
        }
    }
}

extension View {
    /// A popover holding `content`, kept a popover on iPhone too, so it draws as Liquid Glass
    /// beside the control it came from instead of turning into a sheet.
    func glassPopover<Content: View>(isPresented: Binding<Bool>, arrowEdge: Edge? = nil,
                                     @ViewBuilder content: @escaping () -> Content) -> some View {
        popover(isPresented: isPresented, arrowEdge: arrowEdge) {
            content().presentationCompactAdaptation(.popover)
        }
    }

    /// Asks for a name in a popover beside this control while `isPresented`.
    func namePopover(isPresented: Binding<Bool>, title: String, placeholder: String, action: String, initial: String = "",
                     capitalization: TextInputAutocapitalization = .sentences, autocorrects: Bool = true,
                     ready: @escaping (String) -> Bool = { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                     note: @escaping (String) -> String? = { _ in nil },
                     onDone: @escaping (String) -> Void) -> some View {
        glassPopover(isPresented: isPresented) {
            NameForm(title: title, placeholder: placeholder, action: action, initial: initial, capitalization: capitalization,
                     autocorrects: autocorrects, ready: ready, note: note, onDone: onDone)
        }
    }
}

// MARK: Sheets

extension View {
    /// Sizes a sheet to its content, as tall as it needs and no taller, with its handle showing.
    func fittedSheet() -> some View { modifier(FittedSheet()) }
}

private struct FittedSheet: ViewModifier {
    @State private var height: CGFloat?

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .frame(maxHeight: .infinity, alignment: .top)
            .presentationDetents(height.map { [.height($0)] } ?? [.medium])
            .presentationDragIndicator(.visible)
    }
}
