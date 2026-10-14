import CoreImage
import CoreImage.CIFilterBuiltins
import OctoKit
import SwiftUI
import UIKit

// The parts the family sheets share: the header with its avatar and countdown, the middle that
// scrolls with a "More below" cue, the footer that stays put, the QR code, the link row, copy
// buttons and the Anywhere or At home chooser.

/// A QR code as squares, made on the phone with medium error correction.
struct QrMatrix: Equatable {
    let size: Int
    let dark: [Bool]

    func isDark(_ x: Int, _ y: Int) -> Bool { dark[y * size + x] }

    /// The code for a link, or nil when it cannot be made.
    static func make(_ text: String) -> QrMatrix? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let image = filter.outputImage else { return nil }
        let width = Int(image.extent.width)
        let height = Int(image.extent.height)
        var pixels = [UInt8](repeating: 255, count: width * height)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        guard let cg = context.createCGImage(image, from: image.extent),
              let gray = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                   space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        gray.interpolationQuality = .none
        gray.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        // The generator adds a light margin; the code itself is the dark part's bounds.
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[y * width + x] < 128 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let size = maxX - minX + 1
        var dark = [Bool](repeating: false, count: size * size)
        for y in 0..<size {
            for x in 0..<size where minY + y < height { dark[y * size + x] = pixels[(minY + y) * width + minX + x] < 128 }
        }
        return QrMatrix(size: size, dark: dark)
    }
}

/// The QR code on white, with a quiet edge a thirteenth of its side, dimmed when stale.
struct QrTile: View {
    let link: String
    let label: String
    let side: CGFloat
    var dim = false
    @State private var matrix: QrMatrix?

    var body: some View {
        let quiet = side / 13
        Canvas { context, size in
            guard let matrix else { return }
            let cell = size.width / CGFloat(matrix.size)
            for y in 0..<matrix.size {
                for x in 0..<matrix.size where matrix.isDark(x, y) {
                    context.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell + 0.5, height: cell + 0.5)), with: .color(.black))
                }
            }
        }
        .frame(width: side - quiet * 2, height: side - quiet * 2)
        .padding(quiet)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(dim ? 0.12 : 1)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isImage)
        .task(id: link) { matrix = QrMatrix.make(link) }
    }
}

/// The code in its well, cross-fading when the link changes, with anything over it.
struct QrWell<Overlay: View>: View {
    let link: String
    let label: String
    let side: CGFloat
    var dim = false
    /// The code's identifier for tests, when it has one.
    var tag: String?
    @ViewBuilder var overlay: Overlay

    var body: some View {
        ZStack {
            QrTile(link: link, label: label, side: side, dim: dim)
                .id(link)
                .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                .accessibilityIdentifier(tag ?? "")
            overlay
        }
        .frame(width: side + 16, height: side + 16)
        .background(AccountColor.fill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(OctoColor.hairline))
        .animation(.easeInOut(duration: 0.3), value: link)
    }
}

extension QrWell where Overlay == EmptyView {
    init(link: String, label: String, side: CGFloat, dim: Bool = false, tag: String? = nil) {
        self.init(link: link, label: label, side: side, dim: dim, tag: tag) { EmptyView() }
    }
}

/// A grey square where a code will be.
struct QrPlaceholder: View {
    let side: CGFloat
    var label: String?

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .frame(width: side, height: side)
            .accessibilityElement()
            .accessibilityLabel(label ?? "")
    }
}

/// The QR code's side: about 55% of the sheet's width, never under 200 points.
func qrSide(_ width: CGFloat) -> CGFloat { min(max(width * 0.55, 200), width - 40) }

