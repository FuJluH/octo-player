import OctoKit
import SwiftUI

/// Home's shelves in their order, as a system list held in editing: each row's handle drags it to
/// a new place, and its switch shows or hides it on Home. Every change is kept and reaches Home at
/// once. A button at the bottom puts the usual order back, after the system's own question.
struct HomeSectionsPage: View {
    @State private var settings = AppSettings.shared
    @State private var askingReset = false

    var body: some View {
        let entries = settings.homeSections
        List {
            ScreenTitle("Home sections")
                .padding(.top, detailTopGap)
                .plainListRow()
            Section {
                ForEach(entries) { entry in
                    HomeSectionRow(entry: entry) { shown in
                        withAnimation(.easeInOut(duration: 0.2)) { settings.setHomeSectionShown(entry.section, shown) }
                    }
                }
                .onMove { offsets, destination in
                    withAnimation(.easeInOut(duration: 0.25)) { settings.moveHomeSections(fromOffsets: offsets, toOffset: destination) }
                }
                .listRowBackground(OctoColor.surfaceRaised)
                .listRowSeparatorTint(Color.white.opacity(0.10))
            } header: {
                groupLabel("On Home")
            } footer: {
                Text("Drag a section by its handle to move it. A hidden section keeps its place here, ready to show again.")
                    .font(.octoCaption)
                    .foregroundStyle(OctoColor.textMuted)
            }
            Section {
                Button { askingReset = true } label: {
                    Text("Reset to default order")
                        .font(.octoBody)
                        .foregroundStyle(entries == defaultHomeSections ? OctoColor.textMuted : OctoColor.accent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                // A borderless button takes its own taps, so it works while the list is editing.
                .buttonStyle(.borderless)
                .disabled(entries == defaultHomeSections)
                .listRowBackground(OctoColor.surfaceRaised)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .environment(\.editMode, .constant(.active))
        .tint(OctoColor.accent)
        .barClearance()
        .confirmationDialog("Reset Home sections?", isPresented: $askingReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.25)) { settings.resetHomeSections() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every section goes back to its usual place and shows again.")
        }
        .opensWhenAsked("reset_home_sections") { askingReset = true }
    }

    /// A group's quiet capitalized label, as on the other settings pages.
    private func groupLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.settingsLabel)
            .tracking(0.6)
            .foregroundStyle(OctoColor.textMuted)
            .textCase(nil)
            .accessibilityLabel(title)
    }
}

/// One shelf: its name as Home shows it, and the switch that shows or hides it. A hidden shelf's
/// name is dimmed.
private struct HomeSectionRow: View {
    let entry: HomeSectionEntry
    let onChange: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { entry.shown }, set: { onChange($0) })) {
            Text(entry.section.title)
                .font(.octoBody)
                .foregroundStyle(entry.shown ? OctoColor.textPrimary : OctoColor.textMuted)
        }
        .tint(OctoColor.accent)
        .sensoryFeedback(.selection, trigger: entry.shown)
        .frame(minHeight: 40)
    }
}
