import SwiftUI
import AppKit

public struct SystemBuiltinsView: View {
    @Bindable var state: AppState
    @Binding var editingSkill: SkillDefinition?
    @State private var selectedTab: Int = 0
    @State private var searchText: String = ""

    public init(state: AppState, editingSkill: Binding<SkillDefinition?>) {
        self.state = state
        self._editingSkill = editingSkill
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heroBanner
            Divider()

            Picker("", selection: $selectedTab) {
                Text("Built-in Skills (\(state.builtinSkills.count))").tag(0)
                Text("Slash Commands (\(state.slashCommands.count))").tag(1)
            }
            .pickerStyle(.segmented)
            .monospacedDigit()
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.sm)

            Divider()

            SearchBarView(
                text: $searchText,
                placeholder: selectedTab == 0 ? "Search built-in skills..." : "Search slash commands..."
            )
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.xs)

            Divider()

            if selectedTab == 0 {
                BuiltinSkillsTab(
                    skills: state.builtinSkills,
                    editingSkill: $editingSkill,
                    searchText: searchText
                )
            } else {
                SlashCommandsTab(
                    commands: state.slashCommands,
                    searchText: searchText
                )
            }
        }
    }

    private var heroBanner: some View {
        HeroBannerView(
            title: "Antigravity Engine & Built-ins",
            subtitle: "Core engine capabilities, built-in system skills, and slash commands.",
            iconName: "cpu",
            iconGradient: DesignTokens.Gradients.coreTools,
            revealPath: PathConstants.builtinSkillsDirectory.path,
            stats: [
                HeroBannerStatItem(
                    label: "Built-in Skills",
                    value: "\(state.builtinSkills.count)",
                    icon: "shield.fill",
                    tint: .blue
                ),
                HeroBannerStatItem(
                    label: "Slash Commands",
                    value: "\(state.slashCommands.count)",
                    icon: "terminal",
                    tint: .purple
                ),
                HeroBannerStatItem(
                    label: "Engine Runtime",
                    value: "Active",
                    icon: "bolt.fill",
                    tint: .green
                )
            ]
        )
    }
}
