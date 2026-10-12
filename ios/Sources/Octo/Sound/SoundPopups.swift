import OctoKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// What the Sound page asks about in its glass card.
enum SoundSheet: Equatable {
    case savePreset
    case deletePreset(String)
}

/// A glass card that pops up beside what was pressed (`anchor`, in screen points), or in the
/// middle when nothing was. It grows from the corner nearest the control, and closes on a tap
/// outside it. It stays drawn while it fades away.
struct SoundPopupLayer<Content: View>: View {
    let visible: Bool
    let anchor: CGRect?
    let title: String
    let onDismiss: () -> Void
    let onGone: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var size: CGSize = .zero
    @State private var shown = 0.0
    @State private var keepAbove: Bool?
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        GeometryReader { box in
            let window = box.frame(in: .global)
            let spot = place(in: box.size, window: window)
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { onDismiss() }
                    .accessibilityHidden(true)
                content()
                    .frame(maxWidth: min(340, box.size.width - 24))
                    .glassEffect(.regular.tint(Color.black.opacity(0.35)), in: .rect(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.45), radius: 12, y: 8)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                    .scaleEffect(still ? 1 : 0.92 + 0.08 * shown, anchor: UnitPoint(x: spot.origin.x, y: spot.origin.y))
                    .opacity(size == .zero ? 0 : shown)
                    .offset(x: CGFloat(spot.x), y: CGFloat(spot.y))
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(title)
                    .accessibilityAddTraits(.isModal)
                    .accessibilityAction(.escape) { onDismiss() }
            }
        }
        .onAppear { grow(to: visible ? 1 : 0) }
        .onChange(of: visible) { _, now in grow(to: now ? 1 : 0) }
    }

    private func place(in area: CGSize, window: CGRect) -> SoundPopup.Spot {
        let local = anchor.map { $0.offsetBy(dx: -window.minX, dy: -window.minY) }
        let box = local.map { SoundPopup.Box(Int($0.minX), Int($0.minY), Int($0.maxX), Int($0.maxY)) }
        let spot = SoundPopup.place(anchor: box, width: Int(size.width), height: Int(size.height),
                                    windowWidth: Int(area.width), windowHeight: Int(area.height),
                                    margin: SoundPopup.edgeMargin, gap: SoundPopup.anchorGap, keepAbove: keepAbove)
        return spot
    }

    private func grow(to target: Double) {
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: still ? 0.08 : 0.16)) {
            shown = target
        } completion: {
            if target == 0 { onGone() }
        }
    }
}

/// Naming a new preset: the heading, then the field with its button beside it. The keyboard
/// opens as it appears. The button waits until the name will do.
struct SoundPresetNameForm: View {
    let onSave: (String) -> Void
    @State private var name = ""
    @FocusState private var focused: Bool

    private var canSave: Bool { UserPresetRules.canSaveAs(name) }

    /// Why the name will not do, when there is something to say.
    private var note: String? {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !canSave ? "A built-in preset has that name." : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Save as preset")
                .font(SoundStyle.label)
                .foregroundStyle(OctoColor.textPrimary)
                .lineLimit(2)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    TextField("", text: $name, prompt: Text("Preset name").foregroundStyle(OctoColor.textMuted))
                        .font(.octoBody)
                        .foregroundStyle(OctoColor.textPrimary)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focused)
                        .onSubmit { if canSave { onSave(name) } }
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                    Button("Save") { onSave(name) }
                        .buttonStyle(SoundGlassButtonStyle(accent: true))
                        .disabled(!canSave)
                }
                if let note {
                    Text(note)
                        .font(.octoCaption)
                        .foregroundStyle(OctoColor.textMuted)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .padding(6)
        .frame(width: 288)
        .onAppear { focused = true }
    }
}

/// Asking before one of the listener's own presets is deleted.
struct SoundDeleteQuestion: View {
    let name: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Delete \"\(name)\"?")
                .font(.octoBody)
                .foregroundStyle(OctoColor.textPrimary)
                .lineLimit(3)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 10) {
                Button("Delete", action: onConfirm).buttonStyle(SoundGlassButtonStyle(accent: true))
                Button("Cancel", action: onCancel).buttonStyle(SoundGlassButtonStyle())
            }
            .padding(.top, 18)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(width: 288, alignment: .leading)
    }
}

/// A text file the listener saves through the Files app.
struct SoundTextFile: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText]

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Reading a correction file the listener picked.
enum SoundFiles {
    /// The largest file read; real ones are a few hundred bytes.
    static let largestFile = 256 * 1_024

    /// A headphone correction from a picked file, or nothing when it cannot be read or has no
    /// filters Octo can use. It is named after the file.
    static func readCorrection(_ url: URL) -> HeadphoneCorrection? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: largestFile) else { return nil }
        let name = (try? url.resourceValues(forKeys: [.nameKey]).name) ?? url.lastPathComponent
        return ParametricEqFile.correction(fileName: name, text: String(decoding: data, as: UTF8.self))
    }
}