/// The sheet's header: an avatar with the name's first letter, the title, the line under it
/// with a timer, and Close.
struct SheetHeader: View {
    var name: String?
    let title: String
    let subtitle: String
    var subtitleColor: Color = OctoColor.textMuted
    var clock = true
    let close: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let name {
                let initial = name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "?"
                Text(initial)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(OctoColor.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(OctoColor.accentSelected, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.1)))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(OctoColor.textPrimary).accessibilityAddTraits(.isHeader)
                HStack(spacing: 5) {
                    if clock { Image(systemName: "timer").font(.system(size: 11)).foregroundStyle(subtitleColor) }
                    Text(subtitle).font(.octoCaption).foregroundStyle(subtitleColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(OctoColor.textMuted).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }
}

/// The part of a sheet that scrolls when it can't all fit: a soft fade at its bottom edge and a
/// "More below" button that brings `target` into view, both gone once the bottom is reached.
struct SheetScrollArea<Content: View>: View {
    var target: String?
    /// What to bring into view as the sheet opens, by its id.
    var startAt: String?
    @ViewBuilder var content: Content
    @State private var moreBelow = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) { content }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                    .id("top")
                Color.clear.frame(height: 1).id("end")
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 2
            } action: { _, more in
                withAnimation(.easeInOut(duration: 0.2)) { moreBelow = more }
            }
            .onAppear {
                if let startAt { proxy.scrollTo(startAt, anchor: .center) }
            }
            .overlay(alignment: .bottom) {
                if moreBelow {
                    ZStack(alignment: .bottom) {
                        LinearGradient(colors: [.clear, OctoColor.background.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 56)
                            .allowsHitTesting(false)
                        Button {
                            withAnimation {
                                if let target { proxy.scrollTo(target, anchor: .bottom) }
                            }
                            Task {
                                try? await Task.sleep(for: .milliseconds(350))
                                withAnimation { proxy.scrollTo("end", anchor: .bottom) }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(FamilySheetText.moreBelow).font(.system(size: 12, weight: .semibold))
                                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(OctoColor.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(OctoColor.accentSelected, in: Capsule())
                            .overlay(Capsule().strokeBorder(OctoColor.hairline))
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 6)
                        .accessibilityLabel(FamilySheetText.moreBelow)
                    }
                    .transition(.opacity)
                }
            }
        }
    }
}

/// The sheet's footer, always in sight: a hairline, the quiet action and Done.
struct SheetFooter<Start: View>: View {
    let done: () -> Void
    @ViewBuilder var start: Start

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(OctoColor.hairline).frame(height: 1)
            HStack(spacing: 10) {
                start.frame(maxWidth: .infinity, alignment: .leading)
                AccentButton("Done", size: .medium, bright: true, fillWidth: true, action: done)
                    .frame(width: 108)
                    .accessibilityIdentifier("family-sheet-done")
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
    }
}

/// A section label and what it labels, 6 points apart.
struct SheetSection<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(OctoColor.textSecondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Numbered steps in tonal circles.
struct NumberedSteps: View {
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(OctoColor.textPrimary)
                        .frame(width: 20, height: 20)
                        .background(OctoColor.accentTonal, in: Circle())
                    Text(step).font(.octoCaption).foregroundStyle(OctoColor.textPrimary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A copy button: copies the whole value, then for two seconds a green check and "Copied".
struct CopyButton: View {
    let value: String
    let name: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 2) {
            if copied {
                Text(FamilySheetText.copied).font(.system(size: 12, weight: .semibold)).foregroundStyle(OctoColor.signalGreen)
            }
            Button {
                UIPasteboard.general.string = value
                copied = true
                UIAccessibility.post(notification: .announcement, argument: FamilySheetText.copied)
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 17))
                    .foregroundStyle(copied ? OctoColor.signalGreen : OctoColor.textPrimary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(name)
        }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .milliseconds(FamilySheetText.copiedMs))
            copied = false
        }
    }
}

