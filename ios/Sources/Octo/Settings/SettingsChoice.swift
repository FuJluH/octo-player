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

/// The answers to a question as the items of a system menu: the question heads them, each
/// answer has its line under it, and the current one is checked.
struct QuestionMenuItems: View {
    let question: SettingsQuestion

    var body: some View {
        Section(question.title) {
            ForEach(Array(question.answers.enumerated()), id: \.offset) { index, answer in
                MenuPick(answer.label, detail: answer.detail, checked: index == question.selected, enabled: answer.enabled) {
                    question.onPick(index)
                }
            }
        }
    }
}
