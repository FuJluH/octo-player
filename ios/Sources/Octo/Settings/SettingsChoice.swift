import OctoKit
import SwiftUI

/// One answer to a question: its name, and a line about it. An answer that is not `enabled`
/// shows dimmed, with its detail saying why, and cannot be picked.
struct SettingsAnswer: Hashable {
    var label: String
    var detail: String?
    var enabled = true

    init(_ label: String, _ detail: String? = nil, enabled: Bool = true) {
        self.label = label
        self.detail = detail
        self.enabled = enabled
    }
}

/// A question with a few answers, which one is current, and what to do with the one picked.
struct SettingsQuestion {
    var title: String
    var answers: [SettingsAnswer]
    var selected: Int
    var onPick: (Int) -> Void
}

extension SettingsQuestion {
    /// A question whose answers are a list of choices, the current one marked.
    init<T: Equatable>(_ title: String, _ options: [T], current: T, answer: (T) -> SettingsAnswer, pick: @escaping (T) -> Void) {
        self.init(title: title, answers: options.map(answer), selected: options.firstIndex(of: current) ?? -1) { pick(options[$0]) }
    }
}

extension View {
    /// Pops the answers up beside this view as a glass card: under it when there is room, over
    /// it otherwise. A tap outside closes it; picking an answer runs it and closes it at once.
    func choicePopover(isPresented: Binding<Bool>, question: SettingsQuestion) -> some View {
        popover(isPresented: isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            ChoiceList(question: question) { isPresented.wrappedValue = false }
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// The answers under the question, the current one in the darker pill with a white check.
/// Hairlines part the answers, never touching the pill.
struct ChoiceList: View {
    let question: SettingsQuestion
    let close: () -> Void

    var body: some View {
        let looks = MenuRowLook.rows(count: question.answers.count, selected: question.selected)
        VStack(alignment: .leading, spacing: 0) {
            Text(question.title)
                .font(.settingsLabel)
                .foregroundStyle(OctoColor.textSecondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(question.answers.enumerated()), id: \.offset) { index, answer in
                        if index > 0 {
                            Rectangle()
                                .fill(looks[index].lineAbove ? Color.white.opacity(0.08) : .clear)
                                .frame(height: 1)
                                .padding(.horizontal, 14)
                        }
                        ChoiceAnswerRow(answer: answer, selected: looks[index].selected, pickable: question.selected >= 0) {
                            question.onPick(index)
                            close()
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(6)
        .frame(minWidth: 220, maxWidth: 320)
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxHeight: screenHeight * 0.6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(question.title)
    }
}

private struct ChoiceAnswerRow: View {
    let answer: SettingsAnswer
    let selected: Bool
    let pickable: Bool
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(answer.label)
                        .font(.octoBodySmall)
                        .foregroundStyle(answer.enabled ? OctoColor.textPrimary : OctoColor.textMuted)
                    if let detail = answer.detail {
                        Text(detail).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                if selected {
                    Image(systemName: SettingsIcon.check)
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 18, height: 18)
                        .foregroundStyle(.white)
                } else if pickable {
                    Color.clear.frame(width: 18, height: 18)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 40)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.32))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(AnswerPress(selected: selected))
        .disabled(!answer.enabled)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityHint(answer.detail ?? "")
    }
}

/// A finger on an answer that is not chosen shows a quiet accent pill at once.
private struct AnswerPress: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if configuration.isPressed && !selected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(OctoColor.accent.opacity(0.14))
                }
            }
    }
}