/// The link in a soft pill: tap it to open it; the copy button copies all of it.
struct SheetLinkRow: View {
    let url: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "link").font(.system(size: 14)).foregroundStyle(OctoColor.accentHover)
            Button { openLink(url, openURL) } label: {
                Text(shownLink(url, max: 32))
                    .font(.octoBodySmall)
                    .foregroundStyle(OctoColor.accentHover)
                    .lineLimit(2)
                    .minimumScaleFactor(10 / 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(url)
            .accessibilityHint("Open the link")
            CopyButton(value: url, name: "Copy link")
        }
        .padding(.leading, 14)
        .padding(.trailing, 2)
        .background(AccountColor.fill, in: Capsule())
        .overlay(Capsule().strokeBorder(OctoColor.hairline))
    }
}

/// Opens a link: an octo: link goes to this app itself; any other the system opens.
@MainActor
func openLink(_ url: String, _ open: OpenURLAction) {
    if url.lowercased().hasPrefix("octo:"), let link = parseFamilyLink(url) {
        SystemEntries.shared?.family.open(.join(link))
        return
    }
    if let target = URL(string: url) { open(target) }
}

/// Where the link will be used: a question, two equal choices, and a line saying which address
/// the chosen one goes through, or what to do first when it has none.
struct ReachChooser: View {
    let question: String
    let reach: LinkReach
    let options: LinkOptions
    let owner: Bool
    let server: String
    let pick: (LinkReach) -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question).font(.system(size: 12, weight: .semibold)).foregroundStyle(OctoColor.textSecondary)
            HStack(spacing: 10) {
                option(.anywhere, icon: !options.anywhereAvailable && reach != .anywhere ? "lock" : "globe")
                option(.home, icon: "house")
            }
            .fixedSize(horizontal: false, vertical: true)
            if let line = reachLine(reach, options) {
                Text(line).font(.octoCaption).foregroundStyle(OctoColor.textMuted).lineLimit(2)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock").font(.system(size: 14)).foregroundStyle(OctoColor.textSecondary)
                        Text(FamilySheetText.setOutsideFirst).font(.system(size: 14, weight: .semibold)).foregroundStyle(OctoColor.textPrimary)
                    }
                    if owner {
                        GlazeButton(FamilySheetText.openStatus, size: .small) { if let url = URL(string: dashboardStatusPage(server)) { openURL(url) } }
                    } else {
                        Text(FamilySheetText.askOwnerOutside).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AccountColor.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(OctoColor.hairline))
            }
        }
    }

    private func option(_ choice: LinkReach, icon: String) -> some View {
        let chosen = reach == choice
        let ink = chosen ? OctoColor.background : OctoColor.textSecondary
        return Button { pick(choice) } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 16, weight: .medium))
                Text(choice.label).font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(10 / 15)
                    .accessibilityIdentifier("reach-\(choice.rawValue)-label")
            }
            .foregroundStyle(ink)
            .padding(.leading, 10)
            .padding(.trailing, 18)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(chosen ? OctoColor.accent : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(chosen ? .clear : OctoColor.hairline))
            .overlay(alignment: .topTrailing) {
                if chosen { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(ink).padding(5) }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .animation(.easeInOut(duration: 0.18), value: chosen)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? [.isSelected, .isButton] : .isButton)
        .accessibilityLabel(choice.label)
        .accessibilityIdentifier("reach-\(choice.rawValue)")
    }
}

/// A card for how a hand-over ended badly, with a way to try again.
struct ProblemCard: View {
    let words: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "info.circle").font(.system(size: 18)).foregroundStyle(OctoColor.signalOrange)
                Text(words).font(.octoBodySmall).foregroundStyle(OctoColor.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
            GlazeButton(FamilySheetText.tryAgain, size: .small, action: retry)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AccountColor.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(OctoColor.hairline))
    }
}

/// A rounded card of rows with hairlines between, as the Your login card draws them.
struct SoftCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AccountColor.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(OctoColor.hairline))
    }
}

struct SoftHairline: View {
    var body: some View { Rectangle().fill(OctoColor.hairline).frame(height: 1) }
}

/// A value in monospace that shrinks to fit rather than being cut.
struct MonoValue: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14, design: .monospaced))
            .foregroundStyle(OctoColor.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(10 / 14)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
